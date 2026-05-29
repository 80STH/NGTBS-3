-- ui.lua
local ui = {}

-- Вспомогательные функции для отрисовки (дублируются из main, чтобы не создавать циклических зависимостей)
local function isPositionOccupied(q, r, movingEntity, entities, hex, terrainMap)
    if not hex:isActiveHex(q, r) then return true end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then return true end
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            return true
        end
    end
    return false
end

local function findPath(startQ, startR, targetQ, targetR, movingActor, entities, hex, terrainMap)
    if startQ == targetQ and startR == targetR then return {} end
    local nodeInfo = {}
    local startKey = startQ .. "," .. startR
    nodeInfo[startKey] = { q = startQ, r = startR, g = 0, parent = nil }
    local openSet = { startKey }
    local closedSet = {}
    while #openSet > 0 do
        local currentKey = openSet[1]
        local currentIndex = 1
        for i, key in ipairs(openSet) do
            if nodeInfo[key].g < nodeInfo[currentKey].g then
                currentKey = key
                currentIndex = i
            end
        end
        table.remove(openSet, currentIndex)
        local current = nodeInfo[currentKey]
        if current.q == targetQ and current.r == targetR then
            local path = {}
            local node = current
            while node.parent do
                table.insert(path, 1, { q = node.q, r = node.r })
                node = node.parent
            end
            return path
        end
        closedSet[currentKey] = true
        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, neighbor in ipairs(neighbors) do
            if not hex:isValidHex(neighbor.q, neighbor.r) then goto continue end
            local neighborKey = neighbor.q .. "," .. neighbor.r
            if not closedSet[neighborKey] then
                if not isPositionOccupied(neighbor.q, neighbor.r, movingActor, entities, hex, terrainMap) then
                    local tentativeG = current.g + 1
                    if not nodeInfo[neighborKey] then
                        nodeInfo[neighborKey] = { q = neighbor.q, r = neighbor.r, g = tentativeG, parent = current }
                        table.insert(openSet, neighborKey)
                    elseif tentativeG < nodeInfo[neighborKey].g then
                        nodeInfo[neighborKey].g = tentativeG
                        nodeInfo[neighborKey].parent = current
                    end
                end
            end
            ::continue::
        end
    end
    return nil
end

-- ============================================================
-- Отрисовка интерфейса
-- ============================================================

function ui.drawMovementRange(hex, selectedActor, entities, terrainMap)
    if not selectedActor or selectedActor.isMoving or selectedActor.hasActedThisTurn then return end
    if selectedActor.hasMovedThisTurn then return end

    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if not hex:isActiveHex(q, r) then goto continue end
            if q == selectedActor.q and r == selectedActor.r then goto continue end

            local path = findPath(selectedActor.q, selectedActor.r, q, r, selectedActor, entities, hex, terrainMap)
            if path and #path > 0 and #path <= selectedActor.moveRange then
                local isOccupied = isPositionOccupied(q, r, selectedActor, entities, hex, terrainMap)
                local x, y = hex:hexToPixel(q, r)
                local vertices = hex:drawHexagon(x, y, hex.radius)

                if isOccupied then
                    love.graphics.setColor(0.8, 0.2, 0.2, 0.3)
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(1, 1, 1, 0.5)
                    love.graphics.print("🚫", x - 5, y - 8)
                else
                    love.graphics.setColor(0.3, 0.8, 0.3, 0.35)
                    love.graphics.polygon("fill", vertices)
                    love.graphics.setColor(1, 1, 1, 0.8)
                    love.graphics.print(#path, x - 5, y - 5)
                end
            end
            ::continue::
        end
    end
end

function ui.drawPathPreview(hex, selectedActor, hoverQ, hoverR, entities, terrainMap)
    if not selectedActor or selectedActor.isMoving or selectedActor.hasActedThisTurn then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end

    local distance = hex:getDistance(selectedActor.q, selectedActor.r, hoverQ, hoverR)
    if distance > selectedActor.moveRange then return end

    local path = findPath(selectedActor.q, selectedActor.r, hoverQ, hoverR, selectedActor, entities, hex, terrainMap)
    if path and #path > 0 and #path <= selectedActor.moveRange then
        local startX, startY = hex:hexToPixel(selectedActor.q, selectedActor.r)
        local prevX, prevY = startX, startY
        for i = 1, #path do
            local step = path[i]
            local x, y = hex:hexToPixel(step.q, step.r)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            love.graphics.setColor(1, 1, 0, 0.3)
            love.graphics.polygon("fill", vertices)

            love.graphics.setColor(1, 0.8, 0, 0.8)
            love.graphics.setLineWidth(3)
            local angle = math.atan2(y - prevY, x - prevX)
            local arrowLength = 15
            local arrowSize = 8
            love.graphics.line(prevX, prevY, x, y)
            local arrowX = x - math.cos(angle) * 12
            local arrowY = y - math.sin(angle) * 12
            local leftAngle = angle + math.pi * 0.8
            local leftX = arrowX + math.cos(leftAngle) * arrowSize
            local leftY = arrowY + math.sin(leftAngle) * arrowSize
            local rightAngle = angle - math.pi * 0.8
            local rightX = arrowX + math.cos(rightAngle) * arrowSize
            local rightY = arrowY + math.sin(rightAngle) * arrowSize
            love.graphics.line(arrowX, arrowY, leftX, leftY)
            love.graphics.line(arrowX, arrowY, rightX, rightY)
            prevX, prevY = x, y
        end
        love.graphics.setLineWidth(1)
        local targetX, targetY = hex:hexToPixel(hoverQ, hoverR)
        local targetVertices = hex:drawHexagon(targetX, targetY, hex.radius)
        love.graphics.setColor(1, 0.8, 0, 0.4)
        love.graphics.polygon("fill", targetVertices)
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.polygon("line", targetVertices)
    end
end

function ui.drawAttackPreview(hex, selectedActor, selectedAttack, attackMode, hoverQ, hoverR, entities)
    if not attackMode or not selectedAttack or not selectedActor or selectedActor.hasActedThisTurn then return end
    local distance = hex:getDistance(selectedActor.q, selectedActor.r, hoverQ, hoverR)
    if distance > selectedAttack.range then return end

    if selectedAttack.getPreviewCells then
        local cells = selectedAttack:getPreviewCells(selectedActor, hoverQ, hoverR, hex, entities)
        for _, cell in ipairs(cells) do
            if hex:isValidHex(cell.q, cell.r) then
                local x, y = hex:hexToPixel(cell.q, cell.r)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.setColor(1, 0.5, 0, 0.4)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.8, 0, 0.8)
                love.graphics.polygon("line", vertices)
            end
        end
    else
        local target = combat.getEntityAtHex(hoverQ, hoverR, entities)
        if target and (selectedActor.isPlayable ~= target.isPlayable) then
            local x, y = hex:hexToPixel(hoverQ, hoverR)
            local vertices = hex:drawHexagon(x, y, hex.radius)
            love.graphics.setColor(1, 0.2, 0.2, 0.5)
            love.graphics.polygon("fill", vertices)
            love.graphics.setColor(1, 0.5, 0.5, 0.9)
            love.graphics.polygon("line", vertices)
            love.graphics.print("⚔", x - 5, y - 10)
        end
    end
