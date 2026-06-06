-- renderer.lua
-- Отвечает за отрисовку игры. Вызывается из love.draw(state).
local renderer = {}
local ui = require("ui")
local visual = require("visual_effects")
local status = require("status")
local combat = require("combat")

function renderer.draw(state)
    if not state or not state.hex then return end
    local hex = state.hex

    drawHexGrid(state)
    ui.drawPreparedAttacks(hex, state.entities)
    ui.drawDigSites(hex, status.getAllDigSites())
    drawAllEntities(state)
    visual.draw()

    local turnsLeft = state.maxTurns - state.turnCount
    if turnsLeft > 0 then
        love.graphics.setColor(0.9, 0.7, 0.2, 1)
        love.graphics.print("Decay in: " .. turnsLeft, 10, 110)
    elseif turnsLeft == 0 and state.decayAppliedForTurnLimit then
        love.graphics.setColor(0.8, 0.2, 0.2, 1)
        love.graphics.print("DECAY ACTIVE!", 10, 110)
    end

    if not state.attackMode then
        if state.selectedActor and not state.selectedActor.hasActedThisTurn and not state.selectedActor.isMoving and state.turnState.phase == "player" then
            ui.drawMovementRange(hex, state.selectedActor, state.entities, state.terrainMap)
            if hex.hoverQ >= 0 and hex.hoverR >= 0 then
                ui.drawPathPreview(hex, state.selectedActor, hex.hoverQ, hex.hoverR, state.entities, state.terrainMap)
            end
        end
    else
        if state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn then
            ui.drawAttackableCells(hex, state.selectedActor, state.selectedAttack, state.entities, state.terrainMap)
        end
    end

    if state.decayMessageTimer > 0 then
        local alpha = math.min(1, state.decayMessageTimer * 2)
        love.graphics.setColor(0.8, 0.2, 0.2, alpha)
        love.graphics.setFont(love.graphics.newFont(36))
        love.graphics.print("DECAY!", love.graphics.getWidth()/2 - 90, love.graphics.getHeight()/2 - 50)
        love.graphics.setFont(love.graphics.newFont(16))
    end

    if hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity:isCharacter() and not hoverEntity.isPlayable and hoverEntity.health > 0 then
            if not state.attackMode and state.turnState.phase == "player" then
                ui.drawEnemyMovementRange(hex, hoverEntity, state.entities, state.terrainMap)
            end
        end
    end

    if state.attackMode and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        ui.drawAttackPreview(hex, state.selectedActor, state.selectedAttack, state.attackMode, hex.hoverQ, hex.hoverR, state.entities)
    end

    ui.drawUndoButton(state.actionHistory, state.maxUndoCount, state.selectedActor)
    ui.drawEndTurnButton(state.turnState, state.entities)
    ui.drawRestartButton(state.restartButton, state.turnState)
    ui.drawWindTorrentButton(state.windTorrent, state.windTorrentUI, state.turnState)
    ui.drawGlobalHealthBar(state.globalHealth)
    ui.drawAttackPanel(state.selectedActor, state.attackButtons, state.selectedAttack, state.attackMode)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Phase: " .. state.turnState.phase, 10, 10)
    if state.selectedActor then
        love.graphics.print("Selected: " .. state.selectedActor.name .. (state.selectedActor.hasActedThisTurn and " (acted)" or ""), 10, 30)
    end
    love.graphics.print("Left click: Move / Attack (after selecting attack)", 10, 130)

    local mx, my = love.mouse.getPosition()
    local showOrder = ui.drawEnemyOrderButton(mx, my)
    if showOrder then
        local orderMap = getEnemyAttackOrder(state.entities, state.turnState)
        for _, enemy in ipairs(state.entities) do
            if enemy:isCharacter() and not enemy.isPlayable and enemy.health > 0 then
                local num = orderMap[enemy]
                if num then
                    local x, y = hex:hexToPixel(enemy.q, enemy.r)
                    love.graphics.setColor(1, 0.8, 0.2, 0.9)
                    love.graphics.circle("fill", x + 15, y - 20, 12)
                    love.graphics.setColor(0, 0, 0, 1)
                    love.graphics.print(tostring(num), x + 11, y - 28)
                end
            end
        end
    end

    if hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity.health > 0 then
            local panelX = 10
            local panelY = love.graphics.getHeight() - 180
            ui.drawUnitTooltip(hoverEntity, panelX, panelY, state.terrainMap)
        elseif hex:isActiveHex(hex.hoverQ, hex.hoverR) then
            local terrain = state.terrainMap and state.terrainMap[hex.hoverQ] and state.terrainMap[hex.hoverQ][hex.hoverR] or "grass"
            ui.drawCellTooltip(hex.hoverQ, hex.hoverR, terrain, hex)
        end
    end

    for _, entity in ipairs(state.entities) do
        if entity:isCharacter() and not entity.isPlayable and entity.hasPreparedAttack and entity.health > 0 then
            ui.drawPreparedAttackDirection(hex, entity, love.timer.getTime(), state.entities)
        end
    end

    if state.windTorrentUI.active and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local direction = getWindDirectionFromHex(hex.hoverQ, hex.hoverR, hex.centerQ, hex.centerR, hex)
        if direction then
            ui.drawWindTorrentPreview(hex, direction, state.entities, state.terrainMap)
        end
    end

    if not state.gameActive then
        local width = love.graphics.getWidth()
        local height = love.graphics.getHeight()
        local oldFont = love.graphics.getFont()

        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.rectangle("fill", 0, 0, width, height)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(48))
        if state.win then
            love.graphics.printf("VICTORY!", 0, height/2 - 100, width, "center")
        elseif state.loss then
            love.graphics.printf("DEFEAT!", 0, height/2 - 100, width, "center")
        end

        local btnW, btnH = 200, 50
        local btnX = width/2 - btnW/2
        local btnY = height/2 + 20
        love.graphics.setFont(love.graphics.newFont(24))
        love.graphics.setColor(0.2, 0.2, 0.6, 0.9)
        love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("New Game", btnX + 48, btnY + 12)
        love.graphics.setFont(oldFont)
    end
