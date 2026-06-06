-- combat.lua
-- Система боя с кубическими координатами (pointy-top, odd-r)
local combat = {}
local visual = require("visual_effects")
status = require("status")
local Entity = require("entity")
local attack_effects = require("attack_effects")

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

function combat.Attack:pushTargetToHex(target, fromQ, fromR, toQ, toR, hex, entities, sounds, onComplete)
    if target.isPushable == false then
        if onComplete then onComplete(false) end
        return
    end

    -- Проверяем занятость клетки
    local occupant = combat.getEntityAtHex(toQ, toR, entities)
    if occupant and occupant ~= target then
        -- Столкновение → bounce + урон
        combat.addCollisionBounceAnimation(target, fromQ, fromR, toQ, toR, hex, entities, sounds, globalHealth, occupant)
        if onComplete then onComplete(false) end
        return
    end

    -- Вылет за край
    if not hex:isActiveHex(toQ, toR) then
        if target:isCharacter() then
            target.health = target.health - 1
            print(target.name .. " is slammed against the edge! Takes 1 damage!")
            if sounds and sounds.collision then sounds.collision:play() end
            if target.health <= 0 then
                target.startDeath()
            end
        end
        local effectX, effectY = getDrawCoords(fromQ, fromR)
        visual.addEffect(effectX, effectY, "slam")
        if onComplete then onComplete(false) end
        return
    end

    -- Успешное перемещение (без столкновения)
    combat.addPushAnimation(target, fromQ, fromR, toQ, toR, function()
        if onComplete then onComplete(true) end
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

    attack_effects.dash(attacker, firstTarget, lastFree, hex)
    --  Перемещение атакующего в последнюю свободную клетку
    if lastFree and (lastFree.q ~= attacker.q or lastFree.r ~= attacker.r) then
        combat.addPushAnimation(attacker, attacker.q, attacker.r, lastFree.q, lastFree.r)
    end

    -- Наносим урон первой цели, если она есть
    if firstTarget then
        self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds, nil, globalHealth)
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
            if firstTarget.health <= 0 then firstTarget:startDeath() end
            if occupant and occupant.health <= 0 then occupant:startDeath() end
            local effectX, effectY = getDrawCoords(targetHex.q, targetHex.r)
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
    -- ДОБАВЛЕНО: цель должна быть вражеским персонажем (не зданием и не препятствием)
    if not targetActor then return false, "No entity at that hex!" end
    if not targetActor:isCharacter() or targetActor.isPlayable then
        return false, "Target must be an enemy character!"
    end
    local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = hex_utils.axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    local behindX, behindY, behindZ = aX + dirX, aY + dirY, aZ + dirZ
    local behindQ, behindR = hex_utils.cubeToAxial(behindX, behindY, behindZ)
    -- Проверка, что клетка за атакующим существует, активна и не занята ничем
    if not hex:isActiveHex(behindQ, behindR) then
        return false, "No free space behind the attacker!"
    end
    if combat.getEntityAtHex(behindQ, behindR, entities) then
        return false, "Cell behind attacker is occupied!"
    end
    attack_effects.flip(attacker, targetActor, behindQ, behindR, hex)
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
    local targetActor = combat.getEntityAtHex(targetQ, targetR, entities)
    if not targetActor or not targetActor:isCharacter() or targetActor.isPlayable then
        return nil
    end
    local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = hex_utils.axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    local behindX, behindY, behindZ = aX + dirX, aY + dirY, aZ + dirZ
    local behindQ, behindR = hex_utils.cubeToAxial(behindX, behindY, behindZ)
    if not hex:isActiveHex(behindQ, behindR) then return nil end
    if combat.getEntityAtHex(behindQ, behindR, entities) then return nil end
    return {q = behindQ, r = behindR}
end

-- function combat.FlipAttack:getLineDirection(fromQ, fromR, toQ, toR, hex)
--     return nil
-- end

-- 3. ВЫСТРЕЛ (Shoot)
combat.ShootAttack = setmetatable({}, combat.Attack)
combat.ShootAttack.__index = combat.ShootAttack
function combat.ShootAttack.new(range)
    local self = combat.Attack.new("Shoot", "Fire a projectile, pushing the first target", range or 5, 1, {})
    return setmetatable(self, combat.ShootAttack)
