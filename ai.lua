-- ai.lua
-- Простой ИИ для врагов

local ai = {}

-- Максимально примитивный ИИ: просто идет к ближайшему союзнику и атакует
function ai.performEnemyTurn(enemy, actors, obstacles, hex, sounds)
    if enemy.hasActedThisTurn then
        return false, "Already acted"
    end
    
    if enemy.isMoving then
        return false, "Is moving"
    end
    
    -- Находим ближайшего союзного игрока
    local nearestAlly = nil
    local nearestDistance = math.huge
    
    for _, actor in ipairs(actors) do
        if actor.isPlayable and actor.health > 0 then
            local dist = hex:getDistance(enemy.q, enemy.r, actor.q, actor.r)
            if dist < nearestDistance then
                nearestDistance = dist
                nearestAlly = actor
            end
        end
    end
    
    if not nearestAlly then
        print(enemy.name .. " has no target!")
        return false, "No target"
    end
    
    -- Если враг рядом с целью (расстояние 1), атакуем
    if nearestDistance == 1 then
        return ai.performAttack(enemy, nearestAlly, actors, obstacles, hex, sounds)
    else
        -- Иначе двигаемся к цели (на расстояние 1 от нее)
        return ai.performMove(enemy, nearestAlly, actors, obstacles, hex)
    end
end

