function love.load()
    -- Настройки гексагональной сетки
    hex = {}
    hex.radius = 70
    hex.width = hex.radius * 2
    hex.height = hex.radius * 1.75
    hex.gridWidth = 9
    hex.gridHeight = 7
    
    -- Смещение для центрирования
    hex.offsetX = 0
    hex.offsetY = 0
    
    -- Список актеров
    actors = {}
    
    -- Список препятствий (непроходимые объекты)
    obstacles = {}
    
    -- Глобальный стек действий для отмены (максимум 3 действия)
    -- кандидат на переработку - тут хранить вообще весь файл сохранения
    actionHistory = {}  -- Каждый элемент: {actor, fromQ, fromR, toQ, toR, turnNumber}
    
    -- ПОШАГОВАЯ СИСТЕМА
    turnState = {
        currentTurn = 1,           -- Номер текущего хода
        currentActorIndex = 1,     -- Индекс актера, который сейчас ходит
        turnPhase = "waiting",     -- "waiting" (ожидание действия) или "moving" (движется)
        actionsRemaining = {}       -- Сколько действий осталось у каждого актера в этом ходу
    }
    
    -- Кнопка завершения хода
    endTurnButton = {
        x = 10,
        y = 240,
        width = 120,
        height = 30,
        text = "End Turn",
        isHovered = false
    }
    
    -- Функция создания препятствия
    function createObstacle(q, r, type, name)
        local obstacle = {}
        obstacle.q = q
        obstacle.r = r
        obstacle.type = type or "rock"
        obstacle.name = name or "Obstacle"
        
        obstacle.sprite = love.graphics.newCanvas(32, 32)
        love.graphics.setCanvas(obstacle.sprite)
        
        if obstacle.type == "rock" then
            love.graphics.setColor(0.4, 0.4, 0.4, 1)
            love.graphics.circle("fill", 16, 16, 12)
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
            love.graphics.circle("fill", 12, 12, 4)
            love.graphics.circle("fill", 20, 20, 3)
        elseif obstacle.type == "tree" then
            love.graphics.setColor(0.3, 0.5, 0.2, 1)
            love.graphics.polygon("fill", 16, 4, 24, 16, 8, 16)
            love.graphics.setColor(0.5, 0.35, 0.2, 1)
            love.graphics.rectangle("fill", 14, 16, 4, 12)
        elseif obstacle.type == "wall" then
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
            love.graphics.rectangle("fill", 6, 6, 20, 20)
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
            for i = 0, 1 do
                love.graphics.rectangle("fill", 8, 8 + i * 16, 16, 4)
            end
        elseif obstacle.type == "spike" then
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.polygon("fill", 16, 6, 26, 26, 6, 26)
            love.graphics.setColor(0.9, 0.2, 0.2, 1)
            love.graphics.polygon("fill", 16, 8, 22, 22, 10, 22)
        end
        
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line", 16, 16, 14)
        love.graphics.setCanvas()
        
        return obstacle
    end
    
    -- Функция создания актера
    function createActor(q, r, name, color, spriteType, isPlayable, maxHealth, moveRange)
        local actor = {}
        actor.q = q
        actor.r = r
        actor.speed = 0.15
        actor.timer = 0
        actor.isMoving = false
        actor.targetQ = q
        actor.targetR = r
        actor.startX = 0
        actor.startY = 0
        actor.endX = 0
        actor.endY = 0
        actor.path = {}
        actor.currentPathIndex = 0
        actor.name = name
        actor.color = color
        actor.pulse = 0
        actor.pulseSpeed = 0.5 + math.random() * 1.5

        actor.isPlayable = isPlayable or false  -- Управляемый игроком
        actor.hasActedThisTurn = false          -- Сделал ли действие в этом ходу
        
        -- Статы
        actor.maxHealth = maxHealth or 3
        actor.health = actor.maxHealth

        -- Дальность движения (по умолчанию 3, если не указана)
        actor.moveRange = moveRange or 3
        
        -- Создаем спрайт
        actor.sprite = love.graphics.newCanvas(32, 32)
        love.graphics.setCanvas(actor.sprite)
        love.graphics.setColor(color[1], color[2], color[3], color[4])
        love.graphics.circle("fill", 16, 16, 14)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        
        if spriteType == "cross" then
            love.graphics.line(8, 8, 24, 24)
            love.graphics.line(24, 8, 8, 24)
        elseif spriteType == "star" then
            for i = 0, 4 do
                local angle = i * math.pi * 2 / 5
                local x1 = 16 + math.cos(angle) * 10
                local y1 = 16 + math.sin(angle) * 10
                local x2 = 16 + math.cos(angle + math.pi) * 10
                local y2 = 16 + math.sin(angle + math.pi) * 10
                love.graphics.line(x1, y1, x2, y2)
            end
        elseif spriteType == "triangle" then
            love.graphics.polygon("line", 16, 6, 26, 26, 6, 26)
        end
        
        love.graphics.circle("line", 16, 16, 14)
        love.graphics.setCanvas()
        
        return actor
    end
    
    -- Создаем актеров (персонажи игрока)
    table.insert(actors, createActor(2, 2, "Warrior", {1, 0.2, 0.2, 1}, "cross", true, 5, 2))   -- Воин ходит на 2 клетки
    table.insert(actors, createActor(6, 4, "Mage", {0.2, 0.2, 1, 1}, "star", true, 2, 5))       -- Маг ходит на 5 клеток
    table.insert(actors, createActor(4, 1, "Rogue", {0.2, 0.8, 0.2, 1}, "triangle", true, 3, 4)) -- Разбойник ходит на 4 клетки
    table.insert(actors, createActor(4, 2, "Rogue", {0.2, 0.8, 0.2, 1}, "triangle", true, 3, 4)) -- Разбойник ходит на 4 клетки

    -- Враги (неуправляемые)
    table.insert(actors, createActor(3, 5, "Goblin", {0.5, 0.3, 0.1, 1}, "circle", false, 3, 3))  -- Гоблин ходит на 3 клетки
    table.insert(actors, createActor(7, 2, "Orc", {0.6, 0.2, 0.2, 1}, "cross", false, 4, 2))      -- Орк ходит на 2 клетки
        
    -- Создаем препятствия
    table.insert(obstacles, createObstacle(3, 3, "rock", "Big Rock"))
    table.insert(obstacles, createObstacle(5, 2, "tree", "Oak Tree"))
    table.insert(obstacles, createObstacle(1, 4, "wall", "Stone Wall"))
    table.insert(obstacles, createObstacle(7, 5, "spike", "Spike Trap"))
    table.insert(obstacles, createObstacle(4, 4, "tree", "Pine Tree"))
    table.insert(obstacles, createObstacle(2, 5, "rock", "Small Rock"))
    
    -- Инициализируем счетчики действий для каждого актера
    for i, actor in ipairs(actors) do
        if actor.isPlayable then
            turnState.actionsRemaining[i] = 1  -- У каждого по 1 действию на ход
        else
            turnState.actionsRemaining[i] = 0  -- Враги пока не ходят
        end
    end
    
    -- Находим первого играбельного актера
    for i, actor in ipairs(actors) do
        if actor.isPlayable and turnState.actionsRemaining[i] > 0 then
            turnState.currentActorIndex = i
            selectedActor = actor
            hex.selectedQ = actor.q
            hex.selectedR = actor.r
            break
        end
    end
    
    --background = love.graphics.newImage('sprites/background.png')
    
    sounds = {}
    sounds.undo = love.audio.newSource("sounds/blip.wav", "static")
    sounds.undo:setVolume(0.4)
    sounds.turn = love.audio.newSource("sounds/blip.wav", "static")
    sounds.turn:setVolume(0.3)
    
    -- Рассчитываем смещение для центрирования карты
    local mapWidth = hex.gridWidth * hex.width * 0.75 + hex.radius
    local mapHeight = hex.gridHeight * hex.height + hex.radius
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    hex.offsetX = (screenWidth - mapWidth) / 2
    hex.offsetY = (screenHeight - mapHeight) / 2
    
    -- Подсветка гексов
    hex.hoverQ = -1
    hex.hoverR = -1
    hex.selectedQ = -1
    hex.selectedR = -1

    function countPlayableActors()
        local count = 0
        for _, actor in ipairs(actors) do
            if actor.isPlayable then
                count = count + 1
            end
        end
        return count
    end

    -- Глобальный стек действий (теперь с ограничением по количеству союзников)
    actionHistory = {}  -- Каждый элемент: {actor, fromQ, fromR, toQ, toR, turnNumber}
    maxUndoCount = countPlayableActors()  -- Максимум отмен = количество союзных юнитов
