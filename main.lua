-- main.lua
combat = require("combat") --почему для этого нужна переменная?
ai = require("ai")
require("hexgrid")
environment = require("environment")
status = require("status")
ui = require("ui")
pathfinding = require("pathfinding")

-- Делаем очередь анимаций доступной глобально для отрисовки
pushAnimations = pushAnimations or { queue = {}, active = false }

DEBUG_COMBAT = true

windTorrent = nil
windTorrentUI = {
    active = false,
    button = { x = 10, y = 240, width = 120, height = 30 },
    directions = {}
}

function love.load()
    -- Загружаем шрифт с поддержкой эмодзи (размер 16px)
    local emojiFont = love.graphics.newFont("unifont-15.1.04.otf", 16)
    love.graphics.setFont(emojiFont)

    selectedAttack = nil   -- текущая выбранная атака (объект)
    attackMode = false
    attackButtons = {}     -- кнопки атак для текущего персонажа

    sti = require 'libraries/sti'
    local env = require("environment")
    local hexStatuses
    terrainMap, entities, width, height, hexStatuses = env.loadMapFromTiled('maps/map1.lua')
    hex = require("hexgrid").new(56, width, height)  -- используем реальные ширину/высоту из карты
    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())

    -- Инициализируем глобальную таблицу статусов:
    status.initHexStatuses(hexStatuses) -- добавить в status.lua функцию
    hex = require("hexgrid").new(56, 11, 11)
    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())
    status.initHexStatuses(hexStatuses)

    globalHealth = { current = 5, max = 5, initial = 5 }

    -- Состояние игры
    turnState = {
        phase = "enemy_prepare",   -- "enemy_prepare" → "player" → "enemy_attack"
        enemyPrepareQueue = {},    -- очередь врагов на движение+подготовку
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4
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

    -- Инициализация UI ветра (позиции кнопок направлений)
    local startX = love.graphics.getWidth() - 160
    local startY = 100
    local dirIndex = 1
    -- Новый порядок для flat-top: восток, северо-восток, северо-запад, запад, юго-запад, юго-восток
    local dirOrder = {"E", "NE", "NW", "W", "SW", "SE"}
    for _, dirName in ipairs(dirOrder) do
        local row = math.floor((dirIndex - 1) / 2)
        local col = (dirIndex - 1) % 2
        windTorrentUI.directions[dirName] = {
            x = startX + col * 75,
            y = startY + row * 35,
            name = dirName
        }
        dirIndex = dirIndex + 1
    end
    
    windTorrentUI.button = { x = 10, y = 240, width = 120, height = 30, isHovered = false }
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

-- Изменить love.mousepressed (удалить button == 2, добавить обработку кнопок атак и режима атаки)
function love.mousepressed(x, y, button)
    if button == 1 then
        -- ======================================================
        -- 1. СНАЧАЛА проверяем ВСЕ UI-кнопки (не зависят от гексов)
        -- ======================================================

        -- Кнопка Wind Torrent
        if x >= windTorrentUI.button.x and x <= windTorrentUI.button.x + windTorrentUI.button.width and
           y >= windTorrentUI.button.y and y <= windTorrentUI.button.y + windTorrentUI.button.height then
            if turnState.phase == "player" and windTorrent and not windTorrent.hasBeenUsed then
                windTorrentUI.active = true
                print("Select wind direction...")
            elseif windTorrent and windTorrent.hasBeenUsed then
                print("Wind Torrent has already been used this game!")
            elseif turnState.phase ~= "player" then
                print("Can only use Wind Torrent during your turn!")
            else
                print("Wind Torrent not available")
            end
            return
        end

        -- Режим выбора направления ветра
        if windTorrentUI.active then
            for dirName, dir in pairs(windTorrentUI.directions) do
                if x >= dir.x and x <= dir.x + 70 and y >= dir.y and y <= dir.y + 30 then
                    windTorrent:executeGlobalWithAnimation(dirName, hex, entities, sounds, function(success, message)
                        if success then
                            actionHistory = {}
                            print("Wind Torrent used! History cleared.")
                        else
                            print("Wind Torrent failed: " .. (message or "unknown error"))
                        end
                    end)
                    windTorrentUI.active = false
                    return
                end
            end
            local cancelX = love.graphics.getWidth() / 2 - 40
            local cancelY = love.graphics.getHeight() - 80
            if x >= cancelX and x <= cancelX + 80 and y >= cancelY and y <= cancelY + 30 then
                windTorrentUI.active = false
                print("Wind Torrent cancelled")
                return
            end
            windTorrentUI.active = false
            print("Wind Torrent cancelled (click outside)")
            return
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

-- При начале хода игрока сбросить attackMode и selectedAttack
-- В startEnemyPreparePhase или prepareAllEnemies добавить сброс перед переходом к игроку
function prepareAllEnemies()
    local enemies = ai.getLivingEnemies(entities)
    for _, enemy in ipairs(enemies) do
        ai.prepareAttackForEnemy(enemy, entities, hex)
    end
    turnState.phase = "player"
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

-- Обновление фазы атаки врагов (по очереди)
function updateEnemyAttacks(dt)
    if turnState.phase ~= "enemy_attack" then
        return
    end

    if #turnState.enemyAttackQueue == 0 then
        -- Все враги атаковали → переходим к следующей подготовке
        turnState.phase = "enemy_prepare"
        prepareAllEnemies()
        return
    end

    turnState.enemyAttackTimer = turnState.enemyAttackTimer + dt
    if turnState.enemyAttackTimer >= turnState.delayBetweenAttacks then
        turnState.enemyAttackTimer = 0
        local enemy = table.remove(turnState.enemyAttackQueue, 1)
        if enemy and enemy.health > 0 then
            ai.executePreparedAttack(enemy, entities, hex, sounds)
        end
    end
end

-- Функция завершения хода игрока
function endTurn()
    if turnState.phase ~= "player" then
        print("Cannot end turn now")
        return
    end
    -- Принудительно завершаем ход для всех, кто не атаковал
    for _, a in ipairs(entities) do
        if a.isPlayable and not a.hasActedThisTurn then
            a.hasActedThisTurn = true
            print(a.name .. " did not attack, turn ended.")
        end
    end
    -- Собираем врагов для атаки
    local attackers = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 then
            table.insert(attackers, e)
        end
    end
    turnState.enemyAttackQueue = attackers
    turnState.enemyAttackTimer = 0
    turnState.phase = "enemy_attack"
    print("=== ENEMY ATTACK PHASE ===")
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

-- Отмена последнего движения (работает только если не было атаки)
function undoLastAction()
    if #actionHistory == 0 then
        print("No moves to undo!")
        return false
    end
    
    local action = actionHistory[#actionHistory]
    local actor = action.actor
    
    if not actor or actor.health <= 0 then
        table.remove(actionHistory)
        return undoLastAction()
    end
    
    if actor.isMoving then
        print("Cannot undo while moving")
        return false
    end
    
    -- Откатываем позицию
    actor.q = action.fromQ
    actor.r = action.fromR
    actor.hasActedThisTurn = false   -- разрешаем атаковать снова
    actor.hasMovedThisTurn = false   -- разрешаем двигаться снова
    actor.isMoving = false
    actor.path = {}
    actor.currentPathIndex = 0
    
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

-- Добавление движения в историю
function addToHistory(actor, fromQ, fromR, toQ, toR)
    if not actor.isPlayable then return end
    table.insert(actionHistory, {
        actor = actor,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        type = "move"
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
    -- Проверяем, есть ли сущность на клетке
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            -- Если сущность – союзник, то проходим (не блокируем)
            if isAlly(movingEntity, e) then
                return false   -- союзник не мешает
            else
                return true    -- враг или препятствие блокирует
            end
        end
    end
    return false
end

function killEntitiesOnWater()
    for i = #entities, 1, -1 do
        local e = entities[i]
        if e:isCharacter() then    -- только живые существа
            local isWater = terrainMap and terrainMap[e.q] and terrainMap[e.q][e.r] == "water"
            if isWater then
                print(string.format("💧 %s stands on water and dies!", e.name))
                if sounds and sounds.collision then sounds.collision:play() end
                table.remove(entities, i)
            end
        end
    end
end

function getEntityAtHex(q, r)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then
            return e
        end
    end
    return nil
end

-- performMove (убрана проверка isEdgeCell)
function performMove(actor, targetQ, targetR)
    if not actor.isPlayable then return false end
    if not hex:isActiveHex(targetQ, targetR) then  -- используем isActiveHex
        print("Target cell is outside the playable hexagon")
        return false
    end
    if actor.isMoving or actor.hasActedThisTurn then return false end
    if actor.hasMovedThisTurn then
        print(actor.name .. " has already moved this turn! You can still attack.")
        return false
    end
    if actor.q == targetQ and actor.r == targetR then return false end
    local distance = hex:getDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        print("Too far")
        return false
    end
    if isPositionOccupied(targetQ, targetR, actor) then
        print("Cell occupied")
        return false
    end
    local path = pathfinding.findPath(actor.q, actor.r, targetQ, targetR, actor.moveRange,
        function(q, r) return isPositionOccupied(q, r, actor) end, hex)
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
            if not actor.isMoving and actor.currentPathIndex > #actor.path then
                status.onMoveFinished(actor, actor.q, actor.r, terrainMap, globalHealth)
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

function applyFireDamageToAll()
    status.applyFireDamage(entities, hex, terrainMap, globalHealth)
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
        -- Уже подготовлен, сразу переходим к следующему
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    elseif status == "failed" then
        -- Не может подготовиться (нет целей или движение невозможно)
        -- Просто пропускаем этого врага
        print(enemy.name .. " cannot prepare attack, skipping")
        turnState.currentPreparingEnemy = nil
        processNextEnemyPrepare()
    elseif status == "moving" then
        -- Будем ждать завершения движения в love.update
        -- Ничего не делаем, ждём установки enemy.movementFinished
    end
end

function love.update(dt)
    -- Обновление анимаций движения всех сущностей (включая врагов)
    for _, actor in ipairs(entities) do
        updateActorMovement(actor, dt)
        ai.updateEnemyMovement(actor, dt, hex)  -- внутри проверяет isMoving
        if actor.pulse then
            actor.pulse = actor.pulse + dt * (actor.pulseSpeed or 5)
        end
    end
    combat.updatePushAnimations(dt, hex)

    if turnState.phase == "enemy_prepare" and turnState.currentPreparingEnemy then
        local enemy = turnState.currentPreparingEnemy
        if not enemy or enemy.health <= 0 then
            turnState.currentPreparingEnemy = nil
            processNextEnemyPrepare()
        elseif not enemy.isMoving and enemy.movementFinished then
            ai.prepareAttackForEnemy(enemy, entities, hex)
            enemy.movementFinished = false
            turnState.currentPreparingEnemy = nil
            processNextEnemyPrepare()
        elseif not enemy.isMoving and not enemy.movementFinished then
            -- Движение не началось и не завершилось – возможно, moveAndPrepare вернул "prepared" или "failed"
            -- В любом случае, завершаем обработку этого врага
            if not enemy.hasPreparedAttack then
                -- Пробуем подготовить, если цель рядом
                local dist = ai.getDistanceToNearestPlayer(enemy, entities, hex)
                if dist == 1 then
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
            end
        end
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
    -- Проверяем, не оказался ли кто на воде
    killEntitiesOnWater()
end

function drawHexGrid()
    -- Сначала рисуем terrain текстуры (под всеми сущностями)
    if environment.terrainTextures then
        for q = 0, hex.gridWidth - 1 do
            for r = 0, hex.gridHeight - 1 do
                if not hex:isActiveHex(q, r) then goto continue end
                local texture = environment.terrainTextures[q] and environment.terrainTextures[q][r]
                if texture then
                    local x, y = hex:hexToPixel(q, r)
                    local sw, sh = texture:getDimensions()
                    local scaleX = (hex.radius * 2) / sw
                    local scaleY = (hex.radius * 2) / sh
                    -- 👇 ВАЖНО: сбрасываем цвет на белый перед рисованием текстуры
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(texture, x, y, 0, scaleX, scaleY, sw/2, sh/2)
                else
                    -- fallback цвет для клеток без текстуры (только если нужно)
                    love.graphics.setColor(0.2, 0.2, 0.2, 0.5)
                    local x, y = hex:hexToPixel(q, r)
                    local vertices = hex:drawHexagon(x, y, hex.radius)
                    love.graphics.polygon("fill", vertices)
                end
                ::continue::
            end
        end
    end

    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            local hexStatuses = status.getAtHex(q, r)
            if #hexStatuses > 0 then
                local x, y = hex:hexToPixel(q, r)
                for i, st in ipairs(hexStatuses) do
                    if st == "fire" then
                        love.graphics.setColor(1, 0.5, 0, 0.8)
                        love.graphics.circle("fill", x - 15 + i*10, y - 15, 6)
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.print("🔥", x - 18 + i*10, y - 22)
                    elseif st == "acid" then
                        love.graphics.setColor(0.5, 1, 0, 0.8)
                        love.graphics.circle("fill", x - 15 + i*10, y - 15, 6)
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.print("🧪", x - 18 + i*10, y - 22)
                    end
                end
            end
        end
    end
    
    -- Затем рисуем выделения и границы
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            local x, y = hex:hexToPixel(q, r)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            
            -- Выделения (выбранный, ховер, и т.д.)
            local hasEntity = getEntityAtHex(q, r) ~= nil
            local isCurrentActor = selectedActor and selectedActor.q == q and selectedActor.r == r
            
            if isCurrentActor then
                love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
                love.graphics.polygon("fill", vertices)
            elseif hex.selectedQ == q and hex.selectedR == r then
                love.graphics.setColor(0.2, 0.4, 0.8, 0.5)
                love.graphics.polygon("fill", vertices)
            elseif hex.hoverQ == q and hex.hoverR == r then
                love.graphics.setColor(0.5, 0.8, 0.3, 0.5)
                love.graphics.polygon("fill", vertices)
            end
            
            -- Рамка
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.polygon("line", vertices)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Функция для получения позиции отрисовки сущности с учётом всех анимаций
function getEntityDrawPosition(entity)
    -- Проверяем глобальную очередь pushAnimations (отталкивания, ветер)
    local pushAnim = nil
    if pushAnimations and pushAnimations.queue then
        for _, anim in ipairs(pushAnimations.queue) do
            if anim.obj == entity and anim.isMoving then
                pushAnim = anim
                break
            end
        end
    end
    
    if pushAnim then
        -- Активная анимация смещения (push, wind, collision)
        local t = math.min(1, pushAnim.timer / pushAnim.duration)
        -- Используем easing для плавности
        local easeOut = 1 - (1 - t) * (1 - t)
        if pushAnim.startX and pushAnim.endX then
            local x = pushAnim.startX + (pushAnim.endX - pushAnim.startX) * easeOut
            local y = pushAnim.startY + (pushAnim.endY - pushAnim.startY) * easeOut
            return x, y
        else
            -- Fallback: просто координаты гекса
            return hex:hexToPixel(entity.q, entity.r)
        end
    elseif entity.isMoving then
        -- Обычное движение по пути (step-by-step movement)
        local t = entity.timer / entity.speed
        if t >= 1 then t = 1 end
        -- Используем easing для плавного старта и остановки
        local easeInOut = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
        local x = entity.startX + (entity.endX - entity.startX) * easeInOut
        local y = entity.startY + (entity.endY - entity.startY) * easeInOut
        return x, y
    else
        -- Статическое положение
        return hex:hexToPixel(entity.q, entity.r)
    end
end

-- Унифицированная отрисовка полоски здоровья для любых сущностей
function drawHealthBar(entity, x, y)
    -- Показываем полоску только если есть максимальное здоровье > 1
    if not entity.maxHealth or entity.maxHealth <= 1 then
        return
    end
    
    local barWidth = 40
    local barHeight = 6
    local healthPercent = math.max(0, entity.health / entity.maxHealth)
    
    -- Для зданий используем другой цвет
    local bgColor, fgColor
    if entity:isBuilding() then
        bgColor = {0.5, 0.3, 0.1, 0.8}
        fgColor = {0.9, 0.6, 0.2, 0.8}
    elseif entity:isObstacle() then
        bgColor = {0.4, 0.2, 0.1, 0.8}
        fgColor = {0.6, 0.4, 0.2, 0.8}
    else
        bgColor = {0.5, 0, 0, 0.8}
        fgColor = {0, 1, 0, 0.8}
    end
    
    -- Фон
    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", x - barWidth/2, y - 28, barWidth, barHeight, 2)
    
    -- Заполнение
    love.graphics.setColor(fgColor)
    love.graphics.rectangle("fill", x - barWidth/2, y - 28, barWidth * healthPercent, barHeight, 2)
    
    -- Рамка
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", x - barWidth/2, y - 28, barWidth, barHeight, 2)
    
    -- Текст здоровья (только для персонажей и если достаточно места)
    if entity:isCharacter() then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(entity.health .. "/" .. entity.maxHealth, x - 15, y - 40)
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

-- Унифицированная отрисовка любой сущности
function drawEntity(entity)
    local x, y = getEntityDrawPosition(entity)
    
    if entity.isPlayable and entity.hasMovedThisTurn and not entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.8, 0.5, 0.9)
        love.graphics.print("🏃", x + 18, y - 20)
    end

    if entity.sprite then
        local sw, sh = entity.sprite:getDimensions()
        local scale = 6
        if selectedActor == entity and entity:isCharacter() then
            scale = 6 + math.sin(entity.pulse) * 0.2
        end
        -- pivot в центр спрайта
        love.graphics.draw(entity.sprite, x, y, 0, scale, scale, sw/2, sh/2)
    else
        -- fallback круг
        love.graphics.setColor(entity.color or {1, 1, 1, 1})
        love.graphics.circle("fill", x, y, 14)
    end
    
    -- Имя сущности (только для персонажей)
    if entity:isCharacter() then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(entity.name, x - 20, y - 25)
    end

    local entityStatuses = status.getEntityStatuses(entity)
    if #entityStatuses > 0 then
        for i, st in ipairs(entityStatuses) do
            if st == "fire" then
                love.graphics.setColor(1, 0.5, 0, 1)
                love.graphics.print("🔥", x - 25 + i*10, y - 25)
            elseif st == "acid" then
                love.graphics.setColor(0.5, 1, 0, 1)
                love.graphics.print("🧪", x - 25 + i*10, y - 25)
            end
        end
    end
    
    -- Полоска здоровья
    drawHealthBar(entity, x, y)
    
    -- Индикатор действия
    drawActionIndicator(entity, x, y)
    
    -- Рамка выделения для выбранного персонажа
    if selectedActor == entity and entity:isCharacter() then
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


-- В love.draw добавить вызовы:
function love.draw()
    drawHexGrid()
    drawAllEntities()
    ui.drawPreparedAttacks(hex, entities)
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
    ui.drawWindTorrentUI(windTorrent, windTorrentUI, turnState)
    ui.drawGlobalHealthBar(globalHealth)
    ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode)
    love.graphics.setColor(1,1,1,1)
    love.graphics.print("Phase: " .. turnState.phase, 10, 10)
    if selectedActor then
        love.graphics.print("Selected: " .. selectedActor.name .. (selectedActor.hasActedThisTurn and " (acted)" or ""), 10, 30)
    end
    love.graphics.print("Left click: Move / Attack (after selecting attack)", 10, 130)
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
    else
        print("Attack failed: " .. (message or "unknown"))
    end
    return success, message
end

-- Проверка, находится ли актер на краю карты
function isAtEdge(entity)
    return entity.q == 0 or entity.q == hex.gridWidth - 1 or entity.r == 0 or entity.r == hex.gridHeight - 1
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

-- Удалить любые упоминания drawAttackIndicators и обработку правой кнопки
-- В love.keypressed убрать обработку tab
function love.keypressed(key)
    if key == "u" or key == "U" then
        if #actionHistory > 0 then undoLastAction() end
    elseif key == "e" or key == "E" then
        if turnState.phase == "player" then endTurn() end
    end
    -- Tab больше не переключает атаку
end