end

-- ============================================================
-- ФУНКЦИИ ОТРИСОВКИ (перемещены из main.lua)
-- ============================================================

function drawHexGrid(state)
    local hex = state.hex
    love.graphics.setLineWidth(1)
    local gridW = hex.gridWidth
    local gridH = hex.gridHeight
    if not gridW or not gridH then return end

    local cells = {}
    for row = 0, gridH - 1 do
        for col = 0, gridW - 1 do
            if hex:isActiveHex(col, row) then
                local terrainType = state.terrainMap and state.terrainMap[col] and state.terrainMap[col][row] or "grass"
                local cellX, cellY = hex:hexToPixel(col, row)
                local yOffset = (terrainType == "water") and state.config.WATER_Y_OFFSET or 0
                local depth = cellY + yOffset
                table.insert(cells, { q = col, r = row, x = cellX, y = cellY, terrain = terrainType, depth = depth })
            end
        end
    end

    table.sort(cells, function(a, b) return a.depth < b.depth end)

    for _, cell in ipairs(cells) do
        hex:drawTerrainHex(cell.q, cell.r, cell.terrain, cell.x, cell.y)
        local hexStatuses = status.getAtHex(cell.q, cell.r)
        if #hexStatuses > 0 then
            local yOffset = (cell.terrain == "water") and state.config.WATER_Y_OFFSET or 0
            ui.drawCellStatusEffects(cell.x, cell.y + yOffset, hex.radius, hexStatuses, love.timer.getTime())
        end
    end

    for _, cell in ipairs(cells) do
        local yOffset = (cell.terrain == "water") and state.config.WATER_Y_OFFSET or 0
        local vertices = hex:drawHexagon(cell.x, cell.y + yOffset, hex.radius)

        local isCurrentActor = state.selectedActor and state.selectedActor.q == cell.q and state.selectedActor.r == cell.r
        local isSelected = (hex.selectedQ == cell.q and hex.selectedR == cell.r)
        local isHovered = (hex.hoverQ == cell.q and hex.hoverR == cell.r)

        if isCurrentActor then
            love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
            love.graphics.polygon("fill", vertices)
        elseif isSelected then
            love.graphics.setColor(0.2, 0.4, 0.8, 0.5)
            love.graphics.polygon("fill", vertices)
        elseif isHovered then
            love.graphics.setColor(0.5, 0.8, 0.3, 0.5)
            love.graphics.polygon("fill", vertices)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function getEntityDrawPosition(entity, state)
    if entity.currentDrawX and entity.currentDrawY then
        return entity.currentDrawX, entity.currentDrawY
    end

    if state.pushAnimations and state.pushAnimations.queue then
        for _, anim in ipairs(state.pushAnimations.queue) do
            if anim.obj == entity and anim.isMoving then
                local t = math.min(1, anim.timer / anim.duration)
                local ease = 1 - (1 - t) * (1 - t)

                if anim.isShake then
                    if anim.offsetX and anim.offsetY then
                        local x, y = state.hex:hexToPixel(anim.obj.q, anim.obj.r)
                        local curX = x + anim.offsetX * (1 - ease)
                        local curY = y + anim.offsetY * (1 - ease)
                        return curX, curY
                    else
                        return state.hex:hexToPixel(entity.q, entity.r)
                    end
                else
                    if anim.startX and anim.endX then
                        local x = anim.startX + (anim.endX - anim.startX) * ease
                        local y = anim.startY + (anim.endY - anim.startY) * ease
                        return x, y
                    else
                        return state.hex:hexToPixel(entity.q, entity.r)
                    end
                end
            end
        end
    end

    if entity.isMoving then
        local t = entity.timer / entity.speed
        if t > 1 then t = 1 end
        local ease = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
        local x = entity.startX + (entity.endX - entity.startX) * ease
        local y = entity.startY + (entity.endY - entity.startY) * ease
        return x, y
    end

    return getDrawCoords(entity.q, entity.r)
