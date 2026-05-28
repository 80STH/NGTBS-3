-- combat.lua
-- Система боя с кубическими координатами (pointy-top, odd-r)
local combat = {}

-- ============================================================
-- ЕДИНЫЕ ПРЕОБРАЗОВАНИЯ ДЛЯ POINTY-TOP (углом вверх)
-- ============================================================
local function axialToCube(q, r)
    -- pointy-top: x = q - (r - (r%2))/2, z = r
    local x = q - (r - (r % 2)) / 2
    local z = r
    local y = -x - z
    return x, y, z
end

local function cubeToAxial(x, y, z)
    local q = x + (z - (z % 2)) / 2
    local r = z
    return q, r
end

local function applyCubeStep(q, r, stepX, stepY, stepZ)
    local x, y, z = axialToCube(q, r)
    x = x + stepX
    y = y + stepY
    z = z + stepZ
    return cubeToAxial(x, y, z)
end
-- ============================================================

-- ============================================================
-- БАЗОВЫЙ КЛАСС АТАКИ
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

-- Определение направления прямой линии (кубический шаг)
function combat.Attack:getLineDirection(fromQ, fromR, toQ, toR, hex)
    local ax, ay, az = axialToCube(fromQ, fromR)
    local bx, by, bz = axialToCube(toQ, toR)
    local dx, dy, dz = bx - ax, by - ay, bz - az

    local function gcd(a, b)
        a = math.abs(a); b = math.abs(b)
        while b ~= 0 do a, b = b, a % b end
        return a
    end

    local g = gcd(gcd(dx, dy), dz)
    if g == 0 then return nil end

    local stepX, stepY, stepZ = dx / g, dy / g, dz / g
    if math.abs(stepX) > 1 or math.abs(stepY) > 1 or math.abs(stepZ) > 1 then return nil end
    if stepX + stepY + stepZ ~= 0 then return nil end
    return stepX, stepY, stepZ
end

-- Поиск первой цели на линии
function combat.Attack:findFirstTargetOnLine(startQ, startR, stepX, stepY, stepZ, hex, entities)
    local curQ, curR = startQ, startR
    while true do
        curQ, curR = applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isValidHex(curQ, curR) then break end
        local target = combat.getEntityAtHex(curQ, curR, entities)
        if target then return target, {q = curQ, r = curR} end
    end
    return nil, nil
end

-- Поиск первых двух целей на линии
function combat.Attack:findFirstTwoTargetsOnLine(startQ, startR, stepX, stepY, stepZ, hex, entities)
    local curQ, curR = startQ, startR
    local firstTarget, firstHex, secondTarget, secondHex = nil, nil, nil, nil
    while true do
        curQ, curR = applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isValidHex(curQ, curR) then break end
        local target = combat.getEntityAtHex(curQ, curR, entities)
        if target then
            if not firstTarget then
                firstTarget, firstHex = target, {q = curQ, r = curR}
            elseif not secondTarget and target ~= firstTarget then
                secondTarget, secondHex = target, {q = curQ, r = curR}
                break
            end
        end
    end
    return firstTarget, firstHex, secondTarget, secondHex
end

-- Отталкивание в направлении
function combat.Attack:pushTargetInDirection(target, fromQ, fromR, stepX, stepY, stepZ, hex, entities, sounds, onComplete)
    local pushQ, pushR = applyCubeStep(fromQ, fromR, stepX, stepY, stepZ)
    self:pushTargetToHex(target, fromQ, fromR, pushQ, pushR, hex, entities, sounds, onComplete)
end

