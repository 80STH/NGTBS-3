-- combat.lua
-- Система боя: атаки, урон, эффекты
-- Переписана логика прямой линии и отталкивания с использованием кубических координат

local combat = {}

-- ============================================================
-- КОНВЕРТАЦИЯ КООРДИНАТ (кубические <-> осевые)
-- ============================================================

local function axialToCube(q, r)
    local x = q
    local z = r - (q - (q % 2)) / 2
    local y = -x - z
    return x, y, z
end

local function cubeToAxial(x, y, z)
    local q = x
    local r = z + (x - (x % 2)) / 2
    return q, r
end

-- Применение кубического шага к осевым координатам
local function applyCubeStep(q, r, stepX, stepY, stepZ)
    local x, y, z = axialToCube(q, r)
    x = x + stepX
    y = y + stepY
    z = z + stepZ
    return cubeToAxial(x, y, z)
end

local function debugPrint(...)
    if _G.DEBUG_COMBAT then
        print(...)
    end
end

-- ============================================================
-- БАЗОВЫЙ КЛАСС ДЛЯ АТАК
-- ============================================================

combat.Attack = {}
combat.Attack.__index = combat.Attack

function combat.Attack.new(name, description, range, damage, effects)
    local self = setmetatable({}, combat.Attack)
    self.name = name or "Attack"
    self.description = description or "A basic attack"
    self.range = range or 1
    self.damage = damage or 1
    self.effects = effects or {}
    return self
end

-- ============================================================
-- ОПРЕДЕЛЕНИЕ ПРЯМОЙ ЛИНИИ (кубические координаты)
-- ============================================================

function combat.Attack:getLineDirection(fromQ, fromR, toQ, toR, hex)
    debugPrint("--- getLineDirection ---")
    local ax, ay, az = axialToCube(fromQ, fromR)
    local bx, by, bz = axialToCube(toQ, toR)
    local dx, dy, dz = bx - ax, by - ay, bz - az

    local function gcd(a, b)
        a = math.abs(a)
        b = math.abs(b)
        while b ~= 0 do
            a, b = b, a % b
        end
        return a
    end

    local g = gcd(gcd(dx, dy), dz)
    if g == 0 then
        debugPrint("Same point, no direction")
        return nil
    end

    local stepX, stepY, stepZ = dx / g, dy / g, dz / g

    -- Направление должно быть единичным вектором в кубических координатах
    if math.abs(stepX) > 1 or math.abs(stepY) > 1 or math.abs(stepZ) > 1 then
        debugPrint("Not a unit direction")
        return nil
    end
    if stepX + stepY + stepZ ~= 0 then
        debugPrint("Invalid cube direction (sum != 0)")
        return nil
    end

    debugPrint(string.format("Cube direction: (%d, %d, %d)", stepX, stepY, stepZ))
    return stepX, stepY, stepZ
end

-- ============================================================
-- ПОИСК ЦЕЛЕЙ НА ЛИНИИ (с использованием кубического шага)
-- ============================================================

function combat.Attack:findFirstTargetOnLine(startQ, startR, stepX, stepY, stepZ, hex, actors, obstacles)
    debugPrint("--- findFirstTargetOnLine (cube step) ---")
    local curQ, curR = startQ, startR
    local step = 0
    while true do
        curQ, curR = applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        step = step + 1
        if not hex:isValidHex(curQ, curR) then
            debugPrint("Reached map edge")
            break
        end
        debugPrint(string.format("Step %d: checking (%d, %d)", step, curQ, curR))
        local target = combat.getActorAtHex(curQ, curR, actors) or
                       combat.getObstacleAtHex(curQ, curR, obstacles)
        if target then
            debugPrint(string.format("Target found at (%d, %d)", curQ, curR))
            return target, {q = curQ, r = curR}
        end
    end
    debugPrint("No target found")
    return nil, nil
end

function combat.Attack:findFirstTwoTargetsOnLine(startQ, startR, stepX, stepY, stepZ, hex, actors, obstacles)
    debugPrint("--- findFirstTwoTargetsOnLine (cube step) ---")
    local curQ, curR = startQ, startR
    local step = 0
    local firstTarget, firstHex = nil, nil
    local secondTarget, secondHex = nil, nil
    while true do
        curQ, curR = applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        step = step + 1
        if not hex:isValidHex(curQ, curR) then break end
        debugPrint(string.format("Step %d: checking (%d, %d)", step, curQ, curR))
        local target = combat.getActorAtHex(curQ, curR, actors) or
                       combat.getObstacleAtHex(curQ, curR, obstacles)
        if target then
            if not firstTarget then
                firstTarget = target
                firstHex = {q = curQ, r = curR}
                debugPrint(string.format("First target at (%d, %d)", curQ, curR))
            elseif not secondTarget and target ~= firstTarget then
                secondTarget = target
                secondHex = {q = curQ, r = curR}
                debugPrint(string.format("Second target at (%d, %d)", curQ, curR))
                break
            end
        end
    end
    return firstTarget, firstHex, secondTarget, secondHex
