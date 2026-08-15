-- ui_buttons.lua
-- Right column: Abilities toggle, Order, Undo (vertical stack)
-- Bottom center: End Turn
-- Left column: Attacks OR Abilities (toggled)
return function(ui)
    local fonts = require("util.fonts")
    local buttonFont = fonts.get(14)
    local icon_cache = require("ui.icon_cache")

    local rightCol = { x = 0, w = 190, btnH = 56, gap = 6, margin = 10 }
    local leftCol  = { x = 10, w = 190, itemH = 56, gap = 6, margin = 10 }

    function ui.getRightBtnRect(index)
        -- index: 1=Undo, 2=Order, 3=Abilities (bottom→top)
        local cb = rightCol
        cb.x = logicalW - cb.w - cb.margin
        local baseY = logicalH - cb.margin
        return {
            x = cb.x,
            y = baseY - cb.btnH * index - cb.gap * (index - 1),
            w = cb.w,
            h = cb.btnH,
        }
    end

    ui.endTurnHoldTime = 0.7

    function ui.getEndTurnRect()
        local w, h = 220, 64
        return {
            x = math.floor((logicalW - w) / 2),
            y = logicalH - h - 10,
            w = w,
            h = h,
        }
    end

    function ui.getLeftItemRect(index)
        local cb = leftCol
        local baseY = logicalH - cb.margin
        local off = (index - 1) * (cb.itemH + cb.gap)
        return {
            x = cb.x,
            y = baseY - cb.itemH - off,
            w = cb.w,
            h = cb.itemH,
        }
    end

    -- ═══ Mechanism Button (index 4, top of right column) ═══
    -- One press drives every environment mechanism on the map:
    -- retractable highground, teleporters, conveyor belts.
    function ui.drawMechanismButton(state)
        local hasHighground = #(_G.retractableCells or {}) > 0
        local hasConveyor = next(_G.conveyorCells or {}) ~= nil
        local hasTeleporter = require("system.teleporters").hasActivePair()
        if not (hasHighground or hasConveyor or hasTeleporter) then return end
        local r = ui.getRightBtnRect(4)
        local mx, my = love.mouse.getPosition()
        mx, my = mx / (_G.dpiScale or 1), my / (_G.dpiScale or 1)
        local isHover = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
        local isPlayerTurn = state.turnState and state.turnState.phase == "player"
        local available = isPlayerTurn and not _G.mechanismUsedThisTurn

        love.graphics.setColor(0.55, 0.4, 0.15, available and 0.9 or 0.4)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        icon_cache.drawSmall("abil_unearth", r.x + 20, r.y + r.h / 2, 36, available and 1 or 0.5)
        love.graphics.setColor(1, 1, 1, available and 1 or 0.5)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Mechanism", r.x + 40, r.y + r.h / 2 - 10, r.w - 40, "center")
        love.graphics.setFont(old)
        love.graphics.setColor(1, 1, 1, 1)

        if isHover then
            -- Highlight the cells the mechanism affects
            local function cellHint(q, r, color)
                local x, y = getDrawCoords(q, r)
                local verts = hex:drawInsetHexagon(x, y, hex.radius, 0.92)
                love.graphics.setColor(color[1], color[2], color[3], 0.25)
                love.graphics.polygon("fill", verts)
                love.graphics.setColor(color[1], color[2], color[3], 0.9)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", verts)
                love.graphics.setLineWidth(1)
            end
            for _, c in ipairs(_G.retractableCells or {}) do
                cellHint(c.q, c.r, _G.highgroundRaised and {1, 0.4, 0.3} or {1, 0.7, 0.2})
            end
            for _, c in ipairs(require("system.teleporters").getActiveCells()) do
                cellHint(c.q, c.r, {0.75, 0.35, 1})
            end
            for key in pairs(_G.conveyorCells or {}) do
                local q, r = key:match("^(%d+),(%d+)$")
                if q then cellHint(tonumber(q), tonumber(r), {0.95, 0.8, 0.25}) end
            end

            -- Simulate the belts: push arrows for free moves, collision icons
            -- (like the regular push preview) where a unit would be slammed
            -- into an occupied cell.
            local hex_utils = require("grid.hex_utils")
            local colIcons = {}
            for _, e in ipairs(_G.entities or {}) do
                if e:isCharacter() and e.health > 0 and not e.isDying and not e.isMoving then
                    local dir = _G.conveyorCells and _G.conveyorCells[e.q .. "," .. e.r]
                    if dir then
                        local nq, nr = hex_utils.applyCubeStep(e.q, e.r, dir[1], dir[2], dir[3])
                        if hex:isActiveHex(nq, nr) then
                            local x1, y1 = getDrawCoords(e.q, e.r)
                            local x2, y2 = getDrawCoords(nq, nr)
                            local occ = getEntityAtHex(nq, nr)
                            if occ then
                                colIcons[#colIcons + 1] = {
                                    x = (x1 + x2) / 2, y = (y1 + y2) / 2,
                                    icon = occ.noCollisionDamage and "collision_no_damage" or "collision_damage",
                                }
                            else
                                local terrain = _G.terrainMap and _G.terrainMap[nq] and _G.terrainMap[nq][nr] or "grass"
                                if terrain ~= "water" or e.waterWalker or e.hovering then
                                    ui.drawPushArrow(x1, y1, x2, y2, nil, nil, nil, nil,
                                        e.q, e.r, nq, nr, 0.55)
                                end
                            end
                        end
                    end
                end
            end
            if #colIcons > 0 then ui.drawPreviewIcons(hex, colIcons) end

            -- Teleporters: ghost silhouette of everyone who would be
            -- teleported, drawn at their new position.
            local teleporters = require("system.teleporters")
            for _, e in ipairs(_G.entities or {}) do
                if e:isCharacter() and e.health > 0 and not e.isDying and not e.isMoving then
                    local _, other = teleporters.getCellInfo(e.q, e.r)
                    if other then
                        local x2, y2 = getDrawCoords(other.q, other.r)
                        if e.sprite then
                            local sw, sh = e.sprite:getDimensions()
                            love.graphics.setColor(1, 1, 1, 0.5)
                            love.graphics.draw(e.sprite, x2, y2, 0, 6, 6, sw / 2, sh / 2)
                            love.graphics.setColor(1, 1, 1, 1)
                        else
                            love.graphics.setColor(0.75, 0.35, 1, 0.35)
                            love.graphics.circle("fill", x2, y2, hex.radius * 0.45)
                            love.graphics.setColor(1, 1, 1, 1)
                        end
                    end
                end
            end

            local lines = {}
            if hasHighground then lines[#lines + 1] = _G.highgroundRaised and "- Lower the highground" or "- Raise the highground" end
            if hasTeleporter then lines[#lines + 1] = "- Activate the teleporters" end
            if hasConveyor then lines[#lines + 1] = "- Run the conveyor belts" end
            lines[#lines + 1] = "Cooldown: 1 turn."
            if _G.mechanismUsedThisTurn then lines[#lines + 1] = "(used this turn)" end
            local ttW, ttH = 250, 36 + #lines * 16
            local ttx = r.x - ttW - 8
            local tty = r.y + r.h / 2 - ttH / 2
            love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
            love.graphics.rectangle("fill", ttx, tty, ttW, ttH, 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.rectangle("line", ttx, tty, ttW, ttH, 6)
            love.graphics.setColor(1, 1, 0.6, 1)
            love.graphics.print("Mechanism", ttx + 8, tty + 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            for j, line in ipairs(lines) do
                love.graphics.print(line, ttx + 8, tty + 22 + (j - 1) * 16)
            end
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- ═══ Abilities Toggle Button (index 3) ═══
    function ui.drawAbilitiesToggleButton(state, mouseX, mouseY)
        local r = ui.getRightBtnRect(3)
        local isHover = mouseX and mouseX >= r.x and mouseX <= r.x + r.w and mouseY >= r.y and mouseY <= r.y + r.h
        local open = global_abilities.showPanel

        local cr, cg, cb = 0.25, 0.25, 0.4
        if open then cr, cg, cb = 0.35, 0.2, 0.6 end
        love.graphics.setColor(cr, cg, cb, isHover and 0.95 or 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)

        local iconKey = icon_cache.keyForAbility("Heal") or "abil_heal"
        icon_cache.drawSmall(iconKey, r.x + 20, r.y + r.h / 2, 36)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        local arrow = open and "▲" or "▼"
        love.graphics.printf("Abilities " .. arrow, r.x + 40, r.y + r.h / 2 - 10, r.w - 40, "center")
        love.graphics.setFont(old)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- ═══ Order Button (index 3) ═══
    function ui.drawEnemyOrderButton(mouseX, mouseY)
        local r = ui.getRightBtnRect(2)
        local isHover = mouseX >= r.x and mouseX <= r.x + r.w and mouseY >= r.y and mouseY <= r.y + r.h

        love.graphics.setColor(isHover and 0.6 or 0.3, 0.4, 0.6, 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        icon_cache.drawSmall("btn_order", r.x + 20, r.y + r.h / 2, 36)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Order (O)", r.x + 40, r.y + r.h / 2 - 10, r.w - 40, "center")
        love.graphics.setFont(old)

        if isHover then
            -- Interactive tooltip: only phases whose objects exist on the map right now
            local lines = {}
            local hasCaravan, hasBlockpost = false, false
            local hasEnemies, hasPrepared = false, false
            local hasUnitTargets, hasBuildingTargets = false, false
            local hasBurningOrDecay = false
            for _, e in ipairs(entities) do
                if e:isCharacter() and not e.isPlayable and e.health > 0 then
                    hasEnemies = true
                    if e.hasPreparedAttack then
                        hasPrepared = true
                        if e._preparedTargetType == "building" then
                            hasBuildingTargets = true
                        else
                            hasUnitTargets = true
                        end
                    end
                end
                if e.health and e.health > 0 and not e.isDying then
                    if e.name == "Caravan" then hasCaravan = true
                    elseif e.name == "Blockpost" then hasBlockpost = true end
                    if status.hasEntityStatus(e, "fire") or status.hasEntityStatus(e, "decay") then
                        hasBurningOrDecay = true
                    end
                end
            end
            if hasCaravan and hasBlockpost then lines[#lines + 1] = "Caravans move" end
            if hasEnemies then lines[#lines + 1] = "Enemies move & prepare attacks" end
            lines[#lines + 1] = "Player turn"
            if hasPrepared then
                if hasUnitTargets then lines[#lines + 1] = "Enemies attack player/units (in order)" end
                if hasBuildingTargets then lines[#lines + 1] = "Enemies attack buildings (in order)" end
            end
            if hasBurningOrDecay then lines[#lines + 1] = "Debuffs: fire & decay apply" end
            if status.getAllDigSites and #status.getAllDigSites() > 0 then
                lines[#lines + 1] = "Dig sites damage & spawn"
            end

            local ttW, ttH = 260, 22 + #lines * 16
            local tx = logicalW - ttW - 10
            local ty = 46
            love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
            love.graphics.rectangle("fill", tx, ty, ttW, ttH, 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.rectangle("line", tx, ty, ttW, ttH, 6)
            love.graphics.setColor(1, 1, 0.6, 1)
            love.graphics.print("Turn Order", tx + 8, ty + 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            for i, line in ipairs(lines) do
                love.graphics.print(i .. ". " .. line, tx + 8, ty + 22 + (i - 1) * 16)
            end
            love.graphics.setColor(1, 1, 1, 1)
        end
        return isHover
    end

    -- ═══ Undo Button (index 1) ═══
    function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
        local canUndo = #undo.history > 1
        local count = #undo.history - 1
        local r = ui.getRightBtnRect(1)

        love.graphics.setColor(canUndo and 0.2 or 0.5, 0.2, 0.8, 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        icon_cache.drawSmall("btn_undo", r.x + 20, r.y + r.h / 2, 36)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Undo (U) [" .. count .. "]", r.x + 40, r.y + r.h / 2 - 10, r.w - 40, "center")
            love.graphics.setFont(old)
            if not canUndo then
                love.graphics.setColor(0, 0, 0, 0.6)
                love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
            end
    end

    -- ═══ End Turn Button (bottom center) ═══
    function ui.drawEndTurnButton(turnState, entities, turnCount, maxTurns, state)
        local isPlayerTurn = (turnState.phase == "player")
        local btn = endTurnButton
        local isPressed = btn.isHeld
        local pressedOffset = isPressed and 2 or 0
        local r = ui.getEndTurnRect()

        local hasActiveUnits = false
        if isPlayerTurn then
            for _, e in ipairs(entities) do
                local done = e.hasActedThisTurn and not (e.soloActions and (e.movesLeft or 0) > 0)
                if e.isPlayable and e.health > 0 and not done then
                    hasActiveUnits = true
                    break
                end
            end
        end
        local canUseAbility = false
        if isPlayerTurn and state and global_abilities then
            for _, name in ipairs(global_abilities.getDisplayOrder(state)) do
                local ab = global_abilities.registry[name]
                if ab and not ab.hasBeenUsed and not global_abilities.abilityUsedThisTurn
                    and global_abilities.mana >= ab.manaCost then
                    canUseAbility = true
                    break
                end
            end
        end
        local nothingLeft = isPlayerTurn and not hasActiveUnits and not canUseAbility
        ui.endTurnHoldTime = nothingLeft and 0.3 or 0.7

        local baseR, baseG, baseB = 0.8, 0.2, 0.2
        if nothingLeft then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4)
            baseR = 0.2 + 0.6 * pulse
            baseG = 0.6 + 0.4 * pulse
            baseB = 0.2 + 0.3 * pulse
        elseif not isPlayerTurn then
            baseR, baseG, baseB = 0.4, 0.2, 0.2
        elseif isPressed then
            baseR, baseG, baseB = 0.5, 0.2, 0.2
        end

        love.graphics.setColor(baseR, baseG, baseB, 0.85)
        love.graphics.rectangle("fill", r.x, r.y + pressedOffset, r.w, r.h - pressedOffset, 8)

        if isPressed then
            local hTime = ui.endTurnHoldTime
            local progress = math.min(btn.holdTimer / hTime, 1)
            love.graphics.setColor(0.9, 0.3, 0.2, 0.6)
            love.graphics.rectangle("fill", r.x, r.y + pressedOffset, r.w * progress, r.h - pressedOffset, 8)
        end

        icon_cache.drawSmall("btn_end_turn", r.x + r.w / 2 - 70, r.y + r.h / 2 + pressedOffset, 40)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("End Turn (E)", r.x + r.w / 2 - 35, r.y + r.h / 2 - 10 + pressedOffset, r.w / 2, "left")
        love.graphics.setFont(old)
        if not isPlayerTurn then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8)
        end

        if btn.isHovered and isPlayerTurn and hasActiveUnits then
            local unitsLeft = {}
            for _, e in ipairs(entities) do
                local done = e.hasActedThisTurn and not (e.soloActions and (e.movesLeft or 0) > 0)
                if e.isPlayable and e.health > 0 and not done then
                    table.insert(unitsLeft, e.name)
                end
            end
            if #unitsLeft > 0 then
                local names = table.concat(unitsLeft, ", ")
                local ttW, ttH = 260, 48
                local tx, ty = r.x + r.w / 2 - ttW / 2, r.y - ttH - 6
                love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
                love.graphics.rectangle("fill", tx, ty, ttW, ttH, 6)
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                love.graphics.rectangle("line", tx, ty, ttW, ttH, 6)
                love.graphics.setColor(1, 0.8, 0.4, 1)
                love.graphics.print("Hold to end turn:", tx + 8, ty + 6)
                love.graphics.setColor(0.9, 0.9, 0.9, 1)
                love.graphics.print(names, tx + 8, ty + 26)
            end
        end
    end

    -- ═══ Attack Panel (left column, only when abilities hidden) ═══
    function ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode)
        if global_abilities.showPanel then return end
        if not selectedActor or selectedActor.hasActedThisTurn then return end
        if #attackButtons == 0 then return end

        if selectedActor.chainAttack then
            love.graphics.setColor(1, 0.8, 0.2, 1)
            local cy = logicalH - leftCol.margin - #attackButtons * (leftCol.itemH + leftCol.gap) - leftCol.itemH - 20
            love.graphics.print("Chain: " .. selectedActor.chainAttack, leftCol.x, cy)
        end

        for i, btn in ipairs(attackButtons) do
            local ri = ui.getLeftItemRect(i)
            btn.x = ri.x
            btn.y = ri.y
            btn.width = ri.w
            btn.height = ri.h
            local isSelected = (selectedAttack == btn.attack and attackMode)
            love.graphics.setColor(isSelected and 0.9 or 0.3, 0.7, 0.3, 0.8)
            love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 5)

            local iconKey = icon_cache.keyForAttack(btn.name)
            if iconKey then
                icon_cache.drawSmall(iconKey, btn.x + 22, btn.y + leftCol.itemH / 2, 36)
            end
            love.graphics.setColor(1, 1, 1, 1)
            local old = love.graphics.getFont()
            love.graphics.setFont(buttonFont)
            local prefix = ""
            love.graphics.printf(prefix .. btn.name .. (isSelected and " ✓" or ""), btn.x + 42, btn.y + leftCol.itemH / 2 - 10, leftCol.w - 42, "center")
            love.graphics.setFont(old)
        end

        for _, btn in ipairs(attackButtons) do
            if selectedAttack == btn.attack and attackMode then
                love.graphics.setColor(1, 1, 0.5, 0.9)
                local font = love.graphics.getFont()
                local descX = leftCol.x + leftCol.w + 10
                local descY = btn.y
                local maxW = 200
                local lines = {}
                for word in btn.desc:gmatch("%S+") do
                    if #lines == 0 then
                        table.insert(lines, word)
                    else
                        local candidate = lines[#lines] .. " " .. word
                        if font:getWidth(candidate) <= maxW then
                            lines[#lines] = candidate
                        else
                            table.insert(lines, word)
                        end
                    end
                end
                for i, line in ipairs(lines) do
                    love.graphics.print(line, descX, descY + (i - 1) * 16)
                end
                break
            end
        end
    end

    -- ═══ Ability buttons (left column, only when panel open) ═══
    function ui.drawAbilityButtons(state)
        if not global_abilities.showPanel then return end
        local displayOrder = global_abilities.getDisplayOrder(state)
        if #displayOrder == 0 then return end

        local mx, my = love.mouse.getPosition()
        mx, my = mx / (state.dpiScale or 1), my / (state.dpiScale or 1)

        for i, name in ipairs(displayOrder) do
            local ab = global_abilities.registry[name]
            if not ab then goto continue end

            local ri = ui.getLeftItemRect(i)
            ab.button.x = ri.x
            ab.button.y = ri.y
            ab.button.width = ri.w
            ab.button.height = ri.h
            ab:drawButton(mx, my, state)

            local unlimited = state.unlimitedAbilities
            local available = (state.turnState.phase == "player"
                and (unlimited or (not ab.hasBeenUsed and not global_abilities.abilityUsedThisTurn
                and global_abilities.mana >= ab.manaCost)))
            local isActive = (global_abilities.activeAbility == ab)

            local cr, cg, cb = 0.22, 0.22, 0.32
            if isActive then
                cr, cg, cb = 0.4, 0.25, 0.7
            elseif available then
                cr, cg, cb = 0.28, 0.28, 0.45
            end
            love.graphics.setColor(cr, cg, cb, available and 0.9 or 0.35)
            love.graphics.rectangle("fill", ri.x, ri.y, ri.w, ri.h, 5)

            local iconKey = icon_cache.keyForAbility(name) or "abil_heal"
            icon_cache.drawSmall(iconKey, ri.x + 22, ri.y + ri.h / 2, 36)

            love.graphics.setColor(1, 1, 1, available and 1 or 0.5)
            local old = love.graphics.getFont()
            love.graphics.setFont(buttonFont)
            local label = (isActive and "[ " .. name .. " ]" or name)
            love.graphics.printf(label, ri.x + 42, ri.y + ri.h / 2 - 10, ri.w - 65, "left")
            love.graphics.setColor(1, 1, 1, (global_abilities.mana >= ab.manaCost) and 1 or 0.4)
            love.graphics.print("[" .. ab.manaCost .. "]", ri.x + ri.w - 34, ri.y + ri.h / 2 - 10)
            love.graphics.setFont(old)

            -- Tooltip on hover
            if mx >= ri.x and mx <= ri.x + ri.w and my >= ri.y and my <= ri.y + ri.h then
                local ttW = 240
                local ttH = 36 + #(ab._cfg and ab._cfg.tooltipLines or {}) * 16
                local ttx = ri.x + ri.w + 8
                local tty = ri.y + ri.h / 2 - ttH / 2
                if ttx + ttW > logicalW - 10 then ttx = ri.x - ttW - 8 end
                love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
                love.graphics.rectangle("fill", ttx, tty, ttW, ttH, 6)
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                love.graphics.rectangle("line", ttx, tty, ttW, ttH, 6)
                love.graphics.setColor(1, 1, 0.6, 1)
                local usedText = ab.hasBeenUsed and " (used)" or ""
                love.graphics.print((ab._cfg and ab._cfg.tooltipTitle or name) .. usedText, ttx + 8, tty + 6)
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                if ab._cfg then
                    for j, line in ipairs(ab._cfg.tooltipLines or {}) do
                        love.graphics.print(line, ttx + 8, tty + 22 + (j - 1) * 16)
                    end
                end
            end

            ::continue::
        end
    end
end
