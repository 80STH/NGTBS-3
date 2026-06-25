-- game.lua
-- Game lifecycle: restart, end check, global effects.
-- Functions are global (used by other modules via _G).

local turnManager = require("core.turn_manager")
local objectives = require("system.objectives")
local trains = require("system.trains")
local Entity = require("entity.entity")
local log = require("util.log")

function endTurn()
    turnManager.endPlayerTurn()
end

function restartGame(mapPath)
    mapPath = mapPath or selectedMapPath or 'maps/map1.lua'
    selectedMapPath = mapPath
    log.infof("game", "=== RESTARTING GAME: %s ===", mapPath)

    -- Guarantee a clean turnState on every restart (previously for deploy maps
    -- it was not re-initialized, which could carry state from the previous game).
    turnState = {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false,
        caravansMoving = false,
    }

    local hexStatuses
    local deployableAllies

    -- Load native format map
    local mapData = love.filesystem.load(mapPath)()
    local mapActiveRadius, mapCenterQ, mapCenterR
    terrainMap, entities, width, height, hexStatuses, _, deployableAllies, orientation, upperTerrainMap = environment.loadNativeMap(mapData)
    mapActiveRadius = mapData and mapData.activeRadius or config.ACTIVE_RADIUS
    mapCenterQ = mapData and mapData.centerQ or math.floor(width / 2)
    mapCenterR = mapData and mapData.centerR or math.floor(height / 2)
    orientation = orientation or "pointy"

    hex = require("grid.hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        mapActiveRadius,
        mapCenterQ,
        mapCenterR,
        orientation
    )
    hex:centerOnScreen(love.graphics.getWidth() / dpiScale, love.graphics.getHeight() / dpiScale)
    hex.rotation = (orientation == "flat") and 0 or config.GRID_ROTATION_ANGLE

    status.initHexStatuses(hexStatuses)



    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.hasPreparedAttack = false
            e.preparePos = nil
            e.preparedTarget = nil
            e.movementFinished = false
            e.isMoving = false
            e.path = {}
            e.currentPathIndex = 0
        end
        if e.rootedTarget then
            status.removeFromEntity(e.rootedTarget, "rooted")
            e.rootedTarget = nil
        end
    end

    -- Map4: Power Lich boss + 4 pre-dug enemies
    if mapPath:match("map4") then
        local occupiedSet = {}
        for _, e in ipairs(entities) do
            local k = e.q .. "," .. e.r
            occupiedSet[k] = true
        end
        local candidates = {}
        for q = 0, width - 1 do
            for r = 0, height - 1 do
                if hex:isActiveHex(q, r) then
                    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                    if terrain ~= "water" and terrain ~= "underwater_mines" and not occupiedSet[q .. "," .. r] and not status.hasNegativeHexStatus(q, r) then
                        table.insert(candidates, {q = q, r = r})
                    end
                end
            end
        end
        for i = #candidates, 2, -1 do
            local j = love.math.random(i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end

        -- Place Power Lich
        if #candidates >= 1 then
            local cell = candidates[1]
            local lich = environment.createEnemyByType("PowerLich", cell.q, cell.r)
            lich.isLeader = true
            table.insert(entities, lich)
            log.debugf("game", "Power Lich placed at (%d,%d)", cell.q, cell.r)
        end

        -- Place 4 pre-dug enemies
        local enemyTypes = { "Zombie", "Ghost", "Lich", "Brute" }
        for i = 1, math.min(4, #candidates - 1) do
            local cell = candidates[i + 1]
            local etype = enemyTypes[(i - 1) % #enemyTypes + 1]
            local enemy = environment.createEnemyByType(etype, cell.q, cell.r)
            table.insert(entities, enemy)
            log.debugf("game", "Pre-dug %s placed at (%d,%d)", etype, cell.q, cell.r)
        end
    -- For map1, spawn 5 random enemies if none are present (user cleared the entity layer)
    elseif mapPath:match("map1%.lua$") then
        local occupiedSet = {}
        for _, e in ipairs(entities) do
            local k = e.q .. "," .. e.r
            occupiedSet[k] = true
        end
        local candidates = {}
        for q = 0, width - 1 do
            for r = 0, height - 1 do
                if hex:isActiveHex(q, r) then
                    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                    if terrain ~= "water" and terrain ~= "underwater_mines" and not occupiedSet[q .. "," .. r] and not status.hasNegativeHexStatus(q, r) then
                        table.insert(candidates, {q = q, r = r})
                    end
                end
            end
        end
        for i = #candidates, 2, -1 do
            local j = love.math.random(i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end
        local initialSpawn = 5
        local spawned = 0
        for _, cell in ipairs(candidates) do
            if spawned >= initialSpawn then break end
            local enemy = environment.createRandomEnemy(cell.q, cell.r)
            table.insert(entities, enemy)
            spawned = spawned + 1
            log.debugf("game", "Spawned random enemy %s at (%d,%d)", enemy.name, cell.q, cell.r)
        end
        log.debugf("game", "Spawned %d random enemies on map1", spawned)

        -- 50% chance to spawn SummoningRod
        if love.math.random() < 0.5 then
            local emptyCells = findRandomEmptyCells(1)
            if #emptyCells > 0 then
                local cell = emptyCells[1]
                local rod = environment.createEnemyByType("SummoningRod", cell.q, cell.r)
                table.insert(entities, rod)
                log.debugf("game", "SummoningRod spawned at (%d,%d) with 50%% chance", cell.q, cell.r)
            end
        end
    end

    -- Setup deploy phase
    local skipDeploy = mapPath:match("test_polygon_[12]")
    if selectedSquad then
        local squads = menu.getSquads()
        local squad = squads[selectedSquad]
        unplacedAllies = {}
        for _, unitDef in ipairs(squad.units) do
            table.insert(unplacedAllies, environment.createSquadUnit(unitDef, -1, -1))
        end
    else
        unplacedAllies = deployableAllies or {}
    end
    placedAllies = {}
    deploySelectedIdx = nil

    if not skipDeploy then
        for _, ally in ipairs(unplacedAllies) do
            ally.q = -1
            ally.r = -1
        end
    end

    selectedActor = nil
    hex.selectedQ = -1
    hex.selectedR = -1
    hex.hoverQ = -1
    hex.hoverR = -1

    global_abilities.initWithCommander(selectedCommander)
    global_abilities.reset()
    _G.squadHpBonus = 0
    _G.squadMoveBonus = 0
    _G.squadArmorBonus = 0
    dpiScale = love.window.getDPIScale()

    flipTargetActor = nil
    vortexTargetCell = nil
    pullHookTargetCell = nil
    pushDirTargetCell = nil
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
    undo.clear()
    pushAnimations = { queue = {}, active = false }
    visual.effects = {}
    decayMessageTimer = 0

    maxUndoCount = 0

    turnCount = 0
    gameActive = true
    win = false
    loss = false
    fireAppliedForTurnLimit = false
    decayAppliedForTurnLimit = false
    chaos = 0
    lichKilledPlayer = false
    status.clearAllDigSites()

    -- map3 train setup: inject tunnels and railway if needed
    if mapPath:match("map3") then
        local hasTunnels = false
        for _, e in ipairs(entities) do
            if e.name == "Tunnel" then hasTunnels = true; break end
        end
        if not hasTunnels then
            local envMod = require("entity.environment")
            local loadedMap = envMod.loadedMap
            local tileW = (loadedMap and loadedMap.tilewidth) or 14
            local tileH = (loadedMap and loadedMap.tileheight) or 12
            local tunnelData = {{2,2},{6,2},{2,6},{6,6}}
            local railCells = {{2,2},{3,2},{4,2},{5,2},{6,2},{2,6},{3,6},{4,6},{5,6},{6,6}}

            for _, cell in ipairs(railCells) do
                local q, r = cell[1], cell[2]
                if not terrainMap[q] then terrainMap[q] = {} end
                terrainMap[q][r] = "railway"
            end

            for _, td in ipairs(tunnelData) do
                local tunnel = Entity.new("Tunnel", Entity.TYPES.BUILDING, td[1], td[2], 2, false, 0, nil, nil, {})
                tunnel.isObjective = true
                tunnel.sprite = envMod.generateBuildingSprite("Tunnel", tileW, tileH)
                table.insert(entities, tunnel)
                log.debugf("game", "Placed Tunnel at (%d,%d)", td[1], td[2])
            end
        end
    end

    trains.init(entities, terrainMap, hex)
    objectives.reset()
    objectives.generate(entities, hex, mapData and mapData.objectives)
    objectives.update(entities)

    if skipDeploy then
        if selectedSquad then
            local idx = 0
            for q = 0, hex.gridWidth - 1 do
                for r = 0, hex.gridHeight - 1 do
                    if hex:isActiveHex(q, r) then
                        local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                        if terrain ~= "water" then
                            local occupied = false
                            for _, e in ipairs(entities) do
                                if e.q == q and e.r == r then occupied = true; break end
                            end
                            if not occupied then
                                idx = idx + 1
                                if idx <= #unplacedAllies then
                                    unplacedAllies[idx].q = q
                                    unplacedAllies[idx].r = r
                                else break end
                            end
                        end
                    end
                end
            end
        end
        for _, ally in ipairs(unplacedAllies) do
            table.insert(entities, ally)
        end
        unplacedAllies = {}
        placedAllies = {}
        selectedActor = nil
        for _, a in ipairs(entities) do
            if a.isPlayable and a.health > 0 then
                selectedActor = a
                hex.selectedQ, hex.selectedR = a.q, a.r
                break
            end
        end
        for _, a in ipairs(entities) do
            if a.isPlayable then
                a.hasActedThisTurn = false
                a.hasMovedThisTurn = false
            end
        end
        turnState = {
            phase = "enemy_prepare",
            enemyPrepareQueue = {},
            currentPreparingEnemy = nil,
            enemyAttackQueue = {},
            enemyAttackTimer = 0,
            delayBetweenAttacks = 0.4,
            pendingDigProcessing = false,
            caravansMoving = false,
        }
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.hasPreparedAttack = false
            e.preparePos = nil
            e.preparedTarget = nil
            e.movementFinished = false
            e.isMoving = false
            e.path = {}
            e.currentPathIndex = 0
        end
        if e.rootedTarget then
            status.removeFromEntity(e.rootedTarget, "rooted")
            e.rootedTarget = nil
        end
    end
    updateAttackButtons(selectedActor)
    maxUndoCount = countPlayableActors()
    updateAttackButtons(selectedActor)
    maxUndoCount = countPlayableActors()
    turnManager.startGame()
        gamePhase = "playing"
    else
        gamePhase = "deploy"
    end
    clearCellDuplicateWarnings()
    rebuildEntityIndex()
    syncState()
    log.infof("game", "=== MAP LOADED — %s ===", (skipDeploy and "GAME STARTED" or "DEPLOY YOUR ALLIES"))
end

function confirmDeploy()
    for _, ally in ipairs(placedAllies) do
        table.insert(entities, ally)
    end

    selectedActor = nil
    for _, a in ipairs(entities) do
        if a.isPlayable and a.health > 0 then
            selectedActor = a
            hex.selectedQ, hex.selectedR = a.q, a.r
            break
        end
    end

    for _, a in ipairs(entities) do
        if a.isPlayable then
            a.hasActedThisTurn = false
            a.hasMovedThisTurn = false
        end
    end

    turnState = {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false,
        caravansMoving = false,
    }

    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.hasPreparedAttack = false
            e.preparePos = nil
            e.preparedTarget = nil
            e.movementFinished = false
            e.isMoving = false
            e.path = {}
            e.currentPathIndex = 0
        end
        if e.rootedTarget then
            status.removeFromEntity(e.rootedTarget, "rooted")
            e.rootedTarget = nil
        end
    end

    updateAttackButtons(selectedActor)
    maxUndoCount = countPlayableActors()
    gameActive = true
    if rebuildEntityIndex then rebuildEntityIndex() end

    turnManager.startGame()
    gamePhase = "playing"

    unplacedAllies = {}
    placedAllies = {}
    deploySelectedIdx = nil

    syncState()
    log.info("game", "=== DEPLOY CONFIRMED — GAME STARTED ===")
end

function checkGameEnd()
    if not gameActive then return end

    if (chaos or 0) >= chaosMax then
        loss = true
        gameActive = false
        log.warn("game", "DEFEAT: Chaos has consumed the realm!")
        syncState()
        return
    end

    local anyEnemy = false
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isDying then
            anyEnemy = true
            break
        end
    end
    if not anyEnemy and decayAppliedForTurnLimit then
        win = true
        gameActive = false
        objectives.checkOnVictory(entities)
        log.info("game", "VICTORY: All enemies defeated after turn limit!")
        syncState()
        return
    end

    if turnCount >= maxTurns and not anyEnemy then
        win = true
        gameActive = false
        objectives.checkOnVictory(entities)
        log.info("game", "VICTORY: Turn limit reached and all enemies defeated!")
        syncState()
    end
end

function applyDecayToAllEnemies()
    log.debugf("game", "applyDecayToAllEnemies called, turnCount=%s maxTurns=%s", turnCount, maxTurns)
    local count = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            count = count + 1
            if not status.hasEntityStatus(e, "decay") then
                status.applyToEntity(e, "decay")
                log.debugf("game", "Decay afflicts %s", e.name)
            end
        end
    end
    log.debugf("game", "Total living enemies found: %d", count)
end

function updateDeathAnimations(dt)
    for i = #entities, 1, -1 do
        local e = entities[i]
        if e.isDying then
            e.deathTimer = e.deathTimer + dt
            if e.deathTimer >= e.deathDuration then
                if e.isTrainCar then
                    local trains_mod = require("system.trains")
                    local group = trains_mod.getCarGroup(e)
                    if group then
                        group.active = false
                        local loco = group.cars[1]
                        if loco then
                            loco.hasPreparedAttack = false
                            loco.isTrainAttack = nil
                        end
                    end
                end
                if e.name == "Tunnel" or e.name == "OccupiedTunnel" then
                    local dtunnel = Entity.new("DestroyedTunnel", Entity.TYPES.BUILDING, e.q, e.r, 1, false, 0, nil, nil, {})
                    dtunnel.indestructible = true
                    dtunnel.sprite = environment.generateBuildingSprite("DestroyedTunnel", hex.tileWidth, hex.tileHeight)
                    table.insert(entities, dtunnel)
                end
                if e.name == "MountainHouse" or e.name == "SmallMountainHouse" then
                    local ruined = Entity.new("RuinedMountainHouse", Entity.TYPES.BUILDING, e.q, e.r, 1, false, 0, nil, nil, {})
                    ruined.indestructible = true
                    ruined.sprite = environment.generateBuildingSprite("RuinedMountainHouse", hex.tileWidth, hex.tileHeight)
                    table.insert(entities, ruined)
                end

                -- Place upper_terrain rubble for destroyed buildings/obstacles
                if e:isObstacle() and not e.indestructible then
                    if not upperTerrainMap[e.q] then upperTerrainMap[e.q] = {} end
                    upperTerrainMap[e.q][e.r] = "mountain_rubble"
                elseif e:isBuilding() and not e.isTrainCar
                    and e.name ~= "Tunnel" and e.name ~= "OccupiedTunnel" then
                    if not upperTerrainMap[e.q] then upperTerrainMap[e.q] = {} end
                    upperTerrainMap[e.q][e.r] = "building_rubble"
                end

                table.remove(entities, i)
            end
        end
    end
end

function countPlayableActors()
    local count = 0
    for _, actor in ipairs(entities) do
        if actor.isPlayable then
            count = count + 1
        end
    end
    return count
end

-- ============================================================
-- GENERAL EVENT GENERATION (dig sites, lightning)
-- ============================================================

-- Finds N random empty (unoccupied, non-water) cells
function findRandomEmptyCells(count, excludeFn, qMin)
    qMin = qMin or 0
    local candidates = {}
    local candidatesBias = {}
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) then
                local occupied = false
                for _, e in ipairs(entities) do
                    if e.q == q and e.r == r then occupied = true; break end
                end
                if not occupied then
                    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                    if terrain ~= "water" and terrain ~= "underwater_mines" and terrain ~= "railway" then
                        if not excludeFn or not excludeFn(q, r) then
                            if q >= qMin then
                                table.insert(candidatesBias, {q = q, r = r})
                            else
                                table.insert(candidates, {q = q, r = r})
                            end
                        end
                    end
                end
            end
        end
    end
    -- Prefer biased cells, fill remainder from any cells
    local function shuffle(t)
        for i = #t, 2, -1 do local j = love.math.random(i); t[i], t[j] = t[j], t[i] end
        return t
    end
    shuffle(candidatesBias)
    shuffle(candidates)
    for _, c in ipairs(candidates) do table.insert(candidatesBias, c) end
    local result = {}
    for i = 1, math.min(count, #candidatesBias) do
        table.insert(result, candidatesBias[i])
    end
    return result
end

function processDigSites()
    for _, entity in ipairs(entities) do
        if entity.health > 0 and status.hasDigSite(entity.q, entity.r) then
            local wasDestroyed = entity:takeDamage(1)
            log.infof("game", "Dig site damage: %s takes 1 damage!", entity.name)
            sounds.play("collision")
            if wasDestroyed then
                entity:startDeath()
            end
            status.stepOnDigSite(entity.q, entity.r)
        end
    end

    for i = #entities, 1, -1 do
        if entities[i].health <= 0 and not status.hasEntityStatus(entities[i], "stasis") then
            local e = entities[i]
            if e:isObstacle() and not e.indestructible then
                if not upperTerrainMap[e.q] then upperTerrainMap[e.q] = {} end
                upperTerrainMap[e.q][e.r] = "mountain_rubble"
            elseif e:isBuilding() and not e.isTrainCar
                and e.name ~= "Tunnel" and e.name ~= "OccupiedTunnel" then
                if not upperTerrainMap[e.q] then upperTerrainMap[e.q] = {} end
                upperTerrainMap[e.q][e.r] = "building_rubble"
            end
            table.remove(entities, i)
        end
    end

    local readyDigs = status.decrementDigTimers()
    for _, dig in ipairs(readyDigs) do
        local canSpawn = not (state and state.disableEnemySpawn)
        if canSpawn then
            local occupied = false
            for _, e in ipairs(entities) do
                if e.q == dig.q and e.r == dig.r then
                    occupied = true
                    break
                end
            end
            local terrain = terrainMap and terrainMap[dig.q] and terrainMap[dig.q][dig.r] or "grass"
            if not occupied and terrain ~= "water" and terrain ~= "railway" and not status.hasNegativeHexStatus(dig.q, dig.r) then
                local newEnemy = environment.createRandomEnemy(dig.q, dig.r)
                table.insert(entities, newEnemy)
                local x, y = hex:hexToPixel(dig.q, dig.r)
                visual.addEffect(x, y, "dig", 0.5)
                sounds.play("dig")
                log.infof("game", "A %s digs out at (%d,%d)!", newEnemy.name, dig.q, dig.r)
            else
                log.debugf("game", "Dig site at (%d,%d) blocked, no spawn", dig.q, dig.r)
                _G.objective_digBlocks = (_G.objective_digBlocks or 0) + 1
            end
        else
            log.debugf("game", "Dig site at (%d,%d) suppressed by disableEnemySpawn", dig.q, dig.r)
            _G.objective_digBlocks = (_G.objective_digBlocks or 0) + 1
        end
        status.removeDigSite(dig.q, dig.r)
    end

    status.ageDigSites()

    if decayAppliedForTurnLimit then return end

    local aliveEnemies = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isSummoningRod then
            aliveEnemies = aliveEnemies + 1
        end
    end
    if not (state and state.disableEnemySpawn) then
        local spawnLimit = 7
        local needed = spawnLimit - aliveEnemies
        if needed > 0 then
            local spots = findRandomEmptyCells(needed, function(q, r)
                return status.hasDigSite(q, r) or status.hasNegativeHexStatus(q, r)
            end, 4)
            local digTypes = { "Ghost", "Zombie", "Lich" }
            for _, spot in ipairs(spots) do
                local spawnType = digTypes[love.math.random(1, #digTypes)]
                status.setDigSite(spot.q, spot.r, 1, spawnType)
                log.debugf("game", "New dig site at (%d,%d) -> %s", spot.q, spot.r, spawnType)
            end
        end
    end
end

-- ============================================================
-- LIGHTNING
-- ============================================================
lightningTargetQ = -1
lightningTargetR = -1
lightningWarning = false

function selectLightningTarget()
    lightningTargetQ = -1
    lightningTargetR = -1
    lightningWarning = false
    if not hex then return end

    local spots = findRandomEmptyCells(1)
    if #spots == 0 then return end

    local spot = spots[1]
    lightningTargetQ = spot.q
    lightningTargetR = spot.r
    lightningWarning = true
    log.debugf("game", "Lightning warning at (%d,%d)", spot.q, spot.r)
end

function strikeLightning()
    if lightningTargetQ < 0 or lightningTargetR < 0 then
        lightningWarning = false
        return
    end
    if not hex or not getDrawCoords then
        lightningWarning = false
        return
    end

    local tq, tr = lightningTargetQ, lightningTargetR
    local fx, fy = getDrawCoords(tq, tr)
    if visual and visual.addLightning then
        visual.addLightning(fx, fy, 0.3)
    end
    sounds.play("lightning")

    local target = getEntityAtHex(tq, tr)
    if target and target.health > 0 then
        local wasDestroyed = target:takeDamage(1)
        sounds.play("collision")
        if not wasDestroyed then
            status.applyToEntity(target, "empowered")
            log.infof("game", "Lightning strikes %s! 1 damage, Empowered applied", target.name)
        else
            target:startDeath()
            log.infof("game", "Lightning destroys %s!", target.name)
        end
    end

    lightningTargetQ = -1
    lightningTargetR = -1
    lightningWarning = false
end
