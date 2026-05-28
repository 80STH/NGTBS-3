-- main.lua
combat = require("combat") --почему для этого нужна переменная?
ai = require("ai")
require("hexgrid")
require("environment")

-- Делаем очередь анимаций доступной глобально для отрисовки
pushAnimations = pushAnimations or { queue = {}, active = false }

DEBUG_COMBAT = true  -- Включает подробный вывод отладки боя

windTorrent = nil  -- будет инициализирован в love.load()
windTorrentUI = {
    active = false,           -- режим выбора направления
    button = {
        x = 10, y = 240, width = 120, height = 30
    },
    directions = {
        north = { x = 0, y = 0, name = "↑ North" },
        northeast = { x = 0, y = 0, name = "↗ Northeast" },
        southeast = { x = 0, y = 0, name = "↘ Southeast" },
        south = { x = 0, y = 0, name = "↓ South" },
        southwest = { x = 0, y = 0, name = "↙ Southwest" },
        northwest = { x = 0, y = 0, name = "↖ Northwest" }
    }
}

function love.load()
    sti = require 'libraries/sti'

    -- Загружаем карту и получаем terrainMap + entities
    local env = require("environment")
    terrainMap, entities = env.loadMapFromTiled('maps/map1.lua')

    -- Инициализация гексагональной сетки (под размеры карты)
    hex = require("hexgrid").new(60, 13, 11)   -- ширина=13, высота=11
    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())

    -- Глобальное здоровье (если нужно)
    globalHealth = { current = 5, max = 5, initial = 5 }

    -- Разделяем для удобства (если нужно быстро получить отдельные списки)
    function getPlayableActors()
        local result = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and e.isPlayable then
                table.insert(result, e)
            end
        end
        return result
    end

    function getEnemies()
        local result = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable then
                table.insert(result, e)
            end
        end
        return result
    end

    function getObstacles()
        local result = {}
        for _, e in ipairs(entities) do
            if e:isObstacle() or e:isBuilding() then
                table.insert(result, e)
            end
        end
        return result
    end

    
    -- Глобальный стек действий для отмены
    actionHistory = {}
    
    -- ПОШАГОВАЯ СИСТЕМА
    turnState = {
        currentTurn = 1,
        currentActorIndex = 1,
        turnPhase = "waiting",     -- "waiting" или "moving" или "attacking"
        actionsRemaining = {},
        waitingForEnemies = false, -- Ожидание хода врагов
        enemyTurnTimer = 0
    }
    
    endTurnButton = {
        x = 10,
        y = 280,  -- сдвигаем ниже
        width = 120,
        height = 30,
        text = "End Turn",
        isHovered = false
    }
    
    -- Инициализируем счетчики действий для всех актеров
    for i, actor in ipairs(entities) do
        if actor.isPlayable then
            turnState.actionsRemaining[i] = 1
        else
            turnState.actionsRemaining[i] = 0  -- Враги начинают без действий
            actor.hasActedThisTurn = false
        end
    end
    
    -- Находим первого играбельного актера
    for i, actor in ipairs(entities) do
        if actor.isPlayable and turnState.actionsRemaining[i] > 0 then
            turnState.currentActorIndex = i
            selectedActor = actor
            hex.selectedQ = actor.q
            hex.selectedR = actor.r
            break
        end
    end
    
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
    
    function countPlayableActors()
        local count = 0
        for _, actor in ipairs(entities) do
            if actor.isPlayable then
                count = count + 1
            end
        end
        return count
    end

    maxUndoCount = countPlayableActors()

        -- Создаём глобальное заклинание ветра
    windTorrent = combat.WindTorrentAttack.new()
    
    -- ... остальной код ...
    
    -- Подсчитаем позиции для кнопок направлений на правой панели
    local startX = love.graphics.getWidth() - 160
    local startY = 100
    local dirIndex = 1
    local dirOrder = {"north", "northeast", "southeast", "south", "southwest", "northwest"}
    for _, dirName in ipairs(dirOrder) do
        local row = math.floor((dirIndex - 1) / 2)
        local col = (dirIndex - 1) % 2
        windTorrentUI.directions[dirName].x = startX + col * 75
        windTorrentUI.directions[dirName].y = startY + row * 35
        dirIndex = dirIndex + 1
    end
    
    -- Кнопка Wind Torrent
    windTorrentUI.button.x = 10
    windTorrentUI.button.y = 240
    windTorrentUI.button.width = 120
    windTorrentUI.button.height = 30
end

-- Функция завершения хода
function endTurn()
    -- Проверяем, не начался ли уже ход врагов
    if turnState.waitingForEnemies then
        print("Enemies are already acting!")
        return
    end

    -- === УДАЛЯЕМ проверку, что все союзники сходили ===
    -- (раньше здесь был цикл allAlliesActed и return)

    -- Принудительно помечаем всех союзников как "сходивших" (пропуск хода для неходивших)
    for _, actor in ipairs(entities) do
        if actor.isPlayable and not actor.hasActedThisTurn then
            actor.hasActedThisTurn = true
            print(actor.name .. " skipped turn (end turn forced)")
        end
    end

    -- Очищаем историю действий при завершении хода
    actionHistory = {}
    print("Action history cleared at end of turn.")

    -- Начинаем ход врагов
    turnState.waitingForEnemies = true
    turnState.enemyTurnTimer = 0
    print("=== ENEMY TURN START ===")
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

