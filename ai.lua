-- ai.lua
-- ИИ: враги двигаются к цели, затем подготавливают удар
-- Обновлённая версия: атакует постройки и распределяет цели

local ai = {}
local pathfinding = require("pathfinding")
local hex_utils = require("hex_utils")

ai.DEBUG = true

-- Проверка, лежит ли цель на одной из шести прямых от источника (включая любую дистанцию)
local function isOnStraightLine(fromQ, fromR, toQ, toR, hex)
    local fx, fy, fz = hex_utils.axialToCube(fromQ, fromR)
    local tx, ty, tz = hex_utils.axialToCube(toQ, toR)
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

-- ============================================================
-- НОВАЯ ФУНКЦИЯ: Получить все атакуемые цели (игроки + постройки)
-- ============================================================
function ai.getAttackableTargets(entities)
    local targets = {}
    for _, e in ipairs(entities) do
        -- Только игроки и постройки (горы/препятствия не атакуем)
        if (e:isCharacter() and e.isPlayable and e.health > 0) or
           (e:isBuilding() and e.health > 0) then
            local priority = e.isPlayable and 10 or 8
            table.insert(targets, {entity = e, type = e.isPlayable and "player" or "building", priority = priority, health = e.health})
        end
    end
    return targets
end
-- ============================================================
-- НОВАЯ ФУНКЦИЯ: Получить лучшую цель для конкретного врага
-- с учётом уже выбранных целей другими врагами
-- ============================================================
-- Получить текущую атаку врага (первая)
local function getEnemyAttack(enemy)
    if not enemy.attacks or #enemy.attacks == 0 then return nil end
    return enemy.attacks[1].attack
end

-- Требует ли атака прямой линии (для всех, кроме Bite)
local function attackRequiresLine(attack)
    -- Bite и Magic Bolt требуют прямой линии
    return true
end
-- Должна ли атака поражать первую цель на линии (Ghost, Dash, Shoot) или любую (Lich)
local function attackHitsFirstTarget(attack)
    return attack.name == "Ghost Bolt" or attack.name == "Dash" or attack.name == "Shoot" or attack.name == "Piercing Shot"
end

-- Переписать ai.canPrepareAttack
function ai.canPrepareAttack(enemy, entities)
    local attack = getEnemyAttack(enemy)
    if not attack then return false end
    local targets = ai.getAttackableTargets(entities)
    for _, t in ipairs(targets) do
        local dist = hex:getDistance(enemy.q, enemy.r, t.entity.q, t.entity.r)
        if dist <= attack.range then
            if not attackRequiresLine(attack) or isOnStraightLine(enemy.q, enemy.r, t.entity.q, t.entity.r, hex) then
                return true
            end
        end
    end
    return false
end

-- Переписать ai.getBestTargetForEnemy
function ai.getBestTargetForEnemy(enemy, entities, hex, selectedTargets)
    selectedTargets = selectedTargets or {}
    local attack = getEnemyAttack(enemy)
    if not attack then return nil, -math.huge end

    local bestTarget = nil
    local bestScore = -math.huge
    local targets = ai.getAttackableTargets(entities)

    for _, t in ipairs(targets) do
        local target = t.entity
        local dist = hex:getDistance(enemy.q, enemy.r, target.q, target.r)
        if dist > attack.range then goto continue end

        local valid = false
        if attackRequiresLine(attack) then
            if isOnStraightLine(enemy.q, enemy.r, target.q, target.r, hex) then
                if attackHitsFirstTarget(attack) then
                    -- Проверяем, является ли цель первой на линии
                    local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, target.q, target.r, hex)
                    if stepX then
                        local firstTarget, _ = attack:findFirstTargetOnLine(enemy.q, enemy.r, stepX, stepY, stepZ, hex, entities)
                        if firstTarget == target then
                            valid = true
                        end
                    end
                else
                    valid = true  -- Lich может атаковать любую цель на линии
                end
            end
        else
            -- Bite: достаточно расстояния 1
            valid = (dist == attack.range)
        end

        if not valid then goto continue end

        local score = -dist * 2 + t.priority - (selectedTargets[target] or 0) * 3
        if t.health <= 2 then score = score + 15
        elseif t.health <= 3 then score = score + 5 end
        if t.type == "building" and t.health < t.entity.maxHealth then score = score + 8 end

        if score > bestScore then
            bestScore = score
            bestTarget = target
        end
        ::continue::
    end
    return bestTarget, bestScore
end

-- Переписать ai.prepareAttackForEnemy
function ai.prepareAttackForEnemy(enemy, entities, hex, selectedTargets)
    if not enemy:isCharacter() or enemy.isPlayable or enemy.health <= 0 then return false end
    if not ai.canPrepareAttack(enemy, entities) then return false end

    local attack = getEnemyAttack(enemy)
    if not attack then return false end

    local bestTarget = ai.getBestTargetForEnemy(enemy, entities, hex, selectedTargets)
    if not bestTarget then
        debugPrint(string.format("%s cannot prepare: no valid target", enemy.name))
        return false
    end

    if attackRequiresLine(attack) then
        local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, bestTarget.q, bestTarget.r, hex)
        if not stepX then return false end
        enemy.attackDirection = { dx = stepX, dy = stepY, dz = stepZ }
    end

    enemy.hasPreparedAttack = true
    enemy.preparedTargetEntity = bestTarget
    enemy.preparedAttack = attack

    debugPrint(string.format("%s prepared attack targeting %s (%s)", 
               enemy.name, bestTarget.name, bestTarget:isBuilding() and "building" or "player"))
    return true
