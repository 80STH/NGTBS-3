-- turn_manager.lua
-- Машина состояний для фаз хода (enemy_prepare / player / enemy_attack).
-- Использует глобалы (entities, hex, turnState, sounds, terrainMap).

local turnManager = {}

function turnManager.startGame()
    -- Выкопка с самого первого хода
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

    -- Step 0: Lightning strikes before fire/decay
    strikeLightning()
    checkGameEnd()

    -- Step 1: Simultaneous effects (fire, decay) — no digging
    effects.applyEndOfTurnEffects(entities, terrainMap)
    checkGameEnd()

    if turnCount >= maxTurns and not decayAppliedForTurnLimit then
        applyDecayToAllEnemies()
        decayAppliedForTurnLimit = true
        decayMessageTimer = 2.0
        status.clearAllDigSites()
    end

    -- Step 2: Queue enemy attacks
    local attackers = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 and not e.isDying then
            table.insert(attackers, e)
        end
    end
    turnState.enemyAttackQueue = attackers
    turnState.enemyAttackTimer = 0
    turnState.phase = "enemy_attack"
    turnState.pendingDigProcessing = true
    print("=== ENEMY ATTACK PHASE ===")
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
    if #turnState.enemyAttackQueue == 0 then
        -- Step 3: Simultaneous digging
        if turnState.pendingDigProcessing then
            processDigSites()
            turnState.pendingDigProcessing = false
        end
        turnCount = turnCount + 1
        print("Turn count increased to: " .. turnCount .. "/" .. maxTurns)
        turnState.phase = "enemy_prepare"
        startEnemyPreparePhase()
        return
    end

    turnState.enemyAttackTimer = turnState.enemyAttackTimer + dt
    if turnState.enemyAttackTimer >= turnState.delayBetweenAttacks then
        turnState.enemyAttackTimer = 0
        local enemy = table.remove(turnState.enemyAttackQueue, 1)
        if enemy and enemy.health > 0 then
            ai.executePreparedAttack(enemy, entities, hex, sounds)
            checkGameEnd()
        end
    end
end

function processNextEnemyPrepare()
    if #turnState.enemyPrepareQueue == 0 then
        turnState.phase = "player"
        for _, a in ipairs(entities) do
            if a.isPlayable then
                -- Снимаем нокаут в начале хода: здоровье -> 1, востанавливаем скорость
                if status.hasEntityStatus(a, "knockout") then
                    status.removeFromEntity(a, "knockout")
                    a.health = 1
                    if a._savedMoveRange then
                        a.moveRange = a._savedMoveRange
                        a._savedMoveRange = nil
                    end
                    print(string.format(" %s recovers from knockout! (1 HP)", a.name))
                end
                if a.health > 0 then
                    a.hasActedThisTurn = false
                    a.hasMovedThisTurn = false
                    a.canMoveAfterAttack = false
                end
            end
        end
        actionHistory = {}
        global_abilities.abilityUsedThisTurn = false
        selectLightningTarget()
        print("=== PLAYER TURN ===")
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
        print(enemy.name .. " cannot prepare attack, skipping")
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
