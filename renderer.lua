-- renderer.lua
-- Отвечает за отрисовку игры. Вызывается из love.draw(state).
local renderer = {}
local ui = require("ui")
local visual = require("visual_effects")
local status = require("status")
local combat = require("combat")
local hex_utils = require("hex_utils")
local global_abilities = require("global_abilities")
local objectives = require("objectives")

function renderer.draw(state)
    if not state or not state.hex then return end
    local hex = state.hex

    -- Collect cell overlays for grid rendering
    local cellOverlays = {}
    ui.collectPreparedAttackOverlays(hex, state.entities, cellOverlays)
    if state.attackMode and not state.flipTargetActor and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn then
        ui.collectAttackableCellOverlays(hex, state.selectedActor, state.selectedAttack, state.entities, state.terrainMap, cellOverlays)
    end
    if state.flipTargetActor then
        ui.collectFlipDestOverlays(state.hex, state.selectedActor, state.flipTargetActor, state.selectedAttack, state.entities, cellOverlays)
    end
    global_abilities.collectOverlays(hex, cellOverlays, state)
    if state.attackMode and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local ovCells = {}
        ui.collectAttackPreviewOverlays(hex, state.selectedActor, state.selectedAttack, hex.hoverQ, hex.hoverR, state.entities, ovCells)
        for _, c in ipairs(ovCells) do
            local key = c.q .. "," .. c.r
            if not cellOverlays[key] then
                cellOverlays[key] = {preview = true}
            end
        end
    end

    -- Normalize overlay data
    local t = love.timer.getTime()
    local hexRadius = hex.radius
    local hazardTex = ui.getHazardTexture()
    for key, info in pairs(cellOverlays) do
        if info == true then
            -- Attackable cell
            cellOverlays[key] = {fill = {0.9, 0.8, 0.2, 0.25}, line = {0.9, 0.8, 0.2, 0.7}}
        elseif info.preview then
            -- Attack preview
            cellOverlays[key] = {fill = {1, 0.5, 0, 0.3}, line = {1, 0.7, 0, 0.8}}
        elseif info.threatCount then
            -- Prepared attack (stencil + hazard texture)
            local threatCount = info.threatCount
            local fillR, fillG, fillB, fillA
            local scaleMod
            if threatCount == 1 then
                fillR, fillG, fillB, fillA = 1, 0.5, 0.2, 0.5
                scaleMod = 1.0
            elseif threatCount == 2 then
                fillR, fillG, fillB, fillA = 1, 0.3, 0.1, 0.75
                scaleMod = 1.2
            else
                fillR, fillG, fillB, fillA = 1, 0, 0, 1
                scaleMod = 1.4
            end
            if threatCount <= 2 then
                local pulse = 0.7 + 0.3 * math.sin(t * (5 + threatCount * 3))
                fillA = fillA * pulse
            end
            info.draw = function(vertices, ox, oy)
                love.graphics.stencil(function()
                    love.graphics.polygon("fill", vertices)
                end, "replace", 1)
                love.graphics.setStencilTest("greater", 0)
                love.graphics.setColor(fillR, fillG, fillB, fillA)
                if threatCount >= 2 then
                    love.graphics.draw(hazardTex, ox - hexRadius - 2, oy - hexRadius - 2, 0,
                        hexRadius * 2 / hazardTex:getWidth() * scaleMod,
                        hexRadius * 2 / hazardTex:getHeight() * scaleMod)
                    love.graphics.draw(hazardTex, ox - hexRadius + 2, oy - hexRadius + 2, 0,
                        hexRadius * 2 / hazardTex:getWidth() * scaleMod,
                        hexRadius * 2 / hazardTex:getHeight() * scaleMod)
                end
                love.graphics.draw(hazardTex, ox - hexRadius, oy - hexRadius, 0,
                    hexRadius * 2 / hazardTex:getWidth() * scaleMod,
                    hexRadius * 2 / hazardTex:getHeight() * scaleMod)
                love.graphics.setStencilTest()
            end
        elseif info.flipDest then
            local pulse = 0.6 + 0.4 * math.sin(t * 4)
            cellOverlays[key] = {fill = {0.2, 0.7, 1, 0.25 * pulse}, line = {0.2, 0.7, 1, 0.8 * pulse}}
        elseif info.windTorrentDest then
            cellOverlays[key] = {fill = {0.3, 0.6, 1, 0.4}, line = {0.3, 0.6, 1, 0.8}}
        end
    end

    drawHexGrid(state, cellOverlays)
    ui.drawPreparedAttackHealthBars(hex, state.entities)
    ui.drawDigSites(hex, status.getAllDigSites())
    drawAllEntities(state)
    visual.draw()

    if not state.attackMode then
        local sel = state.selectedActor
        if sel and not sel.isMoving and state.turnState.phase == "player" then
            local canShowMove = (not sel.hasActedThisTurn or sel.canMoveAfterAttack) and (not sel.hasMovedThisTurn or sel.canMoveAfterAttack)
            if canShowMove then
                ui.drawMovementRange(hex, sel, state.entities, state.terrainMap)
                if hex.hoverQ >= 0 and hex.hoverR >= 0 then
                    ui.drawPathPreview(hex, sel, hex.hoverQ, hex.hoverR, state.entities, state.terrainMap)
                end
            end
        end
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

    -- Enemy attack preview on hover (only when not in player attack mode)
    if not state.attackMode and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity:isCharacter() and not hoverEntity.isPlayable and hoverEntity.hasPreparedAttack and hoverEntity.health > 0 then
            local attack = hoverEntity.preparedAttack
            if attack then
                local targetQ, targetR = hoverEntity.q, hoverEntity.r
                if attack.name == "Ghost Bolt" and hoverEntity.attackDirection then
                    local step = hoverEntity.attackDirection
                    local curQ, curR = hoverEntity.q, hoverEntity.r
                    while true do
                        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                        if not hex:isActiveHex(nextQ, nextR) then break end
                        local ent = getEntityAtHex(nextQ, nextR, state.entities)
                        if ent and ent ~= hoverEntity and ent.health > 0 then
                            targetQ, targetR = nextQ, nextR
                            break
                        end
                        curQ, curR = nextQ, nextR
                    end
                elseif attack.name == "Magic Bolt" and hoverEntity.preparedTargetOffset then
                    targetQ, targetR = hex_utils.applyCubeDiff(
                        hoverEntity.q, hoverEntity.r,
                        hoverEntity.preparedTargetOffset.dx,
                        hoverEntity.preparedTargetOffset.dy,
                        hoverEntity.preparedTargetOffset.dz
                    )
                elseif attack.name == "Bite" and hoverEntity.preparedTargetOffset then
                    targetQ, targetR = hex_utils.applyCubeDiff(
                        hoverEntity.q, hoverEntity.r,
                        hoverEntity.preparedTargetOffset.dx,
                        hoverEntity.preparedTargetOffset.dy,
                        hoverEntity.preparedTargetOffset.dz
                    )
                elseif hoverEntity.attackDirection then
                    local step = hoverEntity.attackDirection
                    targetQ, targetR = hex_utils.applyCubeStep(hoverEntity.q, hoverEntity.r, step.dx, step.dy, step.dz)
                end
                if hex:isValidHex(targetQ, targetR) then
                    ui.drawAttackPreview(hex, hoverEntity, attack, true, targetQ, targetR, state.entities)
                end
            end
        end
    end

    local mx, my = love.mouse.getPosition()
    mx = mx / state.dpiScale
    my = my / state.dpiScale

    ui.drawUndoButton(state.actionHistory, state.maxUndoCount, state.selectedActor)
    ui.drawEndTurnButton(state.turnState, state.entities)
    ui.drawRestartButton(state.restartButton, state.turnState)
    global_abilities.drawButtons(mx, my, state)
    ui.drawTestViewButton(mx, my)

    ui.drawGlobalHealthBar(state.globalHealth, mx, my)
    ui.drawAttackPanel(state.selectedActor, state.attackButtons, state.selectedAttack, state.attackMode)
    ui.drawDecayButton(mx, my, state.turnCount, state.maxTurns, state.turnState.phase)
    if state.selectedActor then
        love.graphics.print("Selected: " .. state.selectedActor.name .. (state.selectedActor.hasActedThisTurn and " (acted)" or ""), 10, 23)
    end
    love.graphics.print("Left click: Move / Attack (after selecting attack)", 10, 95)

    local hoverOrder = ui.drawEnemyOrderButton(mx, my)
    local showOrder = hoverOrder or state.showEnemyOrder
    if showOrder then
        local orderMap = getEnemyAttackOrder(state.entities, state.turnState)
        local num = 0
        for _, e in ipairs(state.entities) do
            if e.waterWalker and e.health > 0 then
                num = num + 1
                local x, y = hex:hexToPixel(e.q, e.r)
                love.graphics.setColor(1, 0.8, 0.2, 0.9)
                love.graphics.circle("fill", x + 15, y - 20, 12)
                love.graphics.setColor(0, 0, 0, 1)
                love.graphics.print(tostring(num), x + 11, y - 28)
            end
        end
        for _, enemy in ipairs(state.entities) do
            if enemy:isCharacter() and not enemy.isPlayable and enemy.health > 0 then
                local n = orderMap[enemy]
                if n then
                    num = num + 1
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
            local panelY = logicalH - 180
            ui.drawUnitTooltip(hoverEntity, panelX, panelY, state.terrainMap)
            ui.drawStatusDetails(hoverEntity, panelX, panelY + 125)
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

    global_abilities.drawPreview(hex, state)

    objectives.draw()

    if not state.gameActive then
        local width = logicalW
        local height = logicalH
        local oldFont = love.graphics.getFont()

        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.rectangle("fill", 0, 0, width, height)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(48))
        if state.win then
            love.graphics.printf("VICTORY!", 0, height/2 - 100, width, "center")
            local total = objectives.getTotalCount()
            local completed = objectives.getCompletedCount()
            love.graphics.setFont(love.graphics.newFont(18))
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.printf("Objectives: " .. completed .. " / " .. total .. " completed", 0, height/2 - 50, width, "center")
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
        love.graphics.print("New Game (Enter)", btnX + 20, btnY + 12)
        love.graphics.setFont(oldFont)
    end
