-- combat.lua
-- Система боя с кубическими координатами (pointy-top, odd-r)
local combat = {}
local visual = require("visual_effects")
status = require("status")
local Entity = require("entity")

local hex_utils = require("hex_utils")
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
    local ax, ay, az = hex_utils.axialToCube(fromQ, fromR)
    local bx, by, bz = hex_utils.axialToCube(toQ, toR)
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
        curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
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
        curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
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
    local pushQ, pushR = hex_utils.applyCubeStep(fromQ, fromR, stepX, stepY, stepZ)
    self:pushTargetToHex(target, fromQ, fromR, pushQ, pushR, hex, entities, sounds, onComplete)
end

-- В классе Attack (замените существующую функцию)
function combat.Attack:pushTargetToHex(target, fromQ, fromR, toQ, toR, hex, entities, sounds, onComplete)
    if target.isPushable == false then
        if onComplete then onComplete(false) end
        return
    end

    -- Проверяем, свободна ли клетка назначения
    local occupant = combat.getEntityAtHex(toQ, toR, entities)
    if occupant and occupant ~= target then
        -- Столкновение: урон обоим, цель не перемещается
        if target.health then target.health = target.health - 1 end
        if occupant.health then occupant.health = occupant.health - 1 end
        print(string.format("💥 %s crashes into %s! Both take 1 damage!", target.name, occupant.name))
        if sounds and sounds.collision then sounds.collision:play() end
        if onComplete then onComplete(false) end
        return
    end

    local wasDestroyed = false
    local function finishPush()
        if onComplete then onComplete(not wasDestroyed) end
    end

    -- Вылет за край
    if not hex:isActiveHex(toQ, toR) then
        if target:isCharacter() then
            target.health = target.health - 1
            print(target.name .. " is slammed against the edge! Takes 1 damage!")
            if sounds and sounds.collision then sounds.collision:play() end
            if target.health <= 0 then
                combat.removeEntity(target, entities)
                wasDestroyed = true
            end
        end
        local effectX, effectY = hex:hexToPixel(fromQ, fromR)
        visual.addEffect(effectX, effectY, "slam")
        finishPush()
        return
    end

    -- Успешное перемещение
    combat.addPushAnimation(target, fromQ, fromR, toQ, toR, function()
        finishPush()
    end)
end

-- ============================================================
-- ТИПЫ АТАК (с поддержкой предпросмотра отталкивания)
-- ============================================================
-- Замените существующий класс DashAttack на этот
combat.DashAttack = setmetatable({}, combat.Attack)
combat.DashAttack.__index = combat.DashAttack

function combat.DashAttack.new()
    local self = combat.Attack.new("Dash", "Charge forward, stop before first entity", math.huge, 1, {})
    return setmetatable(self, combat.DashAttack)
end

-- Возвращает первую цель, её клетку и последнюю свободную клетку перед целью
function combat.DashAttack:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)
    local curQ, curR = attacker.q, attacker.r
    local lastFreeQ, lastFreeR = curQ, curR
    local firstTarget = nil
    local targetHex = nil

    while true do
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isActiveHex(nextQ, nextR) then
            -- Достигли края, последняя свободная клетка – текущая
            break
        end

        local occupant = combat.getEntityAtHex(nextQ, nextR, entities)
        if occupant and occupant ~= attacker then
            firstTarget = occupant
            targetHex = {q = nextQ, r = nextR}
            -- lastFree уже установлена как curQ,curR (клетка перед целью)
            break
        end

        -- Клетка свободна, обновляем последнюю свободную
        lastFreeQ, lastFreeR = nextQ, nextR
        curQ, curR = nextQ, nextR
    end

    local lastFree = nil
    if not (lastFreeQ == attacker.q and lastFreeR == attacker.r) then
        lastFree = {q = lastFreeQ, r = lastFreeR}
    end

    return firstTarget, targetHex, lastFree
end

