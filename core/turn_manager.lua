-- turn_manager.lua
-- State machine for turn phases (enemy_prepare / player / enemy_attack).
-- Uses globals (entities, hex, turnState, sounds, terrainMap).

local turnManager = {}
local log = require("util.log")
local push_animator = require("combat.push_animator")

function turnManager.startGame()
    processDigSites()

    turnState.phase = "enemy_prepare"
    turnState.enemyAttackQueue = {}
    turnState.enemyAttackTimer = 0
    turnState.pendingDigProcessing = false
    turnState.caravansMoving = false
    turnState._pendingGroupEnd = false
    turnState._waitingForMoves = false

    moveCaravans()
    if _G.pushAnimations and _G.pushAnimations.active then
        turnState.caravansMoving = true
    else
        local enemies = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.health > 0 then
                table.insert(enemies, e)
            end
        end
        turnState.enemyPrepareQueue = enemies
        turnState._batchMovePlanning = true
        turnState._waitingForMoves = false
    end
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

    if global_abilities.hasPendingRemains() then
        global_abilities.processPendingRemains(entities, hex, sounds)
        checkGameEnd()
    end

    if turnCount >= maxTurns and not decayAppliedForTurnLimit then
        applyDecayToAllEnemies()
        decayAppliedForTurnLimit = true
        decayMessageTimer = 2.0
        status.clearAllDigSites()
    end

    -- Prepare train attacks for this turn
    local trains_mod = require("system.trains")
    trains_mod.prepareTrainAttacks(entities, hex)

    -- All enemies attack one at a time, in order (units first, buildings last,
    -- leaders before regulars, attacksFirst first; trains after everyone else)
    turnState.enemyAttackQueue = turnManager.buildEnemyAttackQueue()
    turnState.enemyAttackTimer = 0
    turnState.phase = "enemy_attack"
    turnState.pendingDigProcessing = true
    turnState.trainShuntInProgress = false
    turnState._pendingGroupEnd = false
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
    if turnState.caravansMoving then
        if _G.pushAnimations and _G.pushAnimations.active then return end
        turnState.caravansMoving = false
        local enemies = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.health > 0 then
                table.insert(enemies, e)
            end
        end
        turnState.enemyPrepareQueue = enemies
        turnState._batchMovePlanning = true
        turnState._waitingForMoves = false
        return
    end

    -- Batch planning: process enemies sequentially (logic only, no visual movement)
    if turnState._batchMovePlanning then
        if #turnState.enemyPrepareQueue == 0 then
            turnState._batchMovePlanning = false
            -- Start all visual movements simultaneously
            local anyMoving = false
            for _, e in ipairs(entities) do
                if e:isCharacter() and not e.isPlayable and e.health > 0 and e.path and #e.path > 0 then
                    ai.startEnemyMove(e, hex)
                    anyMoving = true
                end
            end
            if anyMoving then
                turnState._waitingForMoves = true
            else
                -- No enemies moved — prepare all attacks now
                for _, e in ipairs(entities) do
                    if e:isCharacter() and not e.isPlayable and e.health > 0 then
                        if e._willPrepareAfterMove or not e.hasPreparedAttack then
                            if ai.canPrepareAttack(e, entities) then
                                ai.prepareAttackForEnemy(e, entities, hex)
                            end
                        end
                    end
                end
                transitionToPlayerTurn()
            end
        else
            local enemy = table.remove(turnState.enemyPrepareQueue, 1)
            if enemy and enemy.health > 0 then
                _G._batchMovePlanning = true
                ai.moveAndPrepare(enemy, entities, hex)
                _G._batchMovePlanning = false
            end
        end
        return
    end

    -- Waiting for all enemies to finish moving simultaneously
    if turnState._waitingForMoves then
        local anyMoving = false
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.health > 0 and e.isMoving then
                anyMoving = true
                break
            end
        end
        if not anyMoving then
            turnState._waitingForMoves = false
            -- Prepare attacks for all enemies simultaneously
            for _, e in ipairs(entities) do
                if e:isCharacter() and not e.isPlayable and e.health > 0 then
                    if e._willPrepareAfterMove then
                        ai.prepareAttackForEnemy(e, entities, hex, {})
                    elseif not e.hasPreparedAttack then
                        if ai.canPrepareAttack(e, entities) then
                            ai.prepareAttackForEnemy(e, entities, hex)
                        end
                    end
                end
            end
            transitionToPlayerTurn()
        end
        return
    end
end

function transitionToPlayerTurn()
    turnState.phase = "player"
    sounds.play("turn_start")
    require("system.teleporters").refresh()
    for _, a in ipairs(entities) do
        if a.isPlayable then
            if a.health > 0 then
                a.hasActedThisTurn = false
                a.hasMovedThisTurn = false
                a.canMoveAfterAttack = false
                a.chainAttack = nil
                a.redirectPending = nil
                if a.soloActions then
                    a.attacksLeft = 2
                    a.movesLeft = 2
                end
            end
        end
    end
    undo.clear()
    undo.snapshot()
    global_abilities.abilityUsedThisTurn = false
    _G.mechanismUsedThisTurn = false
    selectLightningTarget()
    log.info("turn", "=== PLAYER TURN ===")
end