-- Отталкивание на конкретную клетку (с анимацией)
function combat.Attack:pushTargetToHex(target, fromQ, fromR, toQ, toR, hex, entities, sounds, onComplete)
    local wasDestroyed = false
    local function finishPush() if onComplete then onComplete(wasDestroyed) end end

    if not hex:isValidHex(toQ, toR) then
        if target:isCharacter() then
            target.health = target.health - 1
            print(target.name .. " is slammed against the edge! Takes 1 damage!")
            if sounds and sounds.collision then sounds.collision:play() end
            if target.health <= 0 then
                combat.removeEntity(target, entities)
                print(target.name .. " has been defeated!")
                wasDestroyed = true
            end
        end
        finishPush()
        return
    end

    local occupant = combat.getEntityAtHex(toQ, toR, entities)
    if not occupant then
        if target:isCharacter() then
            combat.addPushAnimation(target, fromQ, fromR, toQ, toR, function()
                print(target.name .. " is pushed back!")
                finishPush()
            end)
        else
            finishPush()
        end
    else
        if target:isCharacter() then
            combat.addPushAnimation(target, fromQ, fromR, toQ, toR, function()
                occupant.health = occupant.health - 1
                target.health = target.health - 1
                print(target.name .. " crashes into " .. occupant.name .. "! Both take 1 damage!")
                if sounds and sounds.collision then sounds.collision:play() end
                if occupant.health <= 0 then
                    combat.removeEntity(occupant, entities)
                    print(occupant.name .. " has been destroyed!")
                end
                if target.health <= 0 then
                    combat.removeEntity(target, entities)
                    print(target.name .. " has been defeated!")
                    wasDestroyed = true
                end
                finishPush()
            end)
        else
            finishPush()
        end
    end
end

-- ============================================================
-- ТИПЫ АТАК (коротко, только изменённые вызовы push)
-- ============================================================
combat.DashAttack = setmetatable({}, combat.Attack)
combat.DashAttack.__index = combat.DashAttack
function combat.DashAttack.new()
    local self = combat.Attack.new("Dash", "Charge forward, pushing first target", math.huge, 1, {})
    return setmetatable(self, combat.DashAttack)
end
function combat.DashAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then return false, "No target in that direction!" end
    self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, entities, sounds, function()
        attacker.hasActedThisTurn = true
    end)
    attacker.hasActedThisTurn = true
    return true
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

function combat.FlipAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    debugPrint("=== FlipAttack ===")
    debugPrint(string.format("Attacker: (%d,%d) -> Target: (%d,%d)", attacker.q, attacker.r, targetQ, targetR))
    
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    debugPrint(string.format("Distance: %d", distance))
    
    if distance ~= 1 then
        debugPrint("ERROR: Target must be adjacent!")
        return false, "Target must be adjacent!"
    end
    
    local targetActor = combat.getEntityAtHex(targetQ, targetR, entities)
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
    local isOccupied = combat.getEntityAtHex(behindQ, behindR, entities) ~= nil
    
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

function combat.ShootAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    debugPrint("=== ShootAttack ===")
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        return false, "Not a straight line!"
    end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then
        return false, "No target in that direction!"
    end
    local distance = hex:getDistance(attacker.q, attacker.r, targetHex.q, targetHex.r)
    if distance > self.range then
        return false, "Target out of range!"
    end
    self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, entities, sounds)
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

function combat.PiercingShootAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    debugPrint("=== PiercingShootAttack ===")
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        return false, "Not a straight line!"
    end
    local firstTarget, firstHex, secondTarget, secondHex = self:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then
        return false, "No target in that direction!"
    end
    print(string.format("%s shoots through %s!", attacker.name, firstTarget.name or firstTarget.type))
    if secondTarget then
        self:dealDamageToTarget(secondTarget, attacker, 1, entities, sounds)
        self:pushTargetInDirection(secondTarget, secondHex.q, secondHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    end
    self:pushTargetInDirection(firstTarget, firstHex.q, firstHex.r, stepX, stepY, stepZ, hex, entities, sounds)
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

function combat.AoePushAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    debugPrint("=== AoePushAttack ===")
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    local centerTarget = combat.getEntityAtHex(targetQ, targetR, entities)
    if centerTarget then
        self:dealDamageToTarget(centerTarget, attacker, self.damage, entities, sounds)
    end
    local neighbors = hex:getNeighbors(targetQ, targetR)
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
            if target then
                local cX, cY, cZ = axialToCube(targetQ, targetR)
                local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
                local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dirX, dirY, dirZ)
                self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, entities, sounds)
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

