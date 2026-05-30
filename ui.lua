-- ui.lua
-- Все функции интерфейса (кнопки, панели, предпросмотр атак, движения и т.д.)

local ui = {}
local pathfinding = require("pathfinding")
-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ ПРЕДПРОСМОТРА АТАК
-- ============================================================

-- Получить сущность на гексе (глобальная функция из main.lua, дублируем для безопасности)
local function getEntityAtHex(q, r, entities)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then
            return e
        end
    end
    return nil
end


-- Вспомогательная функция: являются ли две сущности союзниками
local function isAlly(entityA, entityB)
    if not entityA or not entityB then return false end
    return entityA.isPlayable == entityB.isPlayable
end

local function isCellBlockedForPath(q, r, actor, entities, terrainMap, hex)
    if not hex:isActiveHex(q, r) then return true end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then return true end
    for _, e in ipairs(entities) do
        if e ~= actor and e.q == q and e.r == r then
            if not isAlly(actor, e) then
                return true   -- враг или препятствие блокирует
            end
            -- союзник – не блокирует, продолжаем проверку? Но на клетке уже есть союзник,
            -- однако путь через союзника возможен. Возвращаем false (свободно).
            return false
        end
    end
    return false
end

-- Отрисовка пути стрелками
function ui.drawPathPreview(hex, actor, hoverQ, hoverR, entities, terrainMap)
    if actor.hasMovedThisTurn or actor.hasActedThisTurn then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end

    local dist = hex:getDistance(actor.q, actor.r, hoverQ, hoverR)
    if dist > actor.moveRange then return end

    if isCellBlockedForPath(hoverQ, hoverR, actor, entities, terrainMap, hex) then
        return
    end

    -- Построение пути
    local path = pathfinding.findPath(
        actor.q, actor.r, hoverQ, hoverR, actor.moveRange,
        function(q, r) return isCellBlockedForPath(q, r, actor, entities, terrainMap, hex) end,
        hex
    )

    if not path or #path == 0 then return end

    -- Добавляем начальную позицию в начало пути (для отрисовки первого сегмента)
    local fullPath = {{q = actor.q, r = actor.r}}
    for _, step in ipairs(path) do
        table.insert(fullPath, step)
    end

    -- Рисуем стрелки между последовательными клетками
    for i = 1, #fullPath - 1 do
        local from = fullPath[i]
        local to = fullPath[i+1]
        local fromX, fromY = hex:hexToPixel(from.q, from.r)
        local toX, toY = hex:hexToPixel(to.q, to.r)
        
        -- Используем существующую функцию отрисовки стрелки
        ui.drawPushArrow(fromX, fromY, toX, toY)
    end

    -- Дополнительно подсветим конечную клетку
    local x, y = hex:hexToPixel(hoverQ, hoverR)
    local vertices = hex:drawHexagon(x, y, hex.radius)
    love.graphics.setColor(0.2, 0.8, 0.2, 0.4)
    love.graphics.polygon("fill", vertices)
    love.graphics.setColor(0.2, 0.8, 0.2, 0.9)
    love.graphics.polygon("line", vertices)
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

-- Нарисовать стрелку отталкивания
function ui.drawPushArrow(fromX, fromY, toX, toY)
    -- Направление
    local angle = math.atan2(toY - fromY, toX - fromX)
    local arrowSize = 12
    local arrowX = toX - math.cos(angle) * 15
    local arrowY = toY - math.sin(angle) * 15

    love.graphics.setColor(1, 0.8, 0.2, 0.9)
    love.graphics.setLineWidth(3)
    love.graphics.line(fromX, fromY, arrowX, arrowY)

    -- Наконечник стрелки
    local leftAngle = angle + math.pi * 0.7
    local rightAngle = angle - math.pi * 0.7
    local tipX = toX
    local tipY = toY
    love.graphics.line(tipX, tipY,
        tipX + math.cos(leftAngle) * arrowSize,
        tipY + math.sin(leftAngle) * arrowSize)
    love.graphics.line(tipX, tipY,
        tipX + math.cos(rightAngle) * arrowSize,
        tipY + math.sin(rightAngle) * arrowSize)
    love.graphics.setLineWidth(1)
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

-- Отрисовать подготовленные атаки врагов
function ui.drawPreparedAttacks(hex, entities)
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack then
            local x, y = hex:hexToPixel(e.q, e.r)
            love.graphics.setColor(1, 0, 0, 0.6)
            love.graphics.circle("fill", x, y, 20)
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

-- Отрисовка диапазона движения
function ui.drawMovementRange(hex, actor, entities, terrainMap)
    if actor.hasMovedThisTurn or actor.hasActedThisTurn then return end
    local range = actor.moveRange
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) then
                local dist = hex:getDistance(actor.q, actor.r, q, r)
                if dist <= range and dist > 0 then
                    local occupied = false
                    for _, e in ipairs(entities) do
                        if e ~= actor and e.q == q and e.r == r then
                            occupied = true
                            break
                        end
                    end
                    local isWater = terrainMap and terrainMap[q] and terrainMap[q][r] == "water"
                    if not occupied and not isWater then
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

return ui