end

-- ============================================================
-- ОТТАЛКИВАНИЕ (с кубическим шагом)
-- ============================================================

-- Отталкивание цели в направлении (кубический шаг)
function combat.Attack:pushTargetInDirection(target, fromQ, fromR, stepX, stepY, stepZ, hex, actors, obstacles, sounds)
    local pushQ, pushR = applyCubeStep(fromQ, fromR, stepX, stepY, stepZ)
    debugPrint(string.format("Pushing %s from (%d,%d) to (%d,%d)", target.name or target.type, fromQ, fromR, pushQ, pushR))
    self:pushTargetToHex(target, fromQ, fromR, pushQ, pushR, hex, actors, obstacles, sounds)
end

-- Отталкивание цели на конкретную клетку (без изменений, логика корректна)
function combat.Attack:pushTargetToHex(target, fromQ, fromR, toQ, toR, hex, actors, obstacles, sounds)
    local isActor = target.maxHealth ~= nil and target.isBuilding ~= true

    if not hex:isValidHex(toQ, toR) then
        debugPrint("Target cell is outside map!")
        if isActor then
            target.health = target.health - 1
            print(target.name .. " is slammed against the edge! Takes 1 additional damage!")
            if sounds and sounds.collision then sounds.collision:play() end
            if target.health <= 0 then
                combat.removeActor(target, actors)
                print(target.name .. " has been defeated!")
            end
        end
        return
    end

    local obstacleAtPush = combat.getObstacleAtHex(toQ, toR, obstacles)
    local actorAtPush = combat.getActorAtHex(toQ, toR, actors)

    if not obstacleAtPush and not actorAtPush then
        debugPrint("Target cell is free, moving")
        if isActor then
            target.q = toQ
            target.r = toR
            print(target.name .. " is pushed back!")
        end
    elseif obstacleAtPush then
        debugPrint(string.format("Collision with obstacle: %s", obstacleAtPush.name))
        if isActor then
            obstacleAtPush.health = obstacleAtPush.health - 1
            target.health = target.health - 1
            print(target.name .. " crashes into " .. obstacleAtPush.name .. "! Both take 1 damage!")
            if sounds and sounds.collision then sounds.collision:play() end
            if obstacleAtPush.health <= 0 then
                combat.removeObstacle(obstacleAtPush, obstacles)
                print(obstacleAtPush.name .. " has been destroyed!")
            end
            if target.health <= 0 then
                combat.removeActor(target, actors)
                print(target.name .. " has been defeated!")
            end
        end
    elseif actorAtPush and actorAtPush ~= target then
        debugPrint(string.format("Collision with actor: %s", actorAtPush.name))
        actorAtPush.health = actorAtPush.health - 1
        target.health = target.health - 1
        print(target.name .. " crashes into " .. actorAtPush.name .. "! Both take 1 damage!")
        if sounds and sounds.collision then sounds.collision:play() end
        if target.health <= 0 then
            combat.removeActor(target, actors)
            print(target.name .. " has been defeated!")
        end
        if actorAtPush.health <= 0 then
            combat.removeActor(actorAtPush, actors)
            print(actorAtPush.name .. " has been defeated!")
        end
    end
end

-- ============================================================
-- НОВЫЕ ТИПЫ АТАК (обновлённые execute)
-- ============================================================

-- 1. РЫВОК ПО ПРЯМОЙ
combat.DashAttack = setmetatable({}, combat.Attack)
combat.DashAttack.__index = combat.DashAttack

function combat.DashAttack.new()
    local self = combat.Attack.new("Dash", "Charge forward in a straight line, pushing the first target hit", math.huge, 1, {})
    return setmetatable(self, combat.DashAttack)
end

