-- combat.lua
-- Система боя с кубическими координатами (pointy-top, odd-r)
local combat = {}
status = require("status")
local Entity = require("entity")

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

-- Отталкивание в направлении (с анимацией)
function combat.Attack:pushTargetInDirection(target, fromQ, fromR, stepX, stepY, stepZ, hex, entities, sounds, onComplete)
    local pushQ, pushR = applyCubeStep(fromQ, fromR, stepX, stepY, stepZ)
    self:pushTargetToHex(target, fromQ, fromR, pushQ, pushR, hex, entities, sounds, onComplete)
end

function combat.Attack:pushTargetToHex(target, fromQ, fromR, toQ, toR, hex, entities, sounds, onComplete)
    -- 🚫 Неподвижные объекты (здания, препятствия) не отталкиваются
    if target.isPushable == false then
        if onComplete then onComplete(false) end
        return
    end

    local wasDestroyed = false
    local function finishPush() if onComplete then onComplete(wasDestroyed) end end

    -- ИЗМЕНЕНО: проверяем не isValidHex, а isActiveHex
    if not hex:isActiveHex(toQ, toR) then
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
-- ТИПЫ АТАК (с поддержкой предпросмотра отталкивания)
-- ============================================================

-- 1. РЫВОК (Dash)
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
-- Предпросмотр: возвращает клетку, куда будет оттолкнут первый враг
function combat.DashAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        local pushQ, pushR = applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
        if hex:isValidHex(pushQ, pushR) then
            return {q = pushQ, r = pushR}
        else
            return {q = pushQ, r = pushR, edge = true} -- за край
        end
    end
    return nil
end

-- 2. ПЕРЕВОРОТ (Flip) – без урона, но с перемещением
combat.FlipAttack = setmetatable({}, combat.Attack)
combat.FlipAttack.__index = combat.FlipAttack
function combat.FlipAttack.new()
    local self = combat.Attack.new("Flip", "Flip the target behind the attacker", 1, 0, {})
    return setmetatable(self, combat.FlipAttack)
end
function combat.FlipAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end
    local targetActor = combat.getEntityAtHex(targetQ, targetR, entities)
    if not targetActor then return false, "No enemy at that hex!" end
    local aX, aY, aZ = axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    local behindX, behindY, behindZ = aX + dirX, aY + dirY, aZ + dirZ
    local behindQ, behindR = cubeToAxial(behindX, behindY, behindZ)
    if not hex:isValidHex(behindQ, behindR) then return false, "No free space behind the attacker!" end
    if combat.getEntityAtHex(behindQ, behindR, entities) then return false, "No free space behind the attacker!" end
    targetActor.q = behindQ
    targetActor.r = behindR
    print(string.format("%s flips %s behind them!", attacker.name, targetActor.name))
    if sounds and sounds.attack then sounds.attack:play() end
    attacker.hasActedThisTurn = true
    return true
end
-- Предпросмотр переворота: куда переместится цель
function combat.FlipAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) ~= 1 then return nil end
    local aX, aY, aZ = axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    local behindX, behindY, behindZ = aX + dirX, aY + dirY, aZ + dirZ
    local behindQ, behindR = cubeToAxial(behindX, behindY, behindZ)
    if hex:isValidHex(behindQ, behindR) then
        return {q = behindQ, r = behindR}
    end
    return nil
end

-- 3. ВЫСТРЕЛ (Shoot)
combat.ShootAttack = setmetatable({}, combat.Attack)
combat.ShootAttack.__index = combat.ShootAttack
function combat.ShootAttack.new(range)
    local self = combat.Attack.new("Shoot", "Fire a projectile, pushing the first target", range or 5, 1, {})
    return setmetatable(self, combat.ShootAttack)
end
function combat.ShootAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then return false, "No target in that direction!" end
    local distance = hex:getDistance(attacker.q, attacker.r, targetHex.q, targetHex.r)
    if distance > self.range then return false, "Target out of range!" end
    self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    attacker.hasActedThisTurn = true
    return true
end
function combat.ShootAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        local pushQ, pushR = applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
        if hex:isValidHex(pushQ, pushR) then
            return {q = pushQ, r = pushR}
        else
            return {q = pushQ, r = pushR, edge = true}
        end
    end
    return nil
end

-- 4. ПРОНЗАЮЩИЙ ВЫСТРЕЛ (Piercing Shoot)
combat.PiercingShootAttack = setmetatable({}, combat.Attack)
combat.PiercingShootAttack.__index = combat.PiercingShootAttack
function combat.PiercingShootAttack.new(range)
    local self = combat.Attack.new("Piercing Shot", "Shoot through the first target (0 dmg, pushes) to hit the second (1 dmg, pushes)", range or 5, 0, {})
    return setmetatable(self, combat.PiercingShootAttack)