end
-- в combat.lua, внутри ShootAttack:execute
function combat.ShootAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then return false, "No target in that direction!" end
    local distance = hex:getDistance(attacker.q, attacker.r, targetHex.q, targetHex.r)
    if distance > self.range then return false, "Target out of range!" end

    -- Вычисляем клетку отталкивания (если есть)
    local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
    local pushValid = hex:isActiveHex(pushQ, pushR)
    attack_effects.shoot(attacker, firstTarget, nil, nil, hex)
    self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds, nil, globalHealth)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    combat.startPushAnimations(hex)
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
    attack_effects.piercingShoot(attacker, firstTarget, secondTarget, stepX, stepY, stepZ, hex)
    if not firstTarget then return false, "No target in that direction!" end
    if secondTarget then
        self:dealDamageToTarget(secondTarget, attacker, 1, entities, sounds, nil, globalHealth)
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

-- ================== STONE THROW (AoePushAttack) ==================
combat.AoePushAttack = setmetatable({}, combat.Attack)
combat.AoePushAttack.__index = combat.AoePushAttack

function combat.AoePushAttack.new()
    local self = combat.Attack.new("Stone Throw", "Throw a stone that pushes three enemies in a cone", math.huge, 0, {})
    self.minRange = 2
    return setmetatable(self, combat.AoePushAttack)
end

-- Вспомогательная функция для получения трёх соседей в направлении
function combat.AoePushAttack:getNeighborsInDirection(centerQ, centerR, dirQ, dirR, hex)
    if centerQ == nil or centerR == nil then
        return {}
    end

    local neighbors = hex:getNeighbors(centerQ, centerR)
    local validNeighbors = {}
    for _, nb in ipairs(neighbors) do
        if nb and nb.q ~= nil and nb.r ~= nil then
            table.insert(validNeighbors, nb)
        end
    end

    if #validNeighbors == 0 then
        return {}
    end

    local dirVec = { q = dirQ or 0, r = dirR or 0 }

    local function dot(a, b)
        return (a.q or 0) * (b.q or 0) + (a.r or 0) * (b.r or 0)
    end

    table.sort(validNeighbors, function(a, b)
        return dot(a, dirVec) > dot(b, dirVec)
    end)

    local top = {}
    for i = 1, math.min(3, #validNeighbors) do
        table.insert(top, validNeighbors[i])
    end
    return top
end

function combat.AoePushAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then
        return false, "Target too close! (minimum 2)"
    end
    -- Проверка прямой линии
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    -- Создаём камень в целевой клетке (если свободно)
    local centerEntity = combat.getEntityAtHex(targetQ, targetR, entities)
    if centerEntity then
    -- Наносим урон цели вместо создания камня
    self:dealDamageToTarget(centerEntity, attacker, 1, entities, sounds, nil, globalHealth)
else
    -- Создаём камень (как было)
    local stone = Entity.new("Stone", Entity.TYPES.OBSTACLE, targetQ, targetR, 1, false, 0, nil, nil, {})
    stone.isPushable = true
    stone.color = {0.5,0.5,0.5,1}
    table.insert(entities, stone)
end
    if not centerEntity then
        local stone = Entity.new("Stone", Entity.TYPES.OBSTACLE, targetQ, targetR, 1, false, 0, nil, nil, {})
        stone.isPushable = true
        stone.color = {0.5, 0.5, 0.5, 1}
        table.insert(entities, stone)
        print("[Stone] A stone appears at (" .. targetQ .. "," .. targetR .. ")")
    else
        print("[Stone] Center cell occupied, stone not placed, but push still occurs")
    end

    -- Направление от атакующего к цели
    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighborsInDirection = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)

    local pushedTargets = {}
    for _, nb in ipairs(neighborsInDirection) do
        local target = combat.getEntityAtHex(nb.q, nb.r, entities)
        if target and target:isCharacter() and target.health > 0 then
            local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dirX, dirY, dirZ)
            table.insert(pushedTargets, {
                entity = target,
                fromCell = {q = nb.q, r = nb.r},
                pushTo = {q = pushQ, r = pushR}
            })
        end
    end

    attack_effects.stoneThrow(targetQ, targetR, pushedTargets, hex)

    for _, pd in ipairs(pushedTargets) do
        self:pushTargetToHex(pd.entity, pd.fromCell.q, pd.fromCell.r, pd.pushTo.q, pd.pushTo.r, hex, entities, sounds)
    end

    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end