function combat.AoeDirectionalAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    debugPrint("=== AoeDirectionalAttack ===")
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end
    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local centerTarget = combat.getEntityAtHex(targetQ, targetR, entities)
    if centerTarget then
        self:dealDamageToTarget(centerTarget, attacker, self.damage, entities, sounds)
    end
    local neighborsInDirection = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)
    for _, neighbor in ipairs(neighborsInDirection) do
        local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
        if target then
            local cX, cY, cZ = axialToCube(targetQ, targetR)
            local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dX, dY, dZ)
            self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, entities, sounds)
        end
    end
    attacker.hasActedThisTurn = true
    return true, nil
end

-- Вспомогательные функции
function combat.getEntityAtHex(q, r, entities)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then return e end
    end
    return nil
end

function combat.removeEntity(entity, entities)
    for i, e in ipairs(entities) do
        if e == entity then table.remove(entities, i); return true end
    end
    return false
end

function combat.Attack:dealDamageToTarget(target, attacker, damage, entities, sounds)
    local wasDestroyed = target:takeDamage(damage)
    if sounds and sounds.attack then sounds.attack:play() end
    if wasDestroyed then combat.removeEntity(target, entities) end
    return wasDestroyed
end

-- ============================================================
-- WIND TORRENT (исправлены внутренние преобразования)
-- ============================================================
combat.WindTorrentAttack = setmetatable({}, combat.Attack)
combat.WindTorrentAttack.__index = combat.WindTorrentAttack

function combat.WindTorrentAttack.new()
    local self = combat.Attack.new("🌬️ Wind Torrent", "Global wind pushes everything one step", 999, 0, {})
    self.hasBeenUsed = false
    return setmetatable(self, combat.WindTorrentAttack)
end

function combat.WindTorrentAttack:executeGlobalWithAnimation(direction, hex, entities, sounds, onComplete)
    if self.hasBeenUsed then
        if onComplete then onComplete(false, "Already used") end
        return false
    end

    local stepMap = {
        north     = {dx = 0,  dy = 1,  dz = -1},
        northeast = {dx = 1,  dy = 0,  dz = -1},
        southeast = {dx = 1,  dy = -1, dz = 0},
        south     = {dx = 0,  dy = -1, dz = 1},
        southwest = {dx = -1, dy = 0,  dz = 1},
        northwest = {dx = -1, dy = 1,  dz = 0},
    }
    local step = stepMap[direction]
    if not step then
        if onComplete then onComplete(false, "Invalid direction") end
        return false
    end

    print(string.format("💨 WIND TORRENT: Pushing everything %s!", direction))

    local function applyStep(q, r)
        local x, y, z = axialToCube(q, r)
        return cubeToAxial(x + step.dx, y + step.dy, z + step.dz)
    end

    local function isValid(q, r) return hex:isValidHex(q, r) end

    -- Сбор всех объектов
    local allObjects = {}
    for _, entity in ipairs(entities) do
        table.insert(allObjects, {obj = entity, type = "actor"})
    end

    local pushes, damageEvents = {}, {}
    for _, entry in ipairs(allObjects) do
        local obj = entry.obj
        local newQ, newR = applyStep(obj.q, obj.r)
        if not isValid(newQ, newR) then
            table.insert(damageEvents, {obj = obj, reason = "edge"})
        else
            table.insert(pushes, {obj = obj, fromQ = obj.q, fromR = obj.r, toQ = newQ, toR = newR})
        end
    end

    -- Разрешение коллизий
    local targetMap, finalPushes, collisions = {}, {}, {}
    for _, push in ipairs(pushes) do
        local key = push.toQ .. "," .. push.toR
        if not targetMap[key] then
            targetMap[key] = push
            table.insert(finalPushes, push)
        else
            local existing = targetMap[key]
            table.insert(collisions, {obj1 = existing.obj, obj2 = push.obj})
            if push.obj.maxHealth ~= nil and existing.obj.maxHealth == nil then
                targetMap[key] = push
                for i, fp in ipairs(finalPushes) do
                    if fp.obj == existing.obj then finalPushes[i] = push; break end
                end
            end
        end
    end

    for _, push in ipairs(finalPushes) do
        combat.addPushAnimation(push.obj, push.fromQ, push.fromR, push.toQ, push.toR)
    end

    local function applyDamage()
        for _, coll in ipairs(collisions) do
            if coll.obj1.health then coll.obj1.health = coll.obj1.health - 1 end
            if coll.obj2.health then coll.obj2.health = coll.obj2.health - 1 end
            print(string.format("💥 %s collides with %s!", coll.obj1.name, coll.obj2.name))
            if sounds and sounds.collision then sounds.collision:play() end
        end
        for _, dmg in ipairs(damageEvents) do
            if dmg.obj.health then dmg.obj.health = dmg.obj.health - 1 end
            print(string.format("💨 %s is blown off the map!", dmg.obj.name))
            if sounds and sounds.collision then sounds.collision:play() end
        end
        for i = #entities, 1, -1 do
            if entities[i].health <= 0 then
                print(string.format("💀 %s has been defeated!", entities[i].name))
                table.remove(entities, i)
            end
        end
        self.hasBeenUsed = true
        if sounds and sounds.wind then sounds.wind:play() end
        if onComplete then onComplete(true, nil) end
    end

    combat.startPushAnimations(hex, applyDamage)
    return true