end
function combat.PiercingShootAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local firstTarget, firstHex, secondTarget, secondHex = self:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then return false, "No target in that direction!" end
    if secondTarget then
        self:dealDamageToTarget(secondTarget, attacker, 1, entities, sounds)
        self:pushTargetInDirection(secondTarget, secondHex.q, secondHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    end
    self:pushTargetInDirection(firstTarget, firstHex.q, firstHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    attacker.hasActedThisTurn = true
    return true
end
-- Предпросмотр: возвращает список клеток отталкивания для двух целей
function combat.PiercingShootAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return {} end
    local firstTarget, firstHex, secondTarget, secondHex = self:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    local cells = {}
    if firstTarget and firstHex then
        local pushQ, pushR = applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
        table.insert(cells, {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)})
    end
    if secondTarget and secondHex then
        local pushQ, pushR = applyCubeStep(secondHex.q, secondHex.r, stepX, stepY, stepZ)
        table.insert(cells, {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)})
    end
    return cells
end

-- 5. АТАКА КАМНЕМ (Stone Throw) – создаёт препятствие и отбрасывает врагов вокруг
combat.AoePushAttack = setmetatable({}, combat.Attack)
combat.AoePushAttack.__index = combat.AoePushAttack

function combat.AoePushAttack.new()
    local self = combat.Attack.new("Stone Throw", "Throw a stone that pushes all enemies around it", 1, 0, {})
    return setmetatable(self, combat.AoePushAttack)
end

function combat.AoePushAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range!"
    end

    -- Проверяем, занята ли целевая клетка
    local centerEntity = combat.getEntityAtHex(targetQ, targetR, entities)
    if not centerEntity then
        -- Создаём камень (препятствие с 1 HP)
        local stone = Entity.new("Stone", Entity.TYPES.OBSTACLE, targetQ, targetR, 1, false, 0, nil, nil, {})
        stone.isPushable = false  -- камень не двигается от отталкиваний
        stone.color = {0.5, 0.5, 0.5, 1}  -- серый цвет (спрайт будет нарисован как круг)
        table.insert(entities, stone)
        print("[Stone] A stone appears at (" .. targetQ .. "," .. targetR .. ")")
    else
        print("[Stone] Center cell occupied, stone not placed, but push still occurs")
    end

    -- Отбрасываем всех врагов (противников) вокруг целевой клетки
    local neighbors = hex:getNeighbors(targetQ, targetR)
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
            -- Отбрасываем только живых врагов (не союзников)
            if target and target:isCharacter() and not target.isPlayable and target.health > 0 then
                -- Направление от центра к соседу в кубических координатах
                local cX, cY, cZ = axialToCube(targetQ, targetR)
                local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
                local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dirX, dirY, dirZ)
                self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, entities, sounds)
            end
        end
    end

    attacker.hasActedThisTurn = true
    return true
end

-- Предпросмотр: показывает, куда будут отброшены враги
function combat.AoePushAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local cells = {}
    local neighbors = hex:getNeighbors(targetQ, targetR)
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
            if target and target:isCharacter() and not target.isPlayable then
                local cX, cY, cZ = axialToCube(targetQ, targetR)
                local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
                local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dirX, dirY, dirZ)
                local isValid = hex:isValidHex(pushQ, pushR)
                table.insert(cells, {q = pushQ, r = pushR, edge = not isValid})
            end
        end
    end
    return cells
end

-- 6. AoE ТРИ ЦЕЛИ В НАПРАВЛЕНИИ (Cone Blast)
combat.AoeDirectionalAttack = setmetatable({}, combat.Attack)
combat.AoeDirectionalAttack.__index = combat.AoeDirectionalAttack
function combat.AoeDirectionalAttack.new()
    local self = combat.Attack.new("Cone Blast", "Deals 1 damage to the center and pushes 3 adjacent targets in a chosen direction", 1, 1, {})
    return setmetatable(self, combat.AoeDirectionalAttack)
end
function combat.AoeDirectionalAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then return false, "Target out of range!" end
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
    return true
end
function combat.AoeDirectionalAttack:getNeighborsInDirection(centerQ, centerR, dirQ, dirR, hex)
    local neighbors = hex:getNeighbors(centerQ, centerR)
    local dirVec = {q = dirQ, r = dirR}
    local function dot(a, b) return a.q * b.q + a.r * b.r end
    table.sort(neighbors, function(a, b)
        return dot(a, dirVec) > dot(b, dirVec)
    end)
    local top = {}
    for i = 1, math.min(3, #neighbors) do
        table.insert(top, neighbors[i])
    end
    return top
end
-- Предпросмотр для Cone Blast
function combat.AoeDirectionalAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local cells = {}
    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighbors = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)
    for _, neighbor in ipairs(neighbors) do
        local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
        if target then
            local cX, cY, cZ = axialToCube(targetQ, targetR)
            local nX, nY, nZ = axialToCube(neighbor.q, neighbor.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = applyCubeStep(neighbor.q, neighbor.r, dX, dY, dZ)
            table.insert(cells, {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)})
        end
    end
    return cells