end

-- ============================================================
-- ФУНКЦИИ ОТРИСОВКИ (перемещены из main.lua)
-- ============================================================

function drawHexGrid(state, cellOverlays)
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
                -- Test view: shift center cell up/down
                local testY = 0
                if testViewActive and col == hex.centerQ and row == hex.centerR then
                    testY = testViewOffsetY
                end
                local depth = cellY + yOffset + testY
                table.insert(cells, { q = col, r = row, x = cellX, y = cellY, terrain = terrainType, depth = depth, testY = testY })
            end
        end
    end

    table.sort(cells, function(a, b) return a.depth < b.depth end)

    for _, cell in ipairs(cells) do
        local drawY = cell.y + (cell.testY or 0)
        local yOffset = (cell.terrain == "water") and state.config.WATER_Y_OFFSET or 0
        hex:drawTerrainHex(cell.q, cell.r, cell.terrain, cell.x, drawY)
        local hexStatuses = status.getAtHex(cell.q, cell.r)
        if #hexStatuses > 0 then
            ui.drawCellStatusEffects(cell.x, drawY + yOffset, hex.radius, hexStatuses, love.timer.getTime())
        end

        local cellKey = cell.q .. "," .. cell.r
        local overlay = cellOverlays and cellOverlays[cellKey]
        if overlay then
            local verts = hex:drawHexagon(cell.x, drawY + yOffset, hex.radius)
            if overlay.fill then
                love.graphics.setColor(overlay.fill[1], overlay.fill[2], overlay.fill[3], overlay.fill[4])
                love.graphics.polygon("fill", verts)
            end
            if overlay.line then
                love.graphics.setColor(overlay.line[1], overlay.line[2], overlay.line[3], overlay.line[4])
                love.graphics.polygon("line", verts)
            end
            if overlay.draw then
                overlay.draw(verts, cell.x, drawY + yOffset)
            end
        end

        local insetVerts = hex:drawHexagon(cell.x, drawY + yOffset, hex.radius - 2)

        local isCurrentActor = state.selectedActor and state.selectedActor.q == cell.q and state.selectedActor.r == cell.r
        local isSelected = (hex.selectedQ == cell.q and hex.selectedR == cell.r)
        local isHovered = (hex.hoverQ == cell.q and hex.hoverR == cell.r)

        if isCurrentActor then
            love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
            love.graphics.polygon("fill", insetVerts)
        elseif isSelected then
            love.graphics.setColor(0.2, 0.4, 0.8, 0.5)
            love.graphics.polygon("fill", insetVerts)
        elseif isHovered then
            love.graphics.setColor(0.5, 0.8, 0.3, 0.5)
            love.graphics.polygon("fill", insetVerts)
        end
        love.graphics.setLineWidth(1)
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
    if entity.health <= 0 or entity.isDying then return end

    local pipW, pipH = 8, 16
    local spacing = 1
    local totalWidth = entity.maxHealth * (pipW + spacing) - spacing
    local startX = x - totalWidth / 2
    local startY = y - 28

    damage = damage or 0
    if status.hasEntityStatus(entity, "acid") then
        damage = damage * 2
    end
    local damageClamped = math.min(damage, entity.health)

    -- Рамка вокруг всех ячеек
    local framePad = 1
    love.graphics.setColor(0.15, 0.15, 0.15, 0.7)
    love.graphics.rectangle("fill", startX - framePad, startY - framePad, totalWidth + framePad * 2, pipH + framePad * 2)
    love.graphics.setColor(0.5, 0.5, 0.5, 0.7)
    love.graphics.rectangle("line", startX - framePad, startY - framePad, totalWidth + framePad * 2, pipH + framePad * 2)

    for i = 1, entity.maxHealth do
        local cellX = startX + (i - 1) * (pipW + spacing)
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
            love.graphics.setColor(0.15, 0.02, 0.02, 0.4)
        end
        love.graphics.rectangle("fill", cellX, cellY, pipW, pipH)
    end

    -- Вертикальные разделители
    love.graphics.setColor(0.1, 0.1, 0.1, 0.6)
    for i = 2, entity.maxHealth do
        local lx = startX + (i - 1) * (pipW + spacing) - 1
        love.graphics.line(lx, startY, lx, startY + pipH)
    end
