local Entity = require("entity.entity")
local log = require("util.log")
local status = require("system.status")
local env = require("entity.environment")
local fonts = require("util.fonts")
local combat = require("combat.combat")
local icon_cache = require("ui.icon_cache")

local objectives = {}

-- Solo mode: chaos sources drain the hero's health instead of the chaos meter.
local function addChaos(amount, msg)
    if _G.soloMode and _G.damageHero then
        _G.damageHero(amount)
        return
    end
    _G.chaos = (_G.chaos or 0) + amount
    log.infof("objectives", msg .. " Chaos +%d (total: %d)", amount, _G.chaos)
end

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
            _G.caravansDestroyed = dead
            for i = 1, dead - prevDead do
                log.infof("objectives", "Caravan destroyed! (total dead: %d)", dead)
            end
        end
    end,
    progress = function()
        local alive = 0
        for _, e in ipairs(_G.entities or {}) do
            if e.name == "Caravan" and e.health and e.health > 0 then
                alive = alive + 1
            end
        end
        return tostring(alive) .. "/" .. tostring(_G.caravanCount or 0)
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
            if (e.name == "TunnelEntrance" or e.name == "TunnelExit") and e.health and e.maxHealth then
                totalDamage = totalDamage + (e.maxHealth - math.max(0, e.health))
            end
        end
        local prev = _G.railwayTakenDamage or 0
        if totalDamage > prev then
            local newDamage = totalDamage - prev
            addChaos(newDamage, "Railway infrastructure damaged!")
            _G.railwayTakenDamage = totalDamage
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
            addChaos(destroyed * 2, "Occupied tunnel destroyed!")
        end
        _G.occupiedTunnelCount = aliveOcc
    end,
    progress = function()
        return tostring(_G.railwayTakenDamage or 0) .. " dmg"
    end,
}

primaryObjectiveDefs.protect_buildings = {
    id = "protect_buildings",
    name = "Protect Buildings",
    desc = "Every damage to buildings increases Chaos!",
    isPrimary = true,
    incompatibleWithSecondary = { "protect_tower", "protect_blockpost" },
    onGenerate = function(entities, hex)
        _G.buildingDamageTracked = 0
    end,
    check = function(entities, state)
        local totalDamage = 0
        for _, e in ipairs(entities) do
            if e:isBuilding() and not e.isTrainCar and e.name ~= "Caravan" and e.name ~= "TunnelEntrance" and e.name ~= "TunnelExit" and e.name ~= "OccupiedTunnel" and e.health and e.maxHealth then
                totalDamage = totalDamage + (e.maxHealth - math.max(0, e.health))
            end
        end
        local prev = _G.buildingDamageTracked or 0
        if totalDamage > prev then
            _G.buildingDamageTracked = totalDamage
            log.infof("objectives", "Buildings damaged! (total: %d)", totalDamage)
        end
    end,
    progress = function()
        return tostring(_G.buildingDamageTracked or 0) .. " dmg"
    end,
}

local function hasTrainCars(entities)
    for _, e in ipairs(entities) do
        if e.name == "TrainCar" or e.name == "Locomotive" then return true end
    end
    return false
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

