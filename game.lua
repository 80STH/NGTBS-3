-- game.lua
-- Жизненный цикл игры: рестарт, проверка конца, общие эффекты.
-- Функции — глобальные (используются другими модулями через _G).

local turnManager = require("turn_manager")
local objectives = require("objectives")

function endTurn()
    turnManager.endPlayerTurn()
end

function restartGame(mapPath)
    mapPath = mapPath or selectedMapPath or 'maps/map1.lua'
    selectedMapPath = mapPath
    print("=== RESTARTING GAME: " .. mapPath .. " ===")

    local hexStatuses
    local deployableAllies
    terrainMap, entities, width, height, hexStatuses, _, deployableAllies = environment.loadMapFromTiled(mapPath)

    hex = require("hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R
    )
    hex:centerOnScreen(love.graphics.getWidth() / dpiScale, love.graphics.getHeight() / dpiScale)

    status.initHexStatuses(hexStatuses)

    globalHealth = { current = 5, max = 5, initial = 5 }
    combat.globalHealth = globalHealth

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
    end

    -- For map1, spawn 5 random enemies if none are present (user cleared the entity layer)
    if mapPath:match("map1%.lua$") then
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
                    if terrain ~= "water" and not occupiedSet[q .. "," .. r] then
                        table.insert(candidates, {q = q, r = r})
                    end
                end
            end
        end
        for i = #candidates, 2, -1 do
            local j = love.math.random(i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end
        local spawned = 0
        for _, cell in ipairs(candidates) do
            if spawned >= 5 then break end
            local enemy = environment.createRandomEnemy(cell.q, cell.r)
            table.insert(entities, enemy)
            spawned = spawned + 1
            print(string.format("  Spawned random enemy %s at (%d,%d)", enemy.name, cell.q, cell.r))
        end
        print(string.format("Spawned %d random enemies on map1", spawned))
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

    global_abilities.reset()
    dpiScale = love.window.getDPIScale()

    flipTargetActor = nil
    vortexTargetCell = nil
    pullHookTargetCell = nil
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
    actionHistory = {}
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
    status.clearAllDigSites()

    objectives.reset()
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
        end
        updateAttackButtons(selectedActor)
        maxUndoCount = countPlayableActors()
        turnManager.startGame()
        gamePhase = "playing"
    else
        gamePhase = "deploy"
    end
    syncGlobalsToState()
    print(skipDeploy and "=== MAP LOADED — GAME STARTED ===" or "=== MAP LOADED — DEPLOY YOUR ALLIES ===")
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
    end

    updateAttackButtons(selectedActor)
    maxUndoCount = countPlayableActors()
    gameActive = true

    turnManager.startGame()
    gamePhase = "playing"

    unplacedAllies = {}
    placedAllies = {}
    deploySelectedIdx = nil

    syncGlobalsToState()
    print("=== DEPLOY CONFIRMED — GAME STARTED ===")
end

function checkGameEnd()
    if not gameActive then return end

    if globalHealth.current <= 0 then
        loss = true
        gameActive = false
        print("DEFEAT: Global health depleted!")
        syncGlobalsToState()
        return
    end

    local anyAlly = false
    for _, e in ipairs(entities) do
        if e.isPlayable and e.health > 0 and not e.isDying then
            anyAlly = true
            break
        end
    end
    if not anyAlly then
        loss = true
        gameActive = false
        print("DEFEAT: All allies destroyed!")
        syncGlobalsToState()
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
        print("VICTORY: All enemies defeated after turn limit!")
        syncGlobalsToState()
        return
    end

    if turnCount >= maxTurns and not anyEnemy then
        win = true
        gameActive = false
        objectives.checkOnVictory(entities)
        print("VICTORY: Turn limit reached and all enemies defeated!")
        syncGlobalsToState()
    end
end

function applyDecayToAllEnemies()
    print("applyDecayToAllEnemies called, turnCount=", turnCount, "maxTurns=", maxTurns)
    local count = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            count = count + 1
            if not status.hasEntityStatus(e, "decay") then
                status.applyToEntity(e, "decay")
                print("Decay afflicts " .. e.name)
            end
        end
    end
    print("Total living enemies found:", count)
end

function updateDeathAnimations(dt)
    for i = #entities, 1, -1 do
        local e = entities[i]
        if e.isDying then
            e.deathTimer = e.deathTimer + dt
            if e.deathTimer >= e.deathDuration then
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
-- ОБЩАЯ ГЕНЕРАЦИЯ СОБЫТИЙ (выкопки, молнии)
-- ============================================================

-- Находит N случайных пустых (не занятых, не вода) клеток
function findRandomEmptyCells(count, excludeFn)
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
                    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                    if terrain ~= "water" then
                        if not excludeFn or not excludeFn(q, r) then
                            table.insert(candidates, {q = q, r = r})
                        end
                    end
                end
            end
        end
    end
    for i = #candidates, 2, -1 do
        local j = love.math.random(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end
    local result = {}
    for i = 1, math.min(count, #candidates) do
        table.insert(result, candidates[i])
    end
    return result
end

function processDigSites()
    for _, entity in ipairs(entities) do
        if entity.health > 0 and status.hasDigSite(entity.q, entity.r) then
            local wasDestroyed = entity:takeDamage(1, globalHealth)
            print(string.format("Dig site damage: %s takes 1 damage!", entity.name))
            if sounds and sounds.collision then sounds.collision:play() end
            if wasDestroyed then
                entity:startDeath()
            end
            status.stepOnDigSite(entity.q, entity.r)
        end
    end

    for i = #entities, 1, -1 do
        if entities[i].health <= 0 then
            table.remove(entities, i)
        end
    end

    local readyDigs = status.decrementDigTimers()
    for _, dig in ipairs(readyDigs) do
        local occupied = false
        for _, e in ipairs(entities) do
            if e.q == dig.q and e.r == dig.r then
                occupied = true
                break
            end
        end
        local terrain = terrainMap and terrainMap[dig.q] and terrainMap[dig.q][dig.r] or "grass"
        if not occupied and terrain ~= "water" and not status.hasNegativeHexStatus(dig.q, dig.r) then
            local newEnemy = environment.createRandomEnemy(dig.q, dig.r)
            table.insert(entities, newEnemy)
            local x, y = hex:hexToPixel(dig.q, dig.r)
            visual.addEffect(x, y, "dig", 0.5)
            print(string.format("A %s digs out at (%d,%d)!", newEnemy.name, dig.q, dig.r))
        else
            print(string.format("Dig site at (%d,%d) blocked, no spawn", dig.q, dig.r))
        end
        status.removeDigSite(dig.q, dig.r)
    end

    status.ageDigSites()

    if decayAppliedForTurnLimit then return end

    local aliveEnemies = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            aliveEnemies = aliveEnemies + 1
        end
    end
    local needed = 7 - aliveEnemies
    if needed > 0 then
        local spots = findRandomEmptyCells(needed, function(q, r)
            return status.hasDigSite(q, r) or status.hasNegativeHexStatus(q, r)
        end)
        for _, spot in ipairs(spots) do
            local types = { "Ghost", "Zombie", "Lich" }
            local spawnType = types[love.math.random(1, #types)]
            status.setDigSite(spot.q, spot.r, 1, spawnType)
            print(string.format("New dig site at (%d,%d) -> %s", spot.q, spot.r, spawnType))
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
    print(string.format("Lightning warning at (%d,%d)", spot.q, spot.r))
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

    local target = getEntityAtHex(tq, tr)
    if target and target.health > 0 then
        local wasDestroyed = target:takeDamage(2, globalHealth)
        if sounds and sounds.collision then sounds.collision:play() end
        if not wasDestroyed then
            status.applyToEntity(target, "empowered")
            print("Lightning strikes " .. target.name .. "! 2 damage, Empowered applied")
        else
            target:startDeath()
            print("Lightning destroys " .. target.name .. "!")
        end
    end

    lightningTargetQ = -1
    lightningTargetR = -1
    lightningWarning = false
end
