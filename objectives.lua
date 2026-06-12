local Entity = require("entity")

local objectives = {}

local activeObjectives = {}
local objectiveStates = {}
local smallFont
local objectivePool = {}

local function findEmptyCells(entities, hex)
    local candidates = {}
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) then
                local occupied = false
                for _, e in ipairs(entities) do
                    if e.q == q and e.r == r then
                        occupied = true
                        break
                    end
                end
                if not occupied then
                    local terrain = _G.terrainMap and _G.terrainMap[q] and _G.terrainMap[q][r] or "grass"
                    if terrain ~= "water" then
                        local status = require("status")
                        if not status.hasNegativeHexStatus(q, r) then
                            table.insert(candidates, {q = q, r = r})
                        end
                    end
                end
            end
        end
    end
    return candidates
end

local function findBuildingToReplace(entities)
    local candidates = {}
    for i, e in ipairs(entities) do
        if e:isBuilding() and e.name ~= "Tower" then
            local terrain = _G.terrainMap and _G.terrainMap[e.q] and _G.terrainMap[e.q][e.r] or "grass"
            if terrain ~= "water" then
                table.insert(candidates, i)
            end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[love.math.random(1, #candidates)]
end

local function createTowerAt(q, r)
    local env = require("environment")
    local loadedMap = env.loadedMap
    local tileW = (loadedMap and loadedMap.tilewidth) or 14
    local tileH = (loadedMap and loadedMap.tileheight) or 12
    local tower = Entity.new("Tower", Entity.TYPES.BUILDING, q, r, 1, false, 0, nil, nil, {})
    tower.globalHealthCost = 1
    tower.isObjective = true
    tower.sprite = env.generateBuildingSprite("Tower", tileW, tileH)
    return tower
end

local function isEntityAlive(entities, name)
    for _, e in ipairs(entities) do
        if e.name == name and e.health and e.health > 0 then
            return true
        end
    end
    return false
end

local function isAnyZombieAlive(entities)
    for _, e in ipairs(entities) do
        if e.health and e.health > 0 and e:isCharacter() and not e.isPlayable then
            local name = e.name or ""
            if name:match("Zombie$") and not name:match("Poisonous") then
                return true
            end
        end
    end
    return false
end

local function definePool()
    objectivePool = {
        {
            id = "protect_tower",
            name = "Protect the Tower",
            desc = "Keep the tower alive until victory",
            onGenerate = function(entities, hex)
                local hasTower = isEntityAlive(entities, "Tower")
                if not hasTower then
                    local idx = findBuildingToReplace(entities)
                    if idx then
                        local old = entities[idx]
                        entities[idx] = createTowerAt(old.q, old.r)
                    else
                        local cells = findEmptyCells(entities, hex)
                        if #cells > 0 then
                            local cell = cells[love.math.random(1, #cells)]
                            table.insert(entities, createTowerAt(cell.q, cell.r))
                        end
                    end
                end
            end,
            check = function(entities, state)
                if not isEntityAlive(entities, "Tower") then
                    state["protect_tower"] = "failed"
                end
            end,
            checkOnVictory = function(entities, state)
                state["protect_tower"] = isEntityAlive(entities, "Tower") and "completed" or "failed"
            end,
        },
        {
            id = "survive_poisonous_zombie",
            name = "Poisonous Zombie Survives",
            desc = "Poisonous zombie must not die before decay is applied",
            onGenerate = function(entities, hex)
                local hasZombie = isEntityAlive(entities, "PoisonousZombie")
                if not hasZombie then
                    for _, e in ipairs(entities) do
                        if e.health and e.health > 0 and e.name:match("Poisonous") then
                            hasZombie = true
                            break
                        end
                    end
                end
                if not hasZombie then
                    local env = require("environment")
                    local cells = findEmptyCells(entities, hex)
                    if #cells > 0 then
                        local cell = cells[love.math.random(1, #cells)]
                        local zombie = env.createEnemyByType("PoisonousZombie", cell.q, cell.r)
                        table.insert(entities, zombie)
                    end
                end
            end,
            check = function(entities, state)
                local decayApplied = _G.decayAppliedForTurnLimit or false
                local alive = isEntityAlive(entities, "PoisonousZombie")
                if not alive then
                    for _, e in ipairs(entities) do
                        if e.health and e.health > 0 and e.name:match("Poisonous") then
                            alive = true
                            break
                        end
                    end
                end
                if not alive then
                    state["survive_poisonous_zombie"] = decayApplied and "completed" or "failed"
                elseif decayApplied then
                    state["survive_poisonous_zombie"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                local decayApplied = _G.decayAppliedForTurnLimit or false
                local alive = isEntityAlive(entities, "PoisonousZombie")
                if not alive then
                    for _, e in ipairs(entities) do
                        if e.health and e.health > 0 and e.name:match("Poisonous") then
                            alive = true
                            break
                        end
                    end
                end
                state["survive_poisonous_zombie"] = (alive or decayApplied) and "completed" or "failed"
            end,
        },
        {
            id = "defend_tower",
            name = "Defend the Tower",
            desc = "A random building was replaced with a tower. Protect it!",
            onGenerate = function(entities, hex)
                local idx = findBuildingToReplace(entities)
                if idx then
                    local old = entities[idx]
                    entities[idx] = createTowerAt(old.q, old.r)
                    print(string.format("Objective 'defend_tower': Building at (%d,%d) replaced with Tower", old.q, old.r))
                else
                    local cells = findEmptyCells(entities, hex)
                    if #cells > 0 then
                        local cell = cells[love.math.random(1, #cells)]
                        table.insert(entities, createTowerAt(cell.q, cell.r))
                        print(string.format("Objective 'defend_tower': Tower placed at (%d,%d)", cell.q, cell.r))
                    end
                end
            end,
            check = function(entities, state)
                if not isEntityAlive(entities, "Tower") then
                    state["defend_tower"] = "failed"
                end
            end,
            checkOnVictory = function(entities, state)
                state["defend_tower"] = isEntityAlive(entities, "Tower") and "completed" or "failed"
            end,
        },
        {
            id = "defend_zombie",
            name = "Defend the Zombie",
            desc = "A zombie appears on the map. It must survive!",
            onGenerate = function(entities, hex)
                local env = require("environment")
                local cells = findEmptyCells(entities, hex)
                if #cells > 0 then
                    local cell = cells[love.math.random(1, #cells)]
                    local zombie = env.createEnemyByType("Zombie", cell.q, cell.r)
                    table.insert(entities, zombie)
                    print(string.format("Objective 'defend_zombie': Zombie spawned at (%d,%d)", cell.q, cell.r))
                end
            end,
            check = function(entities, state)
                local decayApplied = _G.decayAppliedForTurnLimit or false
                local alive = isAnyZombieAlive(entities)
                if not alive then
                    state["defend_zombie"] = decayApplied and "completed" or "failed"
                elseif decayApplied then
                    state["defend_zombie"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                local decayApplied = _G.decayAppliedForTurnLimit or false
                local alive = isAnyZombieAlive(entities)
                state["defend_zombie"] = (alive or decayApplied) and "completed" or "failed"
            end,
        },
    }
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = love.math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

function objectives.generate(entities, hex)
    definePool()
    activeObjectives = {}
    objectiveStates = {}

    local shuffled = shuffle(objectivePool)
    local count = math.min(2, #shuffled)
    for i = 1, count do
        local def = shuffled[i]
        table.insert(activeObjectives, def)
        objectiveStates[def.id] = "pending"
        if def.onGenerate then
            def.onGenerate(entities, hex)
        end
    end

    print(string.format("Generated %d objectives:", count))
    for _, obj in ipairs(activeObjectives) do
        print(string.format("  - %s (%s)", obj.name, obj.id))
    end
end

function objectives.activateAll(entities, hex)
    definePool()
    activeObjectives = {}
    objectiveStates = {}

    for _, def in ipairs(objectivePool) do
        table.insert(activeObjectives, def)
        objectiveStates[def.id] = "pending"
        if def.onGenerate then
            def.onGenerate(entities, hex)
        end
    end

    print(string.format("Activated all %d objectives:", #activeObjectives))
    for _, obj in ipairs(activeObjectives) do
        print(string.format("  - %s (%s)", obj.name, obj.id))
    end
end

function objectives.reset()
    definePool()
    activeObjectives = {}
    objectiveStates = {}
end

function objectives.getList()
    return activeObjectives
end

function objectives.getState(id)
    return objectiveStates[id] or "pending"
end

function objectives.getCompletedCount()
    local count = 0
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "completed" then count = count + 1 end
    end
    return count
end

function objectives.getTotalCount()
    return #activeObjectives
end

function objectives.getFailedCount()
    local count = 0
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "failed" then count = count + 1 end
    end
    return count
end

function objectives.update(entities)
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "pending" then
            if obj.check then
                obj.check(entities, objectiveStates)
            end
        end
    end
end

function objectives.checkOnVictory(entities)
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "pending" then
            if obj.checkOnVictory then
                obj.checkOnVictory(entities, objectiveStates)
            end
        end
    end
end

function objectives.draw()
    if #activeObjectives == 0 then return end

    local x = 10
    local y = 330
    local w = 200
    local lineH = 16
    local padding = 6
    local titleH = 20
    local totalH = titleH + #activeObjectives * lineH + padding * 2

    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", x, y, w, totalH, 5)
    love.graphics.setColor(0.4, 0.4, 0.6, 0.6)
    love.graphics.rectangle("line", x, y, w, totalH, 5)

    if not smallFont then smallFont = love.graphics.newFont(12) end
    love.graphics.setColor(0.9, 0.9, 0.6, 1)
    love.graphics.setFont(smallFont)
    love.graphics.print("Objectives", x + padding, y + padding)

    for i, obj in ipairs(activeObjectives) do
        local sy = y + titleH + (i - 1) * lineH + padding
        local state = objectiveStates[obj.id] or "pending"
        local icon, color
        if state == "completed" then
            icon = "✓"
            color = {0.4, 1, 0.4, 1}
        elseif state == "failed" then
            icon = "✗"
            color = {1, 0.4, 0.4, 1}
        else
            icon = "○"
            color = {0.8, 0.8, 0.8, 1}
        end
        love.graphics.setColor(unpack(color))
        love.graphics.print(icon .. " " .. obj.name, x + padding, sy)
    end
end

definePool()
return objectives