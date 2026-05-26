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

-- УНИФИЦИРОВАННАЯ ФУНКЦИЯ создания препятствия/строения
function environment.createObstacle(q, r, type, name, health, isPermanent, isBuilding, globalHealthCost)
    local obstacle = {}
    obstacle.q = q
    obstacle.r = r
    obstacle.type = type or "rock"
    obstacle.name = name or "Obstacle"
    obstacle.maxHealth = health or 2
    obstacle.health = obstacle.maxHealth
    obstacle.isPermanent = isPermanent or false
    obstacle.isBuilding = isBuilding or false
    obstacle.globalHealthCost = globalHealthCost or health
    
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
    elseif obstacle.type == "house" then
        love.graphics.setColor(0.7, 0.5, 0.3, 1)
        love.graphics.rectangle("fill", 8, 12, 16, 16)
        love.graphics.setColor(0.6, 0.3, 0.2, 1)
        love.graphics.polygon("fill", 6, 12, 16, 4, 26, 12)
        love.graphics.setColor(0.4, 0.3, 0.2, 1)
        love.graphics.rectangle("fill", 14, 20, 8, 8)
        love.graphics.setColor(0.8, 0.7, 0.4, 1)
        love.graphics.rectangle("fill", 15, 21, 2, 3)
    elseif obstacle.type == "tower" then
        love.graphics.setColor(0.5, 0.5, 0.6, 1)
        love.graphics.rectangle("fill", 10, 8, 12, 20)
        love.graphics.setColor(0.6, 0.6, 0.7, 1)
        love.graphics.polygon("fill", 8, 8, 16, 2, 24, 8)
        love.graphics.setColor(0.7, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", 14, 14, 4, 6)
    end
    
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", 16, 16, 14)
    love.graphics.setCanvas()
    
    return obstacle
end

-- Функция создания актера (расширена для поддержки нескольких атак)
function environment.createActor(q, r, name, color, spriteType, isPlayable, maxHealth, moveRange, isPermanent, attacks)
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
    actor.isPermanent = isPermanent or false

    actor.isPlayable = isPlayable or false
    actor.hasActedThisTurn = false
    
    -- Статы
    actor.maxHealth = maxHealth or 3
    actor.health = actor.maxHealth
    actor.moveRange = moveRange or 3
    
    -- Атаки (список атак, доступных персонажу)
    actor.attacks = attacks or {}
    actor.currentAttackIndex = 1  -- индекс выбранной атаки
    
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
    elseif spriteType == "circle" then
        love.graphics.circle("line", 16, 16, 12)
    end
    
    love.graphics.circle("line", 16, 16, 14)
    love.graphics.setCanvas()
    
    return actor
end

-- Генерация карты земли (трава в центре, лава по краям, без переходов)
function environment.generateTerrainMap(hex)
    local terrainMap = {}
    local centerQ = (hex.gridWidth - 1) / 2
    local centerR = (hex.gridHeight - 1) / 2
    local radius = math.min(centerQ, centerR) - 1  -- Радиус травяной зоны
    
    for q = 0, hex.gridWidth - 1 do
        terrainMap[q] = {}
        for r = 0, hex.gridHeight - 1 do
            -- Расстояние Чебышева (квадратная зона) или манхэттенское
            -- Используем максимальное отклонение для чёткой границы
            local distQ = math.abs(q - centerQ)
            local distR = math.abs(r - centerR)
            local maxDist = math.max(distQ, distR)
            
            -- Если внутри радиуса - трава, иначе - лава
            if maxDist <= radius then
                terrainMap[q][r] = environment.terrainTypes[1]  -- grass
            else
                terrainMap[q][r] = environment.terrainTypes[6]  -- lava
            end
        end
    end
    
    return terrainMap
end

-- ============================================================
-- СОЗДАНИЕ АТАК ДЛЯ ПЕРСОНАЖЕЙ
-- ============================================================

-- Импортируем combat для создания атак
local function getCombat()
    return require("combat")
end

function environment.getWarriorAttacks()
    local combat = getCombat()
    return {
        {
            name = "⚔ Shield Bash",
            description = "Knocks enemy back with a shield",
            attack = combat.DashAttack.new(),
            icon = "🛡"
        },
        {
            name = "💪 Mighty Flip",
            description = "Flips enemy behind you",
            attack = combat.FlipAttack.new(),
            icon = "🔄"
        }
    }
end

function environment.getMageAttacks()
    local combat = getCombat()
    return {
        {
            name = "✨ Force Bolt",
            description = "Shoots a projectile that pushes the first target",
            attack = combat.ShootAttack.new(6),
            icon = "⚡"
        },
        {
            name = "🏹 Piercing Arrow",
            description = "Passes through first target, hits second",
            attack = combat.PiercingShootAttack.new(5),
            icon = "➡"
        }
    }
end

function environment.getRogueAttacks()
    local combat = getCombat()
    return {
        {
            name = "AoE Direct",
            description = "AoE Direct",
            attack = combat.AoeDirectionalAttack.new(5),
            icon = "➡"
        },
        {
            name = "Pure AoE",
            description = "Pure AoE forward in a straight line",
            attack = combat.AoePushAttack.new(),
            icon = "⚡"
        }
    }
end

-- ============================================================
-- СОЗДАНИЕ НАЧАЛЬНЫХ АКТЕРОВ (С АТАКАМИ)
-- ============================================================

function environment.createInitialActors()
    local actors = {}
    
    -- ВОИН (Warrior) - танк с щитом и переворотом
    table.insert(actors, environment.createActor(3, 3, "Warrior", {1, 0.2, 0.2, 1}, "cross", true, 6, 2, true, environment.getWarriorAttacks()))
    
    -- МАГ (Mage) - дальнобойщик с шоковой волной
    table.insert(actors, environment.createActor(6, 4, "Mage", {0.2, 0.2, 1, 1}, "star", true, 3, 4, true, environment.getMageAttacks()))
    
    -- РАЗБОЙНИК 1 (Rogue) - с пронзающей стрелой и рывком
    table.insert(actors, environment.createActor(4, 1, "Rogue", {0.2, 0.8, 0.2, 1}, "triangle", true, 4, 4, true, environment.getRogueAttacks()))
    
    -- РАЗБОЙНИК 2 (Rogue) - такой же
    table.insert(actors, environment.createActor(4, 2, "Rogue", {0.2, 0.8, 0.2, 1}, "triangle", true, 4, 4, true, environment.getRogueAttacks()))

    -- ВРАГ: ГОБЛИН (Goblin)
    table.insert(actors, environment.createActor(3, 5, "Goblin", {0.5, 0.3, 0.1, 1}, "circle", false, 3, 3, false))
    
    -- ВРАГ: ОРК (Orc)
    table.insert(actors, environment.createActor(7, 2, "Orc", {0.6, 0.2, 0.2, 1}, "cross", false, 5, 2, false))
    
    return actors
end

-- Создание начальных препятствий и строений
function environment.createInitialObstaclesAndBuildings()
    local obstacles = {}
    
    -- Обычные препятствия
    table.insert(obstacles, environment.createObstacle(3, 3, "rock", "Big Rock", 3, false, false))
    table.insert(obstacles, environment.createObstacle(5, 2, "tree", "Oak Tree", 2, false, false))
    table.insert(obstacles, environment.createObstacle(1, 4, "wall", "Stone Wall", 4, false, false))
    table.insert(obstacles, environment.createObstacle(7, 5, "spike", "Spike Trap", 1, false, false))
    table.insert(obstacles, environment.createObstacle(4, 4, "tree", "Pine Tree", 2, false, false))
    table.insert(obstacles, environment.createObstacle(2, 5, "rock", "Small Rock", 2, false, false))
    
    -- Строения
    table.insert(obstacles, environment.createObstacle(2, 2, "house", "Small House", 3, false, true, 3))
    table.insert(obstacles, environment.createObstacle(5, 5, "house", "Small House", 4, false, true, 4))
    table.insert(obstacles, environment.createObstacle(7, 3, "house", "Small House", 2, false, true, 2))
    table.insert(obstacles, environment.createObstacle(1, 6, "tower", "Watch Tower", 5, false, true, 5))
    
    return obstacles
end

-- Для совместимости
function environment.createInitialObstacles()
    return environment.createInitialObstaclesAndBuildings()
end

function environment.createInitialBuildings()
    return {}
end

return environment