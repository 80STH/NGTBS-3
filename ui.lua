-- ui.lua
-- Все функции интерфейса (кнопки, панели, предпросмотр атак, движения и т.д.)

local ui = {}
local pathfinding = require("pathfinding")
local combat = require("combat")
local visual = require("visual_effects")    -- если ещё нет
local hex_utils = require("hex_utils")

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ПРЕДПРОСМОТРА АТАК
-- ============================================================

local hazardTexture = nil

-- Возвращает реальные координаты для отрисовки сущности (с учётом анимаций)
local function getEntityDisplayPosition(entity, hex)
    if not entity then return nil, nil end
    if entity.currentDrawX and entity.currentDrawY then
        return entity.currentDrawX, entity.currentDrawY
    end
    return getDrawCoords(entity.q, entity.r)
end

local function getHazardTexture()
    if hazardTexture then return hazardTexture end
    local size = 64
    local canvas = love.graphics.newCanvas(size, size)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 0.2, 0.2, 0.85)
    love.graphics.setLineWidth(2)
    for i = -size, size, 10 do
        love.graphics.line(i, 0, i + size, size)
        love.graphics.line(0, i, size, i + size)
    end
    love.graphics.setCanvas()
    hazardTexture = canvas
    return hazardTexture
end

-- Получить сущность на гексе (глобальная функция из main.lua, дублируем для безопасности)
local function getEntityAtHex(q, r, entities)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then
            return e
        end
    end
    return nil
end

-- Проверка, может ли актор дойти до клетки (с учётом препятствий и длины пути)
function ui.isCellReachable(actor, targetQ, targetR, entities, terrainMap, hex)
    if not hex:isActiveHex(targetQ, targetR) then return false end
    
    -- Вода непроходима
    if terrainMap and terrainMap[targetQ] and terrainMap[targetQ][targetR] == "water" then
        return false
    end
    
    -- Клетка не должна быть занята (врагом или препятствием)
    -- isPositionOccupied - глобальная функция из main.lua
    if isPositionOccupied(targetQ, targetR, actor) then
        return false
    end
    
    -- Поиск пути с ограничением по дальности и блокировками
    local path = pathfinding.findPath(actor.q, actor.r, targetQ, targetR, actor.moveRange,
        function(q, r) return isPositionOccupied(q, r, actor) end, hex)
    
    return path ~= nil and #path > 0
end