end

-- Функция завершения хода
function endTurn()
    -- Сбрасываем флаги действий для ВСЕХ актеров
    for i, actor in ipairs(actors) do
        actor.hasActedThisTurn = false
        turnState.actionsRemaining[i] = 1
    end
    
    -- ОЧИЩАЕМ ИСТОРИЮ ДЕЙСТВИЙ ПРИ ЗАВЕРШЕНИИ ХОДА
    actionHistory = {}
    
    -- Обновляем максимальное количество отмен (на случай, если появились новые союзники)
    maxUndoCount = countPlayableActors()
    
    -- Увеличиваем номер хода
    turnState.currentTurn = turnState.currentTurn + 1
    
    -- Находим ПЕРВОГО актера для нового хода
    turnState.currentActorIndex = 1
    selectedActor = actors[1]
    hex.selectedQ = selectedActor.q
    hex.selectedR = selectedActor.r
    turnState.turnPhase = "waiting"
    
    if sounds.turn then
        sounds.turn:play()
    end
    
    print("=== НОВЫЙ ХОД " .. turnState.currentTurn .. " ===")
    print("Очередь: " .. selectedActor.name)
    print("Максимум отмен: " .. maxUndoCount .. " (количество союзных юнитов)")
end

-- Глобальная функция отмены последнего действия
-- Глобальная функция отмены последнего действия (не привязана к выбранному актеру)
function undoLastAction()
    if #actionHistory == 0 then
        print("Нет действий для отмены! (0/" .. maxUndoCount .. ")")
        return false
    end
    
    local lastAction = actionHistory[#actionHistory]
    
    -- Проверяем, не был ли актер уничтожен
    local actorExists = false
    local currentActor = nil
    for _, actor in ipairs(actors) do
        if actor == lastAction.actor then
            actorExists = true
            currentActor = actor
            break
        end
    end
    
    if not actorExists then
        print("Актер больше не существует!")
        table.remove(actionHistory)
        return undoLastAction()  -- Рекурсивно пробуем следующее действие
    end
    
    -- Проверяем, не двигается ли актер
    if currentActor.isMoving then
        print("Нельзя отменить действие во время движения!")
        return false
    end
    
    -- Проверяем, можно ли отменить (актер должен был совершить действие в этом ходу)
    if not currentActor.hasActedThisTurn then
        print(currentActor.name .. " еще не совершал действие в этом ходу!")
        return false
    end
    
    -- Проверяем, свободна ли начальная позиция
    if isPositionOccupied(lastAction.fromQ, lastAction.fromR, currentActor) then
        print("Нельзя отменить: начальная позиция занята!")
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
    for i, a in ipairs(actors) do
        if a == currentActor then
            turnState.actionsRemaining[i] = 1
            break
        end
    end
    
    -- Удаляем действие из истории
    table.remove(actionHistory)
    
    sounds.undo:play()
    print("Отменено действие: " .. currentActor.name)
    print("Осталось отмен: " .. #actionHistory .. "/" .. maxUndoCount)
    return true
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
        print("История превысила лимит (" .. maxUndoCount .. "), удалено старое действие " .. (removed.actor and removed.actor.name or "unknown"))
    end
    
    print("Добавлено действие для " .. actor.name .. ". История: " .. #actionHistory .. "/" .. maxUndoCount)
end

function pixelToHex(px, py)
    local x = px - hex.offsetX
    local y = py - hex.offsetY
    
    local q = math.floor(x / (hex.width * 0.75))
    local r = math.floor(y / hex.height)
    
    if q < 0 then q = 0 end
    if q >= hex.gridWidth then q = hex.gridWidth - 1 end
    if r < 0 then r = 0 end
    if r >= hex.gridHeight then r = hex.gridHeight - 1 end
    
    local bestQ, bestR = q, r
    local bestDist = math.huge
    
    for dq = -1, 1 do
        for dr = -1, 1 do
            local checkQ = q + dq
            local checkR = r + dr
            if checkQ >= 0 and checkQ < hex.gridWidth and checkR >= 0 and checkR < hex.gridHeight then
                local hexX, hexY = hexToPixel(checkQ, checkR)
                local dist = math.sqrt((px - hexX)^2 + (py - hexY)^2)
                if dist < bestDist then
                    bestDist = dist
                    bestQ, bestR = checkQ, checkR
                end
            end
        end
    end
    
    return bestQ, bestR
end

function getNeighbors(q, r)
    local directions
    if q % 2 == 0 then
        directions = {
            {q=1, r=0}, {q=-1, r=0}, {q=0, r=1},
            {q=0, r=-1}, {q=1, r=-1}, {q=-1, r=-1}
        }
    else
        directions = {
            {q=1, r=0}, {q=-1, r=0}, {q=0, r=1},
            {q=0, r=-1}, {q=1, r=1}, {q=-1, r=1}
        }
    end
    
    local neighbors = {}
    for _, dir in ipairs(directions) do
        neighbors[#neighbors+1] = {q = q + dir.q, r = r + dir.r}
    end
    return neighbors
end

function isValidHex(q, r)
    return q >= 0 and q < hex.gridWidth and r >= 0 and r < hex.gridHeight
end

function isPositionOccupied(q, r, movingActor)
    for _, actor in ipairs(actors) do
        if actor ~= movingActor and actor.q == q and actor.r == r then
            return true
        end
    end
    for _, obstacle in ipairs(obstacles) do
        if obstacle.q == q and obstacle.r == r then
            return true
        end
    end
    return false
end

function getObstacleAtHex(q, r)
    for _, obstacle in ipairs(obstacles) do
        if obstacle.q == q and obstacle.r == r then
            return obstacle
        end
    end
    return nil
end

function getActorAtHex(q, r)
    for _, actor in ipairs(actors) do
        if actor.q == q and actor.r == r then
            return actor
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
        local neighbors = getNeighbors(current.q, current.r)
        
        for _, neighbor in ipairs(neighbors) do
            local neighborKey = neighbor.q .. "," .. neighbor.r
            
            if not closedSet[neighborKey] and isValidHex(neighbor.q, neighbor.r) then
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
        end
    end
    
    return nil
end

function performMove(actor, targetQ, targetR)
    if actor.isMoving then
        return false
    end
    
    if actor.q == targetQ and actor.r == targetR then
        return false
    end
    
    -- ПРОВЕРКА ДАЛЬНОСТИ ДВИЖЕНИЯ
    local distance = getHexDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        print(actor.name .. " не может пройти так далеко! Максимальная дистанция: " .. actor.moveRange .. " клеток")
        return false
    end
    
    if isPositionOccupied(targetQ, targetR, actor) then
        local obstacle = getObstacleAtHex(targetQ, targetR)
        if obstacle then
            print("Невозможно пройти: клетка занята препятствием!")
        else
            print("Клетка занята другим актером!")
        end
        return false
    end
    
    local path = findPath(actor.q, actor.r, targetQ, targetR, actor)
    
    if path and #path > 0 then
        -- ДОПОЛНИТЕЛЬНАЯ ПРОВЕРКА: длина пути не должна превышать дальность движения
        if #path > actor.moveRange then
            print(actor.name .. " не может пройти " .. #path .. " клеток! Максимум: " .. actor.moveRange)
            return false
        end
        
        actor.startPosForHistory = {q = actor.q, r = actor.r}
        actor.targetPosForHistory = {q = targetQ, r = targetR}
        
        actor.path = path
        actor.currentPathIndex = 1
        startNextMove(actor)
        
        return true
    else
        print("Путь не найден!")
        return false
    end
end

-- Функция для отображения доступной дистанции движения с учетом препятствий
function drawMovementRange(actor)
    if not actor or actor.isMoving or actor.hasActedThisTurn then
        return
    end
    
    -- Для каждой клетки на карте проверяем, может ли актер до нее дойти (кандидат на оптимизацию?)
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            -- Пропускаем текущую позицию актера
            if not (q == actor.q and r == actor.r) then
                -- Ищем путь до клетки
                local path = findPath(actor.q, actor.r, q, r, actor)
                
                if path and #path > 0 and #path <= actor.moveRange then
                    -- Проверяем, не занята ли целевая клетка (но показываем её, если она занята?)
                    local isOccupied = isPositionOccupied(q, r, actor)
                    
                    local x, y = hexToPixel(q, r)
                    local vertices = drawHexagon(x, y, hex.radius)
                    
                    if isOccupied then
                        -- Занятые клетки подсвечиваем красным (недоступны для перемещения)
                        love.graphics.setColor(0.8, 0.2, 0.2, 0.3)
                        love.graphics.polygon("fill", vertices)
                        love.graphics.setColor(1, 1, 1, 0.5)
                        love.graphics.print("🚫", x - 5, y - 8)
                    else
                        -- Доступные клетки подсвечиваем зеленым
                        love.graphics.setColor(0.3, 0.8, 0.3, 0.35)
                        love.graphics.polygon("fill", vertices)
                        
                        -- Отображаем количество шагов до клетки
                        love.graphics.setColor(1, 1, 1, 0.8)
                        love.graphics.print(#path, x - 5, y - 5)
                    end
                end
            end
        end
    end
end

-- Функция для отображения пути к выбранной клетке (вызывать при наведении)
function drawPathPreview(actor, targetQ, targetR)
    if not actor or actor.isMoving or actor.hasActedThisTurn then
        return
    end
    
    -- Проверяем, можно ли дойти до клетки
    local distance = getHexDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        return
    end
    
    local path = findPath(actor.q, actor.r, targetQ, targetR, actor)
    if path and #path > 0 and #path <= actor.moveRange then
        
        -- Получаем начальную позицию актера
        local startX, startY = hexToPixel(actor.q, actor.r)
        
        -- Отрисовываем весь путь и стрелки
        local prevX, prevY = startX, startY
        
        for i = 1, #path do
            local step = path[i]
            local x, y = hexToPixel(step.q, step.r)
            
            -- Подсвечиваем клетки пути
            local vertices = drawHexagon(x, y, hex.radius)
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
        local targetX, targetY = hexToPixel(targetQ, targetR)
        local targetVertices = drawHexagon(targetX, targetY, hex.radius)
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
        
        actor.startX, actor.startY = hexToPixel(actor.q, actor.r)
        actor.endX, actor.endY = hexToPixel(actor.targetQ, actor.targetR)
    else
        actor.isMoving = false
        actor.path = {}
        actor.currentPathIndex = 0
        
        if actor.startPosForHistory and actor.targetPosForHistory then
            addToHistory(actor,
                        actor.startPosForHistory.q, actor.startPosForHistory.r,
                        actor.targetPosForHistory.q, actor.targetPosForHistory.r)
            actor.startPosForHistory = nil
            actor.targetPosForHistory = nil
            
            -- Помечаем, что актер совершил действие в этом ходу
            actor.hasActedThisTurn = true
            
            -- Уменьшаем счетчик действий
            for i, a in ipairs(actors) do
                if a == actor then
                    turnState.actionsRemaining[i] = 0
                    break
                end
            end
            
            turnState.turnPhase = "waiting"
            print(actor.name .. " завершил действие!")
        end
        
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
                    for i, a in ipairs(actors) do
                        if a == actor then
                            turnState.actionsRemaining[i] = 0
                            break
                        end
                    end
                    
                    turnState.turnPhase = "waiting"
                    print(actor.name .. " завершил действие!")
                end
                
                if selectedActor == actor then
                    hex.selectedQ = actor.q
                    hex.selectedR = actor.r
                end
            end
        end
    end
end

-- Функция для расчета расстояния между двумя гексами
function getHexDistance(q1, r1, q2, r2)
    -- Конвертируем в кубические координаты для простоты расчета
    local x1 = q1
    local z1 = r1 - (q1 - (q1 % 2)) / 2
    local y1 = -x1 - z1
    
    local x2 = q2
    local z2 = r2 - (q2 - (q2 % 2)) / 2
    local y2 = -x2 - z2
    
    return (math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)) / 2
end

function love.update(dt)
    for _, actor in ipairs(actors) do
        updateActorMovement(actor, dt)
        actor.pulse = actor.pulse + dt * actor.pulseSpeed
    end
    
    local mouseX, mouseY = love.mouse.getPosition()
    hex.hoverQ, hex.hoverR = pixelToHex(mouseX, mouseY)
    
    -- Обновляем состояние кнопок
    local mouseInUndo = mouseX >= 10 and mouseX <= 130 and mouseY >= 200 and mouseY <= 230
    undoButton = undoButton or {}
    undoButton.isHovered = mouseInUndo
    
    local mouseInEndTurn = mouseX >= endTurnButton.x and mouseX <= endTurnButton.x + endTurnButton.width and
                         mouseY >= endTurnButton.y and mouseY <= endTurnButton.y + endTurnButton.height
    endTurnButton.isHovered = mouseInEndTurn
end

function hexToPixel(q, r)
    local x = q * hex.width * 0.75
    local y = r * hex.height + (q % 2) * (hex.height / 2)
    return x + hex.radius + hex.offsetX, y + hex.radius + hex.offsetY
end

function drawHexagon(x, y, radius)
    local vertices = {}
    for i = 0, 5 do
        local angle = math.rad(60 * i)
        local vx = x + math.cos(angle) * radius
        local vy = y + math.sin(angle) * radius
        table.insert(vertices, vx)
        table.insert(vertices, vy)
    end
    return vertices
end

function drawHexGrid()
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            local x, y = hexToPixel(q, r)
            local vertices = drawHexagon(x, y, hex.radius)
            
            local hasObstacle = getObstacleAtHex(q, r) ~= nil
            local isCurrentActor = selectedActor and selectedActor.q == q and selectedActor.r == r
            
            if isCurrentActor then
                love.graphics.setColor(0.2, 0.8, 0.2, 0.8)  -- Зеленый для текущего актера
            elseif hex.selectedQ == q and hex.selectedR == r then
                love.graphics.setColor(0.2, 0.4, 0.8, 0.8)
            elseif hex.hoverQ == q and hex.hoverR == r then
                love.graphics.setColor(0.5, 0.8, 0.3, 0.8)
            elseif hasObstacle then
                love.graphics.setColor(0.5, 0.3, 0.2, 0.8)
            elseif (q + r) % 2 == 0 then
                love.graphics.setColor(0.3, 0.6, 0.2, 0.8)
            else
                love.graphics.setColor(0.4, 0.7, 0.3, 0.8)
            end
            
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.polygon("line", vertices)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function drawObstacle(obstacle)
    local x, y = hexToPixel(obstacle.q, obstacle.r)
    love.graphics.draw(obstacle.sprite, x, y, 0, 1, 1, 16, 16)
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

function drawActor(actor)
    local x, y
    if actor.isMoving then
        local t = actor.timer / actor.speed
        x = actor.startX + (actor.endX - actor.startX) * t
        y = actor.startY + (actor.endY - actor.startY) * t
    else
        x, y = hexToPixel(actor.q, actor.r)
    end
    
    local scale = 1 + math.sin(actor.pulse) * 0.05
    love.graphics.draw(actor.sprite, x, y, 0, scale, scale, 16, 16)
    
    -- Подсветка текущего актера
    if selectedActor == actor and turnState.turnPhase == "waiting" then
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.circle("line", x, y, 22)
        love.graphics.setColor(1, 1, 1, 1)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(actor.name, x - 20, y - 25)
    
    -- Отображаем, сделал ли действие
    if actor.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        love.graphics.circle("fill", x + 15, y - 15, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("✓", x + 11, y - 20)
    end

    drawHealthBar(actor, x, y)
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
    -- Всегда активна, просто меняем цвет в зависимости от состояния
    local anyActorActed = false
    for _, actor in ipairs(actors) do
        if actor.isPlayable and actor.hasActedThisTurn then
            anyActorActed = true
            break
        end
    end
    
    if endTurnButton.isHovered then
        if anyActorActed then
            love.graphics.setColor(0.9, 0.6, 0.2, 0.9)  -- Оранжевый при наведении
        else
            love.graphics.setColor(0.7, 0.5, 0.2, 0.6)  -- Тусклый оранжевый
        end
    else
        if anyActorActed then
            love.graphics.setColor(0.7, 0.5, 0.2, 0.8)  -- Нормальный цвет
        else
            love.graphics.setColor(0.5, 0.3, 0.1, 0.5)  -- Полупрозрачный
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

function love.draw()
    --love.graphics.draw(background, 0, 0)
    drawHexGrid()
    
    for _, obstacle in ipairs(obstacles) do
        drawObstacle(obstacle)
    end

    -- Отображаем доступную дистанцию для выбранного актера
    if selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving then
        drawMovementRange(selectedActor)
        
        -- Отображаем путь к клетке под курсором
        if hex.hoverQ >= 0 and hex.hoverR >= 0 then
            drawPathPreview(selectedActor, hex.hoverQ, hex.hoverR)
        end
    end
    
    for _, actor in ipairs(actors) do
        drawActor(actor)
    end
    
    drawUndoButton()
    drawEndTurnButton()
    
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Информация о ходе
    love.graphics.print("Turn: " .. turnState.currentTurn, 10, 10)
    if selectedActor then
        love.graphics.print("Current: " .. selectedActor.name, 10, 30)
        love.graphics.print("Status: " .. (selectedActor.hasActedThisTurn and "Acted ✓" or "Ready to act"), 10, 50)
        love.graphics.print("Move Range: " .. selectedActor.moveRange .. " cells", 10, 70)  -- ДОБАВИТЬ ЭТУ СТРОКУ
    end
    
    love.graphics.print("Click on any hex to move", 10, 130)
    love.graphics.print("Each actor: 1 action per turn", 10, 150)
    love.graphics.print("Press 'U' to undo last move (max 3)", 10, 170)
    
    if hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local obstacle = getObstacleAtHex(hex.hoverQ, hex.hoverR)
        if obstacle then
            love.graphics.print("Obstacle: " .. obstacle.name, 10, 90)
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        -- Проверяем кнопку Undo
        if x >= 10 and x <= 130 and y >= 200 and y <= 230 then
            if #actionHistory > 0 then
                undoLastAction()
            else
                print("Нет действий для отмены!")
            end
            return
        end
        
        -- Проверяем кнопку End Turn
        if x >= endTurnButton.x and x <= endTurnButton.x + endTurnButton.width and
        y >= endTurnButton.y and y <= endTurnButton.y + endTurnButton.height then
            -- Проверяем, есть ли хоть один актер, совершивший действие
            local anyActorActed = false
            for _, actor in ipairs(actors) do
                if actor.isPlayable and actor.hasActedThisTurn then
                    anyActorActed = true
                    break
                end
            end
            
            if anyActorActed then
                endTurn()
            else
                print("Ни один актер еще не совершил действие! Сначала нужно сходить хотя бы одним персонажем.")
            end
            return
        end
        
        -- Клик по гексу
        local targetQ, targetR = pixelToHex(x, y)
        if isValidHex(targetQ, targetR) then
            local clickedActor = getActorAtHex(targetQ, targetR)
            
            -- Если кликнули на актера
            if clickedActor and clickedActor.isPlayable then
                if clickedActor.hasActedThisTurn then
                    print(clickedActor.name .. " уже совершил действие в этом ходу!")
                else
                    selectedActor = clickedActor
                    hex.selectedQ = targetQ
                    hex.selectedR = targetR
                    print("Selected: " .. clickedActor.name)
                end
                return
            end            
            -- Пытаемся переместить выбранного актера
            if selectedActor and not selectedActor.isMoving and not selectedActor.hasActedThisTurn then
                performMove(selectedActor, targetQ, targetR)
                hex.selectedQ = targetQ
                hex.selectedR = targetR
            elseif selectedActor and selectedActor.hasActedThisTurn then
                print(selectedActor.name .. " уже использовал действие!")
            end
        end
    end
end

function love.keypressed(key)
    if key == "u" or key == "U" then
        if #actionHistory > 0 then
            undoLastAction()
        else
            print("Нет действий для отмены!")
        end
    end
    
    if key == "e" or key == "E" then
        endTurn()  -- Всегда заканчиваем ход
    end
    
    -- Тестовая кнопка урона
    if key == "d" and selectedActor then
        selectedActor.health = math.max(0, selectedActor.health - 1)
        print(selectedActor.name .. " took 1 damage! Health: " .. selectedActor.health)
    end
end