-- Примитивное движение к цели
function ai.performMove(enemy, target, actors, obstacles, hex)
    -- Находим все клетки на расстоянии 1 от цели
    local targetNeighbors = hex:getNeighbors(target.q, target.r)
    local bestCell = nil
    local bestDistance = math.huge
    
    -- Проверяем каждую клетку вокруг цели
    for _, neighbor in ipairs(targetNeighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            -- Проверяем, не занята ли клетка
            local isOccupied = false
            
            for _, actor in ipairs(actors) do
                if actor ~= enemy and actor.q == neighbor.q and actor.r == neighbor.r then
                    isOccupied = true
                    break
                end
            end
            
            for _, obstacle in ipairs(obstacles) do
                if obstacle.q == neighbor.q and obstacle.r == neighbor.r then
                    isOccupied = true
                    break
                end
            end
            
            if not isOccupied then
                local distToEnemy = hex:getDistance(enemy.q, enemy.r, neighbor.q, neighbor.r)
                if distToEnemy < bestDistance and distToEnemy <= enemy.moveRange then
                    bestDistance = distToEnemy
                    bestCell = neighbor
                end
            end
        end
    end
    
    -- Если нашли клетку, двигаемся к ней
    if bestCell and bestDistance <= enemy.moveRange then
        return ai.moveToCell(enemy, bestCell.q, bestCell.r, hex, actors, obstacles)
    end
    
    -- Если не нашли клетку рядом с целью, двигаемся в сторону цели
    return ai.moveTowards(enemy, target.q, target.r, actors, obstacles, hex)
end

-- Движение к конкретной клетке
function ai.moveToCell(enemy, targetQ, targetR, hex, actors, obstacles)
    if enemy.isMoving then
        return false
    end
    
    local distance = hex:getDistance(enemy.q, enemy.r, targetQ, targetR)
    if distance > enemy.moveRange then
        return false
    end
    
    -- Проверяем, не занята ли клетка
    for _, actor in ipairs(actors) do
        if actor ~= enemy and actor.q == targetQ and actor.r == targetR then
            return false
        end
    end
    
    for _, obstacle in ipairs(obstacles) do
        if obstacle.q == targetQ and obstacle.r == targetR then
            return false
        end
    end
    
    -- Находим путь
    local path = ai.findSimplePath(enemy.q, enemy.r, targetQ, targetR, enemy, actors, obstacles, hex)
    
    if path and #path > 0 and #path <= enemy.moveRange then
        enemy.path = path
        enemy.currentPathIndex = 1
        ai.startEnemyMove(enemy, hex)
        return true
    end
    
    return false
end

-- Простой поиск пути BFS
function ai.findSimplePath(startQ, startR, targetQ, targetR, enemy, actors, obstacles, hex)
    local queue = {{q = startQ, r = startR, path = {}}}
    local visited = {}
    local startKey = startQ .. "," .. startR
    visited[startKey] = true
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        
        if current.q == targetQ and current.r == targetR then
            return current.path
        end
        
        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, neighbor in ipairs(neighbors) do
            local key = neighbor.q .. "," .. neighbor.r
            
            if not visited[key] and hex:isValidHex(neighbor.q, neighbor.r) then
                -- Проверяем, не занята ли клетка
                local isOccupied = false
                
                for _, actor in ipairs(actors) do
                    if actor ~= enemy and actor.q == neighbor.q and actor.r == neighbor.r then
                        isOccupied = true
                        break
                    end
                end
                
                for _, obstacle in ipairs(obstacles) do
                    if obstacle.q == neighbor.q and obstacle.r == neighbor.r then
                        isOccupied = true
                        break
                    end
                end
                
                if not isOccupied then
                    visited[key] = true
                    local newPath = {}
                    for _, step in ipairs(current.path) do
                        table.insert(newPath, step)
                    end
                    table.insert(newPath, {q = neighbor.q, r = neighbor.r})
                    table.insert(queue, {q = neighbor.q, r = neighbor.r, path = newPath})
                end
            end
        end
    end
    
    return nil
end

-- Движение в сторону цели (прямая линия)
function ai.moveTowards(enemy, targetQ, targetR, actors, obstacles, hex)
    -- Находим всех соседей врага
    local neighbors = hex:getNeighbors(enemy.q, enemy.r)
    
    -- Выбираем соседа, который ближе всего к цели
    local bestNeighbor = nil
    local bestDistance = math.huge
    
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            -- Проверяем, не занята ли клетка
            local isOccupied = false
            
            for _, actor in ipairs(actors) do
                if actor ~= enemy and actor.q == neighbor.q and actor.r == neighbor.r then
                    isOccupied = true
                    break
                end
            end
            
            for _, obstacle in ipairs(obstacles) do
                if obstacle.q == neighbor.q and obstacle.r == neighbor.r then
                    isOccupied = true
                    break
                end
            end
            
            if not isOccupied then
                local distToTarget = hex:getDistance(neighbor.q, neighbor.r, targetQ, targetR)
                if distToTarget < bestDistance then
                    bestDistance = distToTarget
                    bestNeighbor = neighbor
                end
            end
        end
    end
    
    if bestNeighbor then
        return ai.moveToCell(enemy, bestNeighbor.q, bestNeighbor.r, actors, obstacles, hex)
    end
    
    return false
end

-- Запуск движения врага
function ai.startEnemyMove(enemy, hex)
    if enemy.currentPathIndex and enemy.currentPathIndex <= #enemy.path then
        local nextStep = enemy.path[enemy.currentPathIndex]
        enemy.isMoving = true
        enemy.timer = 0
        enemy.targetQ = nextStep.q
        enemy.targetR = nextStep.r
        
        enemy.startX, enemy.startY = hex:hexToPixel(enemy.q, enemy.r)
        enemy.endX, enemy.endY = hex:hexToPixel(enemy.targetQ, enemy.targetR)
    else
        enemy.isMoving = false
        enemy.path = {}
        enemy.currentPathIndex = 0
        
        enemy.hasActedThisTurn = true
        print(enemy.name .. " moved!")
    end
end

-- Обновление движения врага
function ai.updateEnemyMovement(enemy, dt, hex)
    if enemy.isMoving then
        enemy.timer = enemy.timer + dt
        local t = enemy.timer / enemy.speed
        
        if t >= 1 then
            enemy.q = enemy.targetQ
            enemy.r = enemy.targetR
            enemy.isMoving = false
            
            if enemy.currentPathIndex then
                enemy.currentPathIndex = enemy.currentPathIndex + 1
                if enemy.currentPathIndex <= #enemy.path then
                    ai.startEnemyMove(enemy, hex)
                else
                    enemy.path = {}
                    enemy.currentPathIndex = 0
                    enemy.hasActedThisTurn = true
                    print(enemy.name .. " finished moving!")
                end
            end
        end
    end
end

-- Атака врага
function ai.performAttack(enemy, target, actors, obstacles, hex, sounds)
    -- Простая атака с уроном 1
    local damage = 1
    
    -- Проверяем расстояние
    local distance = hex:getDistance(enemy.q, enemy.r, target.q, target.r)
    if distance ~= 1 then
        return false, "Target not adjacent"
    end
    
    -- Наносим урон
    target.health = target.health - damage
    
    print(string.format("%s attacks %s for %d damage!", enemy.name, target.name, damage))
    
    if sounds and sounds.attack then
        sounds.attack:play()
    end
    
    if target.health <= 0 then
        print(target.name .. " has been defeated!")
        for i, a in ipairs(actors) do
            if a == target then
                table.remove(actors, i)
                break
            end
        end
    end
    
    enemy.hasActedThisTurn = true
    return true, nil
end

-- Получение списка всех врагов (неиграбельных актеров)
function ai.getEnemies(actors)
    local enemies = {}
    for _, actor in ipairs(actors) do
        if not actor.isPlayable then
            table.insert(enemies, actor)
        end
    end
    return enemies
end

-- Проверка, остались ли враги, которые еще не ходили
function ai.hasEnemiesToAct(actors)
    for _, actor in ipairs(actors) do
        if not actor.isPlayable and not actor.hasActedThisTurn and not actor.isMoving then
            return true
        end
    end
    return false
end

-- Выполнение хода всех врагов
function ai.performAllEnemiesTurn(actors, obstacles, hex, sounds)
    local anyActed = false
    
    for _, enemy in ipairs(actors) do
        if not enemy.isPlayable and not enemy.hasActedThisTurn and not enemy.isMoving then
            ai.performEnemyTurn(enemy, actors, obstacles, hex, sounds)
            anyActed = true
            break -- Ходим по одному врагу за раз
        end
    end
    
    return anyActed
end

return ai