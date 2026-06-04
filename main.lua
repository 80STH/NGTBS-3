-- main.lua
combat = require("combat") --почему для этого нужна переменная?
ai = require("ai")
require("hexgrid")
environment = require("environment")
status = require("status")
ui = require("ui")
pathfinding = require("pathfinding")
effects = require("effects")
visual = require("visual_effects")
config = require("config")
local hex_utils = require("hex_utils")

-- Делаем очередь анимаций доступной глобально для отрисовки
pushAnimations = pushAnimations or { queue = {}, active = false }

DEBUG_COMBAT = true

windTorrent = nil

function love.load()
    selectedAttack = nil   -- текущая выбранная атака (объект)
    attackMode = false
    attackButtons = {}     -- кнопки атак для текущего персонажа
    restartButton = {
        x = 10, y = 320, width = 120, height = 30,
        text = "Restart Game", isHovered = false
    }
    sti = require 'libraries/sti'
    local hexStatuses
    terrainMap, entities, width, height, hexStatuses = environment.loadMapFromTiled('maps/map1.lua')
    hex = require("hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R
    )

    -- Счётчик ходов и лимит
    turnCount = 0
    maxTurns = 1   -- например, 5 ходов
    decayAppliedForTurnLimit = false
    decayMessageTimer = 0
    gameActive = true
    win = false
    loss = false
    fireAppliedForTurnLimit = false

    windTorrentUI = {
        active = false,
        button = { x = 10, y = 240, width = 120, height = 30 }
    }
    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())

    -- Инициализируем глобальную таблицу статусов:
    status.initHexStatuses(hexStatuses) -- добавить в status.lua функцию

    globalHealth = { current = 5, max = 5, initial = 5 }
    combat.globalHealth = globalHealth

    -- Состояние игры
    turnState = {
        phase = "enemy_prepare",   -- "enemy_prepare" → "player" → "enemy_attack"
        enemyPrepareQueue = {},    -- очередь врагов на движение+подготовку
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false   -- <-- добавить сюда
    }

    -- Инициализация врагов
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.hasPreparedAttack = false
            e.preparePos = nil
            e.preparedTarget = nil
            e.movementFinished = false
        end
    end

    -- Выбираем первого союзника
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

    -- Начинаем фазу подготовки врагов
    startEnemyPreparePhase()

    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())

    sounds = {}
    sounds.undo = love.audio.newSource("sounds/hover.wav", "static")
    sounds.undo:setVolume(0.4)
    sounds.turn = love.audio.newSource("sounds/hover.wav", "static")
    sounds.turn:setVolume(0.3)
    sounds.attack = love.audio.newSource("sounds/blip.wav", "static")
    sounds.attack:setVolume(0.5)
    sounds.collision = love.audio.newSource("sounds/blip.wav", "static")
    sounds.collision:setVolume(0.6)

    maxUndoCount = countPlayableActors()
    actionHistory = {}

    endTurnButton = {
        x = 10, y = 280, width = 120, height = 30,
        text = "End Turn", isHovered = false
    }

    -- Создаём глобальное заклинание ветра
    windTorrent = combat.WindTorrentAttack.new()
    
    windTorrentUI.button = { x = 10, y = 240, width = 120, height = 30, isHovered = false }
end

function applyDecayToAllEnemies()
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            if not status.hasEntityStatus(e, "decay") then
                status.applyToEntity(e, "decay")
                print("💀 " .. e.name .. " is afflicted with decay!")
            end
        end
    end
end

function checkGameEnd()
    if not gameActive then return end

    if globalHealth.current <= 0 then
        loss = true
        gameActive = false
        print("DEFEAT: Global health depleted!")
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
        return
    end

    if turnCount >= maxTurns then
        local anyEnemy = false
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isDying then
                anyEnemy = true
                break
            end
        end
        if not anyEnemy then
            win = true
            gameActive = false
            print("VICTORY: Turn limit reached and all enemies defeated!")
        end
    end
end

-- Функция создания кнопок атак для выбранного персонажа
function updateAttackButtons(actor)
    attackButtons = {}
    if not actor or not actor.attacks or #actor.attacks == 0 then
        return
    end
    local startX = love.graphics.getWidth() - 160
    local startY = 100
    for i, attackInfo in ipairs(actor.attacks) do
        local btn = {
            x = startX,
            y = startY + (i-1) * 35,
            width = 150,
            height = 30,
            attack = attackInfo.attack,
            name = attackInfo.name,
            desc = attackInfo.description
        }
        table.insert(attackButtons, btn)
    end
end

-- Определяет направление ветра по координатам клетки относительно центра (5,5)
function getWindDirectionFromHex(q, r, centerQ, centerR, hex)
    local cx, cy, cz = hex_utils.axialToCube(centerQ, centerR)
    local x, y, z = hex_utils.axialToCube(q, r)
    local dx, dy, dz = x - cx, y - cy, z - cz
    
    if dx == 0 and dy == 0 and dz == 0 then
        return nil
    end
    
    local absDx, absDy, absDz = math.abs(dx), math.abs(dy), math.abs(dz)
    local maxVal = math.max(absDx, absDy, absDz)
    
    local ndx = math.floor(dx / maxVal + 0.5)
    local ndy = math.floor(dy / maxVal + 0.5)
    local ndz = math.floor(dz / maxVal + 0.5)
    
    if ndx + ndy + ndz ~= 0 then
        return nil
    end
    
    local directionMap = {
        {dx=1, dy=-1, dz=0, name="E"},
        {dx=1, dy=0, dz=-1, name="NE"},
        {dx=0, dy=1, dz=-1, name="NW"},
        {dx=-1, dy=1, dz=0, name="W"},
        {dx=-1, dy=0, dz=1, name="SW"},
        {dx=0, dy=-1, dz=1, name="SE"},
    }
    for _, dir in ipairs(directionMap) do
        if dir.dx == ndx and dir.dy == ndy and dir.dz == ndz then
            return dir.name
        end
    end
    return nil
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

