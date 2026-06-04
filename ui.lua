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
    return hex:hexToPixel(entity.q, entity.r)
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
    local startX, startY = hex:hexToPixel(actor.q, actor.r)
    table.insert(points, {x = startX, y = startY})
    for _, step in ipairs(path) do
        local x, y = hex:hexToPixel(step.q, step.r)
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
function ui.drawPushArrow(fromX, fromY, toX, toY)
    local angle = math.atan2(toY - fromY, toX - fromX)
    local arrowSize = 18          -- размер наконечника
    local lineWidth = 4           -- толщина линии
    
    -- Смещаем начало и конец стрелки внутрь от центров (на 20% радиуса гекса)
    local radius = hex.radius      -- радиус гекса (56)
    local offset = radius * 0.3    -- отступ от центра (16.8)
    local startX = fromX + math.cos(angle) * offset
    local startY = fromY + math.sin(angle) * offset
    local endX = toX - math.cos(angle) * offset
    local endY = toY - math.sin(angle) * offset
    
    love.graphics.setLineWidth(lineWidth)
    love.graphics.setColor(1, 0.8, 0.2, 0.9)
    
    -- Линия
    love.graphics.line(startX, startY, endX, endY)
    
    -- Наконечник
    local leftAngle = angle + math.pi * 0.7
    local rightAngle = angle - math.pi * 0.7
    love.graphics.line(endX, endY,
        endX + math.cos(leftAngle) * arrowSize,
        endY + math.sin(leftAngle) * arrowSize)
    love.graphics.line(endX, endY,
        endX + math.cos(rightAngle) * arrowSize,
        endY + math.sin(rightAngle) * arrowSize)
    
    love.graphics.setLineWidth(1)  -- сброс
end

-- Нарисовать значок урона
function ui.drawDamageIcon(x, y, damage)
    love.graphics.setColor(1, 0.2, 0.2, 1)
    love.graphics.circle("fill", x, y, 12)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(tostring(damage), x - 4, y - 6)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.print("⚔", x - 20, y - 8)
end

-- Нарисовать значок столкновения
function ui.drawCollisionIcon(x, y, damage, isDouble)
    love.graphics.setColor(0.8, 0.4, 0, 1)
    love.graphics.circle("fill", x, y, 12)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("💥", x - 8, y - 8)
    if damage and damage > 0 then
        love.graphics.print(tostring(damage), x + 8, y - 6)
    end
end

-- ============================================================
-- ОСНОВНЫЕ UI-ФУНКЦИИ, ВЫЗЫВАЕМЫЕ ИЗ MAIN.LUA
-- ============================================================

-- ui.lua, заменить существующую функцию drawPreparedAttacks

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
                local x, y = hex:hexToPixel(targetCell.q, targetCell.r)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.stencil(function()
                    love.graphics.polygon("fill", vertices)
                end, "replace", 1)
                love.graphics.setStencilTest("greater", 0)
                local tex = getHazardTexture()
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(tex, x - hex.radius, y - hex.radius, 0,
                                   hex.radius * 2 / tex:getWidth(),
                                   hex.radius * 2 / tex:getHeight())
                love.graphics.setStencilTest()
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print("⚔", x - 6, y - 8)
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
                local fromX, fromY = hex:hexToPixel(target.q, target.r)
                local vertices = hex:drawHexagon(fromX, fromY, hex.radius)
                love.graphics.setColor(1, 0.5, 0, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.7, 0, 0.8)
                love.graphics.polygon("line", vertices)
                -- Стрелка переворота
                local toX, toY = hex:hexToPixel(pushCell.q, pushCell.r)
                ui.drawPushArrow(fromX, fromY, toX, toY)
                return
            end
        end
    end
    -- Если цель вне радиуса 1 – ничего не рисуем
    return
end

-- Ghost Bolt
if attack.name == "Ghost Bolt" then
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if stepX then
        local firstTarget, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
        if firstTarget and targetHex then
            local x, y = hex:hexToPixel(targetHex.q, targetHex.r)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            love.graphics.setColor(0.6, 0.2, 0.8, 0.3)
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(0.8, 0.4, 1, 0.8)
            love.graphics.polygon("line", vertices)
            ui.drawDamageIcon(x + 20, y - 20, attack.damage)
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
            local x, y = hex:hexToPixel(hoverQ, hoverR)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            love.graphics.setColor(0.8, 0.2, 0.2, 0.3)
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(1, 0.4, 0.4, 0.8)
            love.graphics.polygon("line", vertices)
            ui.drawDamageIcon(x + 20, y - 20, attack.damage)
        end
    end
    return