end

function drawActionIndicator(entity, x, y)
    if not entity:isCharacter() then return end
    if entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        love.graphics.circle("fill", x + 15, y - 15, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("\xE2\x9C\x93", x + 11, y - 20)
    elseif entity.isPlayable and not entity.hasMovedThisTurn then
        love.graphics.setColor(0.2, 0.9, 0.2, 0.9)
        love.graphics.circle("fill", x + 15, y - 15, 8)
    elseif entity.isPlayable and entity.hasMovedThisTurn then
        love.graphics.setColor(1, 0.7, 0, 0.9)
        love.graphics.circle("fill", x + 15, y - 15, 8)
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

    if entity.sprite then
        local sw, sh = entity.sprite:getDimensions()
        local baseScale = 6
        if state.selectedActor == entity and entity:isCharacter() then
            baseScale = 6 + math.sin(entity.pulse) * 0.2
        end
        if entity:isObstacle() or entity:isBuilding() then
            baseScale = 5
        end
        local finalScale = baseScale * scale
        local drawY = y
        if entity:isObstacle() or entity:isBuilding() then
            drawY = y - 6
        end
        love.graphics.draw(entity.sprite, x, drawY, 0, finalScale, finalScale, sw/2, sh/2)

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
        local overlayRadius = 22
        if entity.sprite then
            local sw, sh = entity.sprite:getDimensions()
            overlayRadius = math.max(sw, sh) * 6 / 2
        end
        ui.drawEntityStatusEffects(x, y, entity, overlayRadius, love.timer.getTime())
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