-- Предпросмотр для Stone Throw
function combat.AoePushAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return {} end

    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return {} end

    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighbors = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)
    local cells = {}
    for _, nb in ipairs(neighbors) do
        local target = combat.getEntityAtHex(nb.q, nb.r, entities)
        if target and target:isCharacter() and target.health > 0 then
            local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dX, dY, dZ)
            table.insert(cells, {
                target = target,
                fromCell = {q = nb.q, r = nb.r},
                pushTo = {q = pushQ, r = pushR, edge = not hex:isActiveHex(pushQ, pushR)}
            })
        end
    end
    return cells
end


-- 6. AoE ТРИ ЦЕЛИ В НАПРАВЛЕНИИ (Cone Blast)
combat.AoeDirectionalAttack = setmetatable({}, combat.Attack)
combat.AoeDirectionalAttack.__index = combat.AoeDirectionalAttack
function combat.AoeDirectionalAttack.new()
    local self = combat.Attack.new("Cone Blast", "Deals 1 damage to the center and pushes all 6 surrounding enemies", math.huge, 1, {})
    self.minRange = 2
    return setmetatable(self, combat.AoeDirectionalAttack)
end

function combat.AoeDirectionalAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then
        return false, "Target too close! (minimum 2)"
    end

    if not hex:isActiveHex(targetQ, targetR) then
        return false, "Target cell is not active"
    end
    -- Обязательная прямая линия
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    -- Урон центру
    local centerTarget = combat.getEntityAtHex(targetQ, targetR, entities)
    if centerTarget and centerTarget:isCharacter() then
        self:dealDamageToTarget(centerTarget, attacker, self.damage, entities, sounds, nil, globalHealth)
    end

    attack_effects.coneBlast(targetQ, targetR, hex)

    -- Все 6 соседей
    local allNeighbors = hex:getNeighbors(targetQ, targetR)
    for _, nb in ipairs(allNeighbors) do
        if hex:isActiveHex(nb.q, nb.r) then
            local target = combat.getEntityAtHex(nb.q, nb.r, entities)
            if target and target:isCharacter() and target.health > 0 then
                local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
                local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
                local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
                local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dX, dY, dZ)
                self:pushTargetToHex(target, nb.q, nb.r, pushQ, pushR, hex, entities, sounds)
            end
        end
    end

    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end