function ui.drawPathPreview(hex, actor, hoverQ, hoverR, entities, terrainMap)
    if actor.hasMovedThisTurn or actor.hasActedThisTurn then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end

    local dist = hex:getDistance(actor.q, actor.r, hoverQ, hoverR)
    if dist > actor.moveRange then return end

    -- Не показываем путь, если клетка занята (союзником или врагом)
    if isCellOccupiedForStop(hoverQ, hoverR, actor) then
        return
    end

    local path = pathfinding.findPath(actor.q, actor.r, hoverQ, hoverR, actor.moveRange,
        function(q, r) return not isCellPassable(q, r, actor) end, hex)

    if not path or #path == 0 then return end

    -- Рисуем линию и силуэт (как было ранее)
    local points = {}
    local startX, startY = getDrawCoords(actor.q, actor.r)
    table.insert(points, {x = startX, y = startY})
    for _, step in ipairs(path) do
        local x, y = getDrawCoords(step.q, step.r)
        table.insert(points, {x = x, y = y})
    end

    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.2, 0.8, 0.2, 0.8)
    for i = 1, #points - 1 do
        love.graphics.line(points[i].x, points[i].y, points[i+1].x, points[i+1].y)
    end

    local targetX, targetY = points[#points].x, points[#points].y
    local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
    local alpha = 0.3 + 0.4 * pulse
    if actor.sprite then
        love.graphics.setColor(1, 1, 1, alpha)
        local sw, sh = actor.sprite:getDimensions()
        local scale = 5.9  -- чуть меньше оригинала
        love.graphics.draw(actor.sprite, targetX, targetY, 0, scale, scale, sw/2, sh/2)
        love.graphics.setColor(1, 1, 1, 1)
    else
        love.graphics.setColor(0.2, 0.8, 0.2, alpha)
        love.graphics.circle("fill", targetX, targetY, hex.radius * 0.5)
    end

    local vertices = hex:drawHexagon(targetX, targetY, hex.radius)
    love.graphics.setColor(0.2, 0.8, 0.2, 0.6)
    love.graphics.polygon("line", vertices)

    love.graphics.setLineWidth(1)
end

-- Проверить, получит ли отталкиваемая сущность урон от столкновения
-- возвращает (урон, причина, вторая_сущность)
function ui.checkCollisionDamage(entity, fromQ, fromR, toQ, toR, hex, entities)
    -- Если цель не является персонажем, урон не получает (например, камень)
    if not entity:isCharacter() then
        return 0, nil, nil
    end

    -- Если клетка назначения не активна (вылет за край)
    if not hex:isActiveHex(toQ, toR) then
        return 1, "edge", nil
    end

    -- Проверяем, занята ли клетка другой сущностью
    local occupant = getEntityAtHex(toQ, toR, entities)
    if occupant then
        -- Столкновение с другой сущностью
        -- Обе получают урон, если обе являются персонажами
        if entity:isCharacter() then
            if occupant:isCharacter() then
                return 1, "collision_both", occupant
            else
                -- Неподвижный объект (здание, препятствие) – урон только отталкиваемому
                return 1, "collision_immovable", occupant
            end
        end
    end

    return 0, nil, nil
end

-- Отрисовка стрелки отталкивания (с отступом от центров)
function ui.drawPushArrow(fromX, fromY, toX, toY, r, g, b, alpha)
    local angle = math.atan2(toY - fromY, toX - fromX)
    local arrowSize = 18
    local lineWidth = 4
    local radius = hex.radius
    local offset = radius * 0.3
    local startX = fromX + math.cos(angle) * offset
    local startY = fromY + math.sin(angle) * offset
    local endX = toX - math.cos(angle) * offset
    local endY = toY - math.sin(angle) * offset
    love.graphics.setLineWidth(lineWidth)
    love.graphics.setColor(r or 1, g or 0.8, b or 0.2, alpha or 0.9)
    love.graphics.line(startX, startY, endX, endY)
    local leftAngle = angle + math.pi * 0.7
    local rightAngle = angle - math.pi * 0.7
    love.graphics.line(endX, endY, endX + math.cos(leftAngle) * arrowSize, endY + math.sin(leftAngle) * arrowSize)
    love.graphics.line(endX, endY, endX + math.cos(rightAngle) * arrowSize, endY + math.sin(rightAngle) * arrowSize)
    love.graphics.setLineWidth(1)
end

-- Нарисовать значок столкновения
function ui.drawCollisionIcon(x, y, damage, isDouble)
    love.graphics.setColor(0.8, 0.4, 0, 1)
    love.graphics.circle("fill", x, y, 12)
    love.graphics.setColor(1, 1, 1, 1)
    if damage and damage > 0 then
        love.graphics.print(tostring(damage), x + 8, y - 6)
    end
end

-- ============================================================
-- ОСНОВНЫЕ UI-ФУНКЦИИ, ВЫЗЫВАЕМЫЕ ИЗ MAIN.LUA
-- ============================================================
function ui.drawPreparedAttacks(hex, entities)
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.preparedAttack then
            local attack = e.preparedAttack
            local targetCell = nil

            -- Для атак, которые ищут первую цель на линии (Ghost, Shoot, Dash, Piercing)
            if attack.name == "Ghost Bolt" or attack.name == "Shoot" or attack.name == "Dash" or attack.name == "Piercing Shot" then
                if e.attackDirection then
                    local step = e.attackDirection
                    local curQ, curR = e.q, e.r
                    local lastValidQ, lastValidR = curQ, curR
                    while true do
                        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                        if not hex:isActiveHex(nextQ, nextR) then
                            break
                        end
                        local ent = getEntityAtHex(nextQ, nextR, entities)
                        if ent and ent ~= e and ent.health > 0 then
                            lastValidQ, lastValidR = nextQ, nextR
                            break
                        end
                        lastValidQ, lastValidR = nextQ, nextR
                        curQ, curR = nextQ, nextR
                    end
                    if (lastValidQ ~= e.q or lastValidR ~= e.r) then
                        targetCell = {q = lastValidQ, r = lastValidR}
                    end
                end

            elseif attack.name == "Bite" then
                if e.preparedTargetOffset then
                    local targetQ, targetR = hex_utils.applyCubeDiff(e.q, e.r,
                        e.preparedTargetOffset.dx,
                        e.preparedTargetOffset.dy,
                        e.preparedTargetOffset.dz)
                    if hex:isActiveHex(targetQ, targetR) then
                        targetCell = {q = targetQ, r = targetR}
                    end
                end

            elseif attack.name == "Magic Bolt" then
                if e.preparedTargetOffset then
                    local targetQ, targetR = hex_utils.applyCubeDiff(e.q, e.r,
                        e.preparedTargetOffset.dx,
                        e.preparedTargetOffset.dy,
                        e.preparedTargetOffset.dz)
                    if hex:isActiveHex(targetQ, targetR) then
                        targetCell = {q = targetQ, r = targetR}
                    end
                end
            end

if targetCell then
local x, y = getDrawCoords(targetCell.q, targetCell.r)

                    local targetEntity = getEntityAtHex(targetCell.q, targetCell.r, entities)
                    if targetEntity and targetEntity.health > 0 then
                        drawHealthBar(targetEntity, x, y, attack.damage)
                    end

                    local vertices = hex:drawHexagon(x, y, hex.radius)
    
    -- Подсчёт количества атак на эту цель (от разных врагов)
    local threatCount = 0
    for _, other in ipairs(entities) do
        if other:isCharacter() and not other.isPlayable and other.hasPreparedAttack and other.preparedAttack then
            local otherAttack = other.preparedAttack
            local otherTarget = nil
            -- Аналогично определяем целевую клетку для other
            if otherAttack.name == "Ghost Bolt" or otherAttack.name == "Shoot" or otherAttack.name == "Dash" or otherAttack.name == "Piercing Shot" then
                if other.attackDirection then
                    local step = other.attackDirection
                    local curQ, curR = other.q, other.r
                    while true do
                        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                        if not hex:isActiveHex(nextQ, nextR) then break end
                        local ent = getEntityAtHex(nextQ, nextR, entities)
                        if ent and ent ~= other and ent.health > 0 then
                            otherTarget = {q = nextQ, r = nextR}
                            break
                        end
                        curQ, curR = nextQ, nextR
                    end
                end
            elseif otherAttack.name == "Bite" or otherAttack.name == "Magic Bolt" then
                if other.preparedTargetOffset then
                    local tq, tr = hex_utils.applyCubeDiff(other.q, other.r,
                        other.preparedTargetOffset.dx, other.preparedTargetOffset.dy, other.preparedTargetOffset.dz)
                    if hex:isActiveHex(tq, tr) then
                        otherTarget = {q = tq, r = tr}
                    end
                end
            end
            if otherTarget and otherTarget.q == targetCell.q and otherTarget.r == targetCell.r then
                threatCount = threatCount + 1
            end
        end
    end
    threatCount = math.min(threatCount, 3)  -- ограничиваем до 3
    
    -- Настройки отрисовки в зависимости от количества атак
    local alpha, r, g, b, scaleMod
    if threatCount == 1 then
        alpha = 0.5
        r, g, b = 1, 0.5, 0.2
        scaleMod = 1.0
    elseif threatCount == 2 then
        alpha = 0.75
        r, g, b = 1, 0.3, 0.1
        scaleMod = 1.2
    else -- threatCount >= 3
        alpha = 1.0
        r, g, b = 1, 0, 0
        scaleMod = 1.4
    end
    
    -- Пульсация (только для 1 и 2 атак)
    local pulse = 1.0
    if threatCount <= 2 then
        local t = love.timer.getTime()
        pulse = 0.7 + 0.3 * math.sin(t * (5 + threatCount * 3))
        alpha = alpha * pulse
    end
    
    love.graphics.stencil(function()
        love.graphics.polygon("fill", vertices)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    
    local tex = getHazardTexture()
    love.graphics.setColor(r, g, b, alpha)
    -- Рисуем текстуру, возможно, несколько раз с наложением для усиления
    if threatCount >= 2 then
        -- Для 2+ атак рисуем дважды со сдвигом (имитация плотности)
        love.graphics.draw(tex, x - hex.radius - 2, y - hex.radius - 2, 0,
                           hex.radius * 2 / tex:getWidth() * scaleMod,
                           hex.radius * 2 / tex:getHeight() * scaleMod)
        love.graphics.draw(tex, x - hex.radius + 2, y - hex.radius + 2, 0,
                           hex.radius * 2 / tex:getWidth() * scaleMod,
                           hex.radius * 2 / tex:getHeight() * scaleMod)
    end
    love.graphics.draw(tex, x - hex.radius, y - hex.radius, 0,
                       hex.radius * 2 / tex:getWidth() * scaleMod,
                       hex.radius * 2 / tex:getHeight() * scaleMod)
    
    love.graphics.setStencilTest()
    love.graphics.setColor(1, 1, 1, 1)
end
        end
    end
end

-- ГЛАВНАЯ ФУНКЦИЯ ПРЕДПРОСМОТРА АТАКИ (вызывается при наведении мыши)
function ui.drawAttackPreview(hex, attacker, attack, attackMode, hoverQ, hoverR, entities)
    if not attackMode or not attack then return end
    if not attacker or attacker.hasActedThisTurn then return end

    -- Получаем дистанцию до наведённой клетки
    local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if distance > attack.range then return end

    -- Анализируем тип атаки и получаем детали предпросмотра
    local previewData = nil

    -- Flip обрабатываем отдельно, чтобы не было ложных срабатываний
    if attack.name == "Flip" then
        local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if distance == 1 then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then
                local pushCell = attack:getPushCell(attacker, hoverQ, hoverR, hex, entities)
                if pushCell then
                    -- Подсветка цели
                    local fromX, fromY = getDrawCoords(target.q, target.r)
                    local vertices = hex:drawHexagon(fromX, fromY, hex.radius)
                    love.graphics.setColor(1, 0.5, 0, 0.3)
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(1, 0.7, 0, 0.8)
                    love.graphics.polygon("line", vertices)
                    -- Стрелка переворота
                    local toX, toY = getDrawCoords(pushCell.q, pushCell.r)
                    ui.drawPushArrow(fromX, fromY, toX, toY)
                end
            end
        end
        return
    end

    -- Ghost Bolt
    if attack.name == "Ghost Bolt" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
            if firstTarget and targetHex then
                local x, y = getDrawCoords(targetHex.q, targetHex.r)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.setColor(0.6, 0.2, 0.8, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.8, 0.4, 1, 0.8)
                love.graphics.polygon("line", vertices)
                drawHealthBar(firstTarget, x, y, attack.damage)
            end
        end
        return
    end

    -- Zombie Bite
    if attack.name == "Bite" then
        local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if distance == 1 then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then
                local x, y = getDrawCoords(hoverQ, hoverR)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.setColor(0.8, 0.2, 0.2, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.4, 0.4, 0.8)
                love.graphics.polygon("line", vertices)
                drawHealthBar(target, x, y, attack.damage)
            end
        end
        return
    end

if attack.name == "Magic Bolt" then
    local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if distance <= attack.range then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then
                -- ... подсветка цели ...
                local fromX, fromY = getDrawCoords(attacker.q, attacker.r)
                local toX, toY = getDrawCoords(hoverQ, hoverR)
                local midX = (fromX + toX) / 2
                local midY = (fromY + toY) / 2
                local ctrlX = midX
                local ctrlY = midY - 60
                ui.drawDottedArc(fromX, fromY, toX, toY, ctrlX, ctrlY, 5, 25, time)
            end
        end
    end
    return
end

    if attack.name == "Dash" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex, lastFree = attack:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)
            
            -- Рисуем путь (стрелку) от атакующего до lastFree
            if lastFree then
                local fromX, fromY = getDrawCoords(attacker.q, attacker.r)
                local toX, toY = getDrawCoords(lastFree.q, lastFree.r)
                ui.drawPushArrow(fromX, fromY, toX, toY)
                -- Силуэт атакующего на целевой клетке
                local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
                local alpha = 0.3 + 0.4 * pulse
                if attacker.sprite then
                    love.graphics.setColor(1, 1, 1, alpha)
                    local sw, sh = attacker.sprite:getDimensions()
                    local scale = 5.9
                    love.graphics.draw(attacker.sprite, toX, toY, 0, scale, scale, sw/2, sh/2)
                else
                    love.graphics.setColor(0.2, 0.8, 0.2, alpha)
                    love.graphics.circle("fill", toX, toY, hex.radius * 0.5)
                end
            end

            -- Урон по первой цели + возможный урон от отталкивания
            if firstTarget then
                local targetX, targetY = getDrawCoords(firstTarget.q, firstTarget.r)
                local totalDamage = attack.damage or 1
                if targetHex then
                    local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
                    if hex:isActiveHex(pushQ, pushR) then
                        local collisionDamage, reason, second = ui.checkCollisionDamage(
                            firstTarget, targetHex.q, targetHex.r, pushQ, pushR, hex, entities
                        )
                        totalDamage = totalDamage + (collisionDamage or 0)
                    end
                end
                drawHealthBar(firstTarget, targetX, targetY, totalDamage)
                
                if targetHex then
                    local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
                    if hex:isActiveHex(pushQ, pushR) and not combat.getEntityAtHex(pushQ, pushR, entities) then
                        local pushX, pushY = getDrawCoords(pushQ, pushR)
                        ui.drawPushArrow(targetX, targetY, pushX, pushY)
                    else
                        local blockX, blockY = getDrawCoords(pushQ, pushR)
                        love.graphics.setColor(1, 0, 0, 0.8)
                        love.graphics.circle("fill", blockX, blockY, hex.radius * 0.3)
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.print("✗", blockX - 4, blockY - 6)
                    end
                end
            end
            return
        end
    end

    -- Для атак, у которых есть getPushCell (Shoot и др.)
    if attack.getPushCell then
        local pushCell = attack:getPushCell(attacker, hoverQ, hoverR, hex, entities)
        if pushCell then
            local firstTarget = nil
            if attack.getLineDirection then
                local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
                if stepX then
                    local target, targetHex = nil, nil
                    if attack.findFirstTargetOnLine then
                        target, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                    end
                    if target then firstTarget = target end
                end
            else
                firstTarget = getEntityAtHex(hoverQ, hoverR, entities)
            end

            if firstTarget then
                previewData = {
                    {
                        target = firstTarget,
                        fromCell = {q = firstTarget.q, r = firstTarget.r},
                        pushTo = pushCell,
                        attackDamage = attack.damage or 0,
                    }
                }
                if attack.getPushCells then
                    local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
                    if #pushCells >= 2 then
                        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
                        if stepX then
                            local _, _, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                            if secondTarget then
                                table.insert(previewData, {
                                    target = secondTarget,
                                    fromCell = {q = secondTarget.q, r = secondTarget.r},
                                    pushTo = pushCells[2],
                                    attackDamage = 1,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- Piercing Shot (две цели на линии)
    if attack.getPushCells and not previewData and attack.name == "Piercing Shot" then
        local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
        if pushCells and #pushCells > 0 then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then
                local firstTarget, firstHex, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                previewData = {}
                if firstTarget and firstHex then
                    table.insert(previewData, {
                        target = firstTarget,
                        fromCell = {q = firstHex.q, r = firstHex.r},
                        pushTo = pushCells[1],
                        attackDamage = 0,
                    })
                end
                if secondTarget and secondHex and #pushCells >= 2 then
                    table.insert(previewData, {
                        target = secondTarget,
                        fromCell = {q = secondHex.q, r = secondHex.r},
                        pushTo = pushCells[2],
                        attackDamage = 1,
                    })
                end
            end
        end
    end

-- ================= STONE THROW (AoePushAttack) =================
if attack.name == "Stone Throw" then
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 2) or dist > attack.range then return end

    local dirQ, dirR = hoverQ - attacker.q, hoverR - attacker.r

    -- Проверка прямой линии
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    local centerX, centerY = getDrawCoords(hoverQ, hoverR)
    local centerVertices = hex:drawHexagon(centerX, centerY, hex.radius)  -- <-- добавлено
    love.graphics.setColor(1, 1, 0, 0.3)
    love.graphics.polygon("fill", centerVertices)
    -- Урон, если есть цель
    local targetEntity = getEntityAtHex(hoverQ, hoverR, entities)
    if targetEntity and targetEntity.health > 0 then
        drawHealthBar(targetEntity, centerX, centerY, 1)
    end

    local neighbors = attack:getNeighborsInDirection(hoverQ, hoverR, dirQ, dirR, hex)
    for _, nb in ipairs(neighbors) do
        if hex:isActiveHex(nb.q, nb.r) then
            local cX, cY, cZ = hex_utils.axialToCube(hoverQ, hoverR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dirX, dirY, dirZ)

            -- внутри блока Stone Throw
local target = getEntityAtHex(nb.q, nb.r, entities)
local hasTarget = target and target:isCharacter() and target.health > 0

            local x, y = getDrawCoords(nb.q, nb.r)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            if hasTarget then
                love.graphics.setColor(1, 0.5, 0, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.7, 0, 0.8)
                love.graphics.polygon("line", vertices)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
                love.graphics.polygon("line", vertices)
            end

            local fromX, fromY = getDrawCoords(nb.q, nb.r)
            local toX, toY = getDrawCoords(pushQ, pushR)
            if hasTarget then
                ui.drawPushArrow(fromX, fromY, toX, toY, 1, 0.8, 0.2, 0.9)
                drawHealthBar(target, fromX, fromY, 0)
            else
                ui.drawPushArrow(fromX, fromY, toX, toY, 0.7, 0.7, 0.7, 0.6)
            end
        end
    end
    return
end

-- ================= CONE BLAST (AoeDirectionalAttack) =================
if attack.name == "Cone Blast" then
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 2) or dist > attack.range then return end

    local dirQ, dirR = hoverQ - attacker.q, hoverR - attacker.r

    -- Центр
    local centerX, centerY = getDrawCoords(hoverQ, hoverR)
    local centerVertices = hex:drawHexagon(centerX, centerY, hex.radius)
    local centerTarget = getEntityAtHex(hoverQ, hoverR, entities)
    if centerTarget and centerTarget:isCharacter() and centerTarget.health > 0 then
        love.graphics.setColor(1, 0.5, 0, 0.3)
        love.graphics.polygon("fill", centerVertices)
        love.graphics.setColor(1, 0.7, 0, 0.8)
        love.graphics.polygon("line", centerVertices)
        drawHealthBar(centerTarget, centerX, centerY, 1)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, 0.3)
        love.graphics.polygon("fill", centerVertices)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
        love.graphics.polygon("line", centerVertices)
    end

    -- Соседи в направлении
    local allNeighbors = hex:getNeighbors(hoverQ, hoverR)
    for _, nb in ipairs(allNeighbors) do
        if hex:isActiveHex(nb.q, nb.r) then
            local cX, cY, cZ = hex_utils.axialToCube(hoverQ, hoverR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dirX, dirY, dirZ)

            local target = getEntityAtHex(nb.q, nb.r, entities)
            local hasTarget = target and target:isCharacter() and target.health > 0

            local x, y = getDrawCoords(nb.q, nb.r)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            if hasTarget then
                love.graphics.setColor(1, 0.5, 0, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.7, 0, 0.8)
                love.graphics.polygon("line", vertices)
            else
                love.graphics.setColor(0.5, 0.5, 0.5, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
                love.graphics.polygon("line", vertices)
            end

            local fromX, fromY = getDrawCoords(nb.q, nb.r)
            local toX, toY = getDrawCoords(pushQ, pushR)
            if hasTarget then
                ui.drawPushArrow(fromX, fromY, toX, toY, 1, 0.8, 0.2, 0.9)
                drawHealthBar(target, fromX, fromY, 0)
            else
                ui.drawPushArrow(fromX, fromY, toX, toY, 0.7, 0.7, 0.7, 0.6)
            end
        end
    end
    return
end

    if not previewData or #previewData == 0 then
        return
    end

    -- Отрисовка для каждой цели
    for _, pd in ipairs(previewData) do
        local target = pd.target
        if target and target.health > 0 then
            local fromX, fromY = getDrawCoords(pd.fromCell.q, pd.fromCell.r)
            -- Подсветка исходной клетки цели
            local vertices = hex:drawHexagon(fromX, fromY, hex.radius)
            love.graphics.setColor(1, 0.5, 0, 0.3)
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(1, 0.7, 0, 0.8)
            love.graphics.polygon("line", vertices)

            -- Вычисляем общий урон (атака + возможное столкновение)
            local totalDamage = pd.attackDamage
            if pd.pushTo then
                local collisionDamage, reason, second = ui.checkCollisionDamage(
                    target, pd.fromCell.q, pd.fromCell.r,
                    pd.pushTo.q, pd.pushTo.r, hex, entities
                )
                totalDamage = totalDamage + (collisionDamage or 0)
            end
            if totalDamage > 0 then
                drawHealthBar(target, fromX, fromY, totalDamage)
            end

            -- Отталкивание
            if pd.pushTo then
                local toX, toY = getDrawCoords(pd.pushTo.q, pd.pushTo.r)
                ui.drawPushArrow(fromX, fromY, toX, toY)

                local collisionDamage, reason, second = ui.checkCollisionDamage(
                    target, pd.fromCell.q, pd.fromCell.r,
                    pd.pushTo.q, pd.pushTo.r, hex, entities
                )
                if collisionDamage > 0 then
                    local crashX, crashY = toX, toY
                    if reason == "collision_both" and second then
                        local secX, secY = getDrawCoords(second.q, second.r)
                        ui.drawCollisionIcon(secX, secY, 1, true)
                        ui.drawCollisionIcon(crashX, crashY, 1, true)
                        drawHealthBar(second, secX, secY, 1)   -- <-- добавить урон зданию
                    elseif reason == "collision_immovable" then
                        ui.drawCollisionIcon(crashX, crashY, 1, false)
                        if second then
                            local secX, secY = getDrawCoords(second.q, second.r)
                            drawHealthBar(second, secX, secY, 1)   -- <-- добавить урон зданию
                        end
                    elseif reason == "edge" then
                        ui.drawCollisionIcon(crashX, crashY, 1, false)
                    end
                end
            end
        end
    end

    -- Дополнительно подсветить клетку, куда бьём (только для атак с направлением)
    if attack.getLineDirection then
        local x, y = getDrawCoords(hoverQ, hoverR)
        local vertices = hex:drawHexagon(x, y, hex.radius)
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.polygon("fill", vertices)
        love.graphics.setColor(1, 1, 0, 0.9)
        love.graphics.polygon("line", vertices)
    end
end

function ui.drawMovementRange(hex, actor, entities, terrainMap)
    if actor.hasMovedThisTurn or actor.hasActedThisTurn then return end
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) and ui.isCellReachable(actor, q, r, entities, terrainMap, hex) then
                local terrainType = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                local yOffset = (terrainType == "water") and 12 or 0
                local x, y = getDrawCoords(q, r)
                local vertices = hex:drawHexagon(x, y + yOffset, hex.radius)
                love.graphics.setColor(0.2, 0.8, 0.2, 0.2)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
                love.graphics.polygon("line", vertices)
            end
        end
    end