end

-- ============================================================
-- АНИМАЦИОННАЯ ОЧЕРЕДЬ (без изменений, но оставляем)
-- ============================================================
pushAnimations = { queue = {}, active = false }

function combat.addPushAnimation(obj, fromQ, fromR, toQ, toR, onComplete)
    if not obj then return end
    if obj.isMoving then
        obj.isMoving = false
        obj.path = {}
        obj.currentPathIndex = 0
    end
    table.insert(pushAnimations.queue, {
        obj = obj, fromQ = fromQ, fromR = fromR, toQ = toQ, toR = toR,
        startX = 0, startY = 0, endX = 0, endY = 0, timer = 0, duration = 0.2,
        isMoving = false, onComplete = onComplete or function() end
    })
end

function combat.startPushAnimations(hex, callback)
    if #pushAnimations.queue == 0 then if callback then callback() end; return end
    pushAnimations.active = true
    pushAnimations.globalCallback = callback
    combat.initNextPushAnimation(hex)
end

function combat.initNextPushAnimation(hex)
    if #pushAnimations.queue == 0 then
        pushAnimations.active = false
        if pushAnimations.globalCallback then
            pushAnimations.globalCallback()
            pushAnimations.globalCallback = nil
        end
        return
    end
    local anim = pushAnimations.queue[1]
    if not anim.isMoving then
        anim.startX, anim.startY = hex:hexToPixel(anim.fromQ, anim.fromR)
        anim.endX, anim.endY = hex:hexToPixel(anim.toQ, anim.toR)
        anim.timer = 0
        anim.isMoving = true
        if anim.obj then
            anim.obj.q = anim.toQ
            anim.obj.r = anim.toR
        end
    end
end

function combat.updatePushAnimations(dt, hex)
    if not pushAnimations.active or #pushAnimations.queue == 0 then return end
    local anim = pushAnimations.queue[1]
    if anim and anim.isMoving then
        anim.timer = anim.timer + dt
        if anim.timer >= anim.duration then
            if anim.onComplete then anim.onComplete(anim.obj) end
            table.remove(pushAnimations.queue, 1)
            combat.initNextPushAnimation(hex)
        end
    end
end

function combat.flushPushAnimations()
    for _, anim in ipairs(pushAnimations.queue) do
        if anim.obj then
            anim.obj.q = anim.toQ
            anim.obj.r = anim.toR
        end
    end
    pushAnimations.queue = {}
    pushAnimations.active = false
end

return combat