-- Изменить love.mousepressed (удалить button == 2, добавить обработку кнопок атак и режима атаки)
function love.mousepressed(x, y, button)
    if button == 1 then
        -- Если игра закончена – обрабатываем только кнопку New Game
        if not gameActive then
            local width = love.graphics.getWidth()
            local height = love.graphics.getHeight()
            local btnW, btnH = 200, 50
            local btnX = width/2 - btnW/2
            local btnY = height/2 + 20
            if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
                restartGame()
            end
            return
        end
        -- ======================================================
        -- 1. СНАЧАЛА проверяем ВСЕ UI-кнопки (не зависят от гексов)
        -- ======================================================

    -- Кнопка Wind Torrent
    if x >= windTorrentUI.button.x and x <= windTorrentUI.button.x + windTorrentUI.button.width and
    y >= windTorrentUI.button.y and y <= windTorrentUI.button.y + windTorrentUI.button.height then
        if turnState.phase == "player" and windTorrent and not windTorrent.hasBeenUsed then
            windTorrentUI.active = true
            clearSelectedActor()  -- <-- снимаем выделение
            print("Click on any hex to choose wind direction, or press ESC to cancel")
        elseif windTorrent and windTorrent.hasBeenUsed then
            print("Wind Torrent has already been used this game!")
        elseif turnState.phase ~= "player" then
            print("Can only use Wind Torrent during your turn!")
        else
            print("Wind Torrent not available")
        end
        return
    end

        -- Кнопка Restart
    if x >= restartButton.x and x <= restartButton.x + restartButton.width and
       y >= restartButton.y and y <= restartButton.y + restartButton.height then
        restartGame()
        return
    end

    -- Если активен режим выбора направления и клик по гексу
    if windTorrentUI.active then
        local tq, tr = hex:pixelToHex(x, y)
        if hex:isActiveHex(tq, tr) then
            local direction = getWindDirectionFromHex(tq, tr, hex.centerQ, hex.centerR, hex)
            if direction then
                windTorrent:executeGlobalWithAnimation(direction, hex, entities, sounds, function(success, message)
                    if success then
                        actionHistory = {}
                        print("Wind Torrent used! History cleared.")
                    else
                        print("Wind Torrent failed: " .. (message or "unknown error"))
                    end
                    restoreSelectedActor()  -- <-- восстанавливаем выделение
                end)
                windTorrentUI.active = false
            else
                print("Cannot determine direction from center")
                restoreSelectedActor()  -- <-- восстанавливаем выделение при ошибке
            end
            return
        else
            -- Клик вне активной клетки – отмена
            windTorrentUI.active = false
            restoreSelectedActor()  -- <-- восстанавливаем выделение
            print("Wind Torrent cancelled")
            return
        end
    end


        -- Кнопка Undo
        if x >= 10 and x <= 130 and y >= 200 and y <= 230 then
            if #actionHistory > 0 then
                undoLastAction()
            else
                print("No actions to undo!")
            end
            return
        end

        -- Кнопка End Turn
        if x >= endTurnButton.x and x <= endTurnButton.x + endTurnButton.width and
           y >= endTurnButton.y and y <= endTurnButton.y + endTurnButton.height then
            if turnState.phase == "player" then
                endTurn()
            else
                print("Not your turn")
            end
            return
        end

        -- Кнопки атак (панель справа)
        if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving then
            for _, btn in ipairs(attackButtons) do
                if x >= btn.x and x <= btn.x + btn.width and y >= btn.y and y <= btn.y + btn.height then
                    selectedAttack = btn.attack
                    attackMode = true
                    print("[DEBUG] Attack selected: " .. btn.name .. " (attackMode = true)")
                    return
                end
            end
        end

        -- ======================================================
        -- 2. ТОЛЬКО ТЕПЕРЬ обрабатываем клик по гексу
        -- ======================================================
        local tq, tr = hex:pixelToHex(x, y)
        if not hex:isValidHex(tq, tr) then
            return
        end

        -- Режим атаки (клик по врагу)
        if attackMode and selectedAttack and selectedActor and not selectedActor.hasActedThisTurn then
            print("[DEBUG] Attack mode active, attempting attack at hex", tq, tr)
            local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
            attackMode = false
            selectedAttack = nil
            if not success then
                print("Attack failed: " .. msg)
            end
            return
        end

        -- Выбор персонажа (если кликнули по союзнику)
        local clicked = getEntityAtHex(tq, tr)
        if clicked and clicked.isPlayable and clicked.health > 0 then
            if not clicked.hasActedThisTurn then
                selectedActor = clicked
                hex.selectedQ, hex.selectedR = tq, tr
                updateAttackButtons(selectedActor)
                attackMode = false
                selectedAttack = nil
                print("Selected: " .. clicked.name)
            end
            return
        end

        -- Движение (если персонаж ещё не атаковал и не двигался)
        if selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.hasMovedThisTurn and not selectedActor.isMoving then
            performMove(selectedActor, tq, tr)
            hex.selectedQ, hex.selectedR = selectedActor.q, selectedActor.r
            attackMode = false
            selectedAttack = nil
        end
    end
end

function prepareAllEnemies()
    -- Используем новую функцию с распределением целей
    ai.prepareAllEnemiesWithTargetDistribution(entities, hex)
    turnState.phase = "player"

    -- Увеличиваем счётчик ходов и проверяем лимит
    print("Turn count: " .. turnCount .. " / " .. maxTurns)

    if turnCount >= maxTurns and not decayAppliedForTurnLimit then
        applyDecayToAllEnemies()
        decayAppliedForTurnLimit = true
        decayMessageTimer = 2.0   -- показывать сообщение 2 секунды
    end

    checkGameEnd()

    -- Сброс флагов и режима атаки
    attackMode = false
    selectedAttack = nil
    for _, actor in ipairs(entities) do
        if actor.isPlayable then
            actor.hasActedThisTurn = false
            actor.hasMovedThisTurn = false
        end
    end
    actionHistory = {}
    if selectedActor then
        updateAttackButtons(selectedActor)
    end
    print("=== PLAYER TURN ===")
end

-- Выполнить все подготовленные атаки врагов (вызывается в конце хода игрока)
function executeAllEnemyAttacks()
    local enemies = ai.getLivingEnemies(entities)
    -- Собираем только тех, кто подготовил удар
    local attackers = {}
    for _, e in ipairs(enemies) do
        if e.hasPreparedAttack then
            table.insert(attackers, e)
        end
    end
    turnState.enemyAttackQueue = attackers
    turnState.enemyAttackTimer = 0
    turnState.phase = "enemy_attack"
    print("=== ENEMY ATTACK PHASE ===")
end

