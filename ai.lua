-- ai.lua
-- ИИ: враги двигаются к цели, затем подготавливают удар

local ai = {}
local pathfinding = require("pathfinding")

-- Преобразования для pointy-top (как в combat.lua)
local function axialToCube(q, r)
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

ai.DEBUG = true

-- Проверка, лежит ли цель на одной из шести прямых от источника (включая любую дистанцию)
local function isOnStraightLine(fromQ, fromR, toQ, toR, hex)
    local fx, fy, fz = axialToCube(fromQ, fromR)
    local tx, ty, tz = axialToCube(toQ, toR)
    local dx, dy, dz = tx - fx, ty - fy, tz - fz

    -- Нормализация до единичного шага (одно из направлений)
    local function gcd(a, b)
        a = math.abs(a); b = math.abs(b)
        while b ~= 0 do a, b = b, a % b end
        return a
    end
    local g = gcd(gcd(dx, dy), dz)
    if g == 0 then return false end
    local stepX, stepY, stepZ = dx / g, dy / g, dz / g

    -- Проверяем, что это один из шести базовых векторов
    local validDirections = {
        {1, -1, 0}, {1, 0, -1}, {0, 1, -1},
        {-1, 1, 0}, {-1, 0, 1}, {0, -1, 1}
    }
    for _, dir in ipairs(validDirections) do
        if stepX == dir[1] and stepY == dir[2] and stepZ == dir[3] then
            return true
        end
    end
    return false
end

local function debugPrint(...)
    if ai.DEBUG then
        print("[AI DEBUG]", ...)
    end
end

-- Проверка, может ли враг подготовить удар (есть ли живой игрок)
function ai.canPrepareAttack(enemy, entities)
    for _, e in ipairs(entities) do
        if e:isCharacter() and e.isPlayable and e.health > 0 then
            return true
        end
    end
    return false
end

function ai.getDistanceToNearestPlayer(enemy, entities, hex)
    local best = math.huge
    for _, e in ipairs(entities) do
        if e:isCharacter() and e.isPlayable and e.health > 0 then
            local d = hex:getDistance(enemy.q, enemy.r, e.q, e.r)
            if d < best then best = d end
        end
    end
    return best
end
-- Подготовка удара (теперь с проверкой прямой линии)
function ai.prepareAttackForEnemy(enemy, entities, hex)
    if not enemy:isCharacter() or enemy.isPlayable or enemy.health <= 0 then
        return false
    end
    if not ai.canPrepareAttack(enemy, entities) then
        return false
    end

    -- Ищем ближайшего живого игрока, лежащего на прямой линии от врага
    local bestTarget = nil
    local bestDist = math.huge
    for _, e in ipairs(entities) do
        if e:isCharacter() and e.isPlayable and e.health > 0 then
            local dist = hex:getDistance(enemy.q, enemy.r, e.q, e.r)
            if dist < bestDist and isOnStraightLine(enemy.q, enemy.r, e.q, e.r, hex) then
                bestDist = dist
                bestTarget = e
            end
        end
    end

    if not bestTarget then
        debugPrint(string.format("%s cannot prepare: no valid target on straight line", enemy.name))
        return false
    end

    -- Вычисляем направление в кубических координатах
    local ex, ey, ez = axialToCube(enemy.q, enemy.r)
    local tx, ty, tz = axialToCube(bestTarget.q, bestTarget.r)
    local dx, dy, dz = tx - ex, ty - ey, tz - ez

    -- Нормализуем до единичного шага
    local function gcd(a, b)
        a = math.abs(a); b = math.abs(b)
        while b ~= 0 do a, b = b, a % b end
        return a
    end
    local g = gcd(gcd(dx, dy), dz)
    dx, dy, dz = dx / g, dy / g, dz / g

    enemy.attackDirection = { dx = dx, dy = dy, dz = dz }
    enemy.hasPreparedAttack = true

    debugPrint(string.format("%s prepared attack in direction (%d,%d,%d)", enemy.name, dx, dy, dz))
    return true
end

-- Выполнить подготовленный удар
function ai.executePreparedAttack(enemy, entities, hex, sounds)
    if not enemy.hasPreparedAttack or enemy.health <= 0 then
        return false
    end

    local dir = enemy.attackDirection
    if not dir then
        enemy.hasPreparedAttack = false
        return false
    end

    -- Текущие кубические координаты врага
    local curX, curY, curZ = axialToCube(enemy.q, enemy.r)
    local targetX = curX + dir.dx
    local targetY = curY + dir.dy
    local targetZ = curZ + dir.dz
    local targetQ, targetR = cubeToAxial(targetX, targetY, targetZ)

    if not hex:isValidHex(targetQ, targetR) then
        debugPrint(enemy.name .. " attack misses (outside map)")
        enemy.hasPreparedAttack = false
        return false
    end

    local victim = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e:isCharacter() and e.isPlayable and e.health > 0 then
            victim = e
            break
        end
    end

    if victim then
        victim.health = victim.health - 1
        print(string.format("%s attacks %s for 1 damage!", enemy.name, victim.name))
        if sounds and sounds.attack then sounds.attack:play() end
        if victim.health <= 0 then
            for i = #entities, 1, -1 do
                if entities[i] == victim then
                    table.remove(entities, i)
                    break
                end
            end
        end
    else
        debugPrint(enemy.name .. " attacks empty cell")
    end

    enemy.hasPreparedAttack = false
    enemy.attackDirection = nil
    return true
end