function combat.DashAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    debugPrint("=== DashAttack ===")
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        debugPrint("ERROR: Not a straight line!")
        return false, "Not a straight line!"
    end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, actors, obstacles)
    if not firstTarget then
        debugPrint("ERROR: No target in that direction!")
        return false, "No target in that direction!"
    end
    self:dealDamageToTarget(firstTarget, attacker, self.damage, actors, obstacles, sounds)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, actors, obstacles, sounds)
    attacker.hasActedThisTurn = true
    debugPrint("=== DashAttack complete ===")
    return true, nil
end

-- 2. ПЕРЕВОРОТ ЦЕЛИ ЗА АТАКУЮЩЕГО
combat.FlipAttack = setmetatable({}, combat.Attack)
combat.FlipAttack.__index = combat.FlipAttack

function combat.FlipAttack.new()
    local self = combat.Attack.new(
        "Flip",
        "Flip the target behind the attacker",
        1,
        1,
        {}
    )
    return setmetatable(self, combat.FlipAttack)
end

function combat.FlipAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    debugPrint("=== FlipAttack ===")
    debugPrint(string.format("Attacker: (%d,%d) -> Target: (%d,%d)", attacker.q, attacker.r, targetQ, targetR))
    
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    debugPrint(string.format("Distance: %d", distance))
    
    if distance ~= 1 then
        debugPrint("ERROR: Target must be adjacent!")
        return false, "Target must be adjacent!"
    end
    
    local targetActor = combat.getActorAtHex(targetQ, targetR, actors)
    if not targetActor then
        debugPrint("ERROR: No enemy at that hex!")
        return false, "No enemy at that hex!"
    end
    
    -- Вычисляем позицию ЗА атакующим
    -- Направление от цели к атакующему (цель -> атакующий)
    local aX, aY, aZ = axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = axialToCube(targetQ, targetR)
    
    debugPrint(string.format("Attacker cube: (%d,%d,%d)", aX, aY, aZ))
    debugPrint(string.format("Target cube: (%d,%d,%d)", tX, tY, tZ))
    
    -- Направление от цели к атакующему
    local dirFromTargetToAttackerX = aX - tX
    local dirFromTargetToAttackerY = aY - tY
    local dirFromTargetToAttackerZ = aZ - tZ
    
    debugPrint(string.format("Direction from target to attacker: (%d,%d,%d)", 
        dirFromTargetToAttackerX, dirFromTargetToAttackerY, dirFromTargetToAttackerZ))
    
    -- Позиция за атакующим = позиция атакующего + направление от цели к атакующему
    local behindX = aX + dirFromTargetToAttackerX
    local behindY = aY + dirFromTargetToAttackerY
    local behindZ = aZ + dirFromTargetToAttackerZ
    
    local behindQ, behindR = cubeToAxial(behindX, behindY, behindZ)
    debugPrint(string.format("Behind position (axial): (%d,%d)", behindQ, behindR))
    
    -- Проверяем, можно ли переместить цель
    local isOccupied = combat.getActorAtHex(behindQ, behindR, actors) ~= nil or
                       combat.getObstacleAtHex(behindQ, behindR, obstacles) ~= nil
    
    if not hex:isValidHex(behindQ, behindR) then
        debugPrint("ERROR: Behind position is outside map!")
        return false, "No free space behind the attacker!"
    end
    
    if isOccupied then
        debugPrint("ERROR: Behind position is occupied!")
        return false, "No free space behind the attacker!"
    end
    
    -- Перемещаем цель
    targetActor.q = behindQ
    targetActor.r = behindR
    print(string.format("%s flips %s behind them!", attacker.name, targetActor.name))
    debugPrint(string.format("Moved %s to (%d,%d)", targetActor.name, behindQ, behindR))
    
    if sounds and sounds.attack then
        sounds.attack:play()
    end
    
    attacker.hasActedThisTurn = true
    debugPrint("=== FlipAttack complete ===")
    return true, nil
end

-- 3. ВЫСТРЕЛ ПО ПРЯМОЙ
combat.ShootAttack = setmetatable({}, combat.Attack)
combat.ShootAttack.__index = combat.ShootAttack

function combat.ShootAttack.new(range)
    local self = combat.Attack.new("Shoot", "Fire a projectile in a straight line, pushing the first target hit", range or 5, 1, {})
    return setmetatable(self, combat.ShootAttack)
end

function combat.ShootAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    debugPrint("=== ShootAttack ===")
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        return false, "Not a straight line!"
    end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, actors, obstacles)
    if not firstTarget then
        return false, "No target in that direction!"
    end
    local distance = hex:getDistance(attacker.q, attacker.r, targetHex.q, targetHex.r)
    if distance > self.range then
        return false, "Target out of range!"
    end
    self:dealDamageToTarget(firstTarget, attacker, self.damage, actors, obstacles, sounds)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, actors, obstacles, sounds)
    attacker.hasActedThisTurn = true
    return true, nil
