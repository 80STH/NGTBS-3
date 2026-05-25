-- combat.lua
-- Система боя: атаки, урон, эффекты
-- Легко расширяемый дизайн для добавления новых атак

local combat = {}

-- ============================================================
-- БАЗОВЫЕ КЛАССЫ ДЛЯ АТАК
-- ============================================================

-- Базовый класс для всех атак
combat.Attack = {}
combat.Attack.__index = combat.Attack

function combat.Attack.new(name, description, range, damage, effects)
    local self = setmetatable({}, combat.Attack)
    self.name = name or "Attack"
    self.description = description or "A basic attack"
    self.range = range or 1  -- дальность атаки в гексах
    self.damage = damage or 1
    self.effects = effects or {}  -- таблица эффектов
    return self
end

-- Основной метод атаки (переопределяется в наследниках)
function combat.Attack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    -- Базовое поведение: прямой урон + отталкивание
    return self:dealDamageAndPush(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
end

function combat.Attack:dealDamageAndPush(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    local targetActor = combat.getActorAtHex(targetQ, targetR, actors)
    local targetObstacle = combat.getObstacleAtHex(targetQ, targetR, obstacles)
    
    if not targetActor and not targetObstacle then
        return false, "No target at that hex!"
    end
    
    local target = targetActor or targetObstacle
    
    -- Проверяем, является ли цель строением
    local isBuilding = target.isBuilding == true
    
    -- Наносим урон
    if isBuilding then
        -- Для строений используем специальную обработку
        -- Требуется передать globalHealth из main.lua
        -- Для этого нужно модифицировать вызов или сделать globalHealth глобальной
        local wasDestroyed = combat.handleBuildingDamage(target, self.damage, _G.globalHealth)
        if wasDestroyed then
            combat.removeObstacle(target, obstacles)
        end
    else
        target.health = target.health - self.damage
        print(string.format("%s attacks %s for %d damage!", attacker.name, target.name or target.type, self.damage))
    end
    
    if sounds and sounds.attack then
        sounds.attack:play()
    end
    
    local wasActorDead = targetActor and target.health <= 0
    
    -- Проверка на смерть цели
    local isDead = false
    if target.health <= 0 then
        if targetActor then
            combat.removeActor(targetActor, actors)
            print(targetActor.name .. " has been defeated!")
        elseif not isBuilding then
            combat.removeObstacle(targetObstacle, obstacles)
            print(targetObstacle.name .. " has been destroyed!")
        end
        isDead = true
    end
    
    -- Отталкивание (только если цель выжила или это актер)
    if not isDead or targetActor then
        self:pushTarget(attacker, targetQ, targetR, target, hex, actors, obstacles, sounds, wasActorDead)
    end
    
    return true, nil
end

-- Отталкивание цели

function combat.Attack:pushTarget(attacker, targetQ, targetR, target, hex, actors, obstacles, sounds, wasDeadBeforePush)
    -- Определяем направление отталкивания через кубические координаты
    local function axialToCube(q, r)
        local x = q
        local z = r - (q - (q % 2)) / 2
        return x, -x - z, z
    end
    
    local function cubeToAxial(x, y, z)
        local q = x
        local r = z + (x - (x % 2)) / 2
        return q, r
    end
    
    local aX, aY, aZ = axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = axialToCube(target.q, target.r)
    local dirX = tX - aX
    local dirY = tY - aY
    local dirZ = tZ - aZ
    
    local pushX = tX + dirX
    local pushY = tY + dirY
    local pushZ = tZ + dirZ
    local pushTargetQ, pushTargetR = cubeToAxial(pushX, pushY, pushZ)
    
    local targetActor = combat.getActorAtHex(target.q, target.r, actors)
    
    -- Если цель была актёром и умерла прямо перед отталкиванием
    if wasDeadBeforePush and targetActor == nil then
        self:applyDeathPushDamage(attacker, targetQ, targetR, pushTargetQ, pushTargetR, hex, actors, obstacles, sounds)
        return
    end
    
    -- ЕСЛИ ЦЕЛЬ - СТРОЕНИЕ
    if target.isBuilding then
        if target.health > 0 then
            local oldHealth = target.health
            target.health = target.health - 1
            print(target.name .. " takes additional 1 damage from the force of the blow!")
            
            -- Глобальное здоровье снижается на 1 от дополнительного урона
            if _G.globalHealth then
                _G.globalHealth.current = math.max(0, _G.globalHealth.current - 1)
                print(string.format("⚔ Global health reduced by 1 from impact! (%d/%d)", 
                    _G.globalHealth.current, _G.globalHealth.max))
            end
            
            if target.health <= 0 then
                -- При разрушении от дополнительного урона
                combat.removeObstacle(target, obstacles)
                print(target.name .. " has been destroyed!")
            end
        end
        return
    end
    
    -- Далее существующий код для актеров и обычных препятствий
    if targetActor then
        self:pushActor(targetActor, pushTargetQ, pushTargetR, hex, actors, obstacles, sounds)
    else
        if target.health > 0 then
            target.health = target.health - 1
            print(target.name .. " takes additional 1 damage from the force of the blow!")
            
            if target.health <= 0 then
                combat.removeObstacle(target, obstacles)
                print(target.name .. " has been destroyed!")
            end
        end
    end
end

-- Предсмертный урон от отталкивания (когда цель уже мертва, но толкает врага)
function combat.Attack:applyDeathPushDamage(attacker, deadQ, deadR, pushQ, pushR, hex, actors, obstacles, sounds)
    -- Находим цель, которая должна получить предсмертный удар
    -- (это актёр или препятствие на клетке pushQ, pushR)
    local targetActor = combat.getActorAtHex(pushQ, pushR, actors)
    local targetObstacle = combat.getObstacleAtHex(pushQ, pushR, obstacles)
    
    if targetActor and targetActor ~= attacker then
        targetActor.health = targetActor.health - 1
        print(targetActor.name .. " takes 1 damage from the death throes!")
        if targetActor.health <= 0 then
            combat.removeActor(targetActor, actors)
            print(targetActor.name .. " has been defeated!")
        end
    elseif targetObstacle then
        targetObstacle.health = targetObstacle.health - 1
        print(targetObstacle.name .. " is damaged by the shockwave!")
        if targetObstacle.health <= 0 then
            combat.removeObstacle(targetObstacle, obstacles)
            print(targetObstacle.name .. " has been destroyed!")
        end
    end
    
    if sounds and sounds.collision then
        sounds.collision:play()
    end
end

-- Отталкивание актера
function combat.Attack:pushActor(actor, pushQ, pushR, hex, actors, obstacles, sounds)
    if not hex:isValidHex(pushQ, pushR) then
        -- За границей карты - дополнительный урон
        actor.health = actor.health - 1
        print(actor.name .. " is slammed against the edge! Takes 1 additional damage!")
        
        if sounds and sounds.collision then
            sounds.collision:play()
        end
        
        if actor.health <= 0 then
            combat.removeActor(actor, actors)
            print(actor.name .. " has been defeated!")
        end
        return
    end
    
    local obstacleAtPush = combat.getObstacleAtHex(pushQ, pushR, obstacles)
    local actorAtPush = combat.getActorAtHex(pushQ, pushR, actors)
    
    if not obstacleAtPush and not actorAtPush then
        -- Свободная клетка - просто перемещаем
        actor.q = pushQ
        actor.r = pushR
        print(actor.name .. " is pushed back!")
    elseif obstacleAtPush then
        -- Столкновение с препятствием
        obstacleAtPush.health = obstacleAtPush.health - 1
        actor.health = actor.health - 1
        print(actor.name .. " crashes into " .. obstacleAtPush.name .. "! Both take 1 damage!")
        
        if sounds and sounds.collision then
            sounds.collision:play()
        end
        
        if obstacleAtPush.health <= 0 then
            combat.removeObstacle(obstacleAtPush, obstacles)
            print(obstacleAtPush.name .. " has been destroyed!")
        end
        
        if actor.health <= 0 then
            combat.removeActor(actor, actors)
            print(actor.name .. " has been defeated!")
        end
    elseif actorAtPush then
        -- Столкновение с другим актером
        actorAtPush.health = actorAtPush.health - 1
        actor.health = actor.health - 1
        print(actor.name .. " crashes into " .. actorAtPush.name .. "! Both take 1 damage!")
        
        if sounds and sounds.collision then
            sounds.collision:play()
        end
        
        if actor.health <= 0 then
            combat.removeActor(actor, actors)
            print(actor.name .. " has been defeated!")
        end
        
        if actorAtPush.health <= 0 then
            combat.removeActor(actorAtPush, actors)
            print(actorAtPush.name .. " has been defeated!")
        end
    end
end

-- ============================================================
-- КОНКРЕТНЫЕ ТИПЫ АТАК
-- ============================================================

-- 1. Базовая атака (меч/кулак)
combat.MeleeAttack = setmetatable({}, combat.Attack)
combat.MeleeAttack.__index = combat.MeleeAttack

function combat.MeleeAttack.new()
    local self = combat.Attack.new(
        "Melee Strike",
        "A powerful melee attack that pushes the target back",
        1,  -- дальность
        1,  -- урон
        {}  -- эффекты
    )
    return setmetatable(self, combat.MeleeAttack)
end

-- 2. Дальняя атака (без отталкивания)
combat.RangedAttack = setmetatable({}, combat.Attack)
combat.RangedAttack.__index = combat.RangedAttack

function combat.RangedAttack.new(damage, range)
    local self = combat.Attack.new(
        "Ranged Shot",
        "A projectile attack from distance",
        range or 3,
        damage or 1,
        {}
    )
    return setmetatable(self, combat.RangedAttack)
end

function combat.RangedAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    -- Проверка дальности
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    
    local targetActor = combat.getActorAtHex(targetQ, targetR, actors)
    local targetObstacle = combat.getObstacleAtHex(targetQ, targetR, obstacles)
    
    if not targetActor and not targetObstacle then
        return false, "No target at that hex!"
    end
    
    local target = targetActor or targetObstacle
    
    -- Наносим урон (без отталкивания)
    target.health = target.health - self.damage
    print(string.format("%s shoots %s for %d damage!", attacker.name, target.name or target.type, self.damage))
    
    if sounds and sounds.attack then
        sounds.attack:play()
    end
    
    if target.health <= 0 then
        if targetActor then
            combat.removeActor(targetActor, actors)
            print(targetActor.name .. " has been defeated!")
        else
            combat.removeObstacle(targetObstacle, obstacles)
            print(targetObstacle.name .. " has been destroyed!")
        end
    end
    
    return true, nil
end

-- 3. Атака со стихийным уроном (огонь)
combat.FireAttack = setmetatable({}, combat.Attack)
combat.FireAttack.__index = combat.FireAttack

function combat.FireAttack.new()
    local self = combat.Attack.new(
        "Fire Blast",
        "Deals fire damage and leaves burning ground",
        2,
        2,
        {burn = true}
    )
    return setmetatable(self, combat.FireAttack)
end

function combat.FireAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    
    local targetActor = combat.getActorAtHex(targetQ, targetR, actors)
    
    if not targetActor then
        return false, "No enemy at that hex!"
    end
    
    -- Наносим двойной урон
    targetActor.health = targetActor.health - self.damage
    print(string.format("%s blasts %s with fire for %d damage!", attacker.name, targetActor.name, self.damage))
    
    if sounds and sounds.attack then
        sounds.attack:play()
    end
    
    if targetActor.health <= 0 then
        combat.removeActor(targetActor, actors)
        print(targetActor.name .. " has been defeated!")
    end
    
    -- Эффект горения (можно добавить позже)
    
    return true, nil
end

-- 4. Исцеление (лечение союзника)
combat.HealAttack = setmetatable({}, combat.Attack)
combat.HealAttack.__index = combat.HealAttack

function combat.HealAttack.new(healAmount)
    local self = combat.Attack.new(
        "Heal",
        "Restores health to an ally",
        1,
        0,  -- урон 0
        {heal = healAmount or 2}
    )
    return setmetatable(self, combat.HealAttack)
end

function combat.HealAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    
    local targetActor = combat.getActorAtHex(targetQ, targetR, actors)
    
    if not targetActor then
        return false, "No ally at that hex!"
    end
    
    local healAmount = self.effects.heal
    local oldHealth = targetActor.health
    targetActor.health = math.min(targetActor.maxHealth, targetActor.health + healAmount)
    local healed = targetActor.health - oldHealth
    
    print(string.format("%s heals %s for %d HP!", attacker.name, targetActor.name, healed))
    
    if sounds and sounds.heal then
        sounds.heal:play()
    end
    
    return true, nil
end

-- 5. Атака с пробиванием (игнорирует часть защиты)
combat.PiercingAttack = setmetatable({}, combat.Attack)
combat.PiercingAttack.__index = combat.PiercingAttack

function combat.PiercingAttack.new()
    local self = combat.Attack.new(
        "Piercing Strike",
        "Ignores armor and deals direct damage",
        1,
        2,
        {piercing = true}
    )
    return setmetatable(self, combat.PiercingAttack)
end

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================

-- Поиск актера на гексе
function combat.getActorAtHex(q, r, actors)
    for _, actor in ipairs(actors) do
        if actor.q == q and actor.r == r then
            return actor
        end
    end
    return nil
end

-- Поиск препятствия на гексе
function combat.getObstacleAtHex(q, r, obstacles)
    for _, obstacle in ipairs(obstacles) do
        if obstacle.q == q and obstacle.r == r then
            return obstacle
        end
    end
    return nil
end

-- Удаление актера
function combat.removeActor(actor, actors)
    for i, a in ipairs(actors) do
        if a == actor then
            table.remove(actors, i)
            return true
        end
    end
    return false
end

-- Удаление препятствия
function combat.removeObstacle(obstacle, obstacles)
    for i, o in ipairs(obstacles) do
        if o == obstacle then
            table.remove(obstacles, i)
            return true
        end
    end
    return false
end

-- Фабрика атак (для удобного создания)
combat.attackFactory = {
    melee = function() return combat.MeleeAttack.new() end,
    ranged = function(damage, range) return combat.RangedAttack.new(damage or 1, range or 3) end,
    fire = function() return combat.FireAttack.new() end,
    heal = function(amount) return combat.HealAttack.new(amount or 2) end,
    piercing = function() return combat.PiercingAttack.new() end,
}

-- Создание атаки для персонажа
function combat.createAttackForActor(attackType, params)
    local factory = combat.attackFactory[attackType]
    if factory then
        return factory(params)
    end
    return combat.MeleeAttack.new()
end

-- ============================================================
-- ОСНОВНАЯ ФУНКЦИЯ АТАКИ (для вызова из main.lua)
-- ============================================================

function combat.performAttack(attacker, targetQ, targetR, hex, actors, obstacles, sounds, attackOverride)
    if attacker.isMoving then
        return false, "Cannot attack while moving!"
    end
    
    if attacker.hasActedThisTurn then
        return false, attacker.name .. " has already acted this turn!"
    end
    
    -- Выбираем атаку (можно переопределить для разных юнитов)
    local attack = attackOverride or attacker.attack or combat.MeleeAttack.new()
    
    -- Проверяем дальность
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > attack.range then
        return false, "Target out of range! Max range: " .. attack.range
    end
    
    -- Выполняем атаку
    local success, message = attack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    
    if not success then
        print(message)
        return false
    end
    
    -- Помечаем атакующего как совершившего действие
    attacker.hasActedThisTurn = true
    
    -- Очищаем историю действий (нельзя отменить атаку)
    return true
end


function combat.handleBuildingDamage(building, damage, globalHealth)
    local oldHealth = building.health
    building.health = building.health - damage
    local actualDamage = oldHealth - building.health  -- Сколько реально урона прошло
    
    -- Глобальное здоровье снижается на ВЕЛИЧИНУ РЕАЛЬНОГО УРОНА
    -- (2 урона = -2 к глобальному здоровью)
    local globalLoss = actualDamage
    globalHealth.current = math.max(0, globalHealth.current - globalLoss)
    
    print(string.format("%s takes %d damage! (%d/%d HP)", 
        building.name, actualDamage, math.max(0, building.health), building.maxHealth))
    print(string.format("⚔ Global health reduced by %d! (%d/%d)", 
        globalLoss, globalHealth.current, globalHealth.max))
    
    -- Проверяем, уничтожено ли строение
    local wasDestroyed = building.health <= 0
    
    if wasDestroyed then
        -- При уничтожении - просто сообщаем, глобальное здоровье уже уменьшено на actualDamage
        print(string.format("%s has been destroyed!", building.name))
        return true
    end
    
    return false
end

return combat