end

function ui.drawPreparedAttacks(hex, entities)
    for _, enemy in ipairs(entities) do
        if enemy:isCharacter() and not enemy.isPlayable and enemy.hasPreparedAttack then
            local deltaQ = enemy.q - enemy.preparePos.q
            local deltaR = enemy.r - enemy.preparePos.r
            local targetQ = enemy.preparedTarget.q + deltaQ
            local targetR = enemy.preparedTarget.r + deltaR
            if hex:isValidHex(targetQ, targetR) then
                local x, y = hex:hexToPixel(targetQ, targetR)
                local vertices = hex:drawHexagon(x, y, hex.radius)
                love.graphics.setColor(1, 0, 0, 0.5)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(1, 0.2, 0.2, 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.polygon("line", vertices)
                love.graphics.setLineWidth(1)
                love.graphics.print("⚔", x - 6, y - 10)
            end
        end
    end
end

function ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode)
    if not selectedActor or selectedActor.hasActedThisTurn or selectedActor.isMoving then
        return
    end
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", love.graphics.getWidth() - 170, 80, 160, #attackButtons * 35 + 10, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", love.graphics.getWidth() - 170, 80, 160, #attackButtons * 35 + 10, 5)
    love.graphics.print("Attacks:", love.graphics.getWidth() - 160, 85)
    for i, btn in ipairs(attackButtons) do
        local mx, my = love.mouse.getPosition()
        local hover = (mx >= btn.x and mx <= btn.x + btn.width and my >= btn.y and my <= btn.y + btn.height)
        if selectedAttack == btn.attack and attackMode then
            love.graphics.setColor(0.3, 0.8, 0.3, 0.9)
        elseif hover then
            love.graphics.setColor(0.4, 0.6, 1, 0.9)
        else
            love.graphics.setColor(0.2, 0.4, 0.6, 0.8)
        end
        love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 5)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", btn.x, btn.y, btn.width, btn.height, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(btn.name, btn.x + 5, btn.y + 8)
        if hover then
            love.graphics.setColor(1, 1, 0.8, 1)
            love.graphics.print(btn.desc, btn.x + 5, btn.y - 15)
        end
    end
end