end

-- Переписать ai.executePreparedAttack
function ai.executePreparedAttack(enemy, entities, hex, sounds, globalHealth)
    if not enemy.hasPreparedAttack or enemy.health <= 0 then return false end
    local attack = enemy.preparedAttack
    if not attack then return false end

    local target = nil
    if attackHitsFirstTarget(attack) then
        -- Ghost, Dash, Shoot: ищем первую цель по направлению
        local dir = enemy.attackDirection
        if not dir then return false end
        local curQ, curR = enemy.q, enemy.r
        while true do
            curQ, curR = hex_utils.applyCubeStep(curQ, curR, dir.dx, dir.dy, dir.dz)
            if not hex:isValidHex(curQ, curR) then break end
            local e = combat.getEntityAtHex(curQ, curR, entities)
            if e and e.health > 0 and e ~= enemy then
                if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                    target = e
                    break
                end
            end
        end
    else
        -- Lich и Bite: используем сохранённую цель
        local saved = enemy.preparedTargetEntity
        if saved and saved.health > 0 then
            local dist = hex:getDistance(enemy.q, enemy.r, saved.q, saved.r)
            if dist <= attack.range then
                target = saved
            end
        end
    end

    if not target then
        debugPrint(enemy.name .. " has no valid target, attack cancelled")
        enemy.hasPreparedAttack = false
        enemy.attackDirection = nil
        enemy.preparedTargetEntity = nil
        enemy.preparedAttack = nil
        return false
    end

    local damage = attack.damage
    local wasDestroyed = target:takeDamage(damage, globalHealth)
    print(string.format("%s attacks %s for %d damage!", enemy.name, target.name, damage))
    if sounds and sounds.attack then sounds.attack:play() end

    if wasDestroyed then
        for i = #entities, 1, -1 do
            if entities[i] == target then
                table.remove(entities, i)
                break
            end
        end
    end

    enemy.hasPreparedAttack = false
    enemy.attackDirection = nil
    enemy.preparedTargetEntity = nil
    enemy.preparedAttack = nil
    return true
end

function ai.getDistanceToNearestTarget(enemy, entities, hex)
    local best = math.huge
    local targets = ai.getAttackableTargets(entities)
    for _, t in ipairs(targets) do
        local d = hex:getDistance(enemy.q, enemy.r, t.entity.q, t.entity.r)
        if d < best then best = d end
    end
    return best
end

-- Найти первую живую цель на линии от (q,r) в направлении (dx,dy,dz)
function findFirstTargetInDirection(startQ, startR, dx, dy, dz, hex, entities)
    local curQ, curR = startQ, startR
    while true do
        curQ, curR = hex_utils.applyCubeStep(curQ, curR, dx, dy, dz)
        if not hex:isValidHex(curQ, curR) then break end
        for _, e in ipairs(entities) do
            if e.q == curQ and e.r == curR and e.health > 0 then
                    return e, curQ, curR
            end
        end
    end
    return nil, nil, nil
end

-- Получить текущую атаку врага (предполагаем, что у врага только одна атака)
function getEnemyAttack(enemy)
    if not enemy.attacks or #enemy.attacks == 0 then
        return nil
    end
    return enemy.attacks[1].attack
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

    -- Ищем ближайшую цель (игрок или постройка)
    local nearestTarget = nil
    local nearestDist = math.huge
    local targets = ai.getAttackableTargets(entities)
    
    for _, t in ipairs(targets) do
        local target = t.entity
        local dist = hex:getDistance(enemy.q, enemy.r, target.q, target.r)
        if dist < nearestDist then
            nearestDist = dist
            nearestTarget = target
        end
    end

    if not nearestTarget then
        return "failed"
    end

    -- Если уже рядом (дистанция 1) – сразу готовим удар
    if nearestDist == 1 then
        -- Для подготовки нужна прямая линия, проверяем
        if isOnStraightLine(enemy.q, enemy.r, nearestTarget.q, nearestTarget.r, hex) then
            ai.prepareAttackForEnemy(enemy, entities, hex, {})
        else
            debugPrint(enemy.name .. " adjacent but not on straight line, cannot prepare")
            return "failed"
        end
        return "prepared"
    end

    -- Иначе пытаемся приблизиться
    local success = ai.performMoveTowards(enemy, nearestTarget, entities, hex)
    if success then
        return "moving"
    else
        debugPrint(enemy.name .. " cannot move towards target, skip")
        return "failed"
    end
end