end

-- ============================================================
-- WIND TORRENT (глобальное заклинание, без изменений)
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
        E  = {dx = 1, dy = -1, dz = 0},
        NE = {dx = 1, dy = 0, dz = -1},
        NW = {dx = 0, dy = 1, dz = -1},
        W  = {dx = -1, dy = 1, dz = 0},
        SW = {dx = -1, dy = 0, dz = 1},
        SE = {dx = 0, dy = -1, dz = 1},
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

    local function isValid(q, r) return hex:isActiveHex(q, r) end

    -- Собираем только подвижные объекты (isPushable == true)
    local movableObjects = {}
    for _, entity in ipairs(entities) do
        if entity.isPushable then
            table.insert(movableObjects, entity)
        end
    end

    -- Построение карты неподвижных объектов для быстрой проверки
    local immovableMap = {}
    for _, entity in ipairs(entities) do
        if not entity.isPushable then
            local key = entity.q .. "," .. entity.r
            immovableMap[key] = entity
        end
    end

    local pushes = {}       -- успешные перемещения
    local damageEvents = {} -- урон от вылета за край или столкновения с неподвижным

    for _, obj in ipairs(movableObjects) do
        local newQ, newR = applyStep(obj.q, obj.r)
        if not isValid(newQ, newR) then
            -- Вылет за край
            table.insert(damageEvents, {obj = obj, reason = "edge"})
        else
            -- Проверяем, не занята ли клетка неподвижным объектом
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                -- Столкновение с неподвижным препятствием: только урон, без движения
                table.insert(damageEvents, {obj = obj, reason = "immovable"})
            else
                table.insert(pushes, {obj = obj, fromQ = obj.q, fromR = obj.r, toQ = newQ, toR = newR})
            end
        end
    end

    -- Разрешение коллизий между подвижными объектами (клетка может быть занята другим подвижным)
    local targetMap, finalPushes, collisions = {}, {}, {}
    for _, push in ipairs(pushes) do
        local key = push.toQ .. "," .. push.toR
        if not targetMap[key] then
            targetMap[key] = push
            table.insert(finalPushes, push)
        else
            local existing = targetMap[key]
            table.insert(collisions, {obj1 = existing.obj, obj2 = push.obj})
            -- Если один из объектов имеет больше здоровья, он вытесняет другого (опционально)
            if push.obj.maxHealth and existing.obj.maxHealth and push.obj.maxHealth > existing.obj.maxHealth then
                targetMap[key] = push
                for i, fp in ipairs(finalPushes) do
                    if fp.obj == existing.obj then finalPushes[i] = push; break end
                end
            end
        end
    end

    -- Запускаем анимации для успешных перемещений
    for _, push in ipairs(finalPushes) do
        combat.addPushAnimation(push.obj, push.fromQ, push.fromR, push.toQ, push.toR)
    end

    local function applyDamage()
        -- Урон от столкновений подвижных друг с другом
        for _, coll in ipairs(collisions) do
            if coll.obj1.health then coll.obj1.health = coll.obj1.health - 1 end
            if coll.obj2.health then coll.obj2.health = coll.obj2.health - 1 end
            print(string.format("💥 %s collides with %s!", coll.obj1.name, coll.obj2.name))
            if sounds and sounds.collision then sounds.collision:play() end
        end
        -- Урон от вылета за край или столкновения с неподвижным
        for _, dmg in ipairs(damageEvents) do
            if dmg.obj.health then
                dmg.obj.health = dmg.obj.health - 1
                if dmg.reason == "edge" then
                    print(string.format("💨 %s is blown off the map!", dmg.obj.name))
                else
                    print(string.format("💥 %s crashes into an obstacle!", dmg.obj.name))
                end
                if sounds and sounds.collision then sounds.collision:play() end
            end
        end
        -- Удаляем погибших
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
-- АНИМАЦИОННАЯ ОЧЕРЕДЬ
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

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (общие)
-- ============================================================
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
    local multiplier = status.getDamageMultiplier(target)
    local finalDamage = math.floor(damage * multiplier)
    local wasDestroyed = target:takeDamage(finalDamage)
    if sounds and sounds.attack then sounds.attack:play() end
    if wasDestroyed then combat.removeEntity(target, entities) end
    return wasDestroyed
end

return combat