end

-- Кнопка Undo
function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
    local canUndo = #actionHistory > 0 and selectedActor and not selectedActor.hasActedThisTurn
    love.graphics.setColor(canUndo and 0.2 or 0.5, 0.2, 0.8, 0.8)
    love.graphics.rectangle("fill", 10, 200, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Undo (U)", 30, 208)
    if not canUndo then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 200, 120, 30, 5)
    end
end

-- Кнопка End Turn
function ui.drawEndTurnButton(turnState, entities)
    local isPlayerTurn = (turnState.phase == "player")
    love.graphics.setColor(isPlayerTurn and 0.8 or 0.4, 0.2, 0.2, 0.8)
    love.graphics.rectangle("fill", 10, 280, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("End Turn (E)", 24, 288)
    if not isPlayerTurn then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 280, 120, 30, 5)
    end
end

-- Интерфейс Wind Torrent
function ui.drawWindTorrentUI(windTorrent, windTorrentUI, turnState)
    local available = (turnState.phase == "player" and windTorrent and not windTorrent.hasBeenUsed)
    love.graphics.setColor(available and 0.2 or 0.5, 0.6, 0.8, 0.8)
    love.graphics.rectangle("fill", windTorrentUI.button.x, windTorrentUI.button.y, windTorrentUI.button.width, windTorrentUI.button.height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Wind Torrent (W)", windTorrentUI.button.x + 5, windTorrentUI.button.y + 8)

    if windTorrentUI.active then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, logicalW, logicalH)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Select wind direction:", logicalW/2 - 80, 50)
        for dirName, dir in pairs(windTorrentUI.directions) do
            love.graphics.setColor(0.3, 0.5, 0.9, 0.9)
            love.graphics.rectangle("fill", dir.x, dir.y, 70, 30, 5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(dirName, dir.x + 25, dir.y + 8)
        end
        local cx, cy = logicalW/2 - 40, logicalH - 80
        love.graphics.setColor(0.8, 0.2, 0.2, 0.9)
        love.graphics.rectangle("fill", cx, cy, 80, 30, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Cancel (ESC)", cx + 5, cy + 8)
    end
end

-- Полоска глобального здоровья (ячейками)
function ui.drawGlobalHealthBar(globalHealth)
    local pipWidth = 16
    local pipHeight = 32
    local pipSpacing = 0
    local x = 10
    local y = 56
    local totalW = globalHealth.max * (pipWidth + pipSpacing) - pipSpacing
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Global Health:", x, y - 16)
    -- Рамка вокруг всех ячеек
    love.graphics.setColor(0.25, 0.25, 0.25, 0.8)
    love.graphics.rectangle("fill", x - 2, y - 2, totalW + 4, pipHeight + 4, 3)
    love.graphics.setColor(0.6, 0.6, 0.6, 0.9)
    love.graphics.rectangle("line", x - 2, y - 2, totalW + 4, pipHeight + 4, 3)
    for i = 0, globalHealth.max - 1 do
        local px = x + (pipWidth + pipSpacing) * i
        local py = y
        if i < globalHealth.current then
            love.graphics.setColor(0.9, 0.2, 0.15, 0.95)
            love.graphics.rectangle("fill", px, py, pipWidth, pipHeight)
        else
            love.graphics.setColor(0.15, 0.02, 0.02, 0.5)
            love.graphics.rectangle("fill", px, py, pipWidth, pipHeight)
        end
    end
    -- Вертикальные разделители между ячейками
    love.graphics.setColor(0.15, 0.15, 0.15, 0.8)
    for i = 1, globalHealth.max - 1 do
        local lx = x + (pipWidth + pipSpacing) * i - 1
        love.graphics.line(lx, y, lx, y + pipHeight)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(globalHealth.current .. "/" .. globalHealth.max, x + totalW + 8, y + pipHeight / 2 - 4)
end

-- Панель атак
function ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode)
    if not selectedActor or selectedActor.hasActedThisTurn then return end
    if #attackButtons == 0 then return end

    for i, btn in ipairs(attackButtons) do
        local isSelected = (selectedAttack == btn.attack and attackMode)
        love.graphics.setColor(isSelected and 0.9 or 0.3, 0.7, 0.3, 0.8)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 5)
        love.graphics.setColor(1, 1, 1, 1)
        local prefix = i .. "."
        love.graphics.print(prefix .. " " .. btn.name .. (isSelected and " ✓" or ""), btn.x + 5, btn.y + 8)
        if isSelected then
            love.graphics.setColor(1, 1, 0.5, 0.9)
            love.graphics.print(btn.desc, btn.x + 5, btn.y - 18)
        end
    end