function updateEnemyAttacks(dt)
    if turnState.phase ~= "enemy_attack" then return end

    if #turnState.enemyAttackQueue == 0 then
        turnState.phase = "enemy_prepare"
        -- Увеличиваем счётчик ходов перед началом нового раунда
        turnCount = turnCount + 1
        print("Turn count increased to: " .. turnCount .. "/" .. maxTurns)
        prepareAllEnemies()
        turnState.currentAttackingEnemy = nil
        return
    end

    if turnState.enemyAttackTimer >= turnState.delayBetweenAttacks then
        turnState.enemyAttackTimer = 0
        local enemy = table.remove(turnState.enemyAttackQueue, 1)
        turnState.currentAttackingEnemy = enemy
        if enemy and enemy.health > 0 then
            ai.executePreparedAttack(enemy, entities, hex, sounds, globalHealth)
            checkGameEnd()   -- <-- добавить
        end
        turnState.currentAttackingEnemy = nil
    end
end

function endTurn()
    if turnState.phase ~= "player" then
        print("Cannot end turn now")
        return
    end
    for _, a in ipairs(entities) do
        if a.isPlayable and not a.hasActedThisTurn then
            a.hasActedThisTurn = true
            print(a.name .. " did not attack, turn ended.")
        end
    end

    effects.applyEndOfTurnEffects(entities, terrainMap, globalHealth)
    checkGameEnd()  -- <-- добавить

    -- Собираем врагов для атаки
    local attackers = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 and not e.isDying then
            table.insert(attackers, e)
        end
    end
    turnState.enemyAttackQueue = attackers
    turnState.enemyAttackTimer = 0
    turnState.phase = "enemy_attack"
    print("=== ENEMY ATTACK PHASE ===")
    -- ВНИМАНИЕ: processDigSites будет вызван ПОСЛЕ того, как враги отстреляются
    -- Для этого добавим флаг, что после атак нужно вызвать обработку выкопок
    turnState.pendingDigProcessing = true
end
-- Обработка хода врагов
function updateEnemyTurn(dt)
    if not turnState.waitingForEnemies then
        return
    end
    
    -- Задержка перед каждым действием врага (для читаемости)
    turnState.enemyTurnTimer = turnState.enemyTurnTimer + dt
    
    if turnState.enemyTurnTimer >= 0.3 then
        -- Проверяем, есть ли враги, которые еще не ходили
        local hasEnemyToAct = false
        for _, actor in ipairs(entities) do
            if not actor.isPlayable and not actor.hasActedThisTurn and not actor.isMoving then
                hasEnemyToAct = true
                break
            end
        end
        
        if hasEnemyToAct then
            -- Выполняем действие одного врага
            for _, enemy in ipairs(entities) do
                if not enemy.isPlayable and not enemy.hasActedThisTurn and not enemy.isMoving then
                    ai.performEnemyTurn(enemy, entities, hex, sounds)
                    turnState.enemyTurnTimer = 0
                    break
                end
            end
        else
            -- Все враги сходили, заканчиваем их ход
            turnState.waitingForEnemies = false
            
            -- Сбрасываем флаги действий для всех актеров
            for _, actor in ipairs(entities) do
                actor.hasActedThisTurn = false
                if actor.isPlayable then
                    -- Сбрасываем счетчик действий для союзников
                    for i, a in ipairs(entities) do
                        if a == actor then
                            turnState.actionsRemaining[i] = 1
                            break
                        end
                    end
                end
            end
            
            turnState.currentTurn = turnState.currentTurn + 1
            print("=== NEW ROUND " .. turnState.currentTurn .. " ===")
            print("Your turn again!")
        end
    end
end

