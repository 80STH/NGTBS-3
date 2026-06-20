local Entity = require("entity")

local objectives = {}

local activeObjectives = {}
local activePrimaryObjective = nil
local objectiveStates = {}
local smallFont
local objectivePool = {}

local primaryObjectiveDefs = {}

primaryObjectiveDefs.protect_caravans = {
    id = "protect_caravans",
    name = "Protect Caravans",
    desc = "Every caravan destroyed increases Chaos!",
    isPrimary = true,
    forceSecondary = "protect_blockpost",
    onGenerate = function(entities, hex)
        _G.chaos = 0
        _G.caravanCount = 0
        for _, e in ipairs(entities) do
            if e.name == "Caravan" then
                _G.caravanCount = (_G.caravanCount or 0) + 1
            end
        end
    end,
    check = function(entities, state)
        local alive = 0
        for _, e in ipairs(entities) do
            if e.name == "Caravan" and e.health and e.health > 0 then
                alive = alive + 1
            end
        end
        local dead = (_G.caravanCount or 0) - alive
        local prevDead = _G.caravansDestroyed or 0
        if dead > prevDead then
            local newDead = dead - prevDead
            _G.chaos = (_G.chaos or 0) + newDead
            _G.caravansDestroyed = dead
            for i = 1, newDead do
                print(string.format("Caravan destroyed! Chaos +1 (total: %d)", _G.chaos))
            end
        end
    end,
}

primaryObjectiveDefs.protect_railway = {
    id = "protect_railway",
    name = "Protect Railway Infrastructure",
    desc = "Every damage to train or tunnel increases Chaos!",
    isPrimary = true,
    incompatibleWithSecondary = { "protect_tower", "protect_blockpost" },
    onGenerate = function(entities, hex)
        _G.railwayTakenDamage = 0
        _G.occupiedTunnelCount = 0
        for _, e in ipairs(entities) do
            if e.name == "OccupiedTunnel" and e.health and e.health > 0 then
                _G.occupiedTunnelCount = (_G.occupiedTunnelCount or 0) + 1
            end
        end
    end,
    check = function(entities, state)
        local totalDamage = 0
        for _, e in ipairs(entities) do
            if e.isTrainCar and e.health and e.maxHealth then
                totalDamage = totalDamage + (e.maxHealth - math.max(0, e.health))
            end
            if e.name == "Tunnel" and e.health and e.maxHealth then
                totalDamage = totalDamage + (e.maxHealth - math.max(0, e.health))
            end
        end
        local prev = _G.railwayTakenDamage or 0
        if totalDamage > prev then
            local newDamage = totalDamage - prev
            _G.chaos = (_G.chaos or 0) + newDamage
            _G.railwayTakenDamage = totalDamage
            print(string.format("Railway infrastructure damaged! Chaos +%d (total: %d)", newDamage, _G.chaos))
        end

        local aliveOcc = 0
        for _, e in ipairs(entities) do
            if e.name == "OccupiedTunnel" and e.health and e.health > 0 then
                aliveOcc = aliveOcc + 1
            end
        end
        local prevOcc = _G.occupiedTunnelCount or 0
        if prevOcc > aliveOcc then
            local destroyed = prevOcc - aliveOcc
            _G.chaos = (_G.chaos or 0) + destroyed * 2
            print(string.format("Occupied tunnel destroyed! Chaos +%d (total: %d)", destroyed * 2, _G.chaos))
        end
        _G.occupiedTunnelCount = aliveOcc
    end,
}

local function hasTrainCars(entities)
    for _, e in ipairs(entities) do
        if e.name == "TrainCar" or e.name == "Locomotive" then return true end
    end
    return false
end

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
                    if terrain ~= "water" and terrain ~= "underwater_mines" then
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
        if e:isBuilding() and e.name ~= "Tower" and e.maxHealth == 1 then
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