function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
    local canUndo = #actionHistory > 0
    if not selectedActor then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
    elseif canUndo and (undoButton and undoButton.isHovered) then
        love.graphics.setColor(0.3, 0.6, 0.9, 0.9)
    elseif canUndo then
        love.graphics.setColor(0.2, 0.4, 0.7, 0.8)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    end
    love.graphics.rectangle("fill", 10, 200, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", 10, 200, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 1)
    local text = "Undo (" .. #actionHistory .. "/" .. maxUndoCount .. ")"
    if #actionHistory == 0 then
        text = "Nothing to Undo"
    end
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(text)
    love.graphics.print(text, 10 + (120 - textWidth) / 2, 208)
end

function ui.drawEndTurnButton(turnState, entities)
    if turnState.waitingForEnemies then
        love.graphics.setColor(0.4, 0.3, 0.1, 0.5)
        love.graphics.rectangle("fill", 10, 280, 120, 30, 5)
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
        love.graphics.rectangle("line", 10, 280, 120, 30, 5)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.7)
        love.graphics.print("Enemies turn...", 25, 288)
        return
    end
    local anyActorActed = false
    for _, actor in ipairs(entities) do
        if actor.isPlayable and actor.hasActedThisTurn then
            anyActorActed = true
            break
        end
    end
    local hover = (endTurnButton and endTurnButton.isHovered) or false
    if hover then
        if anyActorActed then
            love.graphics.setColor(0.9, 0.6, 0.2, 0.9)
        else
            love.graphics.setColor(0.7, 0.5, 0.2, 0.6)
        end
    else
        if anyActorActed then
            love.graphics.setColor(0.7, 0.5, 0.2, 0.8)
        else
            love.graphics.setColor(0.5, 0.3, 0.1, 0.5)
        end
    end
    love.graphics.rectangle("fill", 10, 280, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", 10, 280, 120, 30, 5)
    love.graphics.setColor(1, 1, 1, 1)
    local text = "End Turn"
    if not anyActorActed then
        text = "End Turn (no actions)"
    end
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(text)
    love.graphics.print(text, 10 + (120 - textWidth) / 2, 288)
end

function ui.drawWindTorrentUI(windTorrent, windTorrentUI, turnState)
    local canUse = windTorrent and not windTorrent.hasBeenUsed and turnState.phase == "player"
    local isHover = (windTorrentUI.button.isHovered or false)
    if windTorrentUI.active then
        love.graphics.setColor(0.3, 0.5, 0.8, 0.9)
    elseif canUse and isHover then
        love.graphics.setColor(0.2, 0.6, 0.9, 0.9)
    elseif canUse then
        love.graphics.setColor(0.1, 0.4, 0.7, 0.8)
    else
        love.graphics.setColor(0.4, 0.4, 0.4, 0.6)
    end
    love.graphics.rectangle("fill", windTorrentUI.button.x, windTorrentUI.button.y,
                           windTorrentUI.button.width, windTorrentUI.button.height, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", windTorrentUI.button.x, windTorrentUI.button.y,
                           windTorrentUI.button.width, windTorrentUI.button.height, 5)
    love.graphics.setColor(1, 1, 1, 1)
    local text = "🌬️ Wind Torrent"
    if windTorrent and windTorrent.hasBeenUsed then
        text = "❌ Wind Torrent (used)"
    end
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(text)
    love.graphics.print(text, windTorrentUI.button.x + (windTorrentUI.button.width - textWidth) / 2,
                       windTorrentUI.button.y + 8)
    if windTorrentUI.active then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 0.5, 1)
        love.graphics.print("Choose wind direction:", love.graphics.getWidth() / 2 - 100, 40)
        love.graphics.print("(Click on a direction button)", love.graphics.getWidth() / 2 - 90, 65)
        for dirName, dir in pairs(windTorrentUI.directions) do
            local mx, my = love.mouse.getPosition()
            local hover = mx >= dir.x and mx <= dir.x + 70 and my >= dir.y and my <= dir.y + 30
            if hover then
                love.graphics.setColor(0.4, 0.7, 1, 0.9)
            else
                love.graphics.setColor(0.2, 0.4, 0.6, 0.8)
            end
            love.graphics.rectangle("fill", dir.x, dir.y, 70, 30, 5)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.rectangle("line", dir.x, dir.y, 70, 30, 5)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(dirName, dir.x + 5, dir.y + 8)
        end
        local cancelX = love.graphics.getWidth() / 2 - 40
        local cancelY = love.graphics.getHeight() - 80
        local mx, my = love.mouse.getPosition()
        local cancelHover = mx >= cancelX and mx <= cancelX + 80 and my >= cancelY and my <= cancelY + 30
        if cancelHover then
            love.graphics.setColor(0.8, 0.3, 0.3, 0.9)
        else
            love.graphics.setColor(0.6, 0.2, 0.2, 0.8)
        end
        love.graphics.rectangle("fill", cancelX, cancelY, 80, 30, 5)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.rectangle("line", cancelX, cancelY, 80, 30, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Cancel", cancelX + 15, cancelY + 8)
    end
end

function ui.drawGlobalHealthBar(globalHealth)
    local barWidth = 200
    local barHeight = 20
    local x = love.graphics.getWidth() - barWidth - 10
    local y = 10
    local healthPercent = globalHealth.current / globalHealth.max
    love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
    love.graphics.rectangle("fill", x, y, barWidth, barHeight, 5)
    if healthPercent > 0.6 then
        love.graphics.setColor(0.2, 0.8, 0.2, 0.8)
    elseif healthPercent > 0.3 then
        love.graphics.setColor(0.8, 0.8, 0.2, 0.8)
    else
        love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
    end
    love.graphics.rectangle("fill", x, y, barWidth * healthPercent, barHeight, 5)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", x, y, barWidth, barHeight, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Global Health: " .. globalHealth.current .. "/" .. globalHealth.max,
                       x + 10, y + 3)
end

return ui