end

function ui.drawEnemyOrderButton(mouseX, mouseY)
    local btnW, btnH = 100, 30
    local x = logicalW - btnW - 10
    local y = logicalH - btnH - 10
    local isHover = mouseX >= x and mouseX <= x + btnW and mouseY >= y and mouseY <= y + btnH

    love.graphics.setColor(isHover and 0.6 or 0.3, 0.4, 0.6, 0.8)
    love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Order (O)", x + 13, y + 8)

    return isHover
end

-- ui.lua (добавить в конец)

local function getTime()
    return love.timer.getTime()
end

function ui.drawFireOnHex(x, y, radius, time)
    local t = time * 5
    love.graphics.setBlendMode("add")
    for i = 1, 5 do
        local angle = (i / 5) * math.pi * 2 + t * 2
        local lenVar = 0.5 + 0.3 * math.sin(t * 3 + i)
        local height = radius * 0.6 * lenVar
        local width = radius * 0.3 * (0.7 + 0.3 * math.sin(t * 5 + i))
        
        local tipX = x + math.cos(angle) * width * 0.5
        local tipY = y - height * 0.8
        local baseLeftX = x + math.cos(angle - 0.3) * width
        local baseLeftY = y + math.sin(angle - 0.3) * width * 0.5
        local baseRightX = x + math.cos(angle + 0.3) * width
        local baseRightY = y + math.sin(angle + 0.3) * width * 0.5
        
        local rCol = 1
        local gCol = 0.3 + 0.7 * (lenVar - 0.5) * 2
        love.graphics.setColor(rCol, gCol, 0, 0.8)
        love.graphics.polygon("fill", tipX, tipY, baseLeftX, baseLeftY, baseRightX, baseRightY)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 0.6, 0, 0.9)
    love.graphics.circle("fill", x, y, radius * 0.2)
end

function ui.drawAcidOnHex(x, y, radius, time)
    local t = time * 2
    love.graphics.setColor(0.3, 0.8, 0.2, 0.7 + 0.3 * math.sin(t))
    love.graphics.circle("fill", x, y, radius * 0.4)
    for i = 1, 4 do
        local angle = (i * 1.5 + t) % (math.pi * 2)
        local bx = x + math.cos(angle) * radius * 0.5
        local by = y + math.sin(angle) * radius * 0.6
        local size = radius * 0.15 * (0.7 + 0.3 * math.sin(t * 3 + i))
        love.graphics.setColor(0.5, 0.9, 0.3, 0.8)
        love.graphics.circle("fill", bx, by, size)
    end
end

function ui.drawCellStatusEffects(x, y, radius, statuses, time)
    for _, st in ipairs(statuses) do
        if st == "fire" then
            ui.drawFireOnHex(x, y, radius, time)
        elseif st == "acid" then
            ui.drawAcidOnHex(x, y, radius, time)
        end
    end
end

-- ui.lua (новая функция)