local function definePool()
    objectivePool = {
        {
            id = "protect_blockpost",
            name = "Protect the Blockpost",
            desc = "Blockpost HP lost increases Chaos!",
            onGenerate = function(entities, hex)
                for _, e in ipairs(entities) do
                    if e.name == "Blockpost" and e.health and e.health > 0 then
                        _G.blockpostMaxHealth = e.maxHealth
                        break
                    end
                end
            end,
            check = function(entities, state)
                for _, e in ipairs(entities) do
                    if e.name == "Blockpost" and e.maxHealth then
                        local curHealth = math.max(0, e.health or 0)
                        local damageTaken = e.maxHealth - curHealth
                        local prevDamage = _G.blockpostDamageTracked or 0
                        if damageTaken > prevDamage then
                            local newDamage = damageTaken - prevDamage
                            _G.chaos = (_G.chaos or 0) + newDamage
                            _G.blockpostDamageTracked = damageTaken
                            print(string.format("Blockpost damaged! Chaos +%d (total: %d)", newDamage, _G.chaos))
                        end
                        return
                    end
                end
            end,
            checkOnVictory = function(entities, state)
                state["protect_blockpost"] = "completed"
            end,
        },
        {
            id = "protect_tower",
            name = "Protect the Tower",
            desc = "Keep the tower alive until victory",
            incompatibleWithPrimary = true,
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
            id = "kill_poisonous_with_decay",
            name = "Poisonous Dies With Decay",
            desc = "The poisonous enemy must die with decay applied",
            incompatible = { "slaughter" },
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
                _G.poisonousSeenAlive = false
                _G.poisonousResolved = false
                _G.poisonousHadDecay = false
            end,
            check = function(entities, state)
                if _G.poisonousResolved then return end
                local target = nil
                local status_mod = require("status")
                for _, e in ipairs(entities) do
                    if e.health and e.health > 0 and e.name:match("Poisonous") then
                        target = e
                        break
                    end
                end
                if target then
                    _G.poisonousSeenAlive = true
                    if status_mod.hasEntityStatus(target, "decay") then
                        _G.poisonousHadDecay = true
                    end
                    if target.isDying or target.health <= 0 then
                        state["kill_poisonous_with_decay"] = _G.poisonousHadDecay and "completed" or "failed"
                        _G.poisonousResolved = true
                    end
                elseif _G.poisonousSeenAlive and not _G.poisonousResolved then
                    state["kill_poisonous_with_decay"] = _G.poisonousHadDecay and "completed" or "failed"
                    _G.poisonousResolved = true
                end
            end,
            checkOnVictory = function(entities, state)
                if _G.poisonousResolved then return end
                state["kill_poisonous_with_decay"] = "failed"
            end,
        },
        {
            id = "slaughter",
            name = "Slaughter",
            desc = "Kill 7 enemies before decay is applied",
            incompatible = { "kill_poisonous_with_decay" },
            onGenerate = function(entities, hex)
                _G.objective_enemiesKilled = 0
            end,
            check = function(entities, state)
                local decayApplied = _G.decayAppliedForTurnLimit or false
                local killed = _G.objective_enemiesKilled or 0
                if decayApplied then
                    state["slaughter"] = (killed >= 7) and "completed" or "failed"
                end
            end,
            checkOnVictory = function(entities, state)
                local killed = _G.objective_enemiesKilled or 0
                state["slaughter"] = (killed >= 7) and "completed" or "failed"
            end,
        },
        {
            id = "block_dig",
            name = "Block Dig",
            desc = "Block dig sites from spawning at least 2 times",
            onGenerate = function(entities, hex)
                _G.objective_digBlocks = 0
            end,
            check = function(entities, state)
                local blocked = _G.objective_digBlocks or 0
                if blocked >= 2 then
                    state["block_dig"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                local blocked = _G.objective_digBlocks or 0
                state["block_dig"] = (blocked >= 2) and "completed" or "failed"
            end,
        },
        {
            id = "kill_leader",
            name = "Destroy the Leader",
            desc = "Find and eliminate the enemy leader!",
            onGenerate = function(entities, hex)
                local env = require("environment")
                local candidates = {}
                for _, e in ipairs(entities) do
                    if e.health and e.health > 0 and e:isCharacter() and not e.isPlayable and not e.isSummoningRod then
                        table.insert(candidates, e)
                    end
                end
                local leader
                if #candidates > 0 then
                    leader = candidates[love.math.random(1, #candidates)]
                else
                    leader = env.createRandomEnemy(-1, -1)
                    local cells = findEmptyCells(entities, hex)
                    if #cells > 0 then
                        local cell = cells[love.math.random(1, #cells)]
                        leader.q = cell.q
                        leader.r = cell.r
                        table.insert(entities, leader)
                    end
                end
                if leader then
                    leader.isLeader = true
                    leader.maxHealth = 4
                    leader.health = leader.maxHealth
                    leader.moveRange = leader.moveRange + 1
                    if leader.attacks then
                        for _, at in ipairs(leader.attacks) do
                            if at.attack and at.attack.damage then
                                at.attack.damage = at.attack.damage + 2
                            end
                        end
                    end
                    leader.name = "Leader " .. (leader.name or "Enemy")
                    print(string.format("Objective 'kill_leader': Leader created at (%d,%d) - %s", leader.q, leader.r, leader.name))
                end
            end,
            check = function(entities, state)
                local alive = false
                for _, e in ipairs(entities) do
                    if e.isLeader and e.health and e.health > 0 then
                        alive = true
                        break
                    end
                end
                if not alive then
                    state["kill_leader"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                local alive = false
                for _, e in ipairs(entities) do
                    if e.isLeader and e.health and e.health > 0 then
                        alive = true
                        break
                    end
                end
                state["kill_leader"] = alive and "failed" or "completed"
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
    activePrimaryObjective = nil
    objectiveStates = {}

    -- В режиме прогрессии kill_leader — основной босс (заменяет обычный primary)
    if _G.isProgressionRun then
        activePrimaryObjective = killLeaderDef
        objectiveStates[killLeaderDef.id] = "pending"
        if killLeaderDef.onGenerate then
            killLeaderDef.onGenerate(entities, hex)
        end
    else
        -- Choose primary: railway if map has train cars, otherwise caravans
        local primaryId = hasTrainCars(entities) and "protect_railway" or "protect_caravans"
        activePrimaryObjective = primaryObjectiveDefs[primaryId]
        objectiveStates[activePrimaryObjective.id] = "pending"
        if activePrimaryObjective.onGenerate then
            activePrimaryObjective.onGenerate(entities, hex)
        end
    end

    -- Pick 2 secondary objectives from pool
    local shuffled = shuffle(objectivePool)
    local count = 0
    local maxObj = 2

    -- Force-include the secondary linked to the primary
    local forcedId = activePrimaryObjective.forceSecondary
    if forcedId then
        for i = #shuffled, 1, -1 do
            if shuffled[i].id == forcedId then
                local def = table.remove(shuffled, i)
                table.insert(activeObjectives, def)
                objectiveStates[def.id] = "pending"
                if def.onGenerate then
                    def.onGenerate(entities, hex)
                end
                count = count + 1
                break
            end
        end
    end

    -- Mark incompatible secondaries based on primary
    local primaryIncompatible = activePrimaryObjective.incompatibleWithSecondary or {}

    for i = 1, #shuffled do
        if count >= maxObj then break end
        local def = shuffled[i]
        local skip = false

        -- Skip kill_leader from pool in progression mode (it's the primary boss)
        if not skip and _G.isProgressionRun and def.id == "kill_leader" then
            skip = true
        end

        -- Check incompatibility with primary objective
        if not skip and activePrimaryObjective then
            if def.incompatibleWithPrimary then
                print(string.format("Skipping '%s' due to incompatibility with primary objective '%s'", def.id, activePrimaryObjective.id))
                skip = true
            elseif primaryIncompatible then
                for _, pid in ipairs(primaryIncompatible) do
                    if pid == def.id then
                        print(string.format("Skipping '%s' due to incompatibility with primary '%s'", def.id, activePrimaryObjective.id))
                        skip = true
                        break
                    end
                end
            end
        end

        -- Check conflict with already selected secondaries
        if not skip then
            for _, existing in ipairs(activeObjectives) do
                if existing.incompatible then
                    for _, id in ipairs(existing.incompatible) do
                        if id == def.id then
                            skip = true
                            break
                        end
                    end
                end
                if not skip and def.incompatible then
                    for _, id in ipairs(def.incompatible) do
                        if id == existing.id then
                            skip = true
                            break
                        end
                    end
                end
                if skip then break end
            end
        end

        if skip then
            print(string.format("Skipping '%s' due to conflict with selected objectives", def.id))
        else
            table.insert(activeObjectives, def)
            objectiveStates[def.id] = "pending"
            if def.onGenerate then
                def.onGenerate(entities, hex)
            end
            count = count + 1
        end
    end

    print(string.format("Generated %d secondary objectives:", #activeObjectives))
    for _, obj in ipairs(activeObjectives) do
        print(string.format("  - %s (%s)", obj.name, obj.id))
    end
end

function objectives.reset()
    definePool()
    activeObjectives = {}
    activePrimaryObjective = nil
    objectiveStates = {}
    _G.objective_enemiesKilled = 0
    _G.objective_digBlocks = 0
    _G.caravanCount = 0
    _G.caravansDestroyed = 0
    _G.blockpostMaxHealth = 0
    _G.blockpostDamageTracked = 0
    _G.railwayTakenDamage = 0
end

function objectives.getList()
    return activeObjectives
end

function objectives.getPrimary()
    return activePrimaryObjective
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
    local count = #activeObjectives
    if activePrimaryObjective then count = count + 1 end
    return count
end

function objectives.getFailedCount()
    local count = 0
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "failed" then count = count + 1 end
    end
    return count
end

function objectives.update(entities)
    local decayApplied = _G.decayAppliedForTurnLimit or false

    -- Check primary objective every frame
    if activePrimaryObjective and objectiveStates[activePrimaryObjective.id] == "pending" then
        if activePrimaryObjective.check then
            activePrimaryObjective.check(entities, objectiveStates)
        end
        -- kill_leader (Power Lich босс) — завершение/поражение
        if activePrimaryObjective.id == "kill_leader" then
            local state = objectiveStates["kill_leader"]
            if state == "failed" then
                _G.loss = true
                _G.gameActive = false
                print("DEFEAT: Power Lich has slain a hero!")
            elseif state == "completed" then
                _G.win = true
                _G.gameActive = false
                print("VICTORY: Power Lich has been destroyed!")
            end
        end
    end

    -- Check secondary objectives
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "pending" then
            -- Certain objectives check immediately; others wait for decay
            local canCheck = decayApplied or obj.id == "protect_tower" or obj.id == "protect_blockpost"
            if canCheck and obj.check then
                local prevState = objectiveStates[obj.id]
                obj.check(entities, objectiveStates)
                if prevState == "pending" and objectiveStates[obj.id] == "failed" then
                    _G.chaos = (_G.chaos or 0) + 1
                    print(string.format("Objective '%s' failed! Chaos +1 (total: %d)", obj.id, _G.chaos))
                end
            end
        end
    end
end

function objectives.checkOnVictory(entities)
    if activePrimaryObjective and objectiveStates[activePrimaryObjective.id] == "pending" then
        objectiveStates[activePrimaryObjective.id] = "completed"
    end
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "pending" then
            if obj.checkOnVictory then
                obj.checkOnVictory(entities, objectiveStates)
            end
        end
    end
end

function objectives.draw()
    if not smallFont then smallFont = love.graphics.newFont(12) end
    local x = 10
    local y = 1070
    local w = 200
    local lineH = 16
    local padding = 6
    local titleH = 20
    local primaryH = activePrimaryObjective and (titleH + lineH + padding) or 0
    local secondaryH = (#activeObjectives > 0) and (titleH + #activeObjectives * lineH + padding) or 0
    local totalH = primaryH + secondaryH + padding

    if totalH <= padding then return end

    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", x, y, w, totalH, 5)
    love.graphics.setColor(0.4, 0.4, 0.6, 0.6)
    love.graphics.rectangle("line", x, y, w, totalH, 5)

    love.graphics.setFont(smallFont)
    local curY = y + padding

    -- Primary objective
    if activePrimaryObjective then
        love.graphics.setColor(0.9, 0.6, 0.2, 1)
        love.graphics.print("Primary", x + padding, curY)
        curY = curY + titleH
        local state = objectiveStates[activePrimaryObjective.id] or "pending"
        local icon, color
        if state == "failed" then
            icon = "\xc3\x97"
            color = {1, 0.4, 0.4, 1}
        else
            icon = "\xe2\x97\x8b"
            color = {0.9, 0.6, 0.2, 1}
        end
        love.graphics.setColor(unpack(color))
        love.graphics.print(icon .. " " .. activePrimaryObjective.name, x + padding, curY)
        curY = curY + lineH + padding
    end

    -- Secondary objectives
    if #activeObjectives > 0 then
        love.graphics.setColor(0.9, 0.9, 0.6, 1)
        love.graphics.print("Secondary", x + padding, curY)
        curY = curY + titleH

        for i, obj in ipairs(activeObjectives) do
            local sy = curY + (i - 1) * lineH
            local state = objectiveStates[obj.id] or "pending"
            local icon, color
            if state == "completed" then
                icon = "\xe2\x9c\x93"
                color = {0.4, 1, 0.4, 1}
            elseif state == "failed" then
                icon = "\xc3\x97"
                color = {1, 0.4, 0.4, 1}
            else
                icon = "\xe2\x97\x8b"
                color = {0.8, 0.8, 0.8, 1}
            end
            love.graphics.setColor(unpack(color))
            love.graphics.print(icon .. " " .. obj.name, x + padding, sy)
        end
    end
end

definePool()
return objectives