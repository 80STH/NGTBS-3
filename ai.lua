-- ai.lua
-- ИИ: враги двигаются к цели, затем подготавливают удар

local ai = {}

ai.DEBUG = true

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
-- Подготовка удара для одного врага (вызывается после движения или если уже рядом)
function ai.prepareAttackForEnemy(enemy, entities, hex)
    if not enemy:isCharacter() or enemy.isPlayable or enemy.health <= 0 then
        return false
    end
    if not ai.canPrepareAttack(enemy, entities) then
        return false
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
        return false
    end

    enemy.preparePos = { q = enemy.q, r = enemy.r }
    enemy.preparedTarget = { q = nearestAlly.q, r = nearestAlly.r }
    enemy.hasPreparedAttack = true
    debugPrint(string.format("%s prepared attack on (%d,%d)", enemy.name, nearestAlly.q, nearestAlly.r))
    return true
end

-- Выполнить подготовленный удар (фаза enemy_attack)
function ai.executePreparedAttack(enemy, entities, hex, sounds)
    if not enemy.hasPreparedAttack or enemy.health <= 0 then
        return false
    end

    local deltaQ = enemy.q - enemy.preparePos.q
    local deltaR = enemy.r - enemy.preparePos.r
    local targetQ = enemy.preparedTarget.q + deltaQ
    local targetR = enemy.preparedTarget.r + deltaR

    if not hex:isValidHex(targetQ, targetR) then
        debugPrint(enemy.name .. " attack misses (outside map)")
        enemy.hasPreparedAttack = false
        return false
    end

    local victim = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR then
            victim = e
            break
        end
    end

    if victim and victim:isCharacter() and not victim.isPlayable then
        victim = nil
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
    enemy.preparePos = nil
    enemy.preparedTarget = nil
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
        if hex:isValidHex(neighbor.q, neighbor.r) and hex:isActiveHex(neighbor.q, neighbor.r) then  -- добавлено
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

    if bestNeighbor then
        return ai.moveToCell(enemy, bestNeighbor.q, bestNeighbor.r, hex, entities)
    end
    return false
end
-- Перемещение на конкретную клетку с анимацией
function ai.moveToCell(enemy, targetQ, targetR, hex, entities)
    if enemy.isMoving then return false end
    local distance = hex:getDistance(enemy.q, enemy.r, targetQ, targetR)
    if distance > enemy.moveRange then return false end

    -- Проверка занятости
    for _, e in ipairs(entities) do
        if e ~= enemy and e.q == targetQ and e.r == targetR then
            return false
        end
    end

    -- Поиск пути
    local path = ai.findSimplePath(enemy.q, enemy.r, targetQ, targetR, enemy, entities, hex)
    if path and #path > 0 and #path <= enemy.moveRange then
        enemy.path = path
        enemy.currentPathIndex = 1
        ai.startEnemyMove(enemy, hex)
        return true
    end
    return false
end

-- Поиск пути BFS
function ai.findSimplePath(startQ, startR, targetQ, targetR, enemy, entities, hex)
    local queue = {{q = startQ, r = startR, path = {}}}
    local visited = { [startQ .. "," .. startR] = true }
    while #queue > 0 do
        local current = table.remove(queue, 1)
        if current.q == targetQ and current.r == targetR then
            return current.path
        end
        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, nb in ipairs(neighbors) do
            local key = nb.q .. "," .. nb.r
            if not visited[key] and hex:isValidHex(nb.q, nb.r) and hex:isActiveHex(nb.q, nb.r) then  -- ДОБАВЛЕНО isActiveHex
                local occupied = false
                for _, e in ipairs(entities) do
                    if e ~= enemy and e.q == nb.q and e.r == nb.r then
                        occupied = true
                        break
                    end
                end
                if not occupied then
                    visited[key] = true
                    local newPath = {}
                    for _, step in ipairs(current.path) do
                        table.insert(newPath, step)
                    end
                    table.insert(newPath, {q = nb.q, r = nb.r})
                    table.insert(queue, {q = nb.q, r = nb.r, path = newPath})
                end
            end
        end
    end
    return nil
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

-- Обновление анимации движения
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
                    -- движение завершено – сигнал для main
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