function undoLastAction()
    if #actionHistory == 0 then
        print("No moves to undo!")
        return false
    end
    
    local action = actionHistory[#actionHistory]
    local actor = action.actor
    
    if not actor then
        table.remove(actionHistory)
        return undoLastAction()
    end
    
    if actor.isMoving then
        print("Cannot undo while moving")
        return false
    end
    
    -- Откат позиции
    actor.q = action.fromQ
    actor.r = action.fromR
    actor.hasActedThisTurn = false
    actor.hasMovedThisTurn = false
    actor.isMoving = false
    actor.path = {}
    actor.currentPathIndex = 0
    
    -- Откат здоровья и статусов
    if action.healthBefore ~= nil then
        actor.health = action.healthBefore
    end
    if action.statusesBefore then
        status.setEntityStatuses(actor, action.statusesBefore)
    end
    
    -- Если персонаж был мёртв (health <= 0), но в истории здоровье > 0 – воскрешаем
    -- и добавляем обратно в entities, если был удалён
    if actor.health > 0 then
        local found = false
        for _, e in ipairs(entities) do
            if e == actor then
                found = true
                break
            end
        end
        if not found then
            table.insert(entities, actor)
            print(actor.name .. " was resurrected by undo!")
        end
    end
    
    if selectedActor == actor then
        hex.selectedQ = actor.q
        hex.selectedR = actor.r
    end
    
    -- Удаляем последнее действие из истории
    table.remove(actionHistory)
    
    sounds.undo:play()
    print("Undone move for " .. actor.name .. ". History size: " .. #actionHistory)
    return true
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

function isAlly(entityA, entityB)
    if not entityA or not entityB then return false end
    -- Если оба игровые персонажи (isPlayable) – союзники
    -- Если оба враги (not isPlayable) – тоже союзники (между собой)
    return entityA.isPlayable == entityB.isPlayable
end

function addToHistory(actor, fromQ, fromR, toQ, toR)
    if not actor.isPlayable then return end
    table.insert(actionHistory, {
        actor = actor,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        type = "move",
        healthBefore = actor.health,
        statusesBefore = status.copyEntityStatuses(actor),
    })
    print("Move recorded. History size: " .. #actionHistory)
end

-- Проверка занятости (для движения)
-- main.lua
function isPositionOccupied(q, r, movingEntity)
    -- Неактивная клетка – занята
    if not hex:isActiveHex(q, r) then
        return true
    end
    -- Вода непроходима
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
        return true
    end
    -- Любая сущность (союзник, враг, препятствие) блокирует клетку
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            return true
        end
    end
    return false
end

function getEntityAtHex(q, r)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then
            return e
        end
    end
    return nil
end

function performMove(actor, targetQ, targetR)
    if not actor.isPlayable then return false end
    if not hex:isActiveHex(targetQ, targetR) then
        print("Target cell is outside the playable hexagon")
        return false
    end
    if actor.isMoving or actor.hasActedThisTurn then return false end
    if actor.hasMovedThisTurn then
        print(actor.name .. " has already moved this turn!")
        return false
    end
    if actor.q == targetQ and actor.r == targetR then return false end
    local distance = hex:getDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        print("Too far")
        return false
    end
    -- Проверяем, не занята ли целевая клетка (союзник или враг)
    if isCellOccupiedForStop(targetQ, targetR, actor) then
        print("Cell occupied")
        return false
    end
    -- Поиск пути с использованием isCellPassable (союзники не блокируют)
    local path = pathfinding.findPath(actor.q, actor.r, targetQ, targetR, actor.moveRange,
        function(q, r) return not isCellPassable(q, r, actor) end, hex)
    if not path or #path == 0 then
        print("No valid path")
        return false
    end
    addToHistory(actor, actor.q, actor.r, targetQ, targetR)
    actor.hasMovedThisTurn = true
    actor.path = path
    actor.currentPathIndex = 1
    startNextMove(actor)
    return true
end

function startNextMove(actor)
    if actor.currentPathIndex <= #actor.path then
        local step = actor.path[actor.currentPathIndex]
        actor.isMoving = true
        actor.timer = 0
        actor.targetQ = step.q
        actor.targetR = step.r
        actor.startX, actor.startY = hex:hexToPixel(actor.q, actor.r)
        actor.endX, actor.endY = hex:hexToPixel(actor.targetQ, actor.targetR)
    else
        actor.isMoving = false
        actor.path = {}
        actor.currentPathIndex = 0
        if selectedActor == actor then
            hex.selectedQ = actor.q
            hex.selectedR = actor.r
        end
    end
end


function updateActorMovement(actor, dt)
    if actor.isMoving then
        actor.timer = actor.timer + dt
        local t = actor.timer / actor.speed
        if t >= 1 then
            actor.q = actor.targetQ
            actor.r = actor.targetR
            if actor.currentPathIndex >= #actor.path then
                local died = effects.applyAllCellEffects(actor, actor.q, actor.r, terrainMap, entities, globalHealth)
                if died then
                    local x, y = hex:hexToPixel(actor.q, actor.r)
                    visual.addEffect(x, y, "drown") --wtf
                    checkGameEnd()
                end
            end
            actor.isMoving = false
            actor.currentPathIndex = actor.currentPathIndex + 1
            if actor.currentPathIndex <= #actor.path then
                startNextMove(actor)
            else
                actor.path = {}
                actor.currentPathIndex = 0
                if selectedActor == actor then
                    hex.selectedQ = actor.q
                    hex.selectedR = actor.r
                end
            end
        end
    end
end

function startEnemyPreparePhase()
    local enemies = ai.getLivingEnemies(entities)
    turnState.enemyPrepareQueue = {}
    for _, e in ipairs(enemies) do
        table.insert(turnState.enemyPrepareQueue, e)
    end
    turnState.phase = "enemy_prepare"
    turnState.currentPreparingEnemy = nil
    -- Запускаем первого врага
    processNextEnemyPrepare()
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
        -- Ждём завершения движения
    end
end

function love.update(dt)
    visual.update(dt)
    updateDeathAnimations(dt)
    -- Обновление анимаций движения всех сущностей (включая врагов)
    for _, actor in ipairs(entities) do
        updateActorMovement(actor, dt)
        ai.updateEnemyMovement(actor, dt, hex)  -- внутри проверяет isMoving
        if actor.pulse then
            actor.pulse = actor.pulse + dt * (actor.pulseSpeed or 5)
        end
    end
    combat.updatePushAnimations(dt, hex)
    if decayMessageTimer > 0 then
        decayMessageTimer = decayMessageTimer - dt
    end

    if turnState.phase == "enemy_prepare" and turnState.currentPreparingEnemy then
        local enemy = turnState.currentPreparingEnemy
        if not enemy or enemy.health <= 0 then
            turnState.currentPreparingEnemy = nil
            processNextEnemyPrepare()
        elseif not enemy.isMoving and enemy.movementFinished then
            -- Движение завершено, теперь подготавливаем атаку (если возможно)
            if not enemy.hasPreparedAttack then
                if ai.canPrepareAttack(enemy, entities) then
                    ai.prepareAttackForEnemy(enemy, entities, hex)
                end
            end
            enemy.movementFinished = false
            turnState.currentPreparingEnemy = nil
            processNextEnemyPrepare()
        elseif not enemy.isMoving and not enemy.movementFinished then
            -- Движение не началось или завершилось без флага – проверяем возможность атаки
            if not enemy.hasPreparedAttack then
                if ai.canPrepareAttack(enemy, entities) then
                    ai.prepareAttackForEnemy(enemy, entities, hex)
                end
            end
            turnState.currentPreparingEnemy = nil
            processNextEnemyPrepare()
        end
    end

    -- Обновление фазы атаки врагов
    if turnState.phase == "enemy_attack" then
        if #turnState.enemyAttackQueue == 0 then
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
                ai.executePreparedAttack(enemy, entities, hex, sounds, globalHealth)
                checkGameEnd()
            end
        end
    end

    if turnState.phase == "enemy_attack" and #turnState.enemyAttackQueue == 0 then
        if turnState.pendingDigProcessing then
            processDigSites()
            turnState.pendingDigProcessing = nil
        end
        turnCount = turnCount + 1
        print("Turn count increased to: " .. turnCount .. "/" .. maxTurns)
        turnState.phase = "enemy_prepare"
        startEnemyPreparePhase()
        return
    end

    -- Ховер для мыши
    local mx, my = love.mouse.getPosition()
    local hq, hr = hex:pixelToHex(mx, my)
    -- Устанавливаем ховер только если клетка активна (внутри шестиугольника)
    if hex:isActiveHex(hq, hr) then
        hex.hoverQ, hex.hoverR = hq, hr
    else
        hex.hoverQ, hex.hoverR = -1, -1
    end

    -- Ховер кнопок
    undoButton = undoButton or {}
    undoButton.isHovered = (mx >= 10 and mx <= 130 and my >= 200 and my <= 230)
    endTurnButton.isHovered = (mx >= endTurnButton.x and mx <= endTurnButton.x + endTurnButton.width and
                               my >= endTurnButton.y and my <= endTurnButton.y + endTurnButton.height)
    windTorrentUI.button.isHovered = (mx >= windTorrentUI.button.x and mx <= windTorrentUI.button.x + windTorrentUI.button.width and
                                      my >= windTorrentUI.button.y and my <= windTorrentUI.button.y + windTorrentUI.button.height)

                                          -- После того как все анимации завершились (или даже во время, но после перемещения)
end

function drawHexGrid()
    love.graphics.setLineWidth(1)
    local gridW = hex.gridWidth
    local gridH = hex.gridHeight
    if not gridW or not gridH then return end

    -- 1. Рисуем terrain и эффекты сверху вниз (по возрастанию r)
    for row = 0, gridH - 1 do
        for col = 0, gridW - 1 do
            if hex:isActiveHex(col, row) then
                local terrainType = terrainMap and terrainMap[col] and terrainMap[col][row] or "grass"
                local cellX, cellY = hex:hexToPixel(col, row)
                hex:drawTerrainHex(col, row, terrainType, cellX, cellY)

                local hexStatuses = status.getAtHex(col, row)
                if #hexStatuses > 0 then
                    ui.drawCellStatusEffects(cellX, cellY, hex.radius, hexStatuses, love.timer.getTime())
                end
            end
        end
    end

    -- 2. Рисуем рамки и выделения (также сверху вниз)
    for row = 0, gridH - 1 do
        for col = 0, gridW - 1 do
            if not hex:isActiveHex(col, row) then goto continue end
            local cellX, cellY = hex:hexToPixel(col, row)
            local vertices = hex:drawHexagon(cellX, cellY, hex.radius)

            local isCurrentActor = selectedActor and selectedActor.q == col and selectedActor.r == row
            local isSelected = (hex.selectedQ == col and hex.selectedR == row)
            local isHovered = (hex.hoverQ == col and hex.hoverR == row)

            if isCurrentActor then
                love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
                love.graphics.polygon("fill", vertices)
            elseif isSelected then
                love.graphics.setColor(0.2, 0.4, 0.8, 0.5)
                love.graphics.polygon("fill", vertices)
            elseif isHovered then
                love.graphics.setColor(0.5, 0.8, 0.3, 0.5)
                love.graphics.polygon("fill", vertices)
            end

            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.polygon("line", vertices)
            ::continue::
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function getEntityDrawPosition(entity)
    -- 1. Проверяем, есть ли у сущности временные координаты, установленные shake-анимацией
    if entity.currentDrawX and entity.currentDrawY then
        return entity.currentDrawX, entity.currentDrawY
    end

    -- 2. Проверяем глобальную очередь push-анимаций (отталкивания, bounce, collisions)
    if pushAnimations and pushAnimations.queue then
        for _, anim in ipairs(pushAnimations.queue) do
            if anim.obj == entity and anim.isMoving then
                local t = math.min(1, anim.timer / anim.duration)
                -- Easing для плавности (ease out)
                local ease = 1 - (1 - t) * (1 - t)
                
                if anim.isShake then
                    -- shake-анимация: возвращаем смещённые координаты, если они заданы в анимации
                    if anim.offsetX and anim.offsetY then
                        local x, y = hex:hexToPixel(anim.obj.q, anim.obj.r)
                        local curX = x + anim.offsetX * (1 - ease)
                        local curY = y + anim.offsetY * (1 - ease)
                        return curX, curY
                    else
                        return hex:hexToPixel(entity.q, entity.r)
                    end
                else
                    -- Обычный push или bounce
                    if anim.startX and anim.endX then
                        local x = anim.startX + (anim.endX - anim.startX) * ease
                        local y = anim.startY + (anim.endY - anim.startY) * ease
                        return x, y
                    else
                        return hex:hexToPixel(entity.q, entity.r)
                    end
                end
            end
        end
    end

    -- 3. Обычное движение по пути (step-by-step)
    if entity.isMoving then
        local t = entity.timer / entity.speed
        if t > 1 then t = 1 end
        -- Плавное ускорение/замедление (ease in-out)
        local ease = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
        local x = entity.startX + (entity.endX - entity.startX) * ease
        local y = entity.startY + (entity.endY - entity.startY) * ease
        return x, y
    end

    -- 4. Статическое положение
    return hex:hexToPixel(entity.q, entity.r)
end

function drawHealthBar(entity, x, y, damage)
    -- Защита от nil-координат
    if not x or not y then
        if entity and entity.q ~= nil and entity.r ~= nil and hex then
            x, y = hex:hexToPixel(entity.q, entity.r)
        else
            return
        end
    end

    if not entity.maxHealth or entity.maxHealth <= 0 then return end
    if entity.maxHealth > 10 then return end

    local cellSize = 8
    local spacing = 1
    local totalWidth = entity.maxHealth * (cellSize + spacing) - spacing
    local startX = x - totalWidth / 2
    local startY = y - 28

    damage = damage or 0
    local damageClamped = math.min(damage, entity.health)  -- сколько ячеек будет повреждено

    for i = 1, entity.maxHealth do
        local cellX = startX + (i - 1) * (cellSize + spacing)
        local cellY = startY
        local isAlive = i <= entity.health
        local willTakeDamage = damageClamped > 0 and i > entity.health - damageClamped and i <= entity.health

        if willTakeDamage then
            -- Мигание: красный с пульсацией
            local t = love.timer.getTime()
            local blink = 0.5 + 0.5 * math.sin(t * 8)
            love.graphics.setColor(1, 0.2 + blink * 0.3, 0.2, 0.9)
        elseif isAlive then
            love.graphics.setColor(0, 0.8, 0, 0.9)
        else
            love.graphics.setColor(0.4, 0.1, 0.1, 0.6)
        end
        love.graphics.rectangle("fill", cellX, cellY, cellSize, cellSize)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.rectangle("line", cellX, cellY, cellSize, cellSize)
    end
end

-- Унифицированная отрисовка иконки "действие выполнено"
function drawActionIndicator(entity, x, y)
    if entity:isCharacter() and entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        love.graphics.circle("fill", x + 15, y - 15, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("✓", x + 11, y - 20)
    end
end

function drawEntity(entity)
    love.graphics.setColor(1, 1, 1, 1) --временно
    local x, y = getEntityDrawPosition(entity)
    
    -- Анимация смерти: прозрачность и масштаб
    local alpha = 1
    local scale = 1
    if entity.isDying then
        local t = entity.deathTimer / entity.deathDuration  -- 0..1
        alpha = 1 - t
        scale = 1 - t * 0.7
        love.graphics.setColor(1, 1, 1, alpha)
    end
    
    if entity.isPlayable and entity.hasMovedThisTurn and not entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.8, 0.5, 0.9)
        love.graphics.print("🏃", x + 18, y - 20)
    end

    if entity.sprite then
        local sw, sh = entity.sprite:getDimensions()
        local baseScale = 6
        if selectedActor == entity and entity:isCharacter() then
            baseScale = 6 + math.sin(entity.pulse) * 0.2
        end
        local finalScale = baseScale * scale
        love.graphics.draw(entity.sprite, x, y, 0, finalScale, finalScale, sw/2, sh/2)
    else
        -- fallback круг
        love.graphics.setColor(entity.color or {1, 1, 1, 1})
        love.graphics.circle("fill", x, y, 14)
    end
    
    -- Красная подсветка для умирающих
    if entity.isDying then
        love.graphics.setColor(1, 0.2, 0.2, alpha)
        love.graphics.circle("fill", x, y, 18)
    end

    local entityStatuses = status.getEntityStatuses(entity)
    if #entityStatuses > 0 then
        ui.drawEntityStatusEffects(x, y, entityStatuses, 20, love.timer.getTime())
    end
    
    -- Полоска здоровья
    drawHealthBar(entity, x, y)
    
    -- Индикатор действия
    drawActionIndicator(entity, x, y)
    
    -- Рамка выделения для выбранного персонажа
    if selectedActor == entity and entity:isCharacter() and not entity.isDying then
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.circle("line", x, y, 22)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- Отрисовка всех сущностей
function drawAllEntities()
    for _, entity in ipairs(entities) do
        drawEntity(entity)
    end
end

-- Обновление анимаций всех сущностей (пульсация)
function updateEntityAnimations(dt)
    for _, entity in ipairs(entities) do
        if entity.pulse then
            entity.pulse = (entity.pulse or 0) + dt * (entity.pulseSpeed or 5)
        end
    end
end

function drawAttackIndicators()
    if not selectedActor or selectedActor.hasActedThisTurn or selectedActor.isMoving then
        return
    end
    
    -- Подсвечиваем соседние клетки для атаки
    local neighbors = hex:getNeighbors(selectedActor.q, selectedActor.r)
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local target = getEntityAtHex(neighbor.q, neighbor.r)
            if target then
                local x, y = hex:hexToPixel(neighbor.q, neighbor.r)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                
                love.graphics.setColor(1, 0.2, 0.2, 0.4)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.5, 0.5, 0.8)
                love.graphics.polygon("line", vertices)
                
                -- Отображаем иконку атаки
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print("⚔", x - 5, y - 10)
            end
        end
    end
end


-- main.love.draw (добавить вызов)
function love.draw()
    drawHexGrid()
    ui.drawPreparedAttacks(hex, entities)
    ui.drawDigSites(hex, status.getAllDigSites())
    drawAllEntities()
    visual.draw()
    -- Обратный отсчёт до Decay
    local turnsLeft = maxTurns - turnCount
    if turnsLeft > 0 then
        love.graphics.setColor(0.9, 0.7, 0.2, 1)
        love.graphics.print("Decay in: " .. turnsLeft, 10, 110)
    elseif turnsLeft == 0 and decayAppliedForTurnLimit then
        love.graphics.setColor(0.8, 0.2, 0.2, 1)
        love.graphics.print("DECAY ACTIVE!", 10, 110)
    end

    -- Анимированное сообщение "DECAY!" при первом применении
    if decayMessageTimer > 0 then
        local alpha = math.min(1, decayMessageTimer * 2)  -- затухание
        love.graphics.setColor(0.8, 0.2, 0.2, alpha)
        love.graphics.setFont(love.graphics.newFont(36))
        love.graphics.print("💀 DECAY! 💀", love.graphics.getWidth()/2 - 120, love.graphics.getHeight()/2 - 50)
        love.graphics.setFont(love.graphics.newFont(16))  -- восстановить
    end

    -- Подсветка дальности движения врага при наведении
    if hex.hoverQ and hex.hoverQ >= 0 and hex.hoverR and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity:isCharacter() and not hoverEntity.isPlayable and hoverEntity.health > 0 then
            if not attackMode and turnState.phase == "player" then
                ui.drawEnemyMovementRange(hex, hoverEntity, entities, terrainMap)
            end
        end
    end

    if attackMode and selectedAttack and selectedActor and not selectedActor.hasActedThisTurn and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        ui.drawAttackPreview(hex, selectedActor, selectedAttack, attackMode, hex.hoverQ, hex.hoverR, entities)
    end
    if selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving and turnState.phase == "player" then
        ui.drawMovementRange(hex, selectedActor, entities, terrainMap)
        if not attackMode and hex.hoverQ >= 0 and hex.hoverR >= 0 then
            ui.drawPathPreview(hex, selectedActor, hex.hoverQ, hex.hoverR, entities, terrainMap)
        end
    end
    ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
    ui.drawEndTurnButton(turnState, entities)
    ui.drawRestartButton(restartButton, turnState)
    ui.drawWindTorrentButton(windTorrent, windTorrentUI, turnState)
    ui.drawGlobalHealthBar(globalHealth)
    ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode) -- <-- добавлено
    love.graphics.setColor(1,1,1,1)
    love.graphics.print("Phase: " .. turnState.phase, 10, 10)
    if selectedActor then
        love.graphics.print("Selected: " .. selectedActor.name .. (selectedActor.hasActedThisTurn and " (acted)" or ""), 10, 30)
    end
    love.graphics.print("Left click: Move / Attack (after selecting attack)", 10, 130)

    local mx, my = love.mouse.getPosition()
    local showOrder = ui.drawEnemyOrderButton(mx, my)

    if showOrder then
        local orderMap = getEnemyAttackOrder(entities, turnState)
        for _, enemy in ipairs(entities) do
            if enemy:isCharacter() and not enemy.isPlayable and enemy.health > 0 then
                local num = orderMap[enemy]
                if num then
                    local x, y = hex:hexToPixel(enemy.q, enemy.r)
                    -- фон кружка
                    love.graphics.setColor(1, 0.8, 0.2, 0.9)
                    love.graphics.circle("fill", x + 15, y - 20, 12)
                    -- цифра
                    love.graphics.setColor(0, 0, 0, 1)
                    love.graphics.print(tostring(num), x + 11, y - 28)
                end
            end
        end
    end

    -- ===== ПОДСКАЗКА ПРИ НАВЕДЕНИИ НА ЮНИТА =====
    if hex.hoverQ and hex.hoverQ >= 0 and hex.hoverR and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity.health > 0 then
            local panelX = 10
            local panelY = love.graphics.getHeight() - 180  -- немного выше, чтобы поместилась дополнительная строка
            ui.drawUnitTooltip(hoverEntity, panelX, panelY, terrainMap, hex)
        elseif hex:isActiveHex(hex.hoverQ, hex.hoverR) then
            local terrain = terrainMap and terrainMap[hex.hoverQ] and terrainMap[hex.hoverQ][hex.hoverR] or "grass"
            ui.drawCellTooltip(hex.hoverQ, hex.hoverR, terrain, hex)
        end
    end

    -- Стрелка направления подготовленной атаки (при наведении на врага)
    for _, entity in ipairs(entities) do
        if entity:isCharacter() and not entity.isPlayable and entity.hasPreparedAttack and entity.health > 0 then
            ui.drawPreparedAttackDirection(hex, entity, love.timer.getTime(), entities)  -- добавлен entities
        end
    end

    -- После отрисовки остального интерфейса, перед выводом фаз
    if windTorrentUI.active and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local direction = getWindDirectionFromHex(hex.hoverQ, hex.hoverR, hex.centerQ, hex.centerR, hex)
        if direction then
            ui.drawWindTorrentPreview(hex, direction, entities, terrainMap)
        end
    end
    if not gameActive then
        local width = love.graphics.getWidth()
        local height = love.graphics.getHeight()
        
        -- Сохраняем текущий шрифт
        local oldFont = love.graphics.getFont()
        
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.rectangle("fill", 0, 0, width, height)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(48))
        if win then
            love.graphics.printf("VICTORY!", 0, height/2 - 100, width, "center")
        elseif loss then
            love.graphics.printf("DEFEAT!", 0, height/2 - 100, width, "center")
        end

        -- Кнопка New Game
        local btnW, btnH = 200, 50
        local btnX = width/2 - btnW/2
        local btnY = height/2 + 20
        love.graphics.setColor(0.2, 0.2, 0.6, 0.9)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(24))
        love.graphics.print("New Game", btnX + 48, btnY + 12)
        
        -- Восстанавливаем старый шрифт
        love.graphics.setFont(oldFont)
    end