function combat.AoeDirectionalAttack:getNeighborsInDirection(centerQ, centerR, dirQ, dirR, hex)
    -- Защита от некорректных аргументов
    if centerQ == nil or centerR == nil then
        return {}
    end

    local neighbors = hex:getNeighbors(centerQ, centerR)
    local validNeighbors = {}

    -- Отфильтровываем элементы с отсутствующими координатами
    for _, nb in ipairs(neighbors) do
        if nb and nb.q ~= nil and nb.r ~= nil then
            table.insert(validNeighbors, nb)
        end
    end

    if #validNeighbors == 0 then
        return {}
    end

    local dirVec = { q = dirQ or 0, r = dirR or 0 }

    local function dot(a, b)
        return (a.q or 0) * (b.q or 0) + (a.r or 0) * (b.r or 0)
    end

    table.sort(validNeighbors, function(a, b)
        return dot(a, dirVec) > dot(b, dirVec)
    end)

    local top = {}
    for i = 1, math.min(3, #validNeighbors) do
        table.insert(top, validNeighbors[i])
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
        -- Любой персонаж, а не только враг
        if target and target:isCharacter() then
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

-- 7. МАГИЧЕСКИЙ СНАРЯД LICH'а (игнорирует препятствия)
-- 7. МАГИЧЕСКИЙ СНАРЯД LICH'а (игнорирует препятствия, не требует прямой линии)
combat.LichBoltAttack = setmetatable({}, combat.Attack)
combat.LichBoltAttack.__index = combat.LichBoltAttack

function combat.LichBoltAttack.new(range)
    local self = combat.Attack.new("Magic Bolt", "Throw a bolt that hits any target in range, ignoring obstacles and line of sight", range or 5, 1, {})
    return setmetatable(self, combat.LichBoltAttack)
end

function combat.LichBoltAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then
        return false, "Target out of range"
    end

    -- Проверка прямой линии
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        return false, "Target not in a straight line!"
    end

    local target = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                target = e
                break
            end
        end
    end

    if not target then
        return false, "No valid target at that cell"
    end

    local damage = self.damage
    local wasDestroyed = target:takeDamage(damage, globalHealth)
    print(string.format(" %s throws a magic bolt at %s for %d damage!", attacker.name, target.name, damage))
    if sounds and sounds.attack then sounds.attack:play() end

    if hex and visual then
        local x, y = getDrawCoords(target.q, target.r)
        visual.addEffect(x, y, "hit", 0.4)
    end

    if wasDestroyed then target:startDeath() end

    attack_effects.magicBolt(attacker, target, hex)

    attacker.hasActedThisTurn = true
    return true
end

function combat.LichBoltAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) > self.range then
        return nil
    end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                return {q = targetQ, r = targetR}
            end
        end
    end
    return nil
end

-- 8. GHOST: магический снаряд с неограниченной дальностью, первая цель на линии, урон 2
combat.GhostBoltAttack = setmetatable({}, combat.Attack)
combat.GhostBoltAttack.__index = combat.GhostBoltAttack

function combat.GhostBoltAttack.new()
    local self = combat.Attack.new("Ghost Bolt", "Piercing shot with unlimited range, hits first target", math.huge, 2, {})
    return setmetatable(self, combat.GhostBoltAttack)
end

function combat.GhostBoltAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then return false, "No target in that direction!" end

    -- Наносим урон (не отталкиваем)
    self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds, nil, globalHealth)
    attacker.hasActedThisTurn = true

    attack_effects.ghostBolt(attacker, firstTarget, hex)
    return true
end

-- Для предпросмотра
function combat.GhostBoltAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        return targetHex
    end
    return nil
end

-- 9. ZOMBIE: удар в упор, урон 3
combat.ZombieBiteAttack = setmetatable({}, combat.Attack)
combat.ZombieBiteAttack.__index = combat.ZombieBiteAttack

function combat.ZombieBiteAttack.new()
    local self = combat.Attack.new("Bite", "Devastating bite at close range", 1, 3, {})
    return setmetatable(self, combat.ZombieBiteAttack)
end

function combat.ZombieBiteAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end

    local target = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            target = e
            break
        end
    end
    if not target then return false, "No target at that hex" end

    attack_effects.bite(attacker, target, hex)

    self:dealDamageToTarget(target, attacker, self.damage, entities, sounds, nil, globalHealth)
    attacker.hasActedThisTurn = true
    return true
end

function combat.ZombieBiteAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) == 1 then
        local target = nil
        for _, e in ipairs(entities) do
            if e.q == targetQ and e.r == targetR and e.health > 0 then
                target = e
                break
            end
        end
        if target then return {q = targetQ, r = targetR} end
    end
    return nil
end

-- ============================================================
-- WIND TORRENT (глобальное заклинание, без изменений)
-- ============================================================
combat.WindTorrentAttack = setmetatable({}, combat.Attack)
combat.WindTorrentAttack.__index = combat.WindTorrentAttack

function combat.WindTorrentAttack.new()
    local self = combat.Attack.new("Wind Torrent", "Global wind pushes everything one step", 999, 0, {})
    self.hasBeenUsed = false
    return setmetatable(self, combat.WindTorrentAttack)
end