function ui.drawUnitTooltip(entity, x, y, terrainMap)
    local bgColor = {0.1, 0.1, 0.2, 0.9}
    local borderColor = {0.8, 0.8, 0.8, 1}
    if entity.isPlayable then
        bgColor = {0.1, 0.2, 0.1, 0.9}
        borderColor = {0.4, 0.9, 0.4, 1}
    else
        bgColor = {0.2, 0.1, 0.1, 0.9}
        borderColor = {0.9, 0.4, 0.4, 1}
    end

    local statuses = status.getEntityStatuses(entity)
    local lineHeight = 16
    local titleHeight = 40
    local debuffsHeight = #statuses > 0 and (20 + #statuses * lineHeight) or 30
    local terrainHeight = 20
    local attackHeight = 0
    local attackText = nil
    
    -- Для врагов берём первую атаку
    if not entity.isPlayable and entity.attacks and #entity.attacks > 0 then
        attackHeight = 36  -- название + описание
        attackText = entity.attacks[1]
    end

    local prepareHeight = 0
    local prepareText = nil
    if entity.hasPreparedAttack and entity.preparePosCube and entity.preparedTargetCube then
        prepareHeight = 20
        local curX, curY, curZ = hex_utils.axialToCube(entity.q, entity.r)
        local deltaX = curX - entity.preparePosCube.x
        local deltaY = curY - entity.preparePosCube.y
        local deltaZ = curZ - entity.preparePosCube.z
        local targetX = entity.preparedTargetCube.x + deltaX
        local targetY = entity.preparedTargetCube.y + deltaY
        local targetZ = entity.preparedTargetCube.z + deltaZ
        local targetQ, targetR = hex_utils.cubeToAxial(targetX, targetY, targetZ)
        prepareText = string.format(" Prepares: (%d,%d) → (%d,%d) for 1 dmg", entity.q, entity.r, targetQ, targetR)
    end

    local panelWidth = 200
    local panelHeight = titleHeight + debuffsHeight + terrainHeight + attackHeight + prepareHeight

    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 8)
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 8)

    -- Имя и здоровье
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(entity.name, x + 8, y + 6)
    love.graphics.print(" " .. entity.health .. "/" .. entity.maxHealth, x + 8, y + 24)

    -- Дебаффы
    love.graphics.setColor(1, 0.8, 0.4, 1)
    love.graphics.print("Debuffs:", x + 8, y + 40)
    if #statuses == 0 then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print("None", x + 18, y + 58)
    else
        local iconMap = { fire = "Fire", acid = "Acid" }
        love.graphics.setColor(1, 0.9, 0.6, 1)
        for i, st in ipairs(statuses) do
            local text = iconMap[st] or st
            love.graphics.print(text, x + 18, y + 58 + (i-1) * lineHeight)
        end
    end

    -- Террейн
    local terrain = "grass"
    if terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] then
        terrain = terrainMap[entity.q][entity.r]
    end
    love.graphics.setColor(0.9, 0.9, 0.7, 1)
    love.graphics.print("Terrain: " .. terrain, x + 8, y + 40 + debuffsHeight)

    -- Добавить информацию о выкопке
    local hasDig = status.hasDigSite(entity.q, entity.r)
    if hasDig then
        local digSites = status.getAllDigSites()
        local digInfo = nil
        for _, site in ipairs(digSites) do
            if site.q == entity.q and site.r == entity.r then
                digInfo = site
                break
            end
        end
        if digInfo then
            love.graphics.setColor(0.8, 0.6, 0.2, 1)
            love.graphics.print("Under Dig Site", x + 8, y + 40 + debuffsHeight + terrainHeight)
            love.graphics.setColor(1, 0.9, 0.5, 1)
            love.graphics.print("Spawn in: " .. digInfo.timer .. " turn(s)", x + 18, y + 40 + debuffsHeight + terrainHeight + lineHeight)
            love.graphics.print("Age: " .. digInfo.age .. " / 3", x + 18, y + 40 + debuffsHeight + terrainHeight + lineHeight * 2)
        end
    end

    -- Атака врага (если есть)
    if attackText then
        love.graphics.setColor(0.9, 0.6, 0.3, 1)
        love.graphics.print(" " .. attackText.name, x + 8, y + 40 + debuffsHeight + terrainHeight)
        love.graphics.setColor(0.8, 0.8, 0.7, 1)
        love.graphics.print(attackText.description, x + 12, y + 56 + debuffsHeight + terrainHeight)
    end

    -- Подготовленная атака (если есть)
    if prepareText then
        love.graphics.setColor(1, 0.5, 0, 1)
        love.graphics.print(prepareText, x + 8, y + 40 + debuffsHeight + terrainHeight + attackHeight)
    end
end
function ui.drawTerrainOnlyTooltip(terrain, x, y)
    local panelWidth = 120
    local panelHeight = 30
    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 5)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Terrain: " .. terrain, x + 8, y + 8)
end



function ui.drawPreparedAttackDirection(hex, enemy, time, entities)
    if not enemy.hasPreparedAttack then return end
    local attack = enemy.preparedAttack
    if not attack then return end

    local fromQ = enemy.preparedFromQ or enemy.q
    local fromR = enemy.preparedFromR or enemy.r
    local fromX, fromY = getDrawCoords(fromQ, fromR)
    if not fromX then return end

    -- Ghost Bolt: первая цель на линии
if attack.name == "Ghost Bolt" then
    if enemy.attackDirection then
        local step = enemy.attackDirection
        local curQ, curR = enemy.q, enemy.r
        local lastValidQ, lastValidR = curQ, curR
        -- Идём по линии до неактивной клетки
        while true do
            local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
            if not hex:isActiveHex(nextQ, nextR) then
                break  -- дошли до неактивной клетки (выход за пределы шестиугольника)
            end
            -- Проверяем, есть ли живая цель (первая встреченная)
            local ent = getEntityAtHex(nextQ, nextR, entities)
            if ent and ent ~= enemy and ent.health > 0 then
                lastValidQ, lastValidR = nextQ, nextR
                break
            end
            lastValidQ, lastValidR = nextQ, nextR
            curQ, curR = nextQ, nextR
        end
        -- Если есть хоть одна клетка, не совпадающая с позицией врага
        if (lastValidQ ~= enemy.q or lastValidR ~= enemy.r) then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(lastValidQ, lastValidR)
            ui.drawDottedLine(fromX, fromY, toX, toY, 6, 25, time)
        end
    end
    return
end

if attack.name == "Magic Bolt" then
    if enemy.preparedTargetOffset then
        local targetQ, targetR = hex_utils.applyCubeDiff(
            enemy.q, enemy.r,
            enemy.preparedTargetOffset.dx,
            enemy.preparedTargetOffset.dy,
            enemy.preparedTargetOffset.dz
        )
        if hex:isActiveHex(targetQ, targetR) then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)

            local midX = (fromX + toX) / 2
            local midY = (fromY + toY) / 2

            ui.drawDottedArc(fromX, fromY, toX, toY, midX, midY - 60, 6, 25, time)
        end
    end
    return
end

    -- ===== Bite (Zombie) =====
    if attack.name == "Bite" then
        if enemy.preparedTargetOffset then
            local targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
            if hex:isActiveHex(targetQ, targetR) then
                local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
                local toX, toY = getDrawCoords(targetQ, targetR)
                -- Рисуем обычную стрелку
                local angle = math.atan2(toY - fromY, toX - fromX)
                local arrowSize = 18
                local lineWidth = 4
                local radius = hex.radius
                local offset = radius * 0.3

                local startX = fromX + math.cos(angle) * offset
                local startY = fromY + math.sin(angle) * offset
                local endX = toX - math.cos(angle) * offset
                local endY = toY - math.sin(angle) * offset

                local pulse = 0.5 + 0.5 * math.sin(time * 8)
                local alpha = 0.5 + 0.3 * pulse

                love.graphics.setLineWidth(lineWidth)
                love.graphics.setColor(1, 0.2, 0.2, alpha)
                love.graphics.line(startX, startY, endX, endY)

                local leftAngle = angle + math.pi * 0.7
                local rightAngle = angle - math.pi * 0.7
                love.graphics.line(endX, endY,
                    endX + math.cos(leftAngle) * arrowSize,
                    endY + math.sin(leftAngle) * arrowSize)
                love.graphics.line(endX, endY,
                    endX + math.cos(rightAngle) * arrowSize,
                    endY + math.sin(rightAngle) * arrowSize)

                love.graphics.setLineWidth(1)
            end
        end
        return
    end
    

    -- Для атак с направлением (Dash, Shoot, Piercing) – используем направление
    if enemy.attackDirection then
        local step = enemy.attackDirection
        local targetQ, targetR = hex_utils.applyCubeStep(enemy.q, enemy.r, step.dx, step.dy, step.dz)
        if hex:isValidHex(targetQ, targetR) then
            local toX, toY = getDrawCoords(targetQ, targetR)
            local angle = math.atan2(toY - fromY, toX - fromX)
            local arrowSize = 18
            local lineWidth = 4
            local radius = hex.radius
            local offset = radius * 0.3

            local startX = fromX + math.cos(angle) * offset
            local startY = fromY + math.sin(angle) * offset
            local endX = toX - math.cos(angle) * offset
            local endY = toY - math.sin(angle) * offset

            local pulse = 0.5 + 0.5 * math.sin(time * 8)
            local alpha = 0.5 + 0.3 * pulse

            love.graphics.setLineWidth(lineWidth)
            love.graphics.setColor(1, 0.2, 0.2, alpha)
            love.graphics.line(startX, startY, endX, endY)

            local leftAngle = angle + math.pi * 0.7
            local rightAngle = angle - math.pi * 0.7
            love.graphics.line(endX, endY,
                endX + math.cos(leftAngle) * arrowSize,
                endY + math.sin(leftAngle) * arrowSize)
            love.graphics.line(endX, endY,
                endX + math.cos(rightAngle) * arrowSize,
                endY + math.sin(rightAngle) * arrowSize)

            love.graphics.setLineWidth(1)
        end
    end