function ai.performMoveTowards(enemy, target, entities, hex)
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
                    -- Проверяем опасность клетки
                    if not isCellDangerousForEntity(neighbor.q, neighbor.r, enemy) then
                        bestDist = distToEnemy
                        bestCell = neighbor
                    end
                end
            end
        end
    end

    if bestCell then
        return ai.moveToCell(enemy, bestCell.q, bestCell.r, hex, entities)
    end

    -- Если нет безопасной клетки рядом с целью, пробуем шаг за шагом (moveStepTowards)
    return ai.moveStepTowards(enemy, target.q, target.r, hex, entities)
end

function ai.moveStepTowards(enemy, targetQ, targetR, hex, entities)
    local neighbors = hex:getNeighbors(enemy.q, enemy.r)
    local bestNeighbor = nil
    local bestDist = math.huge
    local dangerousNeighbor = nil  -- запасной вариант, если все клетки опасны
    local dangerousDist = math.huge

    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) and hex:isActiveHex(neighbor.q, neighbor.r) then
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
                    if not isCellDangerousForEntity(neighbor.q, neighbor.r, enemy) then
                        bestDist = dist
                        bestNeighbor = neighbor
                    else
                        -- Запоминаем опасную клетку, если безопасных нет
                        if dist < dangerousDist then
                            dangerousDist = dist
                            dangerousNeighbor = neighbor
                        end
                    end
                end
            end
        end
    end

    -- Если есть безопасная клетка – идём в неё
    if bestNeighbor then
        return ai.moveToCell(enemy, bestNeighbor.q, bestNeighbor.r, hex, entities)
    end
    -- Если нет безопасной, но есть опасная – идём в неё (чтобы не застрять)
    if dangerousNeighbor then
        debugPrint(enemy.name .. " forced to move into dangerous cell (fire/acid)")
        return ai.moveToCell(enemy, dangerousNeighbor.q, dangerousNeighbor.r, hex, entities)
    end
    return false
end

function ai.moveToCell(enemy, targetQ, targetR, hex, entities)
    if enemy.isMoving then return false end
    local distance = hex:getDistance(enemy.q, enemy.r, targetQ, targetR)
    if distance > enemy.moveRange then return false end

    function ai.isPositionOccupied(q, r, movingEntity, entities, hex)
        if not hex:isActiveHex(q, r) then
            return true
        end
        -- Вода непроходима (используем глобальный terrainMap)
        if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
            return true
        end
        for _, e in ipairs(entities) do
            if e ~= movingEntity and e.q == q and e.r == r then
                return true
            end
        end
        return false
    end
    -- Поиск пути с единой проверкой проходимости
    local path = pathfinding.findPath(enemy.q, enemy.r, targetQ, targetR, enemy.moveRange,
        function(q, r) return ai.isPositionOccupied(q, r, enemy, entities, hex) end, hex)

    if path and #path > 0 and #path <= enemy.moveRange then
        enemy.path = path
        enemy.currentPathIndex = 1
        ai.startEnemyMove(enemy, hex)
        return true
    end
    return false
end

-- Проверка занятости клетки (с учётом построек и активной зоны)
function ai.isPositionOccupied(q, r, movingEntity, entities, hex)
    if not hex:isActiveHex(q, r) then
        return true
    end
    -- Вода непроходима (если есть terrainMap, но здесь нет доступа, используем hex)
    -- Вода проверяется в pathfinding через isActiveHex или отдельно
    
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            -- Союзники ИИ (другие враги) считаются проходимыми? Нет, они блокируют
            return true
        end
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
                    -- движение завершено
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

-- Проверка, опасна ли клетка для существа (если статус ещё не наложен на существо)
function isCellDangerousForEntity(q, r, entity)
    local cellStatuses = status.getAtHex(q, r)
    if not cellStatuses or #cellStatuses == 0 then
        return false
    end
    for _, st in ipairs(cellStatuses) do
        if st == "fire" or st == "acid" then
            -- Если у существа уже есть этот статус, то клетка не считается опасной
            if not status.hasEntityStatus(entity, st) then
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- НОВАЯ ФУНКЦИЯ: Подготовка всех врагов с распределением целей
-- Вызывается из main.lua в начале фазы подготовки
-- ============================================================
function ai.prepareAllEnemiesWithTargetDistribution(entities, hex)
    local enemies = ai.getLivingEnemies(entities)
    local selectedTargets = {}  -- цель -> количество врагов, выбравших её
    
    -- Сначала каждый враг выбирает лучшую цель с учётом уже выбранных
    for _, enemy in ipairs(enemies) do
        local bestTarget = ai.getBestTargetForEnemy(enemy, entities, hex, selectedTargets)
        if bestTarget then
            -- Инкрементируем счётчик выбранной цели
            selectedTargets[bestTarget] = (selectedTargets[bestTarget] or 0) + 1
        end
    end
    
    -- Теперь готовим атаки
    for _, enemy in ipairs(enemies) do
        ai.prepareAttackForEnemy(enemy, entities, hex, selectedTargets)
    end
    
    return selectedTargets
end


return ai