-- ui_buttons.lua
-- Extracted button functions. Do not depend on other ui.* functions.
-- Takes a ui-table and registers functions on it.
return function(ui)
    local buttonFont = love.graphics.newFont(11)

    function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
        local canUndo = #actionHistory > 0
        local btnY = logicalH - 65
        love.graphics.setColor(canUndo and 0.2 or 0.5, 0.2, 0.8, 0.8)
            love.graphics.rectangle("fill", 10, btnY, 120, 30, 5)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Undo (U)", 10, btnY + 9, 120, "center")
        love.graphics.setFont(old)
        if not canUndo then
            love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, btnY, 120, 30, 5)
        end
    end

    function ui.drawDecayButton(mouseX, mouseY, turnCount, maxTurns, phase)
        local decayActive = turnCount >= maxTurns
        local text = decayActive and "Decay active!" or ("Decay in: " .. (maxTurns - turnCount))
        local btnW, btnH = 140, 22
        local x = 10
    local y = logicalH - 105

    local isHover = mouseX >= x and mouseX <= x + btnW and mouseY >= y and mouseY <= y + btnH

        if decayActive then
            local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 3)
            love.graphics.setColor(pulse, 0.2, 0.2, 0.9)
        else
            love.graphics.setColor(isHover and 0.5 or 0.35, 0.35, 0.25, 0.85)
        end
        love.graphics.rectangle("fill", x, y, btnW, btnH, 4)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(text, x + 6, y + 4)

        if isHover then
            local tooltipW, tooltipH = 300, 82
            local tx, ty = x + btnW + 6, y
            if tx + tooltipW > logicalW - 10 then
                tx = x - tooltipW - 6
            end
            love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
            love.graphics.rectangle("fill", tx, ty, tooltipW, tooltipH, 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.rectangle("line", tx, ty, tooltipW, tooltipH, 6)

            love.graphics.setColor(1, 1, 0.6, 1)
            love.graphics.print("Turn " .. turnCount .. " / " .. maxTurns .. "  |  Phase: " .. phase, tx + 8, ty + 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.print("All enemies gain Decay (1 dmg/end),", tx + 8, ty + 26)
            love.graphics.print("dig sites are cleared, and new ones", tx + 8, ty + 42)
            love.graphics.print("stop appearing. Defeat all to win.", tx + 8, ty + 58)
            love.graphics.setColor(1, 1, 1, 1)
        end

        return isHover
    end

    function ui.drawEndTurnButton(turnState, entities)
        local isPlayerTurn = (turnState.phase == "player")
        local btn = endTurnButton
        local isPressed = btn.isHeld
        local pressedOffset = isPressed and 2 or 0
        local btnY = logicalH - 65

        love.graphics.setColor(isPlayerTurn and (isPressed and 0.5 or 0.8) or 0.4, 0.2, 0.2, 0.8)
        love.graphics.rectangle("fill", 140, btnY + pressedOffset, 110, 30 - pressedOffset, 5)

        if isPressed then
            local progress = math.min(btn.holdTimer / config.HOLD_TIME, 1)
            love.graphics.setColor(0.9, 0.3, 0.2, 0.6)
            love.graphics.rectangle("fill", 140, btnY + pressedOffset, 110 * progress, 30 - pressedOffset, 5)
        end

        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("End Turn (E)", 140, btnY + 9 + pressedOffset, 110, "center")
        love.graphics.setFont(old)
        if not isPlayerTurn then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", 140, btnY, 110, 30, 5)
        end

        if btn.isHovered and isPlayerTurn then
            local unitsLeft = {}
            for _, e in ipairs(entities) do
                if e.isPlayable and e.health > 0 and not e.hasActedThisTurn then
                    table.insert(unitsLeft, e.name)
                end
            end
            if #unitsLeft > 0 then
                local names = table.concat(unitsLeft, ", ")
                local tooltipW, tooltipH = 260, 48
                local tx, ty = 140 + 110 + 6, btnY
                if tx + tooltipW > logicalW - 10 then
                    tx = 140 - tooltipW - 6
                end
                love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
                love.graphics.rectangle("fill", tx, ty, tooltipW, tooltipH, 6)
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                love.graphics.rectangle("line", tx, ty, tooltipW, tooltipH, 6)
                love.graphics.setColor(1, 0.8, 0.4, 1)
                love.graphics.print("Hold to end turn:", tx + 8, ty + 6)
                love.graphics.setColor(0.9, 0.9, 0.9, 1)
                love.graphics.print(names, tx + 8, ty + 26)
            end
        end
    end

    function ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode)
        if not selectedActor or selectedActor.hasActedThisTurn then return end
        if #attackButtons == 0 then return end

        for i, btn in ipairs(attackButtons) do
            btn.x = logicalW - 155
            btn.y = 100 + (i - 1) * 32
            btn.width = 145
            btn.height = 28
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
        -- Show chain indicator
        if selectedActor.chainAttack then
            love.graphics.setColor(1, 0.8, 0.2, 1)
            love.graphics.print("Chain: " .. selectedActor.chainAttack, logicalW - 155, 100 - 16)
        end
    end

    function ui.drawEnemyOrderButton(mouseX, mouseY)
        local btnW, btnH = 100, 30
        local x = 160
        local y = logicalH - 105
        local isHover = mouseX >= x and mouseX <= x + btnW and mouseY >= y and mouseY <= y + btnH

        love.graphics.setColor(isHover and 0.6 or 0.3, 0.4, 0.6, 0.8)
        love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Order (O)", x + 13, y + 8)

        if isHover then
            local tooltipW, tooltipH = 260, 140
            local tx, ty = x - tooltipW - 6, y
            if tx < 10 then tx = x + btnW + 6 end
            if ty + tooltipH > logicalH - 10 then
                ty = logicalH - tooltipH - 10
            end
            love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
            love.graphics.rectangle("fill", tx, ty, tooltipW, tooltipH, 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.rectangle("line", tx, ty, tooltipW, tooltipH, 6)
            love.graphics.setColor(1, 1, 0.6, 1)
            love.graphics.print("Turn Order", tx + 8, ty + 6)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.print("1. Neutral NPCs move", tx + 8, ty + 26)
            love.graphics.print("2. Effects: fire & decay apply", tx + 8, ty + 42)
            love.graphics.print("   simultaneously to all units", tx + 8, ty + 58)
            love.graphics.print("3. Enemies attack in sequence", tx + 8, ty + 74)
            love.graphics.print("4. Dig sites damage simultaneously", tx + 8, ty + 90)
            love.graphics.print("5. Trains move (locomotive crushes", tx + 8, ty + 106)
            love.graphics.print("   anything in its path)", tx + 8, ty + 122)
            love.graphics.setColor(1, 1, 1, 1)
        end

        return isHover
    end

    function ui.drawRestartButton(button, turnState)
        local isPressed = button.isHeld
        local pressedOffset = isPressed and 2 or 0
        love.graphics.setColor(0.4, 0.2, 0.6, 0.8)
        love.graphics.rectangle("fill", button.x, button.y + pressedOffset, button.width, button.height - pressedOffset, 5)
        if isPressed then
            local progress = math.min(button.holdTimer / config.HOLD_TIME, 1)
            love.graphics.setColor(0.9, 0.3, 0.6, 0.6)
            love.graphics.rectangle("fill", button.x, button.y + pressedOffset, button.width * progress, button.height - pressedOffset, 5)
        end
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf(button.text .. " (R)", button.x, button.y + 9 + pressedOffset, button.width, "center")
        love.graphics.setFont(old)
    end

end
