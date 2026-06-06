-- turn_manager.lua
-- Машина состояний для фаз хода (enemy_prepare / player / enemy_attack).
-- Использует глобалы (entities, hex, turnState, sounds, globalHealth, terrainMap).

local turnManager = {}

function turnManager.startGame()
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
    effects.applyEndOfTurnEffects(entities, terrainMap, globalHealth)
    checkGameEnd()

    if turnCount >= maxTurns and not decayAppliedForTurnLimit then
        applyDecayToAllEnemies()
        decayAppliedForTurnLimit = true
        decayMessageTimer = 2.0
    end

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
        if turnState.pendingDigProcessing then
            processDigSites()
            turnState.pendingDigProcessing = false
        end
        turnCount = turnCount + 1
        print("Turn count increased to: " .. turnCount .. "/" .. maxTurns)
        turnState.phase = "enemy_prepare"
        effects.applyEndOfTurnEffects(entities, terrainMap, globalHealth)
        startEnemyPreparePhase()
        return
    end

    turnState.enemyAttackTimer = turnState.enemyAttackTimer + dt
    if turnState.enemyAttackTimer >= turnState.delayBetweenAttacks then
        turnState.enemyAttackTimer = 0
        local enemy = table.remove(turnState.enemyAttackQueue, 1)
        if enemy and enemy.health > 0 then
            ai.executePreparedAttack(enemy, entities, hex, sounds, globalHealth)
            checkGameEnd()
        end
    end
end

function processNextEnemyPrepare()
    if #turnState.enemyPrepareQueue == 0 then
        turnState.phase = "player"
        for _, a in ipairs(entities) do
            if a.isPlayable and a.health > 0 then
                a.hasActedThisTurn = false
                a.hasMovedThisTurn = false
            end
        end
        actionHistory = {}
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

function startEnemyPreparePhase()
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
