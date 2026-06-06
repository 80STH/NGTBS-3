-- entity.lua
-- Единая сущность для актеров и препятствий

local Entity = {}
Entity.__index = Entity

-- Типы сущностей
Entity.TYPES = {
    CHARACTER = "character",  -- Игровой персонаж
    OBSTACLE = "obstacle",    -- Препятствие (разрушаемое)
    BUILDING = "building"     -- Здание (влияет на глобальное здоровье)
}

function Entity.new(name, type, q, r, maxHealth, isPlayable, moveRange, sprite, color, attacks)
    local self = setmetatable({}, Entity)
    
    self.name = name or "Unknown"
    self.type = type or Entity.TYPES.CHARACTER
    self.q = q or 0
    self.r = r or 0
    self.maxHealth = maxHealth or 3
    self.health = self.maxHealth
    self.isPlayable = isPlayable or false
    self.moveRange = moveRange or 0
    self.sprite = sprite
    self.color = color or {1, 1, 1, 1}
    
    -- Анимация
    self.isMoving = false
    self.path = {}
    self.currentPathIndex = 0
    self.timer = 0
    self.speed = 0.2
    self.pulse = math.random() * math.pi * 2
    self.pulseSpeed = 5
    
    -- Атаки (только для персонажей)
    self.attacks = attacks or {}
    self.currentAttackIndex = 1
    
    -- Флаги
    self.hasActedThisTurn = false
    self.hasMovedThisTurn = false   -- для союзников
    
    -- Для строительных объектов
    self.globalHealthCost = nil
    
    --  НЕПОДВИЖНОСТЬ: препятствия и здания не отталкиваются
    self.isPushable = (type == Entity.TYPES.CHARACTER)
    
    -- Анимация смерти
    self.isDying = false
    self.deathTimer = 0
    self.deathDuration = 0.4   -- длительность анимации исчезновения
    
    return self
end

-- Проверка, является ли сущность персонажем
function Entity:isCharacter()
    return self.type == Entity.TYPES.CHARACTER
end

-- Проверка, является ли сущность препятствием
function Entity:isObstacle()
    return self.type == Entity.TYPES.OBSTACLE
end

-- Проверка, является ли сущность зданием
function Entity:isBuilding()
    return self.type == Entity.TYPES.BUILDING
end

-- Можно ли оттолкнуть сущность
function Entity:isPushable()
    return self.isPushable
end

-- Получить текущую атаку
function Entity:getCurrentAttack()
    if #self.attacks == 0 then
        return nil
    end
    return self.attacks[self.currentAttackIndex].attack
end

-- Переключить атаку
function Entity:switchAttack()
    if #self.attacks > 0 and not self.hasActedThisTurn and not self.isMoving then
        self.currentAttackIndex = (self.currentAttackIndex % #self.attacks) + 1
        local attack = self:getCurrentAttack()
        print(string.format("%s switched to: %s", self.name, attack.name))
        return true
    end
    return false
end

-- Применить урон
function Entity:takeDamage(damage, globalHealth)
    local actualDamage = math.min(damage, self.health)
    self.health = self.health - actualDamage
    
    if self:isBuilding() and globalHealth then
        globalHealth.current = math.max(0, globalHealth.current - actualDamage)
        print(string.format("%s takes %d damage! (%d/%d HP)", 
              self.name, actualDamage, math.max(0, self.health), self.maxHealth))
        print(string.format(" Global health reduced by %d! (%d/%d)", 
              actualDamage, globalHealth.current, globalHealth.max))
        
        -- ВЫЗЫВАЕМ ПРОВЕРКУ КОНЦА ИГРЫ
        if checkGameEnd then checkGameEnd() end
    else
        print(string.format("%s takes %d damage! (%d/%d HP)", 
              self.name, actualDamage, math.max(0, self.health), self.maxHealth))
    end
    
    return self.health <= 0
end

-- Запуск анимации смерти
function Entity:startDeath()
    if self.isDying then return end
    self.isDying = true
    self.deathTimer = 0
    self.health = 0   -- гарантируем, что здоровье ноль
    if sounds and sounds.death then
        sounds.death:play()
    end
end

-- Получить строковое представление
function Entity:getTypeString()
    if self:isCharacter() then
        return self.isPlayable and "ally" or "enemy"
    elseif self:isObstacle() then
        return "obstacle"
    else
        return "building"
    end
end

function Entity:isEnemy()
    return self:isCharacter() and not self.isPlayable
end

function Entity:isAlly()
    return self:isCharacter() and self.isPlayable
end

function Entity:isDestructible()
    return self:isObstacle() or self:isBuilding()
end

return Entity