end

-- 4. ПРОНЗАЮЩИЙ ВЫСТРЕЛ
combat.PiercingShootAttack = setmetatable({}, combat.Attack)
combat.PiercingShootAttack.__index = combat.PiercingShootAttack

function combat.PiercingShootAttack.new(range)
    local self = combat.Attack.new("Piercing Shot", "Shoot through the first target (0 dmg, pushes) to hit the second (1 dmg, pushes)", range or 5, 0, {})
    return setmetatable(self, combat.PiercingShootAttack)
end

function combat.PiercingShootAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    debugPrint("=== PiercingShootAttack ===")
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        return false, "Not a straight line!"
    end
    local firstTarget, firstHex, secondTarget, secondHex = self:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, actors, obstacles)
    if not firstTarget then
        return false, "No target in that direction!"
    end
    print(string.format("%s shoots through %s!", attacker.name, firstTarget.name or firstTarget.type))
    if secondTarget then
        self:dealDamageToTarget(secondTarget, attacker, 1, actors, obstacles, sounds)
        self:pushTargetInDirection(secondTarget, secondHex.q, secondHex.r, stepX, stepY, stepZ, hex, actors, obstacles, sounds)
    end
    self:pushTargetInDirection(firstTarget, firstHex.q, firstHex.r, stepX, stepY, stepZ, hex, actors, obstacles, sounds)
    attacker.hasActedThisTurn = true
    return true, nil
end

-- 5. AoE ОТТАЛКИВАНИЕ ВОКРУГ (без изменений)
combat.AoePushAttack = setmetatable({}, combat.Attack)
combat.AoePushAttack.__index = combat.AoePushAttack

function combat.AoePushAttack.new()
    local self = combat.Attack.new("Shockwave", "Deals 1 damage to the center and pushes all adjacent targets outward", 1, 1, {})
    return setmetatable(self, combat.AoePushAttack)
end

function combat.AoePushAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    debugPrint("=== AoePushAttack ===")
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    local centerTarget = combat.getActorAtHex(targetQ, targetR, actors) or combat.getObstacleAtHex(targetQ, targetR, obstacles)
    if centerTarget then
        self:dealDamageToTarget(centerTarget, attacker, self.damage, actors, obstacles, sounds)
    end
    local neighbors = hex:getNeighbors(targetQ, targetR)
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local target = combat.getActorAtHex(neighbor.q, neighbor.r, actors) or combat.getObstacleAtHex(neighbor.q, neighbor.r, obstacles)
            if target then
                local cX, cY, cZ = axialToCube(targetQ, targetR)
                local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
                local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dirX, dirY, dirZ)
                self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, actors, obstacles, sounds)
            end
        end
    end
    attacker.hasActedThisTurn = true
    return true, nil
end

-- 6. AoE ТРИ ЦЕЛИ В НАПРАВЛЕНИИ (без изменений)
combat.AoeDirectionalAttack = setmetatable({}, combat.Attack)
combat.AoeDirectionalAttack.__index = combat.AoeDirectionalAttack

function combat.AoeDirectionalAttack.new()
    local self = combat.Attack.new("Cone Blast", "Deals 1 damage to the center and pushes 3 adjacent targets in a chosen direction", 1, 1, {})
    return setmetatable(self, combat.AoeDirectionalAttack)
end

function combat.AoeDirectionalAttack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    debugPrint("=== AoeDirectionalAttack ===")
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local centerTarget = combat.getActorAtHex(targetQ, targetR, actors) or combat.getObstacleAtHex(targetQ, targetR, obstacles)
    if centerTarget then
        self:dealDamageToTarget(centerTarget, attacker, self.damage, actors, obstacles, sounds)
    end
    local neighborsInDirection = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)
    for _, neighbor in ipairs(neighborsInDirection) do
        local target = combat.getActorAtHex(neighbor.q, neighbor.r, actors) or combat.getObstacleAtHex(neighbor.q, neighbor.r, obstacles)
        if target then
            local cX, cY, cZ = axialToCube(targetQ, targetR)
            local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dX, dY, dZ)
            self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, actors, obstacles, sounds)
        end
    end
    attacker.hasActedThisTurn = true
    return true, nil
end

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (без изменений)
-- ============================================================

function combat.getActorAtHex(q, r, actors)
    for _, actor in ipairs(actors) do
        if actor.q == q and actor.r == r then return actor end
    end
    return nil