local killLeaderDef = {
    id = "kill_leader",
    name = "Destroy the Leader",
    desc = "Find and eliminate the enemy leader!",
    onGenerate = function(entities, hex)
        -- Power Lich already placed in game.lua — just mark it
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.name == "PowerLich" then
                e.isLeader = true
                log.debugf("objectives", "Objective 'kill_leader': PowerLich found at (%d,%d)", e.q, e.r)
                break
            end
        end
    end,
    check = function(entities, state)
        local leaderAlive = false
        for _, e in ipairs(entities) do
            if e.isLeader and e.health and e.health > 0 then
                leaderAlive = true
                break
            end
        end
        if _G.lichKilledPlayer then
            state["kill_leader"] = "failed"
        elseif not leaderAlive then
            state["kill_leader"] = "completed"
        end
    end,
}

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
                            addChaos(newDamage, "Blockpost damaged!")
                            _G.blockpostDamageTracked = damageTaken
                        end
                        return
                    end
                end
            end,
            checkOnVictory = function(entities, state)
                state["protect_blockpost"] = "completed"
            end,
            progress = function()
                for _, e in ipairs(_G.entities or {}) do
                    if e.name == "Blockpost" and e.maxHealth then
                        return tostring(math.max(0, e.health or 0)) .. "/" .. tostring(e.maxHealth)
                    end
                end
                return nil
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
                        local cells = findRandomEmptyCells(1, function(q, r) return status.hasNegativeHexStatus(q, r) end, 4)
                        if #cells > 0 then
                            local cell = cells[1]
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
                        if e.health and e.health > 0 and combat.isPoisonousEnemy(e) then
                            hasZombie = true
                            break
                        end
                    end
                end
                if not hasZombie then
                    local cells = findRandomEmptyCells(1, function(q, r) return status.hasNegativeHexStatus(q, r) end)
                    if #cells > 0 then
                        local cell = cells[1]
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
                local status_mod = require("system.status")
                for _, e in ipairs(entities) do
                    if e.health and e.health > 0 and combat.isPoisonousEnemy(e) then
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
            progress = function()
                return tostring(_G.objective_enemiesKilled or 0) .. "/7"
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
            progress = function()
                return tostring(_G.objective_digBlocks or 0) .. "/2"
            end,
        },
        -- Hero-exclusive objectives (solo mode): only offered when the hero
        -- has the required capabilities (see solo_mode.lua hero `tags`).
        {
            id = "burn_sites",
            name = "Scorched Earth",
            desc = "Ignite 5 different cells",
            heroOnly = true,
            requires = {"fire"},
            onGenerate = function(entities, hex)
                _G.objective_burnCells = {}
                _G.objective_burnSites = 0
            end,
            check = function(entities, state)
                local n = 0
                for _ in pairs(_G.objective_burnCells or {}) do n = n + 1 end
                if n >= 5 then
                    state["burn_sites"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                local n = 0
                for _ in pairs(_G.objective_burnCells or {}) do n = n + 1 end
                state["burn_sites"] = (n >= 5) and "completed" or "failed"
            end,
            progress = function()
                local n = 0
                for _ in pairs(_G.objective_burnCells or {}) do n = n + 1 end
                return tostring(n) .. "/5"
            end,
        },
        {
            id = "burn_kill",
            name = "Burn Them",
            desc = "Kill 2 enemies with fire damage",
            heroOnly = true,
            requires = {"fire"},
            onGenerate = function(entities, hex)
                _G.objective_burnKills = 0
            end,
            check = function(entities, state)
                if (_G.objective_burnKills or 0) >= 2 then
                    state["burn_kill"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                state["burn_kill"] = ((_G.objective_burnKills or 0) >= 2) and "completed" or "failed"
            end,
            progress = function()
                return tostring(_G.objective_burnKills or 0) .. "/2"
            end,
        },
        {
            id = "fatal_push",
            name = "Deadly Push",
            desc = "Kill an enemy with push damage",
            heroOnly = true,
            requires = {"push"},
            onGenerate = function(entities, hex)
                _G.objective_fatalPushes = 0
            end,
            check = function(entities, state)
                if (_G.objective_fatalPushes or 0) >= 1 then
                    state["fatal_push"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                state["fatal_push"] = ((_G.objective_fatalPushes or 0) >= 1) and "completed" or "failed"
            end,
            progress = function()
                return tostring(_G.objective_fatalPushes or 0) .. "/1"
            end,
        },
        {
            id = "all_attacks",
            name = "Full Arsenal",
            desc = "Use every hero attack in battle",
            heroOnly = true,
            onGenerate = function(entities, hex)
                _G.objective_usedAttacks = {}
            end,
            check = function(entities, state)
                local hero = _G.hero
                local used = 0
                for _ in pairs(_G.objective_usedAttacks or {}) do used = used + 1 end
                if hero and #hero.attacks > 0 and used >= #hero.attacks then
                    state["all_attacks"] = "completed"
                end
            end,
            checkOnVictory = function(entities, state)
                local hero = _G.hero
                local used = 0
                for _ in pairs(_G.objective_usedAttacks or {}) do used = used + 1 end
                state["all_attacks"] = (hero and #hero.attacks > 0 and used >= #hero.attacks)
                    and "completed" or "failed"
            end,
            progress = function()
                local hero = _G.hero
                local used = 0
                for _ in pairs(_G.objective_usedAttacks or {}) do used = used + 1 end
                if hero and #hero.attacks > 0 then
                    return tostring(used) .. "/" .. tostring(#hero.attacks)
                end
                return nil
            end,
        },
        {
            id = "kill_leader",
            name = "Destroy the Leader",
            desc = "Find and eliminate the enemy leader!",
            onGenerate = function(entities, hex)
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
                    local cells = findRandomEmptyCells(1, function(q, r) return status.hasNegativeHexStatus(q, r) end)
                    if #cells > 0 then
                        local cell = cells[1]
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
                    log.debugf("objectives", "Objective 'kill_leader': Leader created at (%d,%d) - %s", leader.q, leader.r, leader.name)
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

function objectives.generate(entities, hex, forcedObjectives)
    definePool()
    activeObjectives = {}
    activePrimaryObjective = nil
    objectiveStates = {}

    -- Hero-exclusive objectives: only offer what the selected hero can do
    local heroTags = {}
    if _G.soloMode and _G.selectedSoloHero then
        local hdef = env.getSoloHeroDef(_G.selectedSoloHero)
        if hdef and hdef.tags then
            for _, t in ipairs(hdef.tags) do
                heroTags[t] = true
            end
        end
    end

    -- Primary selection: forced > map4 auto > content-based auto
    local isMap4 = _G.selectedMapPath and _G.selectedMapPath:match("map4")
    if forcedObjectives and forcedObjectives.primary then
        if forcedObjectives.primary == "kill_leader" then
            activePrimaryObjective = killLeaderDef
        else
            activePrimaryObjective = primaryObjectiveDefs[forcedObjectives.primary]
        end
        if activePrimaryObjective then
            objectiveStates[activePrimaryObjective.id] = "pending"
            if activePrimaryObjective.onGenerate then
                activePrimaryObjective.onGenerate(entities, hex)
            end
            log.infof("objectives", "Primary objective '%s' set from map config", activePrimaryObjective.id)
        else
            activePrimaryObjective = nil
        end
    elseif isMap4 then
        activePrimaryObjective = killLeaderDef
        objectiveStates[killLeaderDef.id] = "pending"
        if killLeaderDef.onGenerate then
            killLeaderDef.onGenerate(entities, hex)
        end
        log.info("objectives", "kill_leader set as primary objective on map4")
    else
        local primaryId = hasTrainCars(entities) and "protect_railway" or "protect_caravans"
        activePrimaryObjective = primaryObjectiveDefs[primaryId]
        objectiveStates[activePrimaryObjective.id] = "pending"
        if activePrimaryObjective.onGenerate then
            activePrimaryObjective.onGenerate(entities, hex)
        end
    end

    -- Secondary selection: forced from map config > auto pool
    local count = 0
    local maxObj = 2

    if forcedObjectives and forcedObjectives.secondaries and #forcedObjectives.secondaries > 0 then
        for _, secId in ipairs(forcedObjectives.secondaries) do
            if count >= maxObj then break end
            local def = nil
            if secId == "kill_leader" then
                def = killLeaderDef
            else
                for _, poolDef in ipairs(objectivePool) do
                    if poolDef.id == secId then
                        def = poolDef
                        break
                    end
                end
            end
            if def then
                table.insert(activeObjectives, def)
                objectiveStates[def.id] = "pending"
                if def.onGenerate then
                    def.onGenerate(entities, hex)
                end
                count = count + 1
                log.debugf("objectives", "Forced secondary objective '%s' from map config", def.id)
            end
        end
    else
        -- Auto-pick from pool
        local shuffled = shuffle(objectivePool)

        -- Force-include the secondary linked to the primary
        local forcedId = activePrimaryObjective and activePrimaryObjective.forceSecondary
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
        local primaryIncompatible = activePrimaryObjective and activePrimaryObjective.incompatibleWithSecondary or {}

        for i = 1, #shuffled do
            if count >= maxObj then break end
            local def = shuffled[i]
            local skip = false

            -- Hero-exclusive: skip in non-solo modes or when the hero lacks the tags
            if not skip and def.heroOnly then
                if not _G.soloMode then
                    skip = true
                elseif def.requires then
                    for _, t in ipairs(def.requires) do
                        if not heroTags[t] then
                            log.debugf("objectives", "Skipping '%s' — hero lacks '%s' capability", def.id, t)
                            skip = true
                            break
                        end
                    end
                end
            end

            if not skip and def.id == "kill_leader" then
                skip = true
            end

            if not skip and activePrimaryObjective then
                if def.incompatibleWithPrimary then
                    log.debugf("objectives", "Skipping '%s' due to incompatibility with primary objective '%s'", def.id, activePrimaryObjective.id)
                    skip = true
                elseif primaryIncompatible then
                    for _, pid in ipairs(primaryIncompatible) do
                        if pid == def.id then
                            log.debugf("objectives", "Skipping '%s' due to incompatibility with primary '%s'", def.id, activePrimaryObjective.id)
                            skip = true
                            break
                        end
                    end
                end
            end

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
                log.debugf("objectives", "Skipping '%s' due to conflict with selected objectives", def.id)
            else
                table.insert(activeObjectives, def)
                objectiveStates[def.id] = "pending"
                if def.onGenerate then
                    def.onGenerate(entities, hex)
                end
                count = count + 1
            end
        end
    end

    log.debugf("objectives", "Generated %d secondary objectives:", #activeObjectives)
    for _, obj in ipairs(activeObjectives) do
        log.debugf("objectives", "  - %s (%s)", obj.name, obj.id)
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
    _G.objective_burnCells = {}
    _G.objective_burnSites = 0
    _G.objective_burnKills = 0
    _G.objective_fatalPushes = 0
    _G.objective_usedAttacks = {}
    _G.caravansDestroyed = 0
    _G.blockpostMaxHealth = 0
    _G.blockpostDamageTracked = 0
    _G.railwayTakenDamage = 0
    _G.buildingDamageTracked = 0
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

-- Tracking string for an objective (e.g. "3/7" for slaughter), or nil when
-- the objective is binary and needs no counter.
function objectives.getProgress(obj)
    if obj and obj.progress then
        return obj.progress()
    end
    return nil
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
        -- kill_leader (Power Lich boss) — completion/defeat
        if activePrimaryObjective.id == "kill_leader" then
            local state = objectiveStates["kill_leader"]
            if state == "failed" then
                _G.loss = true
                _G.gameActive = false
                log.warn("objectives", "DEFEAT: Power Lich has slain a hero!")
            elseif state == "completed" and decayApplied then
                _G.win = true
                _G.gameActive = false
                log.warn("objectives", "VICTORY: Power Lich has been destroyed!")
            end
        end
    end

    -- Check secondary objectives
    for _, obj in ipairs(activeObjectives) do
        if objectiveStates[obj.id] == "pending" then
            -- Certain objectives check immediately (achievements that flip the
            -- moment their condition is met); others wait for decay (turn-limit
            -- "before decay" goals). fatal_push / burn_kill / burn_sites /
            -- all_attacks are pure kill/use achievements -> live detection.
            local canCheck = decayApplied
                or obj.id == "protect_tower"
                or obj.id == "protect_blockpost"
                or obj.id == "burn_sites"
                or obj.id == "burn_kill"
                or obj.id == "fatal_push"
                or obj.id == "all_attacks"
            if canCheck and obj.check then
                local prevState = objectiveStates[obj.id]
                obj.check(entities, objectiveStates)
                if prevState == "pending" and objectiveStates[obj.id] == "failed" then
                    addChaos(1, "Objective '" .. obj.id .. "' failed!")
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

function objectives.saveState()
    local saved = {}
    for id, state in pairs(objectiveStates) do
        saved[id] = state
    end
    return saved
end

function objectives.restoreState(saved)
    objectiveStates = {}
    if saved then
        for id, state in pairs(saved) do
            objectiveStates[id] = state
        end
    end
end

-- Height of the objectives panel (0 when it would be empty), for stacking UI below it
function objectives.getPanelHeight()
    local lineH = 16
    local padding = 6
    local count = 0
    if activePrimaryObjective then count = count + 1 end
    count = count + #activeObjectives
    if count == 0 then return 0 end
    return padding * 2 + count * lineH
end

function objectives.draw()
    if not smallFont then smallFont = fonts.get(12) end
    local x = 10
    local y = 46
    local w = 200
    local lineH = 16
    local padding = 6
    local totalH = objectives.getPanelHeight()

    if totalH == 0 then return end

    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", x, y, w, totalH, 5)
    love.graphics.setColor(0.4, 0.4, 0.6, 0.6)
    love.graphics.rectangle("line", x, y, w, totalH, 5)

    love.graphics.setFont(smallFont)
    local curY = y + padding

    local function drawObjective(obj, isPrimary)
        local state = objectiveStates[obj.id] or "pending"
        local iconKey, txtColor
        -- A state equals "completed" only for objectives that can actually be
        -- cleared (kill/collect types resolve to completed; protect-types do too,
        -- on victory). Completed -> green, failed -> red, in-progress -> neutral.
        if state == "completed" then
            iconKey = "check"
            txtColor = {0.35, 1, 0.35}
        elseif state == "failed" then
            iconKey = "cross"
            txtColor = {1, 0.45, 0.45}
        else
            iconKey = "circle"
            txtColor = isPrimary and {0.9, 0.65, 0.2} or {0.92, 0.92, 0.92}
        end
        local name = obj.name or obj.id or ""
        -- Reserve room for a right-aligned progress counter.
        local prog = objectives.getProgress(obj)
        local rightW = prog and (smallFont:getWidth(prog) + 4) or 0
        local maxNameW = w - padding * 2 - rightW - 22 -- icon + space
        while name ~= "" and smallFont:getWidth(name) > maxNameW do
            name = name:sub(1, -2)
        end
        if name ~= (obj.name or obj.id or "") then name = name .. "…" end
        local nameX = x + padding
        if icon_cache and icon_cache.get(iconKey) then
            icon_cache.drawSmall(iconKey, nameX + 7, curY + lineH / 2, 14, 1, txtColor)
            nameX = nameX + 16
        end
        -- drawSmall resets to white; re-apply the status color to the name.
        love.graphics.setColor(txtColor[1], txtColor[2], txtColor[3], 1)
        love.graphics.print(name, nameX, curY)
        if prog then
            love.graphics.setColor(0.7, 0.7, 0.8, 1)
            love.graphics.print(prog, x + w - padding - smallFont:getWidth(prog), curY)
        end
        curY = curY + lineH
    end

    -- Primary objective (if any)
    if activePrimaryObjective then
        drawObjective(activePrimaryObjective, true)
    end

    -- Secondary objectives
    for _, obj in ipairs(activeObjectives) do
        drawObjective(obj, false)
    end
end

function objectives.getAvailablePrimaries()
    local list = {}
    for id, def in pairs(primaryObjectiveDefs) do
        table.insert(list, { id = id, name = def.name })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

function objectives.getAvailableSecondaries()
    local list = {}
    for _, def in ipairs(objectivePool) do
        table.insert(list, { id = def.id, name = def.name })
    end
    return list
end

definePool()
return objectives
