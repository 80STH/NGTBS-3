-- turn_manager.lua
-- State machine for turn phases (enemy_prepare / player / enemy_attack).
-- Uses globals (entities, hex, turnState, sounds, terrainMap).

local turnManager = {}
local log = require("util.log")

function turnManager.startGame()
    processDigSites()

    turnState.phase = "enemy_prepare"
    local enemies = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            table.insert(enemies, e)
        end
    end
    turnState.enemyPrepareQueue = enemies
    turnState.currentPreparingEnemy = nil
    turnState.enemyAttackQueue = {}
    turnState.enemyAttackTimer = 0
    turnState.pendingDigProcessing = false
    processNextEnemyPrepare()
end

function turnManager.endPlayerTurn()
    if turnState.phase ~= "player" then return end

    for _, a in ipairs(entities) do
        if a.isPlayable and not a.hasActedThisTurn then
            a.hasActedThisTurn = true
        end
    end

    strikeLightning()
    checkGameEnd()

    effects.applyEndOfTurnEffects(entities, terrainMap)
    checkGameEnd()

    if turnCount >= maxTurns and not decayAppliedForTurnLimit then
        applyDecayToAllEnemies()
        decayAppliedForTurnLimit = true
        decayMessageTimer = 2.0
        status.clearAllDigSites()
    end

    -- Prepare train attacks for this turn
    local trains_mod = require("system.trains")
    trains_mod.prepareTrainAttacks(entities, hex)

    -- Queue enemy attacks
    local attackers = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 and not e.isDying then
            table.insert(attackers, e)
        end
    end

    -- Add train attacks LAST in queue
    local trainGroups = trains_mod.getTrainGroups()
    for _, group in pairs(trainGroups) do
        if group.active and group.cars and #group.cars > 0 then
            local loco = group.cars[1]
            if loco and loco.health and loco.health > 0 and not loco.isDying and loco.hasPreparedAttack then
                table.insert(attackers, loco)
            end
        end
    end

    turnState.enemyAttackQueue = attackers
    turnState.enemyAttackTimer = 0
    turnState.phase = "enemy_attack"
    turnState.pendingDigProcessing = true
    turnState.trainShuntInProgress = false
    log.info("turn", "=== ENEMY ATTACK PHASE ===")
end

function turnManager.update(dt)
    if turnState.phase == "enemy_prepare" then
        updatePreparePhase(dt)
    elseif turnState.phase == "enemy_attack" then
        updateAttackPhase(dt)
    end
end

function updatePreparePhase(dt)
    if not turnState.currentPreparingEnemy then return end

    local enemy = turnState.currentPreparingEnemy
    if not enemy or enemy.health <= 0 then
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    elseif not enemy.isMoving and enemy.movementFinished then
        if not enemy.hasPreparedAttack then
            if ai.canPrepareAttack(enemy, entities) then
                ai.prepareAttackForEnemy(enemy, entities, hex)
            end
        end
        enemy.movementFinished = false
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    elseif not enemy.isMoving and not enemy.movementFinished then
        if not enemy.hasPreparedAttack then
            if ai.canPrepareAttack(enemy, entities) then
                ai.prepareAttackForEnemy(enemy, entities, hex)
            end
        end
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    end
end

function updateAttackPhase(dt)
    -- If a train shunt animation is in progress, update it
    if turnState.trainShuntInProgress then
        local trains_mod = require("system.trains")
        trains_mod.updateMovement(dt)
        if not trains_mod.isAnyAnimating() then
            turnState.trainShuntInProgress = false
            turnState.currentTrainLoco = nil
            checkGameEnd()
        end
        return
    end

    if #turnState.enemyAttackQueue == 0 then
        if turnState.pendingDigProcessing then
            processDigSites()
            turnState.pendingDigProcessing = false
        end
        turnCount = turnCount + 1
        log.infof("turn", "Turn count increased to: %s/%s", turnCount, maxTurns)
        turnState.phase = "enemy_prepare"
        startEnemyPreparePhase()
        return
    end

    turnState.enemyAttackTimer = turnState.enemyAttackTimer + dt
    if turnState.enemyAttackTimer >= turnState.delayBetweenAttacks then
        turnState.enemyAttackTimer = 0
        local enemy = table.remove(turnState.enemyAttackQueue, 1)
        if enemy and enemy.health > 0 then
            if enemy.isTrainAttack then
                local trains_mod = require("system.trains")
                turnState.trainShuntInProgress = true
                turnState.currentTrainLoco = enemy
                trains_mod.executeTrainShunt(enemy, entities, hex, function()
                end)
            else
                ai.executePreparedAttack(enemy, entities, hex, sounds)
            end
            if not enemy.isTrainAttack then
                checkGameEnd()
            end
        end
    end