end

if attack.name == "Magic Bolt" then
    local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if distance <= attack.range then
        -- Добавить проверку прямой линии
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then
                local x, y = hex:hexToPixel(hoverQ, hoverR)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.setColor(0.8, 0.2, 0.8, 0.3)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.9, 0.3, 0.9, 0.8)
                love.graphics.polygon("line", vertices)
                ui.drawDamageIcon(x + 20, y - 20, attack.damage or 1)
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
            local fromX, fromY = hex:hexToPixel(attacker.q, attacker.r)
            local toX, toY = hex:hexToPixel(lastFree.q, lastFree.r)
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

        -- Урон по первой цели
        if firstTarget then
            local targetX, targetY = hex:hexToPixel(firstTarget.q, firstTarget.r)
            ui.drawDamageIcon(targetX + 20, targetY - 20, attack.damage or 1)
            
            -- Проверяем возможность отталкивания
            if targetHex then
                local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
                if hex:isActiveHex(pushQ, pushR) and not combat.getEntityAtHex(pushQ, pushR, entities) then
                    local pushX, pushY = hex:hexToPixel(pushQ, pushR)
                    ui.drawPushArrow(targetX, targetY, pushX, pushY)
                else
                    -- Отображаем, что отталкивание невозможно
                    local blockX, blockY = hex:hexToPixel(pushQ, pushR)
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

    -- Dash, Shoot, Flip (одиночные цели с одним отталкиванием)
    if attack.getPushCell then
        local pushCell = attack:getPushCell(attacker, hoverQ, hoverR, hex, entities)
        if pushCell then
            local firstTarget = nil
            -- Находим первую цель на линии (аналогично execute)
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
                -- Для Flip и др., где цель просто в радиусе 1
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
                -- Дополнительно для PiercingShoot (две цели)
                if attack.getPushCells then
                    local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
                    if #pushCells >= 2 then
                        -- Найдём две цели (вторая цель получает урон)
                        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
                        if stepX then
                            local _, _, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                            if secondTarget then
                                table.insert(previewData, {
                                    target = secondTarget,
                                    fromCell = {q = secondTarget.q, r = secondTarget.r},
                                    pushTo = pushCells[2],
                                    attackDamage = 1, -- Piercing наносит урон только второй цели
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
                        attackDamage = 0,      -- Piercing не наносит урон первой цели
                    })
                end
                if secondTarget and secondHex and #pushCells >= 2 then
                    table.insert(previewData, {
                        target = secondTarget,
                        fromCell = {q = secondHex.q, r = secondHex.r},
                        pushTo = pushCells[2],
                        attackDamage = 1,      -- вторая цель получает 1 урон
                    })
                end
            end
        end
    end

    -- AoePushAttack (Stone Throw) – отталкивает всех врагов вокруг целевой клетки
    if attack.getPushCells and not previewData then
        local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
        if #pushCells > 0 then
            previewData = {}
            -- Собираем все цели вокруг
            local neighbors = hex:getNeighbors(hoverQ, hoverR)
            for i, neighbor in ipairs(neighbors) do
                local target = getEntityAtHex(neighbor.q, neighbor.r, entities)
                if target and target:isCharacter() and not target.isPlayable then
                    table.insert(previewData, {
                        target = target,
                        fromCell = {q = target.q, r = target.r},
                        pushTo = pushCells[i] or {q = target.q, r = target.r},
                        attackDamage = 0,
                    })
                end
            end
        end
    end

    -- AoeDirectionalAttack (Cone Blast) – урон центру, отталкивание трёх соседей
    if attack.getPushCells and not previewData and attack.getNeighborsInDirection then
        local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
        if #pushCells > 0 then
            previewData = {}
            -- Центровая цель (получает урон)
            local centerTarget = getEntityAtHex(hoverQ, hoverR, entities)
            if centerTarget then
                table.insert(previewData, {
                    target = centerTarget,
                    fromCell = {q = hoverQ, r = hoverR},
                    pushTo = nil,
                    attackDamage = 1,
                })
            end
            -- Три отталкиваемые цели
            local neighbors = attack:getNeighborsInDirection(hoverQ, hoverR, hoverQ - attacker.q, hoverR - attacker.r, hex)
            for i, neighbor in ipairs(neighbors) do
                local target = getEntityAtHex(neighbor.q, neighbor.r, entities)
                if target then
                    table.insert(previewData, {
                        target = target,
                        fromCell = {q = target.q, r = target.r},
                        pushTo = pushCells[i] or neighbor,
                        attackDamage = 0,
                    })
                end
            end
        end
    end
    -- Если нет данных превью, выходим
    if not previewData or #previewData == 0 then
        return
    end

    -- Отрисовка для каждой цели
    for _, pd in ipairs(previewData) do
        local target = pd.target
        if target and target.health > 0 then
            local fromX, fromY = hex:hexToPixel(pd.fromCell.q, pd.fromCell.r)
            -- Подсветка исходной клетки цели
            local vertices = hex:drawHexagon(fromX, fromY, hex.radius)
            love.graphics.setColor(1, 0.5, 0, 0.3)
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(1, 0.7, 0, 0.8)
            love.graphics.polygon("line", vertices)

            -- Урон от атаки
            if pd.attackDamage > 0 then
                ui.drawDamageIcon(fromX + 20, fromY - 20, pd.attackDamage)
            end

            -- Отталкивание
            if pd.pushTo then
                local toX, toY = hex:hexToPixel(pd.pushTo.q, pd.pushTo.r)
                ui.drawPushArrow(fromX, fromY, toX, toY)

                -- Проверяем столкновение
                local collisionDamage, reason, second = ui.checkCollisionDamage(
                    target, pd.fromCell.q, pd.fromCell.r,
                    pd.pushTo.q, pd.pushTo.r, hex, entities
                )
                if collisionDamage > 0 then
                    local crashX, crashY = toX, toY
                    if reason == "collision_both" and second then
                        -- Показать урон обоим
                        local secX, secY = hex:hexToPixel(second.q, second.r)
                        ui.drawCollisionIcon(secX, secY, 1, true)
                        ui.drawCollisionIcon(crashX, crashY, 1, true)
                    elseif reason == "collision_immovable" then
                        ui.drawCollisionIcon(crashX, crashY, 1, false)
                    elseif reason == "edge" then
                        ui.drawCollisionIcon(crashX, crashY, 1, false)
                    end
                end
            end
        end
    end

    -- Дополнительно подсветить клетку, куда бьём (только для атак с направлением)
    if attack.getLineDirection then
        local x, y = hex:hexToPixel(hoverQ, hoverR)
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
            if hex:isActiveHex(q, r) then
                -- Используем isCellReachable для проверки достижимости
                if ui.isCellReachable(actor, q, r, entities, terrainMap, hex) then
                    local x, y = hex:hexToPixel(q, r)
                    local vertices = hex:drawHexagon(x, y, hex.radius)
                    love.graphics.setColor(0.2, 0.8, 0.2, 0.2)
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
                    love.graphics.polygon("line", vertices)
                end
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
    love.graphics.print("🌬️ Wind Torrent", windTorrentUI.button.x + 5, windTorrentUI.button.y + 8)

    if windTorrentUI.active then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Select wind direction:", love.graphics.getWidth()/2 - 80, 50)
        for dirName, dir in pairs(windTorrentUI.directions) do
            love.graphics.setColor(0.3, 0.5, 0.9, 0.9)
            love.graphics.rectangle("fill", dir.x, dir.y, 70, 30, 5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(dirName, dir.x + 25, dir.y + 8)
        end
        local cx, cy = love.graphics.getWidth()/2 - 40, love.graphics.getHeight() - 80
        love.graphics.setColor(0.8, 0.2, 0.2, 0.9)
        love.graphics.rectangle("fill", cx, cy, 80, 30, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Cancel", cx + 15, cy + 8)
    end
end

-- Полоска глобального здоровья
function ui.drawGlobalHealthBar(globalHealth)
    local barWidth = 200
    local barHeight = 20
    local x = 10   -- была 10 – это левый край
    local y = 60   -- чуть ниже, чтобы не мешать другим кнопкам (Undo, End Turn)
    love.graphics.setColor(0.5, 0, 0, 0.8)
    love.graphics.rectangle("fill", x, y, barWidth, barHeight, 5)
    local percent = globalHealth.current / globalHealth.max
    love.graphics.setColor(0.8, 0.2, 0.2, 0.9)
    love.graphics.rectangle("fill", x, y, barWidth * percent, barHeight, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Global Health: " .. globalHealth.current .. "/" .. globalHealth.max, x + 5, y + 4)
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
        love.graphics.print(btn.name .. (isSelected and " ✓" or ""), btn.x + 5, btn.y + 8)
        if isSelected then
            love.graphics.setColor(1, 1, 0.5, 0.9)
            love.graphics.print(btn.desc, btn.x + 5, btn.y - 18)
        end
    end
end

function ui.drawEnemyOrderButton(mouseX, mouseY)
    local btnW, btnH = 100, 30
    local x = love.graphics.getWidth() - btnW - 10
    local y = love.graphics.getHeight() - btnH - 10
    local isHover = mouseX >= x and mouseX <= x + btnW and mouseY >= y and mouseY <= y + btnH

    love.graphics.setColor(isHover and 0.6 or 0.3, 0.4, 0.6, 0.8)
    love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Order (hover)", x + 8, y + 8)

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

function ui.drawEntityStatusEffects(x, y, statuses, baseSize, time)
    for i, st in ipairs(statuses) do
        local offsetX = -baseSize * 0.6 + i * baseSize * 0.4
        local offsetY = -baseSize * 0.8
        if st == "fire" then
            ui.drawFireOnHex(x + offsetX, y + offsetY, baseSize * 0.4, time)
        elseif st == "acid" then
            ui.drawAcidOnHex(x + offsetX, y + offsetY, baseSize * 0.35, time)
        elseif st == "decay" then
            love.graphics.setColor(0.3, 0.8, 0.2, 0.9)
            love.graphics.circle("fill", x + offsetX, y + offsetY, baseSize * 0.3)
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.print("☠", x + offsetX - 5, y + offsetY - 6)
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
        prepareText = string.format("⚔ Prepares: (%d,%d) → (%d,%d) for 1 dmg", entity.q, entity.r, targetQ, targetR)
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
    love.graphics.print("❤️ " .. entity.health .. "/" .. entity.maxHealth, x + 8, y + 24)

    -- Дебаффы
    love.graphics.setColor(1, 0.8, 0.4, 1)
    love.graphics.print("💀 Debuffs:", x + 8, y + 40)
    if #statuses == 0 then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print("None", x + 18, y + 58)
    else
        local iconMap = { fire = "🔥 Fire", acid = "🧪 Acid" }
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
            love.graphics.print("🕳️ Under Dig Site", x + 8, y + 40 + debuffsHeight + terrainHeight)
            love.graphics.setColor(1, 0.9, 0.5, 1)
            love.graphics.print("Spawn in: " .. digInfo.timer .. " turn(s)", x + 18, y + 40 + debuffsHeight + terrainHeight + lineHeight)
            love.graphics.print("Age: " .. digInfo.age .. " / 3", x + 18, y + 40 + debuffsHeight + terrainHeight + lineHeight * 2)
        end
    end

    -- Атака врага (если есть)
    if attackText then
        love.graphics.setColor(0.9, 0.6, 0.3, 1)
        love.graphics.print("⚔ " .. attackText.name, x + 8, y + 40 + debuffsHeight + terrainHeight)
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
    local fromX, fromY = hex:hexToPixel(fromQ, fromR)
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
            local fromX, fromY = hex:hexToPixel(enemy.q, enemy.r)
            local toX, toY = hex:hexToPixel(lastValidQ, lastValidR)
            ui.drawDottedLine(fromX, fromY, toX, toY, 6, 25, time)
        end
    end
    return
end

    -- ===== Magic Bolt (Lich) =====
    if attack.name == "Magic Bolt" then
        if enemy.preparedTargetOffset then
            local targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
            if hex:isActiveHex(targetQ, targetR) then
                local fromX, fromY = hex:hexToPixel(enemy.q, enemy.r)
                local toX, toY = hex:hexToPixel(targetQ, targetR)
                ui.drawLichDoubleArrow(fromX, fromY, toX, toY, time)
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
                local fromX, fromY = hex:hexToPixel(enemy.q, enemy.r)
                local toX, toY = hex:hexToPixel(targetQ, targetR)
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
            local toX, toY = hex:hexToPixel(targetQ, targetR)
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

-- ui.lua (добавить в конец файла, перед return ui)

-- Рисует пунктирную линию из больших пульсирующих кружков
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
        love.graphics.setColor(0.7, 0.3, 1, 0.85 * pulse)
        love.graphics.circle("fill", px, py, r)
        love.graphics.setColor(1, 0.8, 1, 0.9)
        love.graphics.circle("line", px, py, r + 2)
    end
end

-- Предпросмотр Wind Torrent: рисует стрелки от каждого подвижного объекта к его новому положению
function ui.drawWindTorrentPreview(hex, direction, entities, terrainMap)
    -- Копируем логику из combat.WindTorrentAttack:executeGlobalWithAnimation
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
        if entity.isPushable then
            table.insert(movableObjects, entity)
        end
    end

    -- Сортировка по дальности вдоль направления (чтобы имитировать порядок обработки)
    table.sort(movableObjects, function(a, b)
        local function getProjection(obj)
            local x, y, z = axialToCube(obj.q, obj.r)
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

    -- Карта занятости для предпросмотра
    local targetMap = {}
    local previewData = {} -- { fromX, fromY, toX, toY, damage, collisionWith }

    for _, obj in ipairs(movableObjects) do
        local newQ, newR = applyStep(obj.q, obj.r)
        local fromX, fromY = hex:hexToPixel(obj.q, obj.r)
        local toX, toY = hex:hexToPixel(newQ, newR)
        local damage = 0
        local collisionTarget = nil

        if not isValid(newQ, newR) then
            -- Вылет за край
            damage = 1
            -- рисуем стрелку до края (toX,toY) уже за пределами? можно до границы карты, но проще нарисовать стрелку до ближайшей точки
            table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isEdge=true})
        else
            -- Проверка неподвижного объекта
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                damage = 1
                table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isCollision=true})
            else
                -- Проверка коллизии с другим подвижным (уже обработанным)
                local key = newQ .. "," .. newR
                if targetMap[key] then
                    -- Столкновение двух подвижных
                    damage = 1
                    collisionTarget = targetMap[key]
                    table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isCollision=true, doubleDamage=true})
                    -- Добавляем также урон для уже записанного объекта (добавим позже)
                else
                    targetMap[key] = obj
                    table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=0})
                end
            end
        end
    end

    -- Рисуем стрелки и иконки урона
    for _, pd in ipairs(previewData) do
        ui.drawPushArrow(pd.fromX, pd.fromY, pd.toX, pd.toY)
        if pd.damage > 0 then
            if pd.isEdge then
                ui.drawCollisionIcon(pd.toX, pd.toY, 1, false)
            elseif pd.isCollision then
                ui.drawCollisionIcon(pd.toX, pd.toY, 1, pd.doubleDamage or false)
            end
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
    love.graphics.print("🌬️ Wind Torrent", windTorrentUI.button.x + 5, windTorrentUI.button.y + 8)