-- Глобальная функция отмены последнего действия (не привязана к выбранному актеру)
function undoLastAction()
    if #actionHistory == 0 then
        print("No actions to undo! (0/" .. maxUndoCount .. ")")
        return false
    end
    
    local lastAction = actionHistory[#actionHistory]
    
    -- Проверяем, не был ли актер уничтожен
    local actorExists = false
    local currentActor = nil
    for _, actor in ipairs(entities) do
        if actor == lastAction.actor then
            actorExists = true
            currentActor = actor
            break
        end
    end
    
    if not actorExists then
        print("Actor no longer exists!")
        table.remove(actionHistory)
        return undoLastAction()  -- Рекурсивно пробуем следующее действие
    end
    
    -- Проверяем, не двигается ли актер
    if currentActor.isMoving then
        print("Cannot undo action while moving!")
        return false
    end
    
    -- Проверяем, можно ли отменить (актер должен был совершить действие в этом ходу)
    if not currentActor.hasActedThisTurn then
        print(currentActor.name .. " hasn't performed an action this turn yet!")
        return false
    end
    
    -- Откатываем позицию актера
    currentActor.q = lastAction.fromQ
    currentActor.r = lastAction.fromR
    
    -- Сбрасываем флаги
    currentActor.hasActedThisTurn = false
    currentActor.isMoving = false
    currentActor.path = {}
    currentActor.currentPathIndex = 0
    
    -- Обновляем выделение, если это выбранный актер
    if selectedActor == currentActor then
        hex.selectedQ = currentActor.q
        hex.selectedR = currentActor.r
    end
    
    -- Восстанавливаем счетчик действий
    for i, a in ipairs(entities) do
        if a == currentActor then
            turnState.actionsRemaining[i] = 1
            break
        end
    end
    
    -- Удаляем действие из истории
    table.remove(actionHistory)
    
    sounds.undo:play()
    print("Undone action: " .. currentActor.name)
    print("Undos remaining: " .. #actionHistory .. "/" .. maxUndoCount)
    return true
end

function isPositionOccupied(q, r, movingEntity)
    for _, entity in ipairs(entities) do
        if entity ~= movingEntity and entity.q == q and entity.r == r then
            return true
        end
    end
    return false
end

function addToHistory(actor, fromQ, fromR, toQ, toR)
    local action = {
        actor = actor,
        fromQ = fromQ,
        fromR = fromR,
        toQ = toQ,
        toR = toR,
        turnNumber = turnState.currentTurn
    }
    
    table.insert(actionHistory, action)
    
    -- Обновляем максимальное количество отмен (на случай, если появятся новые союзники)
    maxUndoCount = countPlayableActors()
    
    -- Ограничиваем историю до КОЛИЧЕСТВА СОЮЗНЫХ ЮНИТОВ
    while #actionHistory > maxUndoCount do
        local removed = table.remove(actionHistory, 1)
        print("History exceeded limit (" .. maxUndoCount .. "), removed old action for " .. (removed.actor and removed.actor.name or "unknown"))
    end
    
    print("Added action for " .. actor.name .. ". History: " .. #actionHistory .. "/" .. maxUndoCount)
end

-- Проверка занятости (для движения)
function isPositionOccupied(q, r, movingEntity)
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

function findPath(startQ, startR, targetQ, targetR, movingActor)
    if startQ == targetQ and startR == targetR then
        return {}
    end
    
    local nodeInfo = {}
    local startKey = startQ .. "," .. startR
    nodeInfo[startKey] = {
        q = startQ,
        r = startR,
        g = 0,
        parent = nil
    }
    
    local openSet = {startKey}
    local closedSet = {}
    
    while #openSet > 0 do
        local currentKey = openSet[1]
        local currentIndex = 1
        
        for i, key in ipairs(openSet) do
            if nodeInfo[key].g < nodeInfo[currentKey].g then
                currentKey = key
                currentIndex = i
            end
        end
        
        table.remove(openSet, currentIndex)
        local current = nodeInfo[currentKey]
        
        if current.q == targetQ and current.r == targetR then
            local path = {}
            local node = current
            while node.parent do
                table.insert(path, 1, {q = node.q, r = node.r})
                node = node.parent
            end
            return path
        end
        
        closedSet[currentKey] = true
        local neighbors = hex:getNeighbors(current.q, current.r)
        
        for _, neighbor in ipairs(neighbors) do
            local neighborKey = neighbor.q .. "," .. neighbor.r
            
            if not closedSet[neighborKey] and hex:isValidHex(neighbor.q, neighbor.r) then
                -- Союзники не могут проходить через край карты
                if movingActor.isPlayable and isEdgeCell(neighbor.q, neighbor.r) then
                    goto continue
                end
                
                if not isPositionOccupied(neighbor.q, neighbor.r, movingActor) then
                    local tentativeG = current.g + 1
                    
                    if not nodeInfo[neighborKey] then
                        nodeInfo[neighborKey] = {
                            q = neighbor.q,
                            r = neighbor.r,
                            g = tentativeG,
                            parent = current
                        }
                        table.insert(openSet, neighborKey)
                    elseif tentativeG < nodeInfo[neighborKey].g then
                        nodeInfo[neighborKey].g = tentativeG
                        nodeInfo[neighborKey].parent = current
                    end
                end
            end
            ::continue::
        end
    end
    
    return nil
end

function performMove(actor, targetQ, targetR)
    if actor.isMoving then return false end
    if actor.q == targetQ and actor.r == targetR then return false end
    if actor.isPlayable and isEdgeCell(targetQ, targetR) then
        print(actor.name .. " cannot move to the edge of the map!")
        return false
    end
    
    local distance = hex:getDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        print(actor.name .. " cannot move that far! Max distance: " .. actor.moveRange)
        return false
    end
    
    if isPositionOccupied(targetQ, targetR, actor) then
        print("Cell is occupied!")
        return false
    end
    
    local path = findPath(actor.q, actor.r, targetQ, targetR, actor)
    if not path or #path == 0 then
        print("Path not found!")
        return false
    end
    
    if #path > actor.moveRange then
        print(actor.name .. " cannot move " .. #path .. " cells! Max: " .. actor.moveRange)
        return false
    end
    
    -- ========== НОВОЕ: СРАЗУ ДОБАВЛЯЕМ В ИСТОРИЮ ==========
    addToHistory(actor, actor.q, actor.r, targetQ, targetR)
    -- ===================================================
    
    -- Запоминаем, что действие уже использовано (чтобы нельзя было двигаться повторно)
    actor.hasActedThisTurn = true
    for i, a in ipairs(entities) do
        if a == actor then
            turnState.actionsRemaining[i] = 0
            break
        end
    end
    
    -- Запускаем анимацию
    actor.path = path
    actor.currentPathIndex = 1
    startNextMove(actor)  -- анимация будет обновлять координаты, но историю уже не трогаем
    
    return true
end

-- Функция для отображения доступной дистанции движения с учетом препятствий
function drawMovementRange(actor)
    if not actor or actor.isMoving or actor.hasActedThisTurn then
        return
    end
    
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            -- Пропускаем текущую позицию актера
            if not (q == actor.q and r == actor.r) then
                -- Союзники не могут ходить на край
                if actor.isPlayable and isEdgeCell(q, r) then
                    -- Показываем как запрещенную зону
                    local x, y = hex:hexToPixel(q, r)
                    local vertices = hex:drawHexagon(x, y, hex.radius)
                    love.graphics.setColor(0.5, 0.2, 0.2, 0.3)
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(1, 0.5, 0.5, 0.8)
                    love.graphics.print("⚠", x - 5, y - 8)
                    goto continue
                end
                
                -- Ищем путь до клетки
                local path = findPath(actor.q, actor.r, q, r, actor)
                
                if path and #path > 0 and #path <= actor.moveRange then
                    local isOccupied = isPositionOccupied(q, r, actor)
                    
                    local x, y = hex:hexToPixel(q, r)
                    local vertices = hex:drawHexagon(x, y, hex.radius)
                    
                    if isOccupied then
                        love.graphics.setColor(0.8, 0.2, 0.2, 0.3)
                        love.graphics.polygon("fill", vertices)
                        love.graphics.setColor(1, 1, 1, 0.5)
                        love.graphics.print("🚫", x - 5, y - 8)
                    else
                        love.graphics.setColor(0.3, 0.8, 0.3, 0.35)
                        love.graphics.polygon("fill", vertices)
                        love.graphics.setColor(1, 1, 1, 0.8)
                        love.graphics.print(#path, x - 5, y - 5)
                    end
                end
            end
            ::continue::
        end
    end
end

-- Функция для отображения пути к выбранной клетке (вызывать при наведении)
function drawPathPreview(actor, targetQ, targetR)
    if not actor or actor.isMoving or actor.hasActedThisTurn then
        return
    end
    
    -- Проверяем, можно ли дойти до клетки
    local distance = hex:getDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        return
    end
    
    local path = findPath(actor.q, actor.r, targetQ, targetR, actor)
    if path and #path > 0 and #path <= actor.moveRange then
        
        -- Получаем начальную позицию актера
        local startX, startY = hex:hexToPixel(actor.q, actor.r)
        
        -- Отрисовываем весь путь и стрелки
        local prevX, prevY = startX, startY
        
        for i = 1, #path do
            local step = path[i]
            local x, y = hex:hexToPixel(step.q, step.r)
            
            -- Подсвечиваем клетки пути
            local vertices = hex:drawHexagon(x, y, hex.radius)
            love.graphics.setColor(1, 1, 0, 0.3)
            love.graphics.polygon("fill", vertices)
            
            -- Рисуем стрелку от предыдущей клетки к текущей
            love.graphics.setColor(1, 0.8, 0, 0.8)
            love.graphics.setLineWidth(3)
            
            -- Вычисляем направление стрелки
            local angle = math.atan2(y - prevY, x - prevX)
            local arrowLength = 15
            local arrowSize = 8
            
            -- Рисуем линию
            love.graphics.line(prevX, prevY, x, y)
            
            -- Рисуем наконечник стрелки (на клетке, не в центре, а ближе к концу)
            local arrowX = x - math.cos(angle) * 12
            local arrowY = y - math.sin(angle) * 12
            
            -- Левое крыло стрелки
            local leftAngle = angle + math.pi * 0.8
            local leftX = arrowX + math.cos(leftAngle) * arrowSize
            local leftY = arrowY + math.sin(leftAngle) * arrowSize
            
            -- Правое крыло стрелки
            local rightAngle = angle - math.pi * 0.8
            local rightX = arrowX + math.cos(rightAngle) * arrowSize
            local rightY = arrowY + math.sin(rightAngle) * arrowSize
            
            love.graphics.line(arrowX, arrowY, leftX, leftY)
            love.graphics.line(arrowX, arrowY, rightX, rightY)
            
            -- Обновляем предыдущую позицию
            prevX, prevY = x, y
        end
        
        love.graphics.setLineWidth(1)
        
        -- Дополнительно подсвечиваем целевую клетку ярче
        local targetX, targetY = hex:hexToPixel(targetQ, targetR)
        local targetVertices = hex:drawHexagon(targetX, targetY, hex.radius)
        love.graphics.setColor(1, 0.8, 0, 0.4)
        love.graphics.polygon("fill", targetVertices)
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.polygon("line", targetVertices)
    end
end

function startNextMove(actor)
    if actor.currentPathIndex <= #actor.path then
        local nextStep = actor.path[actor.currentPathIndex]
        actor.isMoving = true
        actor.timer = 0
        actor.targetQ = nextStep.q
        actor.targetR = nextStep.r
        actor.startX, actor.startY = hex:hexToPixel(actor.q, actor.r)
        actor.endX, actor.endY = hex:hexToPixel(actor.targetQ, actor.targetR)
    else
        actor.isMoving = false
        actor.path = {}
        actor.currentPathIndex = 0
        -- Удалён вызов addToHistory
        
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
            actor.isMoving = false
            
            actor.currentPathIndex = actor.currentPathIndex + 1
            if actor.currentPathIndex <= #actor.path then
                startNextMove(actor)
            else
                actor.path = {}
                actor.currentPathIndex = 0
                
                if actor.startPosForHistory and actor.targetPosForHistory then
                    addToHistory(actor,
                                actor.startPosForHistory.q, actor.startPosForHistory.r,
                                actor.targetPosForHistory.q, actor.targetPosForHistory.r)
                    actor.startPosForHistory = nil
                    actor.targetPosForHistory = nil
                    
                    actor.hasActedThisTurn = true
                    for i, a in ipairs(entities) do
                        if a == actor then
                            turnState.actionsRemaining[i] = 0
                            break
                        end
                    end
                    
                    turnState.turnPhase = "waiting"
                    print(actor.name .. " finished action!")
                end
                
                if selectedActor == actor then
                    hex.selectedQ = actor.q
                    hex.selectedR = actor.r
                end
            end
        end
    end
end

function love.update(dt)
    -- Обновляем движение всех актеров
    for _, actor in ipairs(entities) do
        updateActorMovement(actor, dt)
        ai.updateEnemyMovement(actor, dt, hex)
        actor.pulse = actor.pulse + dt * actor.pulseSpeed
    end
    
    -- Обновляем анимации смещений (ветер, отталкивания)
    combat.updatePushAnimations(dt, hex)

    -- Проверяем край карты
    killPlayableAtEdge()

        
    -- Обрабатываем ход врагов
    updateEnemyTurn(dt)
    
    local mouseX, mouseY = love.mouse.getPosition()
    hex.hoverQ, hex.hoverR = hex:pixelToHex(mouseX, mouseY)
    
    local mouseInUndo = mouseX >= 10 and mouseX <= 130 and mouseY >= 200 and mouseY <= 230
    undoButton = undoButton or {}
    undoButton.isHovered = mouseInUndo
    
    local mouseInEndTurn = mouseX >= endTurnButton.x and mouseX <= endTurnButton.x + endTurnButton.width and
                         mouseY >= endTurnButton.y and mouseY <= endTurnButton.y + endTurnButton.height
    endTurnButton.isHovered = mouseInEndTurn

        -- Ховер для кнопки ветра
    local mouseX, mouseY = love.mouse.getPosition()
    windTorrentUI.button.isHovered = (mouseX >= windTorrentUI.button.x and 
                                      mouseX <= windTorrentUI.button.x + windTorrentUI.button.width and
                                      mouseY >= windTorrentUI.button.y and 
                                      mouseY <= windTorrentUI.button.y + windTorrentUI.button.height)
end

function drawHexGrid()
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            local x, y = hex:hexToPixel(q, r)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            
            -- Получаем тип местности из terrainMap
            local terrainType = (terrainMap[q] and terrainMap[q][r]) or "grass"
            --local terrainColor = getTerrainColor(terrainType)
            local hasEntity = getEntityAtHex(q, r) ~= nil
            local isCurrentActor = selectedActor and selectedActor.q == q and selectedActor.r == r
            
            if isCurrentActor then
                love.graphics.setColor(0.2, 0.8, 0.2, 0.8)
            elseif hex.selectedQ == q and hex.selectedR == r then
                love.graphics.setColor(0.2, 0.4, 0.8, 0.8)
            elseif hex.hoverQ == q and hex.hoverR == r then
                love.graphics.setColor(0.5, 0.8, 0.3, 0.8)
            elseif hasEntity then
                love.graphics.setColor(0.5, 0.3, 0.2, 0.8)
            else
                --love.graphics.setColor(terrainColor)
            end
            
            love.graphics.polygon("fill", vertices)
            
            -- Отрисовка текстур земли (без изменений, но адаптируем terrain.name)
            if not hasEntity and not isCurrentActor and not (hex.selectedQ == q and hex.selectedR == r) and not (hex.hoverQ == q and hex.hoverR == r) then
                if terrainType == "grass" then
                    love.graphics.setColor(0.2, 0.6, 0.1, 0.5)
                    for i = 0, 2 do
                        local angle = math.rad(60 * i + (q * 37 + r * 23) % 360)
                        local tx = x + math.cos(angle) * 15
                        local ty = y + math.sin(angle) * 15
                        love.graphics.line(x + math.cos(angle - 0.2) * 8, y + math.sin(angle - 0.2) * 8, 
                                         tx + math.cos(angle) * 5, ty + math.sin(angle) * 5)
                    end
                elseif terrainType == "sand" then
                    love.graphics.setColor(0.6, 0.5, 0.3, 0.5)
                    for i = 1, 5 do
                        local angle = math.rad(72 * i + (q * 31 + r * 19) % 360)
                        local rad = 8 + math.sin(q * 0.5 + r * 0.5) * 4
                        local tx = x + math.cos(angle) * rad
                        local ty = y + math.sin(angle) * rad
                        love.graphics.circle("fill", tx, ty, 1 + (q + r) % 2)
                    end
                elseif terrainType == "stone" then
                    love.graphics.setColor(0.3, 0.3, 0.35, 0.6)
                    for i = 1, 3 do
                        local startAngle = math.rad(120 * i + (q * 41 + r * 29) % 360)
                        local endAngle = startAngle + math.rad(30)
                        local startX = x + math.cos(startAngle) * 12
                        local startY = y + math.sin(startAngle) * 12
                        local endX = x + math.cos(endAngle) * 18
                        local endY = y + math.sin(endAngle) * 18
                        love.graphics.line(startX, startY, endX, endY)
                    end
                elseif terrainType == "snow" then
                    love.graphics.setColor(0.8, 0.9, 1, 0.6)
                    for i = 1, 6 do
                        local angle = math.rad(60 * i + (q * 43 + r * 37) % 360)
                        local tx = x + math.cos(angle) * 10
                        local ty = y + math.sin(angle) * 10
                        love.graphics.circle("fill", tx, ty, 1.5)
                    end
                elseif terrainType == "swamp" then
                    love.graphics.setColor(0.2, 0.4, 0.2, 0.6)
                    for i = 1, 4 do
                        local angle = math.rad(90 * i + (q * 29 + r * 17) % 360)
                        local rad = 7 + (q + r) % 3
                        local tx = x + math.cos(angle) * rad
                        local ty = y + math.sin(angle) * rad
                        love.graphics.circle("line", tx, ty, 2)
                    end
                elseif terrainType == "lava" then
                    love.graphics.setColor(1, 0.5, 0.1, 0.7)
                    for i = 1, 3 do
                        local angle = math.rad(120 * i + love.timer.getTime() * 5)
                        local rad = 6 + math.sin(love.timer.getTime() * 3 + q + r) * 2
                        local tx = x + math.cos(angle) * rad
                        local ty = y + math.sin(angle) * rad
                        love.graphics.circle("fill", tx, ty, 2)
                    end
                end
            end
            
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.polygon("line", vertices)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function drawHealthBar(actor, x, y)
    local barWidth = 40
    local barHeight = 6
    local healthPercent = actor.health / actor.maxHealth
    
    love.graphics.setColor(0.5, 0, 0, 0.8)
    love.graphics.rectangle("fill", x - barWidth/2, y - 28, barWidth, barHeight)
    
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.rectangle("fill", x - barWidth/2, y - 28, barWidth * healthPercent, barHeight)
    
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", x - barWidth/2, y - 28, barWidth, barHeight)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(actor.health .. "/" .. actor.maxHealth, x - 15, y - 38)
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
    
    -- Отрисовка спрайта
    if entity.sprite then
        -- Пульсация для выбранных персонажей
        local scale = 1
        if selectedActor == entity and entity:isCharacter() then
            scale = 1 + math.sin(entity.pulse) * 0.05
        end
        love.graphics.draw(entity.sprite, x, y, 0, scale, scale, 16, 16)
    else
        -- Fallback: цветной круг если нет спрайта
        love.graphics.setColor(entity.color or {1, 1, 1, 1})
        love.graphics.circle("fill", x, y, 14)
    end
    
    -- Имя сущности (только для персонажей)
    if entity:isCharacter() then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(entity.name, x - 20, y - 25)
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


function drawUndoButton()
    local canUndo = #actionHistory > 0
    
    if not selectedActor then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
    elseif canUndo and undoButton.isHovered then
        love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
    elseif canUndo then
        love.graphics.setColor(0.2, 0.4, 0.7, 0.8)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    end
    
    love.graphics.rectangle("fill", 10, 200, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", 10, 200, 120, 30, 5)
    
    love.graphics.setColor(1, 1, 1, 1)
    local text = "Undo (" .. #actionHistory .. "/" .. maxUndoCount .. ")"
    if #actionHistory == 0 then
        text = "Nothing to Undo"
    end
    
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(text)
    love.graphics.print(text, 10 + (120 - textWidth) / 2, 208)
end

function drawEndTurnButton()
    -- Если враги ходят, кнопка неактивна
    if turnState.waitingForEnemies then
        love.graphics.setColor(0.4, 0.3, 0.1, 0.5)
        love.graphics.rectangle("fill", endTurnButton.x, endTurnButton.y, endTurnButton.width, endTurnButton.height, 5)
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
        love.graphics.rectangle("line", endTurnButton.x, endTurnButton.y, endTurnButton.width, endTurnButton.height, 5)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.7)
        love.graphics.print("Enemies turn...", endTurnButton.x + 15, endTurnButton.y + 8)
        return
    end
    
    local anyActorActed = false
    for _, actor in ipairs(entities) do
        if actor.isPlayable and actor.hasActedThisTurn then
            anyActorActed = true
            break
        end
    end
    
    if endTurnButton.isHovered then
        if anyActorActed then
            love.graphics.setColor(0.9, 0.6, 0.2, 0.9)
        else
            love.graphics.setColor(0.7, 0.5, 0.2, 0.6)
        end
    else
        if anyActorActed then
            love.graphics.setColor(0.7, 0.5, 0.2, 0.8)
        else
            love.graphics.setColor(0.5, 0.3, 0.1, 0.5)
        end
    end
    
    love.graphics.rectangle("fill", endTurnButton.x, endTurnButton.y, endTurnButton.width, endTurnButton.height, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", endTurnButton.x, endTurnButton.y, endTurnButton.width, endTurnButton.height, 5)
    
    love.graphics.setColor(1, 1, 1, 1)
    local text = "End Turn"
    if not anyActorActed then
        text = "End Turn (no actions)"
    end
    
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(text)
    love.graphics.print(text, endTurnButton.x + (endTurnButton.width - textWidth) / 2, endTurnButton.y + 8)
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

function love.draw()
    drawHexGrid()
    
    drawEdgeWarning()
    drawAllEntities()

    if selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving then
        drawMovementRange(selectedActor)
        drawAttackIndicators()
        
        if hex.hoverQ >= 0 and hex.hoverR >= 0 then
            drawPathPreview(selectedActor, hex.hoverQ, hex.hoverR)
        end
    end
    
    drawUndoButton()
    drawEndTurnButton()
    drawWindTorrentUI()
    drawGlobalHealthBar()
    
    love.graphics.setColor(1, 1, 1, 1)
    
    love.graphics.print("Turn: " .. turnState.currentTurn, 10, 10)
    if selectedActor then
        love.graphics.print("Current: " .. selectedActor.name, 10, 30)
        love.graphics.print("Status: " .. (selectedActor.hasActedThisTurn and "Acted ✓" or "Ready to act"), 10, 50)
        love.graphics.print("Move Range: " .. selectedActor.moveRange .. " cells", 10, 70)
    end

    function drawCurrentAttack()
        -- Если враги ходят, показываем другой текст
        if turnState.waitingForEnemies then
            love.graphics.setColor(0.2, 0.2, 0.3, 0.8)
            love.graphics.rectangle("fill", 10, 280, 250, 60, 5)
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.rectangle("line", 10, 280, 250, 60, 5)
            
            love.graphics.setColor(1, 0.5, 0.2, 1)
            love.graphics.print("ENEMY TURN", 15, 300)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.print("Waiting for enemies to act...", 15, 320)
            return
        end
        
        if selectedActor and #selectedActor.attacks > 0 then
            local currentAttack = selectedActor.attacks[selectedActor.currentAttackIndex]
            
            love.graphics.setColor(0.2, 0.2, 0.3, 0.8)
            love.graphics.rectangle("fill", 10, 280, 250, 60, 5)
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.rectangle("line", 10, 280, 250, 60, 5)
            
            love.graphics.setColor(1, 1, 0.5, 1)
            love.graphics.print("Current Attack:", 15, 285)
            
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(currentAttack.name, 15, 300)
            
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.print(currentAttack.description, 15, 315)
            
            love.graphics.setColor(0.5, 0.8, 0.5, 1)
            love.graphics.print("Press TAB to switch attack (" .. selectedActor.currentAttackIndex .. "/" .. #selectedActor.attacks .. ")", 15, 335)
        end
    end
    
    love.graphics.print("Left click: Move | Right click: Attack", 10, 130)
    love.graphics.print("Each actor: 1 action per turn", 10, 150)
    love.graphics.print("Press 'U' to undo last move (not attack)", 10, 170)
    
    if hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local entity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        local terrainType = (terrainMap[hex.hoverQ] and terrainMap[hex.hoverQ][hex.hoverR]) or "grass"
        
        if entity then
            love.graphics.print("Obstacle: " .. entity.name .. " (" .. entity.health .. "/" .. entity.maxHealth .. " HP)", 10, 90)
        else
            love.graphics.print("Terrain: " .. terrainType, 10, 90)
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then  -- Левая кнопка мыши (движение)
            -- Сначала проверяем кнопку Wind Torrent
        if x >= windTorrentUI.button.x and x <= windTorrentUI.button.x + windTorrentUI.button.width and
           y >= windTorrentUI.button.y and y <= windTorrentUI.button.y + windTorrentUI.button.height then
            if windTorrent and not turnState.waitingForEnemies then --and not windTorrent.hasBeenUsed
                windTorrentUI.active = true
                print("Select wind direction...")
            elseif windTorrent and windTorrent.hasBeenUsed then
                print("Wind Torrent has already been used this game!")
            elseif turnState.waitingForEnemies then
                print("Cannot use Wind Torrent during enemy turn!")
            end
            return
        end
        
        -- Если активен режим выбора направления
        if windTorrentUI.active then
            -- Проверяем клик по кнопкам направлений
            for dirName, dir in pairs(windTorrentUI.directions) do
                if x >= dir.x and x <= dir.x + 70 and y >= dir.y and y <= dir.y + 30 then
                    windTorrent:executeGlobalWithAnimation(dirName, hex, entities, sounds, function(success, message)
                        if success then
                            -- Очищаем историю действий после использования глобальной атаки
                            actionHistory = {}
                            print("Action history cleared (Wind Torrent used)")
                        else
                            print("Wind Torrent failed: " .. (message or "unknown error"))
                        end
                    end)
                    windTorrentUI.active = false
                    return
                end
            end
            
            -- Проверяем кнопку Cancel
            local cancelX = love.graphics.getWidth() / 2 - 40
            local cancelY = love.graphics.getHeight() - 80
            if x >= cancelX and x <= cancelX + 80 and y >= cancelY and y <= cancelY + 30 then
                windTorrentUI.active = false
                print("Wind Torrent cancelled")
                return
            end
            
            -- Клик вне кнопок отменяет выбор
            windTorrentUI.active = false
            print("Wind Torrent cancelled")
            return
        end
        -- Проверяем кнопку Undo
        if x >= 10 and x <= 130 and y >= 200 and y <= 230 then
            if #actionHistory > 0 then
                undoLastAction()
            else
                print("No actions to undo!")
            end
            return
        end
        
        -- Проверяем кнопку End Turn
        if x >= endTurnButton.x and x <= endTurnButton.x + endTurnButton.width and
        y >= endTurnButton.y and y <= endTurnButton.y + endTurnButton.height then
            local anyActorActed = false
            for _, actor in ipairs(entities) do
                if actor.isPlayable and actor.hasActedThisTurn then
                    anyActorActed = true
                    break
                end
            end
            
            if anyActorActed then
                endTurn()
            else
                print("No actor has taken an action yet! At least one character must act first.")
            end
            return
        end

        local allAlliesActed = true
        for _, actor in ipairs(entities) do
            if actor.isPlayable and not actor.hasActedThisTurn then
                allAlliesActed = false
                break
            end
        end
        
        if allAlliesActed then
            print("Enemies are acting! Wait for your turn.")
            return
        end
        
        -- Клик по гексу для движения
        local targetQ, targetR = hex:pixelToHex(x, y)
        if hex:isValidHex(targetQ, targetR) then
            local clickedActor = getEntityAtHex(targetQ, targetR)
            
            if clickedActor and clickedActor.isPlayable then
                if clickedActor.hasActedThisTurn then
                    print(clickedActor.name .. " has already acted this turn!")
                else
                    selectedActor = clickedActor
                    hex.selectedQ = targetQ
                    hex.selectedR = targetR
                    print("Selected: " .. clickedActor.name)
                end
                return
            end            
            
            if selectedActor and not selectedActor.isMoving and not selectedActor.hasActedThisTurn then
                performMove(selectedActor, targetQ, targetR)
                hex.selectedQ = targetQ
                hex.selectedR = targetR
            elseif selectedActor and selectedActor.hasActedThisTurn then
                print(selectedActor.name .. " has already used their action!")
            end
        end
    elseif button == 2 then  -- Правая кнопка мыши (атака)
            -- Аналогичная проверка для атаки
        local allAlliesActed = true
        for _, actor in ipairs(entities) do
            if actor.isPlayable and not actor.hasActedThisTurn then
                allAlliesActed = false
                break
            end
        end
        
        if allAlliesActed then
            print("Enemies are acting! Wait for your turn.")
            return
        end
        local targetQ, targetR = hex:pixelToHex(x, y)
        if hex:isValidHex(targetQ, targetR) and selectedActor then
            if selectedActor.hasActedThisTurn then
                print(selectedActor.name .. " has already acted this turn!")
            elseif selectedActor.isMoving then
                print(selectedActor.name .. " is currently moving!")
            else
                performAttackWithSelectedAttack(selectedActor, targetQ, targetR)
            end
        end
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

-- Обновить функцию performAttack для использования выбранной атаки
function performAttackWithSelectedAttack(attacker, targetQ, targetR)
    local attack = getCurrentAttack(attacker)
    if not attack then
        return false, "No attack available!"
    end
    local success, message = combat.performAttack(attacker, targetQ, targetR, hex, entities, sounds, attack)
    
    -- Очищаем историю после успешной атаки союзника
    if success and attacker.isPlayable then
        actionHistory = {}
        print("Action history cleared (attack by " .. attacker.name .. ")")
    end
    
    return success, message
end

function drawWindTorrentUI()
    -- Кнопка активации
    local canUse = windTorrent and not windTorrent.hasBeenUsed and not turnState.waitingForEnemies
    
    if windTorrentUI.active then
        love.graphics.setColor(0.3, 0.5, 0.8, 0.9)
    elseif canUse and (windTorrentUI.button.isHovered or false) then
        love.graphics.setColor(0.2, 0.6, 0.9, 0.9)
    elseif canUse then
        love.graphics.setColor(0.1, 0.4, 0.7, 0.8)
    else
        love.graphics.setColor(0.4, 0.4, 0.4, 0.6)
    end
    
    love.graphics.rectangle("fill", windTorrentUI.button.x, windTorrentUI.button.y, 
                           windTorrentUI.button.width, windTorrentUI.button.height, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", windTorrentUI.button.x, windTorrentUI.button.y,
                           windTorrentUI.button.width, windTorrentUI.button.height, 5)
    
    love.graphics.setColor(1, 1, 1, 1)
    local text = "🌬️ Wind Torrent"
    if windTorrent and windTorrent.hasBeenUsed then
        text = "❌ Wind Torrent (used)"
    end
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(text)
    love.graphics.print(text, windTorrentUI.button.x + (windTorrentUI.button.width - textWidth) / 2,
                       windTorrentUI.button.y + 8)
    
    -- Если активен режим выбора направления
    if windTorrentUI.active then
        -- Полупрозрачный фон
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        
        love.graphics.setColor(1, 1, 0.5, 1)
        love.graphics.print("Choose wind direction:", love.graphics.getWidth() / 2 - 100, 40)
        love.graphics.print("(Click on a direction button)", love.graphics.getWidth() / 2 - 90, 65)
        
        -- Рисуем кнопки направлений
        for dirName, dir in pairs(windTorrentUI.directions) do
            local mx, my = love.mouse.getPosition()
            local isHover = mx >= dir.x and mx <= dir.x + 70 and my >= dir.y and my <= dir.y + 30
            
            if isHover then
                love.graphics.setColor(0.4, 0.7, 1, 0.9)
            else
                love.graphics.setColor(0.2, 0.4, 0.6, 0.8)
            end
            love.graphics.rectangle("fill", dir.x, dir.y, 70, 30, 5)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.rectangle("line", dir.x, dir.y, 70, 30, 5)
            
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(dir.name, dir.x + 5, dir.y + 8)
        end
        
        -- Кнопка отмены
        local cancelX = love.graphics.getWidth() / 2 - 40
        local cancelY = love.graphics.getHeight() - 80
        local mx, my = love.mouse.getPosition()
        local cancelHover = mx >= cancelX and mx <= cancelX + 80 and my >= cancelY and my <= cancelY + 30
        
        if cancelHover then
            love.graphics.setColor(0.8, 0.3, 0.3, 0.9)
        else
            love.graphics.setColor(0.6, 0.2, 0.2, 0.8)
        end
        love.graphics.rectangle("fill", cancelX, cancelY, 80, 30, 5)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", cancelX, cancelY, 80, 30, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Cancel", cancelX + 15, cancelY + 8)
    end
end

function drawGlobalHealthBar()
    local barWidth = 200
    local barHeight = 20
    local x = love.graphics.getWidth() - barWidth - 10
    local y = 10
    local healthPercent = globalHealth.current / globalHealth.max
    
    -- Фон
    love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
    love.graphics.rectangle("fill", x, y, barWidth, barHeight, 5)
    
    -- Заполнение
    if healthPercent > 0.6 then
        love.graphics.setColor(0.2, 0.8, 0.2, 0.8)
    elseif healthPercent > 0.3 then
        love.graphics.setColor(0.8, 0.8, 0.2, 0.8)
    else
        love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
    end
    love.graphics.rectangle("fill", x, y, barWidth * healthPercent, barHeight, 5)
    
    -- Рамка
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", x, y, barWidth, barHeight, 5)
    
    -- Текст
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Global Health: " .. globalHealth.current .. "/" .. globalHealth.max, 
                       x + 10, y + 3)
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

function love.keypressed(key)
    if key == "u" or key == "U" then
        if #actionHistory > 0 then
            undoLastAction()
        else
            print("No actions to undo!")
        end
    end
    
    if key == "e" or key == "E" then
        endTurn()
    end
    
    if key == "d" and selectedActor then
        selectedActor.health = math.max(0, selectedActor.health - 1)
        print(selectedActor.name .. " took 1 damage! Health: " .. selectedActor.health)
        
        if selectedActor.health <= 0 then
            for i, actor in ipairs(entities) do
                if actor == selectedActor then
                    table.remove(entities, i)
                    break
                end
            end
            print(selectedActor.name .. " has been defeated!")
            if #entities > 0 then
                selectedActor = entities[1]
            else
                selectedActor = nil
            end
        end
    end

    if key == "tab" or key == "Tab" then
        switchAttack()
    end
end