end

function processNextEnemyPrepare()
    if #turnState.enemyPrepareQueue == 0 then
        turnState.phase = "player"
        sounds.play("turn_start")
        for _, a in ipairs(entities) do
            if a.isPlayable then
                if a.health > 0 then
                    a.hasActedThisTurn = false
                    a.hasMovedThisTurn = false
                    a.canMoveAfterAttack = false
                    a.chainAttack = nil
                    a.redirectPending = nil
                end
            end
        end
        undo.clear()
        undo.snapshot()
        global_abilities.abilityUsedThisTurn = false
        selectLightningTarget()
        log.info("turn", "=== PLAYER TURN ===")
        return
    end

    local enemy = table.remove(turnState.enemyPrepareQueue, 1)
    turnState.currentPreparingEnemy = enemy
    enemy.movementFinished = false

    local status = ai.moveAndPrepare(enemy, entities, hex)
    if status == "prepared" then
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    elseif status == "failed" then
        log.debug("turn", enemy.name .. " cannot prepare attack, skipping")
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    elseif status == "moving" then
    end
end

function moveCaravans()
    local hex = _G.hex
    if not hex then return end
    local caravans = {}
    local blockposts = {}
    for _, e in ipairs(entities) do
        if e.health and e.health > 0 and not e.isDying then
            if e.name == "Caravan" then
                table.insert(caravans, e)
            elseif e.name == "Blockpost" then
                table.insert(blockposts, e)
            end
        end
    end
    if #caravans == 0 or #blockposts == 0 then return end
    for _, caravan in ipairs(caravans) do
        local nearestBP = nil
        local nearestDist = math.huge
        for _, bp in ipairs(blockposts) do
            local dist = hex:getDistance(caravan.q, caravan.r, bp.q, bp.r)
            if dist > 0 and dist < nearestDist then
                nearestDist = dist
                nearestBP = bp
            end
        end
        if not nearestBP then goto continue end
        local neighbors = hex:getNeighbors(caravan.q, caravan.r)
        local bestNeighbor = nil
        local bestDist = math.huge
        for _, n in ipairs(neighbors) do
            if hex:isActiveHex(n.q, n.r) then
                local terrain = _G.terrainMap and _G.terrainMap[n.q] and _G.terrainMap[n.q][n.r] or "grass"
                if terrain ~= "water" and terrain ~= "underwater_mines" then
                    local occupied = false
                    for _, other in ipairs(entities) do
                        if other ~= caravan and other.q == n.q and other.r == n.r and other.health and other.health > 0 then
                            occupied = true
                            break
                        end
                    end
                    if not occupied then
                        local dist = hex:getDistance(n.q, n.r, nearestBP.q, nearestBP.r)
                        if dist < bestDist then
                            bestDist = dist
                            bestNeighbor = n
                        end
                    end
                end
            end
        end
        if bestNeighbor then
            combat.addDirectPushAnimation(caravan, caravan.q, caravan.r, bestNeighbor.q, bestNeighbor.r)
        end
        ::continue::
    end
    combat.startPushAnimations(hex)
end

function startEnemyPreparePhase()
    moveCaravans()
    local enemies = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            table.insert(enemies, e)
        end
    end
    turnState.enemyPrepareQueue = enemies
    turnState.phase = "enemy_prepare"
    turnState.currentPreparingEnemy = nil
    processNextEnemyPrepare()
end

return turnManager