end

function drawHealthBar(entity, x, y, damage)
    if not x or not y then
        if entity and entity.q ~= nil and entity.r ~= nil and _G.state and _G.state.hex then
            x, y = _G.state.hex:hexToPixel(entity.q, entity.r)
        else
            return
        end
    end

    if not entity.maxHealth or entity.maxHealth <= 0 then return end
    if entity.maxHealth > 10 then return end

    local cellSize = 8
    local spacing = 1
    local totalWidth = entity.maxHealth * (cellSize + spacing) - spacing
    local startX = x - totalWidth / 2
    local startY = y - 28

    damage = damage or 0
    local damageClamped = math.min(damage, entity.health)

    for i = 1, entity.maxHealth do
        local cellX = startX + (i - 1) * (cellSize + spacing)
        local cellY = startY
        local isAlive = i <= entity.health
        local willTakeDamage = damageClamped > 0 and i > entity.health - damageClamped and i <= entity.health

        if willTakeDamage then
            local t = love.timer.getTime()
            local blink = 0.5 + 0.5 * math.sin(t * 8)
            love.graphics.setColor(1, 0.2 + blink * 0.3, 0.2, 0.9)
        elseif isAlive then
            love.graphics.setColor(0, 0.8, 0, 0.9)
        else
            love.graphics.setColor(0.4, 0.1, 0.1, 0.6)
        end
        love.graphics.rectangle("fill", cellX, cellY, cellSize, cellSize)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.rectangle("line", cellX, cellY, cellSize, cellSize)
    end
end

function drawActionIndicator(entity, x, y)
    if entity:isCharacter() and entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        love.graphics.circle("fill", x + 15, y - 15, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("\xE2\x9C\x93", x + 11, y - 20)
    end
end

function drawEntity(entity, state)
    love.graphics.setColor(1, 1, 1, 1)
    local x, y = getEntityDrawPosition(entity, state)

    local alpha = 1
    local scale = 1
    if entity.isDying then
        local t = entity.deathTimer / entity.deathDuration
        alpha = 1 - t
        scale = 1 - t * 0.7
        love.graphics.setColor(1, 1, 1, alpha)
    end

    if entity.isPlayable and entity.hasMovedThisTurn and not entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.8, 0.5, 0.9)
        love.graphics.print("\xF0\x9F\x8F\x83", x + 18, y - 20)
    end

    if entity.sprite then
        local sw, sh = entity.sprite:getDimensions()
        local baseScale = 6
        if state.selectedActor == entity and entity:isCharacter() then
            baseScale = 6 + math.sin(entity.pulse) * 0.2
        end
        local finalScale = baseScale * scale
        love.graphics.draw(entity.sprite, x, y, 0, finalScale, finalScale, sw/2, sh/2)

        if entity:isCharacter() then
            local statusColor = ui.getEntityStatusColor(entity, love.timer.getTime())
            if statusColor then
                love.graphics.setColor(statusColor)
                love.graphics.setBlendMode("add")
                love.graphics.circle("fill", x, y, 22)
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    else
        love.graphics.setColor(entity.color or {1, 1, 1, 1})
        love.graphics.circle("fill", x, y, 14)
    end

    if entity.isDying then
        love.graphics.setColor(1, 0.2, 0.2, alpha)
        love.graphics.circle("fill", x, y, 18)
    end

    local entityStatuses = status.getEntityStatuses(entity)
    if #entityStatuses > 0 then
        ui.drawEntityStatusEffects(x, y, entity, 20, love.timer.getTime())
    end

    drawHealthBar(entity, x, y)
    drawActionIndicator(entity, x, y)

    if state.selectedActor == entity and entity:isCharacter() and not entity.isDying then
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.circle("line", x, y, 22)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function drawAllEntities(state)
    for _, entity in ipairs(state.entities) do
        drawEntity(entity, state)
    end
end

return renderer