function updateAttackPhase(dt)
    -- If a train shunt animation is in progress, update it
    if turnState.trainShuntInProgress then
        local trains_mod = require("system.trains")
        trains_mod.updateMovement(dt)
        if not trains_mod.isAnyAnimating() then
            turnState.trainShuntInProgress = false
            turnState.currentTrainLoco = nil
            local combat = require("combat.combat")
            combat._processPendingDeaths()
            checkGameEnd()
        end
        return
    end

    -- Wait for simultaneous group's animations to complete before next group
    if turnState._pendingGroupEnd then
        if push_animator.isActive() then return end
        turnState._pendingGroupEnd = false
        return
    end

    if #turnState.enemyAttackQueue == 0 then
        if turnState.pendingDigProcessing then
            effects.applyEndOfTurnEffects(entities, terrainMap)
            checkGameEnd()
            processDigSites()
            turnState.pendingDigProcessing = false
        end
        turnCount = turnCount + 1
        log.infof("turn", "Turn count increased to: %s/%s", turnCount, maxTurns)
        turnState.phase = "enemy_prepare"
        startEnemyPreparePhase()
        return
    end

    local group = turnState.enemyAttackQueue[1]

    if group.type == "sequential" then
        local delay = turnState.delayBetweenAttacks
        if _G.slowMode then delay = delay * 2 end
        turnState.enemyAttackTimer = turnState.enemyAttackTimer + dt
        if turnState.enemyAttackTimer < delay then return end
        turnState.enemyAttackTimer = 0

        local enemy = table.remove(group.enemies, 1)
        if enemy and enemy.health > 0 then
            if enemy.isTrainAttack then
                local trains_mod = require("system.trains")
                turnState.trainShuntInProgress = true
                turnState.currentTrainLoco = enemy
                trains_mod.executeTrainShunt(enemy, entities, hex, function() end)
            else
                ai.executePreparedAttack(enemy, entities, hex, sounds)
            end
        end

        if #group.enemies == 0 then
            table.remove(turnState.enemyAttackQueue, 1)
            local combat = require("combat.combat")
            combat._processPendingDeaths()
            checkGameEnd()
        end
        return
    end

    -- Simultaneous: all at once (with optional slow mode lead-in delay)
    if _G.slowMode then
        turnState.enemyAttackTimer = turnState.enemyAttackTimer + dt
        if turnState.enemyAttackTimer < turnState.delayBetweenAttacks * 2 then return end
        turnState.enemyAttackTimer = 0
    end

    local combat = require("combat.combat")
    table.remove(turnState.enemyAttackQueue, 1)

    for _, enemy in ipairs(group.enemies) do
        if enemy and enemy.health > 0 then
            ai.executePreparedAttack(enemy, entities, hex, sounds)
        end
    end

    push_animator.onQueueEmpty = function()
        combat._processPendingDeaths()
        checkGameEnd()
        push_animator.onQueueEmpty = combat._processPendingDeaths
        turnState._pendingGroupEnd = false
    end
    turnState._pendingGroupEnd = true
    if not push_animator.isActive() then
        push_animator.onQueueEmpty()
    end
end

-- processNextEnemyPrepare removed: logic folded into updatePreparePhase

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
    local hasMoves = false
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
                if terrain ~= "water" then
                    local occupied = false
                    for _, other in ipairs(entities) do
                        if other ~= caravan and other.q == n.q and other.r == n.r and other.health and other.health > 0 then
                            occupied = true
                            break
                        end
                    end
                    if status.hasDigSite(n.q, n.r) then occupied = true end
                    -- Also check against caravans already moved this batch (their q/r updated)
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
            local fromQ, fromR = caravan.q, caravan.r
            caravan.q = bestNeighbor.q
            caravan.r = bestNeighbor.r
            combat.addDirectPushAnimation(caravan, fromQ, fromR, bestNeighbor.q, bestNeighbor.r)
            hasMoves = true
        end
        ::continue::
    end
    if hasMoves then
        combat.startPushAnimations(hex)
    end
end

-- One sequential group with every prepared enemy, in attack order
function turnManager.buildEnemyAttackQueue()
    local trains_mod = require("system.trains")
    local enemies = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and not e.isTrainAttack and e.hasPreparedAttack and e.health > 0 and not e.isDying then
            table.insert(enemies, e)
        end
    end
    table.sort(enemies, function(a, b)
        local ta = a._preparedTargetType == "building" and 1 or 0
        local tb = b._preparedTargetType == "building" and 1 or 0
        if ta ~= tb then return ta < tb end
        if a.isLeader ~= b.isLeader then return a.isLeader and not b.isLeader end
        return a.attacksFirst and not b.attacksFirst
    end)
    local trainGroups = trains_mod.getTrainGroups()
    for _, g in pairs(trainGroups) do
        if g.active and g.cars and #g.cars > 0 then
            local loco = g.cars[1]
            if loco and loco.health and loco.health > 0 and not loco.isDying and loco.hasPreparedAttack then
                table.insert(enemies, loco)
            end
        end
    end
    local queue = {}
    if #enemies > 0 then
        table.insert(queue, { type = "sequential", enemies = enemies })
    end
    return queue
end

function startEnemyPreparePhase()
    -- Clear temporary flags from previous turn
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.attacksFirst = nil
        end
    end
    moveCaravans()
    if _G.pushAnimations and _G.pushAnimations.active then
        turnState.caravansMoving = true
    else
        local enemies = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.health > 0 then
                table.insert(enemies, e)
            end
        end
        turnState.enemyPrepareQueue = enemies
        turnState.phase = "enemy_prepare"
        turnState._batchMovePlanning = true
        turnState._waitingForMoves = false
    end
end

return turnManager