function combat.DashAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    local firstTarget, targetHex, lastFree = self:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)

    -- 🏃‍♂️ Перемещение атакующего в последнюю свободную клетку
    if lastFree and (lastFree.q ~= attacker.q or lastFree.r ~= attacker.r) then
        combat.addPushAnimation(attacker, attacker.q, attacker.r, lastFree.q, lastFree.r)
    end

    -- Наносим урон первой цели, если она есть
    if firstTarget then
        self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds)
    end

    -- Отталкивание цели (как было)
    if firstTarget and targetHex then
        local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
        local occupant = combat.getEntityAtHex(pushQ, pushR, entities)
        local isEdge = not hex:isActiveHex(pushQ, pushR)
        if isEdge or occupant then
            -- урон от столкновения
            if firstTarget.health > 0 then
                firstTarget.health = firstTarget.health - 1
                print(firstTarget.name .. " takes 1 collision damage!")
                if sounds and sounds.collision then sounds.collision:play() end
            end
            if occupant and occupant.health > 0 then
                occupant.health = occupant.health - 1
                print(occupant.name .. " takes 1 collision damage!")
                if sounds and sounds.collision then sounds.collision:play() end
            end
            if firstTarget.health <= 0 then combat.removeEntity(firstTarget, entities) end
            if occupant and occupant.health <= 0 then combat.removeEntity(occupant, entities) end
            local effectX, effectY = hex:hexToPixel(targetHex.q, targetHex.r)
            visual.addEffect(effectX, effectY, "slam")
        else
            self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, entities, sounds)
        end
    end

    combat.startPushAnimations(hex)
    return true
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
    local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = hex_utils.axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    local behindX, behindY, behindZ = aX + dirX, aY + dirY, aZ + dirZ
    local behindQ, behindR = hex_utils.cubeToAxial(behindX, behindY, behindZ)
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
    local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = hex_utils.axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    local behindX, behindY, behindZ = aX + dirX, aY + dirY, aZ + dirZ
    local behindQ, behindR = hex_utils.cubeToAxial(behindX, behindY, behindZ)
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
    combat.startPushAnimations(hex)   -- <-- добавить
    attacker.hasActedThisTurn = true
    return true
end
function combat.ShootAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
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
        combat.startPushAnimations(hex)   -- <-- добавить
    end
    self:pushTargetInDirection(firstTarget, firstHex.q, firstHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    combat.startPushAnimations(hex)   -- <-- добавить
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
        local pushQ, pushR = hex_utils.applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
        table.insert(cells, {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)})
    end
    if secondTarget and secondHex then
        local pushQ, pushR = hex_utils.applyCubeStep(secondHex.q, secondHex.r, stepX, stepY, stepZ)
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
        stone.isPushable = true  -- камень не двигается от отталкиваний
        stone.color = {0.5, 0.5, 0.5, 1}
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
                local nX, nY, nZ = hex_utils.axialToCube(neighbor.q, neighbor.r)
                local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = hex_utils.applyCubeStep(neighbor.q, neighbor.r, dirX, dirY, dirZ)
                self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, entities, sounds)
            end
        end
    end
    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end

