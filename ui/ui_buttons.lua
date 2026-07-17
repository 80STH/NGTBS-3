-- ui_buttons.lua
-- Right column: Abilities toggle, Order, Undo, End Turn (vertical stack)
-- Left column: Attacks OR Abilities (toggled)
return function(ui)
    local fonts = require("util.fonts")
    local buttonFont = fonts.get(11)
    local icon_cache = require("ui.icon_cache")

    local rightCol = { x = 0, w = 160, btnH = 48, gap = 5, margin = 10 }
    local leftCol  = { x = 10, w = 200, itemH = 36, gap = 5, margin = 10 }

    function ui.getRightBtnRect(index)
        -- index: 1=EndTurn, 2=Undo, 3=Order, 4=Abilities (bottom→top)
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

    -- ═══ Abilities Toggle Button (index 4, top of right column) ═══
    function ui.drawAbilitiesToggleButton(state, mouseX, mouseY)
        local r = ui.getRightBtnRect(4)
        local isHover = mouseX and mouseX >= r.x and mouseX <= r.x + r.w and mouseY >= r.y and mouseY <= r.y + r.h
        local open = global_abilities.showPanel

        local cr, cg, cb = 0.25, 0.25, 0.4
        if open then cr, cg, cb = 0.35, 0.2, 0.6 end
        love.graphics.setColor(cr, cg, cb, isHover and 0.95 or 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)

        local iconKey = icon_cache.keyForAbility("Heal") or "abil_heal"
        icon_cache.drawSmall(iconKey, r.x + 18, r.y + r.h / 2, 28)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        local arrow = open and "▲" or "▼"
        love.graphics.printf("Abilities " .. arrow, r.x + 34, r.y + r.h / 2 - 9, r.w - 34, "center")
        love.graphics.setFont(old)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- ═══ Order Button (index 3) ═══
    function ui.drawEnemyOrderButton(mouseX, mouseY)
        local r = ui.getRightBtnRect(3)
        local isHover = mouseX >= r.x and mouseX <= r.x + r.w and mouseY >= r.y and mouseY <= r.y + r.h

        love.graphics.setColor(isHover and 0.6 or 0.3, 0.4, 0.6, 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        icon_cache.drawSmall("btn_order", r.x + 18, r.y + r.h / 2, 28)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Order (O)", r.x + 34, r.y + r.h / 2 - 9, r.w - 34, "center")
        love.graphics.setFont(old)

        if isHover then
            local ttW, ttH = 260, 150
            local tx = logicalW - ttW - 10
            local ty = 46
            love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
            love.graphics.rectangle("fill", tx, ty, ttW, ttH, 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.rectangle("line", tx, ty, ttW, ttH, 6)
            love.graphics.setColor(1, 1, 0.6, 1)
            love.graphics.print("Turn Order", tx + 8, ty + 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            local orders = {
                "1. Neutral NPCs move",
                "2. Effects: fire & decay apply",
                "   simultaneously to all units",
                "3. Enemies attack in sequence",
                "4. Dig sites damage simultaneously",
                "5. Trains move (locomotive crushes",
                "   anything in its path)",
            }
            for i, line in ipairs(orders) do
                love.graphics.print(line, tx + 8, ty + 22 + (i - 1) * 16)
            end
            love.graphics.setColor(1, 1, 1, 1)
        end
        return isHover
    end

    -- ═══ Undo Button (index 2) ═══
    function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
        local canUndo = #undo.history > 1
        local count = #undo.history - 1
        local r = ui.getRightBtnRect(2)

        love.graphics.setColor(canUndo and 0.2 or 0.5, 0.2, 0.8, 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        icon_cache.drawSmall("btn_undo", r.x + 18, r.y + r.h / 2, 28)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Undo (U) [" .. count .. "]", r.x + 34, r.y + r.h / 2 - 9, r.w - 34, "center")
        love.graphics.setFont(old)
        if not canUndo then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        end
    end

    -- ═══ End Turn Button (index 1) ═══
    function ui.drawEndTurnButton(turnState, entities, turnCount, maxTurns, state)
        local isPlayerTurn = (turnState.phase == "player")
        local btn = endTurnButton
        local isPressed = btn.isHeld
        local pressedOffset = isPressed and 2 or 0
        local r = ui.getRightBtnRect(1)

        local decayActive = turnCount >= maxTurns
        local decayText = decayActive and "Decay!" or ("Decay: " .. (maxTurns - turnCount))

        local shouldBlink = false
        if isPlayerTurn then
            local hasActiveUnits = false
            for _, e in ipairs(entities) do
                if e.isPlayable and e.health > 0 and not e.hasActedThisTurn
                    and not (status and status.hasEntityStatus and status.hasEntityStatus(e, "stasis")) then
                    hasActiveUnits = true
                    break
                end
            end
            local canUseAbility = false
            if state and global_abilities then
                for _, name in ipairs(global_abilities.getDisplayOrder(state)) do
                    local ab = global_abilities.registry[name]
                    if ab and not ab.hasBeenUsed and not global_abilities.abilityUsedThisTurn
                        and global_abilities.mana >= ab.manaCost then
                        canUseAbility = true
                        break
                    end
                end
            end
            shouldBlink = not hasActiveUnits and not canUseAbility
        end

        local baseR, baseG, baseB = 0.8, 0.2, 0.2
        if shouldBlink then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4)
            baseR = 0.2 + 0.6 * pulse
            baseG = 0.6 + 0.4 * pulse
            baseB = 0.2 + 0.3 * pulse
        elseif not isPlayerTurn then
            baseR, baseG, baseB = 0.4, 0.2, 0.2
        elseif isPressed then
            baseR, baseG, baseB = 0.5, 0.2, 0.2
        end

        love.graphics.setColor(baseR, baseG, baseB, 0.8)
        love.graphics.rectangle("fill", r.x, r.y + pressedOffset, r.w, r.h - pressedOffset, 5)

        if isPressed then
            local progress = math.min(btn.holdTimer / config.HOLD_TIME, 1)
            love.graphics.setColor(0.9, 0.3, 0.2, 0.6)
            love.graphics.rectangle("fill", r.x, r.y + pressedOffset, r.w * progress, r.h - pressedOffset, 5)
        end

        icon_cache.drawSmall("btn_end_turn", r.x + 18, r.y + r.h / 2 + pressedOffset, 28)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("End Turn (E)", r.x + 34, r.y + 9 + pressedOffset, r.w - 34, "center")
        love.graphics.setColor(decayActive and 1 or 0.7, decayActive and 0.3 or 0.7, decayActive and 0.3 or 0.9, 1)
        love.graphics.printf(decayText, r.x + 34, r.y + 27 + pressedOffset, r.w - 34, "center")
        love.graphics.setFont(old)
        if not isPlayerTurn then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        end

        if btn.isHovered and isPlayerTurn then
            local unitsLeft = {}
            for _, e in ipairs(entities) do
                if e.isPlayable and e.health > 0 and not e.hasActedThisTurn
                    and not (status and status.hasEntityStatus and status.hasEntityStatus(e, "stasis")) then
                    table.insert(unitsLeft, e.name)
                end
            end
            if #unitsLeft > 0 then
                local names = table.concat(unitsLeft, ", ")
                local ttW, ttH = 260, 48
                local tx, ty = r.x - ttW - 6, r.y + r.h / 2 - ttH / 2
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
                icon_cache.drawSmall(iconKey, btn.x + 18, btn.y + leftCol.itemH / 2, 28)
            end
            love.graphics.setColor(1, 1, 1, 1)
            local old = love.graphics.getFont()
            love.graphics.setFont(buttonFont)
            local prefix = i .. "."
            love.graphics.printf(prefix .. " " .. btn.name .. (isSelected and " ✓" or ""), btn.x + 34, btn.y + leftCol.itemH / 2 - 9, leftCol.w - 34, "center")
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
            icon_cache.drawSmall(iconKey, ri.x + 18, ri.y + ri.h / 2, 28)

            love.graphics.setColor(1, 1, 1, available and 1 or 0.5)
            local old = love.graphics.getFont()
            love.graphics.setFont(buttonFont)
            local label = (isActive and "[ " .. name .. " ]" or name)
            love.graphics.printf(label, ri.x + 34, ri.y + ri.h / 2 - 9, ri.w - 55, "left")
            love.graphics.setColor(1, 1, 1, (global_abilities.mana >= ab.manaCost) and 1 or 0.4)
            love.graphics.print("[" .. ab.manaCost .. "]", ri.x + ri.w - 30, ri.y + ri.h / 2 - 9)
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