end

-- Предпросмотр Wind Torrent: рисует стрелки от каждого подвижного объекта к его новому положению
-- ui.lua
function ui.drawWindTorrentPreview(hex, direction, entities, terrainMap)
    local stepMap = {
        E  = {dx = 1, dy = -1, dz = 0},
        NE = {dx = 1, dy = 0, dz = -1},
        NW = {dx = 0, dy = 1, dz = -1},
        W  = {dx = -1, dy = 1, dz = 0},
        SW = {dx = -1, dy = 0, dz = 1},
        SE = {dx = 0, dy = -1, dz = 1},
    }
    local step = stepMap[direction]
    if not step then return end

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
    local function applyStep(q, r)
        local x, y, z = axialToCube(q, r)
        return cubeToAxial(x + step.dx, y + step.dy, z + step.dz)
    end
    local function isValid(q, r) return hex:isActiveHex(q, r) end

    -- Собираем подвижные объекты
    local movableObjects = {}
    for _, entity in ipairs(entities) do
        if entity.isPushable and entity.health > 0 then
            table.insert(movableObjects, entity)
        end
    end

    -- Сортировка по дальности
    table.sort(movableObjects, function(a, b)
        local function getProjection(obj)
            local x, y, z = axialToCube(obj.q, obj.r)
            return x * step.dx + y * step.dy + z * step.dz
        end
        return getProjection(a) > getProjection(b)
    end)

    -- Карта неподвижных объектов (здания, препятствия)
    local immovableMap = {}
    for _, entity in ipairs(entities) do
        if not entity.isPushable and entity.health > 0 then
            local key = entity.q .. "," .. entity.r
            immovableMap[key] = entity
        end
    end

    local targetMap = {}
    local previewData = {}
    local damagedEntities = {} -- { entity, damage, x, y }

    for _, obj in ipairs(movableObjects) do
        if obj.health <= 0 then goto continue end

        local newQ, newR = applyStep(obj.q, obj.r)
        local fromX, fromY = getDrawCoords(obj.q, obj.r)
        local toX, toY = getDrawCoords(newQ, newR)
        local damage = 0

        if not isValid(newQ, newR) then
            -- Вылет за край – урон только движущемуся
            damage = 1
            table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isEdge=true, entity=obj})
            table.insert(damagedEntities, {entity=obj, damage=damage, x=fromX, y=fromY})
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                -- Столкновение с неподвижным объектом – урон обоим
                damage = 1
                table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isCollision=true, entity=obj})
                table.insert(damagedEntities, {entity=obj, damage=damage, x=fromX, y=fromY})
                -- Добавляем урон для неподвижного объекта
                local immX, immY = getDrawCoords(immovableMap[immovableKey].q, immovableMap[immovableKey].r)
                table.insert(damagedEntities, {entity=immovableMap[immovableKey], damage=damage, x=immX, y=immY})
            else
                local targetOcc = targetMap[newQ .. "," .. newR]
                if targetOcc then
                    -- Столкновение двух подвижных – урон обоим
                    damage = 1
                    table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isCollision=true, doubleDamage=true, entity=obj, with=targetOcc})
                    table.insert(damagedEntities, {entity=obj, damage=damage, x=fromX, y=fromY})
                    local otherX, otherY = getDrawCoords(targetOcc.q, targetOcc.r)
                    table.insert(damagedEntities, {entity=targetOcc, damage=damage, x=otherX, y=otherY})
                else
                    -- Свободное перемещение
                    targetMap[newQ .. "," .. newR] = obj
                    table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=0, entity=obj})
                end
            end
        end
        ::continue::
    end

    -- Отрисовка стрелок
    for _, pd in ipairs(previewData) do
        ui.drawPushArrow(pd.fromX, pd.fromY, pd.toX, pd.toY)
    end

    -- Отрисовка мигающих полосок здоровья для всех, кто получит урон
    for _, dmg in ipairs(damagedEntities) do
        if dmg.entity and dmg.entity.health > 0 then
            drawHealthBar(dmg.entity, dmg.x, dmg.y, dmg.damage)
        end
    end

    -- Подсветка клеток назначения
    for _, pd in ipairs(previewData) do
        local q, r = hex:pixelToHex(pd.toX, pd.toY)
        if hex:isValidHex(q, r) then
            local vertices = hex:drawHexagon(pd.toX, pd.toY, hex.radius)
            love.graphics.setColor(0.3, 0.6, 1, 0.4)
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(0.3, 0.6, 1, 0.8)
            love.graphics.polygon("line", vertices)
        end
    end
end

function ui.drawWindTorrentButton(windTorrent, windTorrentUI, turnState)
    local available = (turnState.phase == "player" and windTorrent and not windTorrent.hasBeenUsed)
    love.graphics.setColor(available and 0.2 or 0.5, 0.6, 0.8, 0.8)
    love.graphics.rectangle("fill", windTorrentUI.button.x, windTorrentUI.button.y, windTorrentUI.button.width, windTorrentUI.button.height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Wind Torrent (W)", windTorrentUI.button.x + 5, windTorrentUI.button.y + 8)
end

function ui.drawRestartButton(button, turnState)
    local canRestart = (turnState.phase == "player") or true  -- можно в любой момент
    love.graphics.setColor(0.4, 0.2, 0.6, 0.8)
    love.graphics.rectangle("fill", button.x, button.y, button.width, button.height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(button.text .. " (R)", button.x + 10, button.y + 8)
end

-- ui.lua
function ui.drawCellTooltip(q, r, terrain, hex)
    local panelX = 10
    local panelY = logicalH - 130  -- чуть выше, чтобы поместить строку выкопки
    local statuses = status.getAtHex(q, r)
    local hasDig = status.hasDigSite(q, r)
    local digInfo = nil
    if hasDig then
        local digSites = status.getAllDigSites()
        for _, site in ipairs(digSites) do
            if site.q == q and site.r == r then
                digInfo = site
                break
            end
        end
    end
    
    local lineHeight = 16
    local titleHeight = 30
    local statusHeight = #statuses > 0 and (20 + #statuses * lineHeight) or 0
    local digHeight = hasDig and 40 or 0
    local panelWidth = 200
    local panelHeight = titleHeight + statusHeight + digHeight

    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", panelX, panelY, panelWidth, panelHeight, 5)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.rectangle("line", panelX, panelY, panelWidth, panelHeight, 5)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Terrain: " .. terrain, panelX + 8, panelY + 6)

    if #statuses > 0 then
        love.graphics.setColor(1, 0.8, 0.4, 1)
        love.graphics.print("Statuses:", panelX + 8, panelY + 28)
        local iconMap = { fire = "Fire", acid = "Acid" }
        love.graphics.setColor(1, 0.9, 0.6, 1)
        for i, st in ipairs(statuses) do
            local text = iconMap[st] or st
            love.graphics.print(text, panelX + 18, panelY + 28 + i * lineHeight)
        end
    end

    if hasDig and digInfo then
        local yOffset = titleHeight + statusHeight + 8
        love.graphics.setColor(0.8, 0.6, 0.2, 1)
        love.graphics.print("Dig Site", panelX + 8, panelY + yOffset)
        love.graphics.setColor(1, 0.9, 0.5, 1)
        love.graphics.print("Spawn in: " .. digInfo.timer .. " turn(s)", panelX + 18, panelY + yOffset + lineHeight)
        love.graphics.print("Age: " .. digInfo.age .. " / 3", panelX + 18, panelY + yOffset + lineHeight * 2)
    end
end

-- ui.lua
function ui.drawEnemyMovementRange(hex, enemy, entities, terrainMap)
    if not enemy or enemy.isPlayable or not enemy:isCharacter() or enemy.health <= 0 then return end
    if enemy.hasActedThisTurn or enemy.isMoving then return end

    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) and ui.isCellReachableForEnemy(enemy, q, r, entities, terrainMap, hex) then
                local terrainType = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                local yOffset = (terrainType == "water") and 12 or 0
                local x, y = getDrawCoords(q, r)
                local vertices = hex:drawHexagon(x, y + yOffset, hex.radius)
                love.graphics.setColor(0.8, 0.2, 0.2, 0.2)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.8, 0.2, 0.2, 0.5)
                love.graphics.polygon("line", vertices)
            end
        end
    end
end

