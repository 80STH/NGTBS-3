-- ui_buttons.lua
-- Extracted button functions. Do not depend on other ui.* functions.
-- Takes a ui-table and registers functions on it.
return function(ui)
    local fonts = require("util.fonts")
    local buttonFont = fonts.get(11)

    local function layout()
        local btnH = 50
        local margin = 10
        local gap = 10
        local thirdW = math.floor((logicalW - margin * 2 - gap * 2) / 3)
        local btnY = logicalH - btnH - 10
        return btnH, btnY, margin, gap, thirdW
    end

    function ui.drawEnemyOrderButton(mouseX, mouseY)
        local btnH, btnY, margin, gap, thirdW = layout()
        local x = margin
        local y = btnY
        local btnW = thirdW
        local isHover = mouseX >= x and mouseX <= x + btnW and mouseY >= y and mouseY <= y + btnH

        love.graphics.setColor(isHover and 0.6 or 0.3, 0.4, 0.6, 0.8)
        love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Order (O)", x, y + 10, btnW, "center")
        love.graphics.setFont(old)

        if isHover then
            local tooltipW, tooltipH = 260, 140
            local tx = logicalW - tooltipW - 10
            local ty = 10
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

    function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
        local canUndo = #undo.history > 1
        local undoCount = #undo.history - 1
        local btnH, btnY, margin, gap, thirdW = layout()
        local x = margin + thirdW + gap
        local y = btnY
        local btnW = thirdW
        love.graphics.setColor(canUndo and 0.2 or 0.5, 0.2, 0.8, 0.8)
        love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("Undo (U) [" .. undoCount .. "]", x, y + 10, btnW, "center")
        love.graphics.setFont(old)
        if not canUndo then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
        end
    end

    function ui.drawEndTurnButton(turnState, entities, turnCount, maxTurns, state)
        local isPlayerTurn = (turnState.phase == "player")
        local btn = endTurnButton
        local isPressed = btn.isHeld
        local pressedOffset = isPressed and 2 or 0
        local btnH, btnY, margin, gap, thirdW = layout()
        local x = margin + (thirdW + gap) * 2
        local y = btnY
        local btnW = thirdW

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
                local displayOrder = global_abilities.getDisplayOrder(state)
                for _, name in ipairs(displayOrder) do
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
        love.graphics.rectangle("fill", x, y + pressedOffset, btnW, btnH - pressedOffset, 5)

        if isPressed then
            local progress = math.min(btn.holdTimer / config.HOLD_TIME, 1)
            love.graphics.setColor(0.9, 0.3, 0.2, 0.6)
            love.graphics.rectangle("fill", x, y + pressedOffset, btnW * progress, btnH - pressedOffset, 5)
        end

        love.graphics.setColor(1, 1, 1, 1)
        local old = love.graphics.getFont()
        love.graphics.setFont(buttonFont)
        love.graphics.printf("End Turn (E)", x, y + 10 + pressedOffset, btnW, "center")
        love.graphics.setColor(decayActive and 1 or 0.7, decayActive and 0.3 or 0.7, decayActive and 0.3 or 0.9, 1)
        love.graphics.printf(decayText, x, y + 28 + pressedOffset, btnW, "center")
        love.graphics.setFont(old)
        if not isPlayerTurn then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", x, y, btnW, btnH, 5)
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
                local tooltipW, tooltipH = 260, 48
                local tx, ty = x - tooltipW - 6, y
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

        local btnH, btnY = layout()
        local panelX = 10
        local btnW = 145
        local abH = 28
        local btnGap = 32
        local totalAttackH = #attackButtons * abH + (#attackButtons - 1) * (btnGap - abH)
        local btnStartY = btnY - 10 - totalAttackH

        if selectedActor.chainAttack then
            love.graphics.setColor(1, 0.8, 0.2, 1)
            love.graphics.print("Chain: " .. selectedActor.chainAttack, panelX, btnStartY - 16)
        end

        local descY = btnStartY - (selectedActor.chainAttack and 32 or 16)
        local hasDesc = false
        for _, btn in ipairs(attackButtons) do
            if selectedAttack == btn.attack and attackMode then
                hasDesc = true
                love.graphics.setColor(1, 1, 0.5, 0.9)
                local font = love.graphics.getFont()
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
                    love.graphics.print(line, panelX, descY + (i - 1) * 16)
                end
                break
            end
        end

        for i, btn in ipairs(attackButtons) do
            btn.x = panelX
            btn.y = btnStartY + (i - 1) * btnGap
            btn.width = btnW
            btn.height = abH
            local isSelected = (selectedAttack == btn.attack and attackMode)
            love.graphics.setColor(isSelected and 0.9 or 0.3, 0.7, 0.3, 0.8)
            love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 5)
            love.graphics.setColor(1, 1, 1, 1)
            local prefix = i .. "."
            love.graphics.print(prefix .. " " .. btn.name .. (isSelected and " ✓" or ""), btn.x + 5, btn.y + 8)
        end
    end

end