function combat.WindTorrentAttack:executeGlobalWithAnimation(direction, hex, entities, sounds, terrainMap, globalHealth, onComplete)
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

    print(string.format(" WIND TORRENT: Pushing everything %s!", direction))

    local function applyStep(q, r)
        local x, y, z = hex_utils.axialToCube(q, r)
        return hex_utils.cubeToAxial(x + step.dx, y + step.dy, z + step.dz)
    end
    local function isValid(q, r) return hex:isActiveHex(q, r) end

    -- Собираем подвижные объекты
    local movableObjects = {}
    for _, entity in ipairs(entities) do
        if entity.isPushable then
            table.insert(movableObjects, entity)
        end
    end

    -- Сортировка по дальности вдоль направления (максимальная проекция)
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

    -- Карта занятости для предотвращения двойного перемещения
    local occupied = {}

    -- Список анимаций, которые будут добавлены
    local animationsAdded = false

    for _, obj in ipairs(movableObjects) do
        if obj.health <= 0 then goto continue end

        local fromKey = obj.q .. "," .. obj.r
        if occupied[fromKey] and occupied[fromKey] ~= obj then
            -- Конфликт: кто-то уже занял его позицию → bounce-анимация с ним
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, obj.q, obj.r, hex, entities, sounds, globalHealth, occupied[fromKey])
            occupied[fromKey] = obj
            goto continue
        end

        local newQ, newR = applyStep(obj.q, obj.r)
        if not isValid(newQ, newR) then
            -- Вылет за край: bounce-анимация до края и назад
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, globalHealth, nil)
            occupied[fromKey] = obj
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                -- Столкновение с неподвижным объектом
                combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, globalHealth, immovableMap[immovableKey])
                occupied[fromKey] = obj
            else
                local targetOcc = occupied[newQ .. "," .. newR]
                if targetOcc then
                    -- Столкновение с другим подвижным объектом
                    combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, globalHealth, targetOcc)
                    occupied[fromKey] = obj
                else
                    -- Всё свободно – обычное перемещение
                    combat.addPushAnimation(obj, obj.q, obj.r, newQ, newR)
                    occupied[newQ .. "," .. newR] = obj
                end
            end
        end
        ::continue::
    end

    -- Запускаем анимации
    combat.startPushAnimations(hex, function()
        self.hasBeenUsed = true
        if sounds and sounds.wind then sounds.wind:play() end
        if onComplete then onComplete(true, nil) end
        if _G.checkGameEnd then _G.checkGameEnd() end
    end)
    return true
end

-- ============================================================
-- АНИМАЦИОННАЯ ОЧЕРЕДЬ
-- ============================================================
pushAnimations = { queue = {}, active = false }

function combat.addPushAnimation(obj, fromQ, fromR, toQ, toR, onComplete)

    -- Добавляем эффект ветра от стартовой клетки к конечной
    local startX, startY = getDrawCoords(fromQ, fromR)
    local endX, endY = getDrawCoords(toQ, toR)
    visual.addPushEffect(startX, startY, endX, endY, 0.25)

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
                    print(string.format(" %s collides with %s! Both take 1 damage!", pushedObj.name, occupant.name))
                    if sounds and sounds.collision then sounds.collision:play() end
                end
                if occupant.health then
                    occupant.health = occupant.health - 1
                    if occupant.health <= 0 then
                        occupant:startDeath()
                    end
                end
                if pushedObj.health <= 0 then
                    pushedObj:startDeath()
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
                        pushedObj:startDeath()
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
            anim.startX, anim.startY = getDrawCoords(anim.fromQ, anim.fromR)
            anim.endX, anim.endY = getDrawCoords(anim.toQ, anim.toR)
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

        local ease
        if anim.bounceBack then
            -- Движение вперёд на 80% времени, затем возврат
            local forwardT = math.min(1, t * 1.25) -- 0..1 за 80% времени
            ease = forwardT
            if t > 0.8 then
                local backT = (t - 0.8) / 0.2
                ease = 1 - backT
            end
        else
            ease = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
        end

        if anim.isShake then
            local x, y = getDrawCoords(anim.obj.q, anim.obj.r)
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
                -- Возвращаем объект в исходную позицию
                anim.obj.q = anim.fromQ
                anim.obj.r = anim.fromR
                anim.obj.currentDrawX = nil
                anim.obj.currentDrawY = nil
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