function ui.isCellReachableForEnemy(enemy, targetQ, targetR, entities, terrainMap, hex)
    if not hex:isActiveHex(targetQ, targetR) then return false end
    if terrainMap and terrainMap[targetQ] and terrainMap[targetQ][targetR] == "water" then
        return false
    end
    -- Клетка не должна быть занята (союзником или врагом)
    for _, e in ipairs(entities) do
        if e ~= enemy and e.q == targetQ and e.r == targetR then
            return false
        end
    end
    local path = pathfinding.findPath(enemy.q, enemy.r, targetQ, targetR, enemy.moveRange,
        function(q, r) return not isCellPassableForEnemy(q, r, enemy, entities, terrainMap, hex) end, hex)
    return path ~= nil and #path > 0
end

function isCellPassableForEnemy(q, r, enemy, entities, terrainMap, hex)
    if not hex:isActiveHex(q, r) then return false end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then return false end
    for _, e in ipairs(entities) do
        if e ~= enemy and e.q == q and e.r == r then
            return false  -- любые сущности (союзники, другие враги, здания) блокируют путь
        end
    end
    return true
end

function ui.drawLichDoubleArrow(fromX, fromY, toX, toY, time)
    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.1 then return end

    local diveX = fromX + dx * 0.33
    local diveY = fromY + dy * 0.33 + 35
    local riseX = fromX + dx * 0.66
    local riseY = fromY + dy * 0.66 - 35
    local pulse = 0.6 + 0.4 * math.sin(time * 6)
    local alpha = 0.6 + 0.4 * pulse

    -- ===== 1. Стрелка от Лича к точке заныривания =====
    local function drawArrow(ax, ay, bx, by, a)
        local angle = math.atan2(by - ay, bx - ax)
        love.graphics.setLineWidth(4)
        love.graphics.setColor(0.7, 0.2, 1, a)
        love.graphics.line(ax, ay, bx, by)

        local arrowSize = 18
        local leftAngle = angle + math.pi * 0.7
        local rightAngle = angle - math.pi * 0.7
        love.graphics.line(bx, by,
            bx + math.cos(leftAngle) * arrowSize,
            by + math.sin(leftAngle) * arrowSize)
        love.graphics.line(bx, by,
            bx + math.cos(rightAngle) * arrowSize,
            by + math.sin(rightAngle) * arrowSize)
    end

    drawArrow(fromX, fromY, diveX, diveY, alpha)

    -- ===== 2. Эффект "заныривания" (земля разрывается) =====
    love.graphics.setColor(0.5, 0.2, 0.8, alpha * 0.9)
    love.graphics.circle("fill", diveX, diveY, 14)
    love.graphics.setColor(0.9, 0.4, 1, alpha)
    love.graphics.circle("line", diveX, diveY, 18)
    -- Искры
    for i = 1, 5 do
        local angleOff = time * 12 + i
        local offX = math.cos(angleOff) * 12 * pulse
        local offY = math.sin(angleOff) * 8 * pulse
        love.graphics.setColor(1, 0.5, 1, alpha)
        love.graphics.circle("fill", diveX + offX, diveY + offY, 3)
    end

    -- ===== 3. Подземный путь (волнообразные точки) =====
    local numDots = 10
    for i = 1, numDots do
        local t = i / numDots
        local px = diveX + (riseX - diveX) * t
        local py = diveY + (riseY - diveY) * t + math.sin(t * math.pi * 3) * 12
        local dotSize = 6 * (0.4 + 0.6 * math.sin(time * 10 + i))
        love.graphics.setColor(0.4, 0.1, 0.7, alpha * 0.7)
        love.graphics.circle("fill", px, py, dotSize)
        love.graphics.setColor(0.8, 0.3, 1, alpha * 0.5)
        love.graphics.circle("line", px, py, dotSize + 2)
    end

    -- ===== 4. Стрелка от точки выныривания к цели =====
    drawArrow(riseX, riseY, toX, toY, alpha)

    -- ===== 5. Эффект "выныривания" (всплеск магии) =====
    love.graphics.setColor(0.8, 0.3, 1, alpha * 0.9)
    love.graphics.circle("fill", riseX, riseY, 14)
    love.graphics.setColor(1, 0.6, 1, alpha)
    love.graphics.circle("line", riseX, riseY, 18)
    for i = 1, 5 do
        local angleOff = time * 12 + i
        local offX = math.cos(angleOff) * 10 * pulse
        local offY = math.sin(angleOff) * 10 * pulse
        love.graphics.setColor(1, 0.4, 1, alpha)
        love.graphics.circle("fill", riseX + offX, riseY + offY, 3)
    end

    love.graphics.setLineWidth(1)
end

-- ui.lua, функция drawDigSites
function ui.drawDigSites(hex, digSites)
    local time = love.timer.getTime()
    for _, site in ipairs(digSites) do
        local x, y = getDrawCoords(site.q, site.r)
        local radius = hex.radius
        -- Тень ямы
        love.graphics.setColor(0.2, 0.1, 0.05, 0.9)
        love.graphics.circle("fill", x, y, radius * 0.45)
        -- Внутренность ямы (темно-коричневая)
        love.graphics.setColor(0.4, 0.2, 0.1, 0.9)
        love.graphics.circle("fill", x, y, radius * 0.4)
        -- Пульсирующая земля по краям
        local pulse = 0.5 + 0.5 * math.sin(time * 5)
        love.graphics.setColor(0.7, 0.4, 0.1, 0.7 + pulse * 0.3)
        love.graphics.circle("line", x, y, radius * 0.42)
        -- "Земляные" точки вокруг
        for i = 1, 6 do
            local angle = (i / 6) * math.pi * 2 + time * 3
            local dx = math.cos(angle) * radius * 0.5
            local dy = math.sin(angle) * radius * 0.4
            love.graphics.setColor(0.5, 0.3, 0.1, 0.8)
            love.graphics.circle("fill", x + dx, y + dy, 3)
        end
        -- Таймер (количество ходов до спавна) если >1
        if site.timer > 1 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(tostring(site.timer), x + 10, y - 14)
        end
        -- Отображение возраста (для дебага)
        -- love.graphics.print(site.age, x + 15, y + 5)
    end
end

-- ============================================================
-- Функция рисования пунктирной прямой (с тенью)
-- ============================================================
function ui.drawDottedLine(x1, y1, x2, y2, dotRadius, step, time)
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx*dx + dy*dy)
    if length < 0.1 then return end
    local dirX = dx / length
    local dirY = dy / length

    local numDots = math.floor(length / step)
    if numDots < 1 then numDots = 1 end

    for i = 0, numDots do
        local t = i / numDots
        local px = x1 + dx * t
        local py = y1 + dy * t
        local pulse = 0.6 + 0.4 * math.sin(time * 8 + i)
        local r = dotRadius * (0.7 + 0.3 * pulse)
        local alpha = 0.85 * pulse

        -- Тень
        love.graphics.setColor(0, 0, 0, 0.5 * alpha)
        love.graphics.circle("fill", px + 2, py + 2, r)

        -- Основная точка
        love.graphics.setColor(0.7, 0.3, 1, alpha)
        love.graphics.circle("fill", px, py, r)
        love.graphics.setColor(1, 0.8, 1, 0.9)
        love.graphics.circle("line", px, py, r + 2)
    end
end

function ui.drawDottedArc(x1, y1, x2, y2, cx, cy, dotRadius, step, time)
    local function bezier(t)
        local mt = 1 - t
        local x = mt*mt * x1 + 2*mt*t * cx + t*t * x2
        local y = mt*mt * y1 + 2*mt*t * cy + t*t * y2
        return x, y
    end

    -- Приблизительная длина дуги (грубая оценка)
    local mid1x, mid1y = bezier(0.5)
    local len = math.sqrt((x2-x1)^2 + (y2-y1)^2) + math.sqrt((mid1x-cx)^2 + (mid1y-cy)^2)*0.5
    local numDots = math.max(5, math.floor(len / step))
    if numDots < 1 then numDots = 1 end

    for i = 0, numDots do
        local t = i / numDots
        local px, py = bezier(t)
        local pulse = 0.6 + 0.4 * math.sin(time * 8 + i)
        local r = dotRadius * (0.7 + 0.3 * pulse)
        local alpha = 0.85 * pulse

        -- Тень
        love.graphics.setColor(0, 0, 0, 0.5 * alpha)
        love.graphics.circle("fill", px + 2, py + 2, r)

        -- Основная точка
        love.graphics.setColor(0.7, 0.2, 1, alpha)
        love.graphics.circle("fill", px, py, r)
        love.graphics.setColor(1, 0.5, 1, alpha * 0.9)
        love.graphics.circle("line", px, py, r + 2)
    end
end

