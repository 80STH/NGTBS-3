-- ui.lua
-- Все функции интерфейса (кнопки, панели, предпросмотр атак, движения и т.д.)

local ui = {}
local pathfinding = require("pathfinding")
-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ПРЕДПРОСМОТРА АТАК
-- ============================================================

local hazardTexture = nil

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
        love.graphics.draw(actor.sprite, targetX, targetY, 0, 0.9, 0.9, sw/2, sh/2)
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

function ui.drawPreparedAttacks(hex, entities)
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.preparedTarget then
            local x, y = hex:hexToPixel(e.preparedTarget.q, e.preparedTarget.r)
            local radius = hex.radius
            local vertices = hex:drawHexagon(x, y, radius)
            
            -- Обрезаем текстуру по форме гекса
            love.graphics.stencil(function()
                love.graphics.polygon("fill", vertices)
            end, "replace", 1)
            love.graphics.setStencilTest("greater", 0)
            
            local tex = getHazardTexture()
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(tex, x - radius, y - radius, 0, 
                               radius * 2 / tex:getWidth(), 
                               radius * 2 / tex:getHeight())
            
            love.graphics.setStencilTest()
            
            -- Иконка атаки поверх
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("⚔", x - 6, y - 8)
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

    -- Flip – перемещение без урона
    if not previewData and attack.name == "Flip" then
        local target = getEntityAtHex(hoverQ, hoverR, entities)
        if target and hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR) == 1 then
            local pushCell = attack:getPushCell(attacker, hoverQ, hoverR, hex, entities)
            if pushCell then
                previewData = {{
                    target = target,
                    fromCell = {q = target.q, r = target.r},
                    pushTo = pushCell,
                    attackDamage = 0,
                }}
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
                local dist = hex:getDistance(actor.q, actor.r, q, r)
                if dist <= actor.moveRange and dist > 0 then
                    -- Подсвечиваем только свободные клетки (не занятые никем)
                    if not isCellOccupiedForStop(q, r, actor) and isCellPassable(q, r, actor) then
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
    local panelWidth = 200
    local panelHeight = titleHeight + debuffsHeight + terrainHeight

    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 8)
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 8)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(entity.name, x + 8, y + 6)
    love.graphics.print("❤️ " .. entity.health .. "/" .. entity.maxHealth, x + 8, y + 24)

    love.graphics.setColor(1, 0.8, 0.4, 1)
    love.graphics.print("💀 Debuffs:", x + 8, y + 40)

    if #statuses == 0 then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print("None", x + 18, y + 58)
    else
        local iconMap = {
            fire = "🔥 Fire",
            acid = "🧪 Acid",
        }
        love.graphics.setColor(1, 0.9, 0.6, 1)
        for i, st in ipairs(statuses) do
            local text = iconMap[st] or st
            love.graphics.print(text, x + 18, y + 58 + (i-1) * lineHeight)
        end
    end

    local terrainHeight = 20
    local prepareHeight = 0
    local prepareText = nil
    
    if entity.hasPreparedAttack and entity.preparePos and entity.preparedTarget then
        prepareHeight = 20
        local fromQ, fromR = entity.preparePos.q, entity.preparePos.r
        local toQ, toR = entity.preparedTarget.q, entity.preparedTarget.r
        prepareText = string.format("⚔ Prepares: (%d,%d) → (%d,%d) for 1 dmg", fromQ, fromR, toQ, toR)
    end
    
    local panelHeight = titleHeight + debuffsHeight + terrainHeight + prepareHeight

    -- Тип земли (как было)
    local terrain = "grass"
    if terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] then
        terrain = terrainMap[entity.q][entity.r]
    end
    love.graphics.setColor(0.9, 0.9, 0.7, 1)
    love.graphics.print("Terrain: " .. terrain, x + 8, y + 40 + debuffsHeight)
    
    -- Информация о подготовленной атаке
    if prepareText then
        love.graphics.setColor(1, 0.5, 0, 1)
        love.graphics.print(prepareText, x + 8, y + 40 + debuffsHeight + terrainHeight)
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

-- Отрисовка стрелки подготовленной атаки (при ховере)
function ui.drawPreparedAttackDirection(hex, enemy, time)
    if not enemy.hasPreparedAttack or not enemy.preparePos or not enemy.preparedTarget then
        return
    end
    
    local fromX, fromY = hex:hexToPixel(enemy.preparePos.q, enemy.preparePos.r)
    local toX, toY = hex:hexToPixel(enemy.preparedTarget.q, enemy.preparedTarget.r)
    
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

return ui