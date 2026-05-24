-- environment.lua
-- Инициализация карты, актеров и препятствий

local environment = {}

-- Типы земли (только визуальные)
environment.terrainTypes = {
    {name = "grass", color = {0.3, 0.7, 0.2, 0.9}, darkColor = {0.2, 0.5, 0.15, 0.9}},
    {name = "dirt", color = {0.55, 0.4, 0.25, 0.9}, darkColor = {0.45, 0.3, 0.2, 0.9}},
    {name = "sand", color = {0.85, 0.75, 0.5, 0.9}, darkColor = {0.7, 0.6, 0.4, 0.9}},
    {name = "stone", color = {0.5, 0.5, 0.55, 0.9}, darkColor = {0.4, 0.4, 0.45, 0.9}},
    {name = "mud", color = {0.45, 0.35, 0.25, 0.9}, darkColor = {0.35, 0.25, 0.2, 0.9}},
    {name = "lava", color = {0.8, 0.3, 0.1, 0.9}, darkColor = {0.6, 0.2, 0.05, 0.9}},
    {name = "snow", color = {0.9, 0.9, 0.95, 0.9}, darkColor = {0.7, 0.7, 0.75, 0.9}},
    {name = "swamp", color = {0.35, 0.55, 0.3, 0.9}, darkColor = {0.25, 0.4, 0.2, 0.9}}
}

-- Функция создания препятствия с здоровьем
function environment.createObstacle(q, r, type, name, health, isPermanent)
    local obstacle = {}
    obstacle.q = q
    obstacle.r = r
    obstacle.type = type or "rock"
    obstacle.name = name or "Obstacle"
    obstacle.maxHealth = health or 2
    obstacle.health = obstacle.maxHealth
    obstacle.isPermanent = isPermanent or false --цель не исчезает на 0 хп
    
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
function environment.createActor(q, r, name, color, spriteType, isPlayable, maxHealth, moveRange, isPermanent)
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
    actor.isPermanent = isPermanent or false --цель не исчезает на 0 хп

    actor.isPlayable = isPlayable or false
    actor.hasActedThisTurn = false
    
    -- Статы
    actor.maxHealth = maxHealth or 3
    actor.health = actor.maxHealth
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

-- Генерация карты земли
function environment.generateTerrainMap(hex)
    local terrainMap = {}
    for q = 0, hex.gridWidth - 1 do
        terrainMap[q] = {}
        for r = 0, hex.gridHeight - 1 do
            local noiseValue = math.sin(q * 0.5) * math.cos(r * 0.5) + math.sin((q + r) * 0.8) * 0.5
            
            local centerQ = hex.gridWidth / 2
            local centerR = hex.gridHeight / 2
            local distToCenter = math.sqrt((q - centerQ)^2 + (r - centerR)^2)
            
            if distToCenter < 2 then
                terrainMap[q][r] = environment.terrainTypes[1]
            elseif distToCenter < 3.5 then
                if noiseValue > 0.3 then
                    terrainMap[q][r] = environment.terrainTypes[2]
                else
                    terrainMap[q][r] = environment.terrainTypes[1]
                end
            else
                local rand = (q * 7 + r * 13) % 100 / 100
                if rand < 0.3 then
                    terrainMap[q][r] = environment.terrainTypes[2]
                elseif rand < 0.5 then
                    terrainMap[q][r] = environment.terrainTypes[3]
                elseif rand < 0.65 then
                    terrainMap[q][r] = environment.terrainTypes[4]
                elseif rand < 0.75 then
                    terrainMap[q][r] = environment.terrainTypes[6]
                else
                    terrainMap[q][r] = environment.terrainTypes[1]
                end
            end
            
            if (q < 2 and r < 2) or (q > hex.gridWidth - 3 and r > hex.gridHeight - 3) then
                terrainMap[q][r] = environment.terrainTypes[7]
            end
            
            if q < 3 and r > hex.gridHeight - 3 then
                terrainMap[q][r] = environment.terrainTypes[8]
            end
            
            if q > hex.gridWidth - 3 and r < 2 then
                terrainMap[q][r] = environment.terrainTypes[4]
            end
            
            local randomChance = (q * 11 + r * 17) % 100 / 100
            if randomChance < 0.05 and terrainMap[q][r].name ~= "lava" then
                terrainMap[q][r] = environment.terrainTypes[6]
            end
        end
    end
    return terrainMap
end

-- Создание начальных актеров
function environment.createInitialActors()
    local actors = {}
    
    table.insert(actors, environment.createActor(0, 0, "Warrior", {1, 0.2, 0.2, 1}, "cross", true, 5, 2, true))
    table.insert(actors, environment.createActor(6, 4, "Mage", {0.2, 0.2, 1, 1}, "star", true, 2, 5, true))
    table.insert(actors, environment.createActor(4, 1, "Rogue", {0.2, 0.8, 0.2, 1}, "triangle", true, 3, 4, true))
    table.insert(actors, environment.createActor(4, 2, "Rogue", {0.2, 0.8, 0.2, 1}, "triangle", true, 3, 4, true))

    -- Враги
    table.insert(actors, environment.createActor(3, 5, "Goblin", {0.5, 0.3, 0.1, 1}, "circle", false, 3, 3))
    table.insert(actors, environment.createActor(7, 2, "Orc", {0.6, 0.2, 0.2, 1}, "cross", false, 4, 2))
    
    return actors
end

-- Создание начальных препятствий
function environment.createInitialObstacles()
    local obstacles = {}
    
    table.insert(obstacles, environment.createObstacle(3, 3, "rock", "Big Rock", 3))
    table.insert(obstacles, environment.createObstacle(5, 2, "tree", "Oak Tree", 2))
    table.insert(obstacles, environment.createObstacle(1, 4, "wall", "Stone Wall", 4))
    table.insert(obstacles, environment.createObstacle(7, 5, "spike", "Spike Trap", 1))
    table.insert(obstacles, environment.createObstacle(4, 4, "tree", "Pine Tree", 2))
    table.insert(obstacles, environment.createObstacle(2, 5, "rock", "Small Rock", 2))
    
    return obstacles
end

return environment