end

function ui.drawRestartButton(button, turnState)
    local canRestart = (turnState.phase == "player") or true  -- можно в любой момент
    love.graphics.setColor(0.4, 0.2, 0.6, 0.8)
    love.graphics.rectangle("fill", button.x, button.y, button.width, button.height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(button.text, button.x + 15, button.y + 8)
end

-- ui.lua
function ui.drawCellTooltip(q, r, terrain, hex)
    local panelX = 10
    local panelY = love.graphics.getHeight() - 130  -- чуть выше, чтобы поместить строку выкопки
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
        local iconMap = { fire = "🔥 Fire", acid = "🧪 Acid" }
        love.graphics.setColor(1, 0.9, 0.6, 1)
        for i, st in ipairs(statuses) do
            local text = iconMap[st] or st
            love.graphics.print(text, panelX + 18, panelY + 28 + i * lineHeight)
        end
    end

    if hasDig and digInfo then
        local yOffset = titleHeight + statusHeight + 8
        love.graphics.setColor(0.8, 0.6, 0.2, 1)
        love.graphics.print("🕳️ Dig Site", panelX + 8, panelY + yOffset)
        love.graphics.setColor(1, 0.9, 0.5, 1)
        love.graphics.print("Spawn in: " .. digInfo.timer .. " turn(s)", panelX + 18, panelY + yOffset + lineHeight)
        love.graphics.print("Age: " .. digInfo.age .. " / 3", panelX + 18, panelY + yOffset + lineHeight * 2)
    end
end

-- ui.lua
function ui.drawEnemyMovementRange(hex, enemy, entities, terrainMap)
    if not enemy or enemy.isPlayable or not enemy:isCharacter() or enemy.health <= 0 then
        return
    end
    if enemy.hasActedThisTurn or enemy.isMoving then
        return
    end

    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) then
                -- Проверяем, может ли враг дойти до клетки
                if ui.isCellReachableForEnemy(enemy, q, r, entities, terrainMap, hex) then
                    local x, y = hex:hexToPixel(q, r)
                    local vertices = hex:drawHexagon(x, y, hex.radius)
                    love.graphics.setColor(0.8, 0.2, 0.2, 0.2)  -- красноватая подсветка
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(0.8, 0.2, 0.2, 0.5)
                    love.graphics.polygon("line", vertices)
                end
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
        local x, y = hex:hexToPixel(site.q, site.r)
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

return ui