function ui.drawAttackableCells(hex, attacker, attack, entities, terrainMap)
    if not attacker or not attack then return end
    if attacker.hasActedThisTurn then return end

    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if not hex:isActiveHex(q, r) then
                -- клетка неактивна, пропускаем
            else
                local dist = hex:getDistance(attacker.q, attacker.r, q, r)
                if dist <= attack.range then
                    local canApply = false

                    -- 1. Bite
                    if attack.name == "Bite" then
                        if dist == 1 then
                            local target = getEntityAtHex(q, r, entities)
                            if target and target:isCharacter() and not target.isPlayable then
                                canApply = true
                            end
                        end

                    -- 2. Flip
                    elseif attack.name == "Flip" then
                        if dist == 1 then
                            local target = getEntityAtHex(q, r, entities)
                            if target and target:isCharacter() and not target.isPlayable then
                                local pushCell = attack:getPushCell(attacker, q, r, hex, entities)
                                if pushCell and hex:isActiveHex(pushCell.q, pushCell.r) then
                                    local occupant = getEntityAtHex(pushCell.q, pushCell.r, entities)
                                    if not occupant then
                                        canApply = true
                                    end
                                end
                            end
                        end

                    -- 3. Stone Throw и Cone Blast
                    elseif attack.name == "Stone Throw" or attack.name == "Cone Blast" then
                        local minRange = attack.minRange or 1
                        if dist >= minRange then
                            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                            if stepX then
                                canApply = true
                            end
                        end

                    -- 4. Magic Bolt
                    elseif attack.name == "Magic Bolt" then
                        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                        if stepX then
                            local target = getEntityAtHex(q, r, entities)
                            if target and (target:isCharacter() and not target.isPlayable or target:isBuilding()) then
                                canApply = true
                            end
                        end

                    -- 5. Ghost Bolt, Shoot, Dash, Piercing Shot
                    elseif attack.name == "Ghost Bolt" or attack.name == "Shoot" or attack.name == "Dash" or attack.name == "Piercing Shot" then
                        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                        if stepX then
                            local firstTarget, _ = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                            if firstTarget then
                                canApply = true
                            end
                        end
                    end

                    if canApply then
                        local x, y = getDrawCoords(q, r)
                        local vertices = hex:drawHexagon(x, y, hex.radius)
                        love.graphics.setColor(0.9, 0.8, 0.2, 0.25)
                        love.graphics.polygon("fill", vertices)
                        love.graphics.setColor(0.9, 0.8, 0.2, 0.7)
                        love.graphics.polygon("line", vertices)
                    end
                end
            end
        end
    end
end

-- ======================================================
-- ВИЗУАЛЬНЫЕ ЭФФЕКТЫ СТАТУСОВ НА ЮНИТАХ (НЕ НА КЛЕТКАХ)
-- ======================================================

function ui.drawFireOnEntity(x, y, radius, time)
    local t = time * 8
    love.graphics.setBlendMode("add")
    -- Внешнее свечение
    for i = 1, 3 do
        local size = radius * (0.6 + 0.2 * math.sin(t * 2 + i))
        love.graphics.setColor(1, 0.3, 0, 0.2)
        love.graphics.circle("fill", x, y, size)
    end
    -- Языки пламени, вырывающиеся вверх
    for i = 1, 5 do
        local angle = -math.pi/2 + (i-2)*0.5 + math.sin(t*10+i)*0.3
        local len = radius * (0.5 + 0.2 * math.sin(t * 6 + i))
        local tipX = x + math.cos(angle) * len * 0.5
        local tipY = y + math.sin(angle) * len - radius * 0.3
        local baseX1 = x + math.cos(angle - 0.4) * (len * 0.3)
        local baseY1 = y + math.sin(angle - 0.4) * (len * 0.3)
        local baseX2 = x + math.cos(angle + 0.4) * (len * 0.3)
        local baseY2 = y + math.sin(angle + 0.4) * (len * 0.3)
        local rCol = 1
        local gCol = 0.3 + 0.5 * (math.sin(t * 8 + i) * 0.5 + 0.5)
        love.graphics.setColor(rCol, gCol, 0, 0.9)
        love.graphics.polygon("fill", tipX, tipY, baseX1, baseY1, baseX2, baseY2)
    end
    -- Искры
    for i = 1, 4 do
        local sparkAngle = t * 15 + i * 1.2
        local dist = radius * 0.4
        local sparkX = x + math.cos(sparkAngle) * dist
        local sparkY = y - radius * 0.4 + math.sin(sparkAngle) * dist * 0.5
        love.graphics.setColor(1, 0.7, 0.1, 0.9)
        love.graphics.circle("fill", sparkX, sparkY, radius * 0.07)
    end
    love.graphics.setBlendMode("alpha")
end

function ui.drawAcidOnEntity(x, y, radius, time)
    local t = time * 3
    love.graphics.setBlendMode("add")
    -- Кислотная лужа под ногами
    love.graphics.setColor(0.3, 0.8, 0.2, 0.5)
    love.graphics.ellipse("fill", x, y + radius*0.2, radius*0.8, radius*0.3)
    -- Пузыри, поднимающиеся вверх
    for i = 1, 4 do
        local bubbleAngle = t * 4 + i * 1.5
        local dist = radius * 0.5 * math.sin(t * 3 + i)
        local bx = x + math.cos(bubbleAngle) * dist * 0.5
        local by = y - radius * 0.4 + math.sin(bubbleAngle) * dist * 0.3
        local size = radius * 0.1 * (0.6 + 0.4 * math.sin(t * 7 + i))
        love.graphics.setColor(0.4, 1, 0.2, 0.8)
        love.graphics.circle("fill", bx, by, size)
        love.graphics.setColor(0.8, 1, 0.4, 0.5)
        love.graphics.circle("line", bx, by, size * 1.2)
    end
    love.graphics.setBlendMode("alpha")
end

function ui.drawDecayOnEntity(x, y, radius, time)
    local t = time * 2
    love.graphics.setBlendMode("add")
    -- Гнилостное облако
    love.graphics.setColor(0.4, 0.1, 0.5, 0.6)
    love.graphics.circle("fill", x, y, radius * 0.9)
    love.graphics.setColor(0.2, 0.05, 0.3, 0.4)
    love.graphics.circle("fill", x, y, radius * 1.1)
    -- Вращающиеся тёмные частицы
    for i = 1, 6 do
        local angle = t * 2 + (i / 6) * math.pi * 2
        local rDist = radius * 0.5 + math.sin(t * 3 + i) * radius * 0.2
        local px = x + math.cos(angle) * rDist
        local py = y + math.sin(angle) * rDist * 0.6
        love.graphics.setColor(0.5, 0.2, 0.7, 0.7)
        love.graphics.circle("fill", px, py, radius * 0.08)
    end
    love.graphics.setBlendMode("alpha")
end

function ui.drawEntityStatusEffects(x, y, entity, radius, time)
    if not entity:isCharacter() then return end
    
    local statuses = status.getEntityStatuses(entity)
    if #statuses == 0 then return end
    
    -- Рисуем эффект наложением поверх спрайта (приоритет: fire > decay > acid)
    if status.hasEntityStatus(entity, "fire") then
        ui.drawFireOnEntity(x, y, radius, time)
    elseif status.hasEntityStatus(entity, "decay") then
        ui.drawDecayOnEntity(x, y, radius, time)
    elseif status.hasEntityStatus(entity, "acid") then
        ui.drawAcidOnEntity(x, y, radius, time)
    end
end

-- Возвращает цвет для мигания в зависимости от статусов (приоритет: fire > decay > acid)
function ui.getEntityStatusColor(entity, time)
    local statuses = status.getEntityStatuses(entity)
    if not statuses or #statuses == 0 then return nil end

    local pulse = 0.4 + 0.4 * math.sin(time * 8)  -- пульсация 0..0.8
    local color = nil

    -- Приоритет статусов
    if status.hasEntityStatus(entity, "fire") then
        color = {1, 0.2, 0.1, pulse}
    elseif status.hasEntityStatus(entity, "decay") then
        color = {0.6, 0.2, 0.8, pulse}
    elseif status.hasEntityStatus(entity, "acid") then
        color = {0.2, 0.9, 0.2, pulse}
    end

    return color
end

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ УПРАВЛЕНИЯ ВЫБОРОМ
-- ============================================================

function updateAttackButtons(actor)
    attackButtons = {}
    if not actor or not actor.attacks or #actor.attacks == 0 then
        return
    end
    local startX = logicalW - 160
    local startY = 100
    for i, attackInfo in ipairs(actor.attacks) do
        local btn = {
            x = startX,
            y = startY + (i-1) * 35,
            width = 150,
            height = 30,
            attack = attackInfo.attack,
            name = attackInfo.name,
            desc = attackInfo.description
        }
        table.insert(attackButtons, btn)
    end
end

function clearSelectedActor()
    selectedActor = nil
    hex.selectedQ = -1
    hex.selectedR = -1
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
end

function restoreSelectedActor()
    for _, a in ipairs(entities) do
        if a.isPlayable and a.health > 0 then
            selectedActor = a
            hex.selectedQ, hex.selectedR = a.q, a.r
            updateAttackButtons(selectedActor)
            break
        end
    end
end

return ui