-- combat.lua (заменить существующий метод)
function combat.Attack:dealDamageToTarget(target, attacker, damage, entities, sounds, directionIndex, globalHealth)
    -- Базовый множитель = 1.0
    local multiplier = 1.0

    if target.armor and directionIndex and target.armor[directionIndex+1] then
        multiplier = multiplier * target.armor[directionIndex+1]
    end

    -- Уязвимая точка
    if target.weakPoint ~= nil and directionIndex == target.weakPoint then
        multiplier = multiplier * 2.0
        print(string.format(" Critical hit! %s hits %s's weak point!", attacker.name, target.name))
    end

    local statusMultiplier = status.getDamageMultiplier(target)
    multiplier = multiplier * statusMultiplier

    local finalDamage = math.floor(damage * multiplier)
    if finalDamage < 1 and damage > 0 then finalDamage = 1 end

    local wasDestroyed = target:takeDamage(finalDamage, globalHealth)  -- ← передаём globalHealth
    if sounds and sounds.attack then sounds.attack:play() end

    if hex and visual then
        local x, y = getDrawCoords(target.q, target.r)
        visual.addEffect(x, y, "hit", 0.4)
    end

    if wasDestroyed then target:startDeath() end
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

function combat.addCollisionBounceAnimation(obj, fromQ, fromR, toQ, toR, hex, entities, sounds, globalHealth, withEntity)
    -- Эффект столкновения в целевой клетке (визуальный, без урона)
    local x, y = getDrawCoords(toQ, toR)
    visual.addEffect(x, y, "collision", 0.3)
    if sounds and sounds.collision then sounds.collision:play() end

    -- Отложенное нанесение урона после анимации
    local function applyDamage()
        local damage = 1
        if obj.health and obj.health > 0 then
            local wasDestroyed = obj:takeDamage(damage, globalHealth)
            if wasDestroyed then
                obj:startDeath()
            end
        end
        if withEntity and withEntity.health and withEntity.health > 0 then
            local wasDestroyed = withEntity:takeDamage(damage, globalHealth)
            if wasDestroyed then
                withEntity:startDeath()
            end
        end
    end

    -- Bounce-анимация (движение на 80% пути и обратно)
    local startX, startY = getDrawCoords(fromQ, fromR)
    local endX, endY = getDrawCoords(toQ, toR)
    table.insert(pushAnimations.queue, {
        obj = obj,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        bounceBack = true,
        startX = startX, startY = startY,
        endX = endX, endY = endY,
        timer = 0,
        duration = 0.2,
        isMoving = false,
        onComplete = function(pushedObj)
            -- Урон применяется только после завершения анимации
            applyDamage()
            if pushedObj.health <= 0 then
                pushedObj:startDeath()
            end
        end
    })
end

-- ============================================================
-- ДЕЙСТВИЯ ИГРОКА (move / attack / undo)
-- ============================================================

function performMove(actor, targetQ, targetR)
    if not actor.isPlayable then return false end
    if not hex:isActiveHex(targetQ, targetR) then
        print("Target cell is outside the playable hexagon")
        return false
    end
    if actor.isMoving or actor.hasActedThisTurn then return false end
    if actor.hasMovedThisTurn then
        print(actor.name .. " has already moved this turn!")
        return false
    end
    if actor.q == targetQ and actor.r == targetR then return false end
    local distance = hex:getDistance(actor.q, actor.r, targetQ, targetR)
    if distance > actor.moveRange then
        print("Too far")
        return false
    end
    if isCellOccupiedForStop(targetQ, targetR, actor) then
        print("Cell occupied")
        return false
    end
    local path = pathfinding.findPath(actor.q, actor.r, targetQ, targetR, actor.moveRange,
        function(q, r) return not isCellPassable(q, r, actor) end, hex)
    if not path or #path == 0 then
        print("No valid path")
        return false
    end
    addToHistory(actor, actor.q, actor.r, targetQ, targetR)
    actor.hasMovedThisTurn = true
    actor.path = path
    actor.currentPathIndex = 1
    startNextMove(actor)
    return true
end