end

function combat.getObstacleAtHex(q, r, obstacles)
    for _, obstacle in ipairs(obstacles) do
        if obstacle.q == q and obstacle.r == r then return obstacle end
    end
    return nil
end

function combat.removeActor(actor, actors)
    for i, a in ipairs(actors) do
        if a == actor then table.remove(actors, i); return true end
    end
    return false
end

function combat.removeObstacle(obstacle, obstacles)
    for i, o in ipairs(obstacles) do
        if o == obstacle then table.remove(obstacles, i); return true end
    end
    return false
end

function combat.Attack:dealDamageToTarget(target, attacker, damage, actors, obstacles, sounds)
    debugPrint(string.format("dealDamageToTarget: %s, damage=%d", target.name or target.type, damage))
    local isBuilding = target.isBuilding == true
    if isBuilding then
        local wasDestroyed = combat.handleBuildingDamage(target, damage, _G.globalHealth)
        if wasDestroyed then combat.removeObstacle(target, obstacles) end
        return wasDestroyed
    else
        target.health = target.health - damage
        print(string.format("%s deals %d damage to %s!", attacker.name, damage, target.name or target.type))
        if target.health <= 0 then
            if target.maxHealth ~= nil then
                combat.removeActor(target, actors)
            else
                combat.removeObstacle(target, obstacles)
            end
            print(target.name .. " has been defeated!")
            return true
        end
    end
    if sounds and sounds.attack then sounds.attack:play() end
    return false
end

function combat.Attack:getNeighborsInDirection(centerQ, centerR, dirQ, dirR, hex)
    debugPrint("--- getNeighborsInDirection ---")
    local neighbors = {}
    local allNeighbors = hex:getNeighbors(centerQ, centerR)
    local centerX, centerY, centerZ = axialToCube(centerQ, centerR)
    local targetX = centerX + dirQ
    local targetZ = centerR + dirR
    local targetY = -targetX - targetZ
    local function directionScore(q, r)
        local nX, nY, nZ = axialToCube(q, r)
        return (nX - centerX) * (targetX - centerX) +
               (nY - centerY) * (targetY - centerY) +
               (nZ - centerZ) * (targetZ - centerZ)
    end
    table.sort(allNeighbors, function(a, b)
        return directionScore(a.q, a.r) > directionScore(b.q, b.r)
    end)
    for i = 1, math.min(3, #allNeighbors) do
        if hex:isValidHex(allNeighbors[i].q, allNeighbors[i].r) then
            table.insert(neighbors, allNeighbors[i])
        end
    end
    return neighbors
end

function combat.handleBuildingDamage(building, damage, globalHealth)
    local oldHealth = building.health
    building.health = building.health - damage
    local actualDamage = oldHealth - building.health
    globalHealth.current = math.max(0, globalHealth.current - actualDamage)
    print(string.format("%s takes %d damage! (%d/%d HP)", building.name, actualDamage, math.max(0, building.health), building.maxHealth))
    print(string.format("⚔ Global health reduced by %d! (%d/%d)", actualDamage, globalHealth.current, globalHealth.max))
    return building.health <= 0
end

-- ============================================================
-- ФАБРИКА АТАК
-- ============================================================

combat.attackFactory = {
    dash = function() return combat.DashAttack.new() end,
    flip = function() return combat.FlipAttack.new() end,
    shoot = function(range) return combat.ShootAttack.new(range or 5) end,
    piercingShoot = function(range) return combat.PiercingShootAttack.new(range or 5) end,
    aoePush = function() return combat.AoePushAttack.new() end,
    aoeDirectional = function() return combat.AoeDirectionalAttack.new() end,
}

function combat.createAttackForActor(attackType, params)
    local factory = combat.attackFactory[attackType]
    return factory and factory(params) or combat.DashAttack.new()
end

function combat.performAttack(attacker, targetQ, targetR, hex, actors, obstacles, sounds, attackOverride)
    debugPrint(string.format("\n========== PERFORM ATTACK =========="))
    if attacker.isMoving then return false, "Cannot attack while moving!" end
    if attacker.hasActedThisTurn then return false, attacker.name .. " has already acted this turn!" end
    local attack = attackOverride or attacker.attack or combat.DashAttack.new()
    local success, message = attack:execute(attacker, targetQ, targetR, hex, actors, obstacles, sounds)
    if not success then print(message); return false end
    attacker.hasActedThisTurn = true
    return true
end

return combat