-- Предпросмотр: возвращает таблицу с pushCell и направлением для каждого врага
function combat.AoePushAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local cells = {}
    local neighbors = hex:getNeighbors(targetQ, targetR)
    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
            if target and target:isCharacter() and not target.isPlayable and target.health > 0 then
                local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
                local nX, nY, nZ = hex_utils.axialToCube(neighbor.q, neighbor.r)
                local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = hex_utils.applyCubeStep(neighbor.q, neighbor.r, dirX, dirY, dirZ)
                local isValid = hex:isValidHex(pushQ, pushR)
                table.insert(cells, {
                    target = target,
                    fromCell = {q = neighbor.q, r = neighbor.r},
                    pushTo = {q = pushQ, r = pushR, edge = not isValid},
                    direction = {dx = dirX, dy = dirY, dz = dirZ}
                })
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
            local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
            local nX, nY, nZ = hex_utils.axialToCube(neighbor.q, neighbor.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(neighbor.q, neighbor.r, dX, dY, dZ)
            self:pushTargetToHex(target, neighbor.q, neighbor.r, pushQ, pushR, hex, entities, sounds)
        end
    end
    combat.startPushAnimations(hex)   -- <-- добавить
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
        if target and target:isCharacter() and not target.isPlayable then
            local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
            local nX, nY, nZ = hex_utils.axialToCube(neighbor.q, neighbor.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(neighbor.q, neighbor.r, dX, dY, dZ)
            table.insert(cells, {
                target = target,
                fromCell = {q = neighbor.q, r = neighbor.r},
                pushTo = {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)}
            })
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
        local x, y, z = hex_utils.axialToCube(q, r)
        return hex_utils.cubeToAxial(x + step.dx, y + step.dy, z + step.dz)
    end
    local function isValid(q, r) return hex:isActiveHex(q, r) end

    -- Собираем только подвижные объекты
    local movableObjects = {}
    for _, entity in ipairs(entities) do
        if entity.isPushable then
            table.insert(movableObjects, entity)
        end
    end

    -- Сортировка: сначала те, кто дальше по направлению ветра (максимальная проекция)
    table.sort(movableObjects, function(a, b)
        local function getProjection(obj)
            local x, y, z = hex_utils.axialToCube(obj.q, obj.r)
            return x * step.dx + y * step.dy + z * step.dz
        end
        return getProjection(a) > getProjection(b)
    end)

    -- Карта неподвижных объектов
    local immovableMap = {}
    for _, entity in ipairs(entities) do
        if not entity.isPushable then
            local key = entity.q .. "," .. entity.r
            immovableMap[key] = entity
        end
    end

    -- Результаты
    local pushes = {}       -- успешные перемещения
    local damageEvents = {} -- урон без перемещения (с указанием причины и дополнительной цели)

    -- Карта занятости клеток после обработки (чтобы избежать наложений)
    local occupied = {}     -- key "q,r" -> объект, который займёт клетку

    -- Обрабатываем объекты в порядке сортировки
    for _, obj in ipairs(movableObjects) do
        local fromKey = obj.q .. "," .. obj.r
        -- Если клетка, на которой стоит obj, уже занята кем-то другим (не им) – такого быть не должно, но на всякий случай
        if occupied[fromKey] and occupied[fromKey] ~= obj then
            -- Конфликт: кто-то уже занял его позицию – obj получает урон и не двигается
            table.insert(damageEvents, {obj = obj, reason = "collision", with = occupied[fromKey]})
            -- Помечаем его клетку как занятую им же (он остаётся)
            occupied[fromKey] = obj
            goto continue
        end

        local newQ, newR = applyStep(obj.q, obj.r)
        if not isValid(newQ, newR) then
            -- Вылет за край
            table.insert(damageEvents, {obj = obj, reason = "edge"})
            occupied[fromKey] = obj   -- он остаётся на месте
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                -- Столкновение с неподвижным препятствием
                table.insert(damageEvents, {obj = obj, reason = "immovable", obstacle = immovableMap[immovableKey]})
                occupied[fromKey] = obj
            else
                -- Проверяем, не занята ли целевая клетка уже кем-то (кто уже обработан и останется/переместится)
                local targetOcc = occupied[newQ .. "," .. newR]
                if targetOcc then
                    -- Столкновение с другим подвижным объектом (уже обработанным)
                    table.insert(damageEvents, {obj = obj, reason = "collision", with = targetOcc})
                    -- Добавляем урон и для targetOcc (он уже получит урон при своей обработке? Если он уже переместился, то у него не было столкновения. Нужно добавить урон и ему)
                    -- Найдём, не было ли уже damageEvents для targetOcc
                    local found = false
                    for _, de in ipairs(damageEvents) do
                        if de.obj == targetOcc then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(damageEvents, {obj = targetOcc, reason = "collision", with = obj})
                    end
                    occupied[fromKey] = obj   -- obj остаётся на месте
                else
                    -- Всё свободно – перемещаем
                    table.insert(pushes, {obj = obj, fromQ = obj.q, fromR = obj.r, toQ = newQ, toR = newR})
                    occupied[newQ .. "," .. newR] = obj
                    -- Если obj перемещается, его исходная клетка освобождается, поэтому не помечаем occupied[fromKey]
                end
            end
        end
        ::continue::
    end

    -- Применяем урон от damageEvents (без анимации перемещения)
    for _, dmg in ipairs(damageEvents) do
        if dmg.obj.health then
            dmg.obj.health = dmg.obj.health - 1
            if dmg.reason == "edge" then
                print(string.format("💨 %s is blown off the map!", dmg.obj.name))
            elseif dmg.reason == "immovable" then
                print(string.format("💥 %s crashes into an obstacle!", dmg.obj.name))
            elseif dmg.reason == "collision" and dmg.with then
                print(string.format("💥 %s collides with %s!", dmg.obj.name, dmg.with.name))
                -- Второй объект уже получил урон при своей обработке, но если его нет в damageEvents, добавим?
                -- Уже добавили выше, повторно не надо
            end
            if sounds and sounds.collision then sounds.collision:play() end
        end
    end

    -- Удаляем погибших после всех уронов
    for i = #entities, 1, -1 do
        if entities[i].health <= 0 then
            print(string.format("💀 %s has been defeated!", entities[i].name))
            table.remove(entities, i)
        end
    end

    -- Запускаем анимации для успешных перемещений
    for _, push in ipairs(pushes) do
        combat.addPushAnimation(push.obj, push.fromQ, push.fromR, push.toQ, push.toR)
    end

    -- Запускаем очередь анимаций
    combat.startPushAnimations(hex, function()
        self.hasBeenUsed = true
        if sounds and sounds.wind then sounds.wind:play() end
        if onComplete then onComplete(true, nil) end
    end)
    return true
end

-- ============================================================
-- АНИМАЦИОННАЯ ОЧЕРЕДЬ
-- ============================================================
pushAnimations = { queue = {}, active = false }

function combat.addPushAnimation(obj, fromQ, fromR, toQ, toR, onComplete)
    -- Добавляем эффект в точке старта
    local x, y = hex:hexToPixel(fromQ, fromR)
    visual.addEffect(x, y, "hit", 0.3)

    table.insert(pushAnimations.queue, {
        obj = obj, fromQ = fromQ, fromR = fromR, toQ = toQ, toR = toR,
        startX = 0, startY = 0, endX = 0, endY = 0, timer = 0, duration = 0.2,
        isMoving = false,
        onComplete = function(pushedObj)
            -- Проверяем, свободна ли целевая клетка
            local occupant = combat.getEntityAtHex(toQ, toR, entities)
            if occupant and occupant ~= pushedObj and occupant.health > 0 then
                -- Столкновение: урон обоим, перемещение отменяется
                if pushedObj.health and pushedObj.health > 0 then
                    pushedObj.health = pushedObj.health - 1
                    print(string.format("💥 %s collides with %s! Both take 1 damage!", pushedObj.name, occupant.name))
                    if sounds and sounds.collision then sounds.collision:play() end
                end
                if occupant.health then
                    occupant.health = occupant.health - 1
                    if occupant.health <= 0 then
                        combat.removeEntity(occupant, entities)
                    end
                end
                if pushedObj.health <= 0 then
                    combat.removeEntity(pushedObj, entities)
                end
                -- Не перемещаем объект, остаётся на месте
                if pushedObj.health <= 0 then
                    -- Если умер, эффекты клетки не применяем
                else
                    -- Применяем эффекты клетки (огонь, вода) на исходной позиции
                    if terrainMap then
                        effects.applyAllCellEffects(pushedObj, fromQ, fromR, terrainMap, entities, globalHealth)
                    end
                end
            else
                -- Клетка свободна – выполняем перемещение
                pushedObj.q = toQ
                pushedObj.r = toR
                -- Применяем эффекты клетки после перемещения
                if pushedObj and terrainMap then
                    local died = effects.applyAllCellEffects(pushedObj, toQ, toR, terrainMap, entities, globalHealth)
                    if died then
                        combat.removeEntity(pushedObj, entities)
                    end
                end
            end
            if onComplete then onComplete(pushedObj) end
        end
    })
end

function combat.startPushAnimations(hex, callback)
    if #pushAnimations.queue == 0 then if callback then callback() end; return end
    pushAnimations.active = true
    pushAnimations.globalCallback = function()
        if callback then callback() end
        -- Здесь применить эффекты ко всем объектам, участвовавшим в анимациях
        for _, anim in ipairs(pushAnimations.queue) do
            if anim.obj then
                -- но очередь уже очищена? Лучше сохранять список перемещённых объектов
            end
        end
    end
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
        if not anim.isShake then
            anim.startX, anim.startY = hex:hexToPixel(anim.fromQ, anim.fromR)
            anim.endX, anim.endY = hex:hexToPixel(anim.toQ, anim.toR)
        end
        anim.timer = 0
        anim.isMoving = true
    end
end

function combat.updatePushAnimations(dt, hex)
    if not pushAnimations.active or #pushAnimations.queue == 0 then return end
    local anim = pushAnimations.queue[1]
    if anim and anim.isMoving then
        anim.timer = anim.timer + dt
        local t = math.min(1, anim.timer / anim.duration)
        local ease = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2

        if anim.isShake then
            local x, y = hex:hexToPixel(anim.obj.q, anim.obj.r)
            anim.obj.currentDrawX = x + anim.offsetX * (1 - ease)
            anim.obj.currentDrawY = y + anim.offsetY * (1 - ease)
        else
            local x = anim.startX + (anim.endX - anim.startX) * ease
            local y = anim.startY + (anim.endY - anim.startY) * ease
            anim.obj.currentDrawX = x
            anim.obj.currentDrawY = y
        end

        if t >= 1 then
            if anim.isShake then
                anim.obj.currentDrawX = nil
                anim.obj.currentDrawY = nil
            elseif anim.bounceBack then
                if not anim.returnPhase then
                    anim.returnPhase = true
                    anim.startX, anim.startY = anim.endX, anim.endY
                    anim.endX, anim.endY = hex:hexToPixel(anim.fromQ, anim.fromR)
                    anim.timer = 0
                    return
                else
                    anim.obj.q = anim.fromQ
                    anim.obj.r = anim.fromR
                    anim.obj.currentDrawX = nil
                    anim.obj.currentDrawY = nil
                end
            else
                anim.obj.q = anim.toQ
                anim.obj.r = anim.toR
                anim.obj.currentDrawX = nil
                anim.obj.currentDrawY = nil
            end
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

-- combat.lua (заменить существующий метод)
function combat.Attack:dealDamageToTarget(target, attacker, damage, entities, sounds, directionIndex)
    -- Базовый множитель = 1.0
    local multiplier = 1.0

    if target.armor and directionIndex and target.armor[directionIndex+1] then
        multiplier = multiplier * target.armor[directionIndex+1]
    end

    -- Уязвимая точка (если совпадает с направлением атаки)
    if target.weakPoint ~= nil and directionIndex == target.weakPoint then
        multiplier = multiplier * 2.0   -- двойной урон по уязвимой точке
        print(string.format("💥 Critical hit! %s hits %s's weak point!", attacker.name, target.name))
    end

    -- Учитываем эффект кислоты и других статусов (уже есть status.getDamageMultiplier)
    local statusMultiplier = status.getDamageMultiplier(target)
    multiplier = multiplier * statusMultiplier

    local finalDamage = math.floor(damage * multiplier)
    if finalDamage < 1 and damage > 0 then finalDamage = 1 end   -- хотя бы 1 урон

    local wasDestroyed = target:takeDamage(finalDamage)
    if sounds and sounds.attack then sounds.attack:play() end

    -- Визуальный эффект удара
    if hex and visual then
        local x, y = hex:hexToPixel(target.q, target.r)
        visual.addEffect(x, y, "hit", 0.4)
    end

    if wasDestroyed then combat.removeEntity(target, entities) end
    return wasDestroyed
end

function combat.addBounceAnimation(obj, fromQ, fromR, toQ, toR, duration)
    table.insert(pushAnimations.queue, {
        obj = obj,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        bounceBack = true,
        startX = 0, startY = 0,
        endX = 0, endY = 0,
        timer = 0,
        duration = duration or 0.2,
        isMoving = false,
        onComplete = function() end
    })
end

function combat.addShakeAnimation(obj, q, r)
    local offsetX = (math.random() - 0.5) * 10
    local offsetY = (math.random() - 0.5) * 10
    table.insert(pushAnimations.queue, {
        obj = obj,
        isShake = true,
        offsetX = offsetX,
        offsetY = offsetY,
        timer = 0,
        duration = 0.1,
        startX = 0, startY = 0,
        onComplete = function() end
    })
end

return combat