function startNextMove(actor)
    if actor.currentPathIndex <= #actor.path then
        local step = actor.path[actor.currentPathIndex]
        actor.isMoving = true
        actor.timer = 0
        actor.targetQ = step.q
        actor.targetR = step.r
        actor.startX, actor.startY = getDrawCoords(actor.q, actor.r)
        actor.endX, actor.endY = getDrawCoords(actor.targetQ, actor.targetR)
    else
        actor.isMoving = false
        actor.path = {}
        actor.currentPathIndex = 0
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
            -- Применяем эффекты клетки на каждом шагу пути
            if terrainMap then
                local died = effects.applyAllCellEffects(actor, actor.q, actor.r, terrainMap, entities, globalHealth)
                if died then
                    local x, y = hex:hexToPixel(actor.q, actor.r)
                    visual.addEffect(x, y, "drown")
                    checkGameEnd()
                    return
                end
            end
            actor.isMoving = false
            actor.currentPathIndex = actor.currentPathIndex + 1
            if actor.currentPathIndex <= #actor.path then
                startNextMove(actor)
            else
                actor.path = {}
                actor.currentPathIndex = 0
                if selectedActor == actor then
                    hex.selectedQ = actor.q
                    hex.selectedR = actor.r
                end
            end
        end
    end
end

function performAttackWithSelectedAttack(attacker, targetQ, targetR, attack)
    print("[DEBUG] performAttackWithSelectedAttack called")
    print("  attacker:", attacker and attacker.name, "hasActed:", attacker and attacker.hasActedThisTurn)
    print("  targetQ,targetR:", targetQ, targetR)
    print("  attack:", attack and attack.name)

    if not attacker.isPlayable then
        print("[DEBUG] Not a playable character")
        return false, "Not a playable character"
    end
    if attacker.hasActedThisTurn then
        print("[DEBUG] Already acted this turn")
        return false, "Already acted this turn"
    end
    if not attack then
        print("[DEBUG] No attack selected")
        return false, "No attack selected"
    end

    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    print("[DEBUG] Distance to target:", distance, "Attack range:", attack.range)
    if distance > attack.range then
        return false, "Target out of range"
    end

    print("[DEBUG] Executing attack...")
    local success, message = attack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    print("[DEBUG] Attack result:", success, message)

    if success then
        attacker.hasActedThisTurn = true
        actionHistory = {}
        print(attacker.name .. " attacked and ended turn. Move history cleared.")
        attackMode = false
        selectedAttack = nil
        checkGameEnd()
    else
        print("Attack failed: " .. (message or "unknown"))
    end
    return success, message
end

function undoLastAction()
    if #actionHistory == 0 then
        print("No moves to undo!")
        return false
    end

    local action = actionHistory[#actionHistory]
    local actor = action.actor

    if not actor then
        table.remove(actionHistory)
        return undoLastAction()
    end

    if actor.isMoving then
        print("Cannot undo while moving")
        return false
    end

    actor.q = action.fromQ
    actor.r = action.fromR
    actor.hasActedThisTurn = false
    actor.hasMovedThisTurn = false
    actor.isMoving = false
    actor.path = {}
    actor.currentPathIndex = 0

    if action.healthBefore ~= nil then
        actor.health = action.healthBefore
    end
    if action.statusesBefore then
        status.setEntityStatuses(actor, action.statusesBefore)
    end

    if actor.health > 0 then
        local found = false
        for _, e in ipairs(entities) do
            if e == actor then
                found = true
                break
            end
        end
        if not found then
            table.insert(entities, actor)
            print(actor.name .. " was resurrected by undo!")
        end
    end

    if selectedActor == actor then
        hex.selectedQ = actor.q
        hex.selectedR = actor.r
    end

    table.remove(actionHistory)

    sounds.undo:play()
    print("Undone move for " .. actor.name .. ". History size: " .. #actionHistory)
    return true
end

function addToHistory(actor, fromQ, fromR, toQ, toR)
    if not actor.isPlayable then return end
    table.insert(actionHistory, {
        actor = actor,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        type = "move",
        healthBefore = actor.health,
        statusesBefore = status.copyEntityStatuses(actor),
    })
    print("Move recorded. History size: " .. #actionHistory)
end

return combat