-- moveAndPrepare теперь возвращает:
-- "moving" - начато движение
-- "prepared" - сразу подготовлен (уже рядом)
-- "failed" - не может подготовиться (нет целей или движение невозможно)
function ai.moveAndPrepare(enemy, entities, hex)
    if not enemy:isCharacter() or enemy.isPlayable or enemy.health <= 0 then
        return "failed"
    end
    if enemy.isMoving then
        return "moving"
    end

    if not ai.canPrepareAttack(enemy, entities) then
        debugPrint(enemy.name .. " no living enemies, cannot prepare")
        return "failed"
    end

    local nearestAlly = nil
    local nearestDist = math.huge
    for _, e in ipairs(entities) do
        if e:isCharacter() and e.isPlayable and e.health > 0 then
            local dist = hex:getDistance(enemy.q, enemy.r, e.q, e.r)
            if dist < nearestDist then
                nearestDist = dist
                nearestAlly = e
            end
        end
    end

    if not nearestAlly then
        return "failed"
    end

    -- Если уже рядом (дистанция 1) – сразу готовим удар
    if nearestDist == 1 then
        ai.prepareAttackForEnemy(enemy, entities, hex)
        return "prepared"
    end

    -- Иначе пытаемся приблизиться
    local success = ai.performMoveTowards(enemy, nearestAlly, entities, hex)
    if success then
        return "moving"
    else
        -- Не удалось начать движение (нет пути, всё заблокировано)
        debugPrint(enemy.name .. " cannot move towards target, skip")
        return "failed"
    end
end

-- Движение к цели (без атаки) – вызывает анимацию
function ai.performMoveTowards(enemy, target, entities, hex)
    -- Пытаемся найти свободную клетку на расстоянии 1 от цели
    local neighbors = hex:getNeighbors(target.q, target.r)
    local bestCell = nil
    local bestDist = math.huge

    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local occupied = false
            for _, e in ipairs(entities) do
                if e ~= enemy and e.q == neighbor.q and e.r == neighbor.r then
                    occupied = true
                    break
                end
            end
            if not occupied then
                local distToEnemy = hex:getDistance(enemy.q, enemy.r, neighbor.q, neighbor.r)
                if distToEnemy < bestDist and distToEnemy <= enemy.moveRange then
                    bestDist = distToEnemy
                    bestCell = neighbor
                end
            end
        end
    end

    if bestCell then
        return ai.moveToCell(enemy, bestCell.q, bestCell.r, hex, entities)
    end

    -- Если нет свободной клетки рядом с целью – двигаемся по направлению (шаг за шагом)
    return ai.moveStepTowards(enemy, target.q, target.r, hex, entities)
end

-- Пошаговое движение в направлении цели (один шаг)
function ai.moveStepTowards(enemy, targetQ, targetR, hex, entities)
    local neighbors = hex:getNeighbors(enemy.q, enemy.r)
    local bestNeighbor = nil
    local bestDist = math.huge

    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) and hex:isActiveHex(neighbor.q, neighbor.r) then
            if not isPositionOccupied(neighbor.q, neighbor.r, enemy) then
            local occupied = false
            for _, e in ipairs(entities) do
                if e ~= enemy and e.q == neighbor.q and e.r == neighbor.r then
                    occupied = true
                    break
                end
            end
            if not occupied then
                local dist = hex:getDistance(neighbor.q, neighbor.r, targetQ, targetR)
                if dist < bestDist then
                    bestDist = dist
                    bestNeighbor = neighbor
                end
            end
        end
        end
    end

    if bestNeighbor then
        return ai.moveToCell(enemy, bestNeighbor.q, bestNeighbor.r, hex, entities)
    end
    return false
end

function ai.moveToCell(enemy, targetQ, targetR, hex, entities)
    if enemy.isMoving then return false end
    local distance = hex:getDistance(enemy.q, enemy.r, targetQ, targetR)
    if distance > enemy.moveRange then return false end

    -- Проверяем, свободна ли целевая клетка (вода, занятость, активность)
    if isPositionOccupied(targetQ, targetR, enemy) then
        return false
    end

    -- Поиск пути с единой проверкой проходимости
    local path = pathfinding.findPath(enemy.q, enemy.r, targetQ, targetR, enemy.moveRange,
        function(q, r) return isPositionOccupied(q, r, enemy) end, hex)

    if path and #path > 0 and #path <= enemy.moveRange then
        enemy.path = path
        enemy.currentPathIndex = 1
        ai.startEnemyMove(enemy, hex)
        return true
    end
    return false
end

-- Запуск анимации движения
function ai.startEnemyMove(enemy, hex)
    if enemy.currentPathIndex and enemy.currentPathIndex <= #enemy.path then
        local step = enemy.path[enemy.currentPathIndex]
        enemy.isMoving = true
        enemy.timer = 0
        enemy.targetQ = step.q
        enemy.targetR = step.r
        enemy.startX, enemy.startY = hex:hexToPixel(enemy.q, enemy.r)
        enemy.endX, enemy.endY = hex:hexToPixel(step.q, step.r)
    else
        enemy.isMoving = false
        enemy.path = {}
        enemy.currentPathIndex = 0
        -- После завершения движения – подготовить удар
        -- (вызывается из main.lua после анимации)
    end
end

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
                    -- движение завершено – применяем эффекты клетки
                    if enemy.health > 0 then
                        effects.applyAllCellEffects(enemy, enemy.q, enemy.r, terrainMap, entities, globalHealth)
                    end
                    enemy.movementFinished = true
                end
            end
        end
    end
end

function ai.getLivingEnemies(entities)
    local enemies = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            table.insert(enemies, e)
        end
    end
    return enemies
end

return ai