end

-- Проверка, является ли клетка краем карты
function isEdgeCell(q, r)
    return q == 0 or q == hex.gridWidth - 1 or r == 0 or r == hex.gridHeight - 1
end

function drawEdgeWarning()
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if isEdgeCell(q, r) then
                local x, y = hex:hexToPixel(q, r)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.setColor(1, 0.2, 0.2, 0.2)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.3, 0.3, 0.6)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", vertices)
                love.graphics.setLineWidth(1)
                
                -- Иконка опасности
                love.graphics.setColor(1, 0.5, 0.5, 0.9)
                love.graphics.print("⚠", x - 5, y - 8)
            end
        end
    end
end

-- Переключение атаки у выбранного актера
function switchAttack()
    if not selectedActor or selectedActor.hasActedThisTurn or selectedActor.isMoving then
        return false
    end
    
    if #selectedActor.attacks > 0 then
        selectedActor.currentAttackIndex = (selectedActor.currentAttackIndex % #selectedActor.attacks) + 1
        local currentAttack = selectedActor.attacks[selectedActor.currentAttackIndex]
        print("Switched to: " .. currentAttack.name .. " - " .. currentAttack.description)
        return true
    end
    return false
end

-- Получить текущую атаку выбранного актера
function getCurrentAttack(actor)
    if not actor or #actor.attacks == 0 then
        return nil
    end
    return actor.attacks[actor.currentAttackIndex].attack
end

function restartGame()
    print("=== RESTARTING GAME ===")
    
    -- Загружаем карту заново
    local hexStatuses
    terrainMap, entities, width, height, hexStatuses = environment.loadMapFromTiled('maps/map1.lua')
    
    -- Пересоздаём hex-сетку (размеры могли не измениться, но лучше пересоздать)
    hex = require("hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R
    )
    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Сбрасываем статусы на карте
    status.initHexStatuses(hexStatuses)
    
    -- Сброс глобального здоровья
    globalHealth = { current = 5, max = 5, initial = 5 }
    
    -- Сброс состояния игры
    turnState = {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4
    }
    
    -- Инициализация врагов (сброс флагов)
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
    
    -- Выбираем первого союзника
    selectedActor = nil
    for _, a in ipairs(entities) do
        if a.isPlayable and a.health > 0 then
            selectedActor = a
            hex.selectedQ, hex.selectedR = a.q, a.r
            break
        end
    end
    
    -- Сброс флагов действий для союзников
    for _, a in ipairs(entities) do
        if a.isPlayable then
            a.hasActedThisTurn = false
            a.hasMovedThisTurn = false
        end
    end
    
    -- Сброс глобального заклинания ветра
    windTorrent = combat.WindTorrentAttack.new()
    
    -- Сброс UI
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
    actionHistory = {}
    pushAnimations = { queue = {}, active = false }
    visual.effects = {}  -- очищаем визуальные эффекты
    
    -- Обновляем кнопки атак для выбранного персонажа
    updateAttackButtons(selectedActor)
    
    -- Запускаем фазу подготовки врагов
    startEnemyPreparePhase()
    
    print("=== GAME RESTARTED ===")

    turnCount = 0
    gameActive = true
    win = false
    loss = false
    fireAppliedForTurnLimit = false
    status.clearAllDigSites()
    print("=== GAME RESTARTED ===")
end

function refreshAllEnemyPreparations(entities, hex)
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack then
            ai.refreshPreparedAttack(e, entities, hex)
        end
    end
end

-- Атака очищает историю движений
function performAttackWithSelectedAttack(attacker, targetQ, targetR, attack)
    print("[DEBUG] performAttackWithSelectedAttack called")
    print("  attacker:", attacker and attacker.name, "hasActed:", attacker and attacker.hasActedThisTurn)
    print("  targetQ,targetR:", targetQ, targetR)
    print("  attack:", attack and attack.name)

    if not attacker.isPlayable then
        print("[DEBUG] Not a playable character")
        return false, "Not a playable character"
    end
    if attacker.hasActedThisTurn then
        print("[DEBUG] Already acted this turn")
        return false, "Already acted this turn"
    end
    if not attack then
        print("[DEBUG] No attack selected")
        return false, "No attack selected"
    end

    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    print("[DEBUG] Distance to target:", distance, "Attack range:", attack.range)
    if distance > attack.range then
        return false, "Target out of range"
    end

    -- Больше не проверяем, есть ли сущность в целевой клетке
    -- Атака может быть направлена в любую клетку (пустую или занятую)
    -- Логика поиска цели реализована в attack:execute

    print("[DEBUG] Executing attack...")
    local success, message = attack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    print("[DEBUG] Attack result:", success, message)

    if success then
        attacker.hasActedThisTurn = true
        actionHistory = {}
        print(attacker.name .. " attacked and ended turn. Move history cleared.")
        attackMode = false
        selectedAttack = nil
        checkGameEnd()   -- <-- добавить
    else
        print("Attack failed: " .. (message or "unknown"))
    end
    return success, message
end

-- Проверка, находится ли актер на краю карты
function isAtEdge(entity)
    return entity.q == 0 or entity.q == hex.gridWidth - 1 or entity.r == 0 or entity.r == hex.gridHeight - 1
end

function getEnemyAttackOrder(entities, turnState)
    local order = {}
    local queue = {}

    if turnState.phase == "enemy_attack" then
        queue = turnState.enemyAttackQueue or {}
    else
        -- фаза player / enemy_prepare: порядок такой же, как при формировании очереди в endTurn()
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 then
                table.insert(queue, e)
            end
        end
    end

    for i, enemy in ipairs(queue) do
        order[enemy] = i
    end
    return order
end

-- Проверка, можно ли пройти через клетку (для построения пути)
function isCellPassable(q, r, movingEntity)
    if not hex:isActiveHex(q, r) then return false end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then return false end
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            -- Враг или препятствие – непроходимо
            if not e.isPlayable then
                return false
            end
            -- Союзник – проходимо
        end
    end
    return true
end

-- Проверка, занята ли клетка для остановки (нельзя заканчивать движение на занятой клетке)
function isCellOccupiedForStop(q, r, movingEntity)
    if not hex:isActiveHex(q, r) then return true end
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            return true
        end
    end
    return false
end

-- Убить союзного актера на краю карты
function killPlayableAtEdge()
    for i = #entities, 1, -1 do
        local actor = entities[i]
        if actor.isPlayable and isAtEdge(actor) then
            print(actor.name .. " is on the edge of the map and falls to their death!")
            table.remove(entities, i)
            if sounds.death then
                sounds.death:play()
            end
        end
    end
end

function clearSelectedActor()
    selectedActor = nil
    hex.selectedQ = -1
    hex.selectedR = -1
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
end

function restoreSelectedActor()
    for _, a in ipairs(entities) do
        if a.isPlayable and a.health > 0 then
            selectedActor = a
            hex.selectedQ, hex.selectedR = a.q, a.r
            updateAttackButtons(selectedActor)
            break
        end
    end
end
-- Удалить любые упоминания drawAttackIndicators и обработку правой кнопки
-- В love.keypressed убрать обработку tab
function love.keypressed(key)
    if key == "u" or key == "U" then
        if #actionHistory > 0 then undoLastAction() end
    elseif key == "e" or key == "E" then
        if turnState.phase == "player" then endTurn() end
    elseif key == "escape" then
        if windTorrentUI.active then
            windTorrentUI.active = false
            restoreSelectedActor()  -- <-- восстанавливаем выделение
            print("Wind Torrent cancelled")
            return
        end
    end
end

-- Функция обработки выкопок (вызывать после вражеских атак)
function processDigSites()
    -- 1. Урон существам, стоящим на выкопках
    for _, entity in ipairs(entities) do
        if entity.health > 0 and status.hasDigSite(entity.q, entity.r) then
            local wasDestroyed = entity:takeDamage(1, globalHealth)
            print(string.format("💀 %s stepped on a dig site and takes 1 damage!", entity.name))
            if sounds and sounds.collision then sounds.collision:play() end
            if wasDestroyed then
                entity:startDeath()
            end
            status.stepOnDigSite(entity.q, entity.r)
        end
    end

    -- 2. Удаляем мёртвых
    for i = #entities, 1, -1 do
        if entities[i].health <= 0 then
            table.remove(entities, i)
        end
    end

    -- 3. Спавн из готовых выкопок
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
        if not occupied and terrain ~= "water" then
            local newEnemy = environment.createRandomEnemy(dig.q, dig.r)
            table.insert(entities, newEnemy)
            local x, y = hex:hexToPixel(dig.q, dig.r)
            visual.addEffect(x, y, "dig", 0.5)
            print(string.format("🌀 A %s digs out at (%d,%d)!", newEnemy.name, dig.q, dig.r))
        else
            print(string.format("Dig site at (%d,%d) blocked, no spawn", dig.q, dig.r))
        end
        status.removeDigSite(dig.q, dig.r)
    end

    -- 4. Старение выкопок
    status.ageDigSites()

    -- 5. Создание новых выкопок до 7 врагов
    local aliveEnemies = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            aliveEnemies = aliveEnemies + 1
        end
    end
    local needed = 7 - aliveEnemies
    if needed > 0 then
        local candidates = {}
        for q = 0, hex.gridWidth - 1 do
            for r = 0, hex.gridHeight - 1 do
                if hex:isActiveHex(q, r) then
                    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                    if terrain ~= "water" then
                        local occupied = false
                        for _, e in ipairs(entities) do
                            if e.q == q and e.r == r then
                                occupied = true
                                break
                            end
                        end
                        if not occupied and not status.hasDigSite(q, r) then
                            table.insert(candidates, {q = q, r = r})
                        end
                    end
                end
            end
        end
        -- Перемешивание
        for i = #candidates, 2, -1 do
            local j = love.math.random(i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end
        for i = 1, math.min(needed, #candidates) do
            local spot = candidates[i]
            status.setDigSite(spot.q, spot.r, 1)
            print(string.format("🕳️ New dig site at (%d,%d)", spot.q, spot.r))
        end
    end
end