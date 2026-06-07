-- input.lua
-- Обработка ввода (мышь, клавиатура). Использует глобалы, как и остальные модули.
local input = {}

function input.mousepressed(x, y, button)
    if button ~= 1 then return end

    if not gameActive then
        local width = logicalW
        local height = logicalH
        local btnW, btnH = 200, 50
        local btnX = width/2 - btnW/2
        local btnY = height/2 + 20
        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            restartGame()
        end
        return
    end

    if x >= windTorrentUI.button.x and x <= windTorrentUI.button.x + windTorrentUI.button.width and
    y >= windTorrentUI.button.y and y <= windTorrentUI.button.y + windTorrentUI.button.height then
        if turnState.phase == "player" and windTorrent and not windTorrent.hasBeenUsed then
            windTorrentUI.active = true
            clearSelectedActor()
            print("Click on any hex to choose wind direction, or press ESC to cancel")
        elseif windTorrent and windTorrent.hasBeenUsed then
            print("Wind Torrent has already been used this game!")
        elseif turnState.phase ~= "player" then
            print("Can only use Wind Torrent during your turn!")
        else
            print("Wind Torrent not available")
        end
        return
    end

    if x >= restartButton.x and x <= restartButton.x + restartButton.width and
       y >= restartButton.y and y <= restartButton.y + restartButton.height then
        restartGame()
        return
    end

    -- Heal ability button
    local healBtn = { x = 10, y = 120, width = 120, height = 30 }
    if x >= healBtn.x and x <= healBtn.x + healBtn.width and y >= healBtn.y and y <= healBtn.y + healBtn.height then
        if healUI.active then
            healUI.active = false
            restoreSelectedActor()
            print("Heal cancelled")
        elseif turnState.phase ~= "player" then
            print("Can only use abilities during your turn!")
        elseif healAbility.hasBeenUsed then
            print("Heal has already been used this game!")
        else
            windTorrentUI.active = false
            extraMoveUI.active = false
            healUI.active = true
            clearSelectedActor()
            print("Click on an ally to heal, or press ESC to cancel")
        end
        return
    end

    -- Extra Move ability button
    local extraBtn = { x = 10, y = 155, width = 120, height = 30 }
    if x >= extraBtn.x and x <= extraBtn.x + extraBtn.width and y >= extraBtn.y and y <= extraBtn.y + extraBtn.height then
        if extraMoveUI.active then
            extraMoveUI.active = false
            restoreSelectedActor()
            print("Extra Move cancelled")
        elseif turnState.phase ~= "player" then
            print("Can only use abilities during your turn!")
        elseif extraMoveAbility.hasBeenUsed then
            print("Extra Move has already been used this game!")
        else
            windTorrentUI.active = false
            healUI.active = false
            extraMoveUI.active = true
            clearSelectedActor()
            print("Click on an ally that has already attacked, or press ESC to cancel")
        end
        return
    end

    if windTorrentUI.active then
        local tq, tr = hex:pixelToHex(x, y)
        if hex:isActiveHex(tq, tr) then
            local direction = getWindDirectionFromHex(tq, tr, hex.centerQ, hex.centerR, hex)
            if direction then
                windTorrent:executeGlobalWithAnimation(direction, hex, entities, sounds, terrainMap, globalHealth, function(success, message)
                    if success then
                        actionHistory = {}
                        print("Wind Torrent used! History cleared.")
                    else
                        print("Wind Torrent failed: " .. (message or "unknown error"))
                    end
                    restoreSelectedActor()
                end)
                windTorrentUI.active = false
            else
                print("Cannot determine direction from center")
                restoreSelectedActor()
            end
            return
        else
            windTorrentUI.active = false
            restoreSelectedActor()
            print("Wind Torrent cancelled")
            return
        end
    end

    -- Ability targeting (Heal / Extra Move)
    if healUI.active or extraMoveUI.active then
        local tq, tr = hex:pixelToHex(x, y)
        if hex:isActiveHex(tq, tr) then
            local target = getEntityAtHex(tq, tr)
            local success = false
            if healUI.active then
                success = tryUseHealAbility(target)
            elseif extraMoveUI.active then
                success = tryUseExtraMoveAbility(target)
            end
            if success then
                healUI.active = false
                extraMoveUI.active = false
                restoreSelectedActor()
            end
        else
            print("Invalid hex")
        end
        return
    end

    if x >= 10 and x <= 130 and y >= 190 and y <= 220 then
        if #actionHistory > 0 then
            undoLastAction()
        else
            print("No actions to undo!")
        end
        return
    end

    if x >= endTurnButton.x and x <= endTurnButton.x + endTurnButton.width and
       y >= endTurnButton.y and y <= endTurnButton.y + endTurnButton.height then
        if turnState.phase == "player" then
            endTurn()
        else
            print("Not your turn")
        end
        return
    end

    -- Enemy Order button toggle
    local orderBtnX = logicalW - 110
    local orderBtnY = logicalH - 40
    if x >= orderBtnX and x <= orderBtnX + 100 and y >= orderBtnY and y <= orderBtnY + 30 then
        showEnemyOrder = not showEnemyOrder
        print("Enemy order display: " .. (showEnemyOrder and "ON" or "OFF"))
        return
    end

    if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving then
        for _, btn in ipairs(attackButtons) do
            if x >= btn.x and x <= btn.x + btn.width and y >= btn.y and y <= btn.y + btn.height then
                selectedAttack = btn.attack
                attackMode = true
                print("[DEBUG] Attack selected: " .. btn.name .. " (attackMode = true)")
                return
            end
        end
    end

    local tq, tr = hex:pixelToHex(x, y)
    if not hex:isValidHex(tq, tr) then
        return
    end

    if attackMode and selectedAttack and selectedActor and not selectedActor.hasActedThisTurn then
        -- Flip: first select target (any adjacent character), then choose destination cell
        if selectedAttack.name == "Flip" then
            if flipTargetActor then
                -- Step 2: clicked on a destination cell
                local destQ, destR = tq, tr
                local actorQ, actorR = selectedActor.q, selectedActor.r
                local targetQ, targetR = flipTargetActor.q, flipTargetActor.r
                local cells = selectedAttack:getFlipCells(selectedActor, targetQ, targetR, hex, entities)
                local isValidDest = false
                for _, c in ipairs(cells) do
                    if c.q == destQ and c.r == destR then
                        isValidDest = true
                        break
                    end
                end
                if isValidDest then
                    selectedAttack._flipDestCell = {q = destQ, r = destR}
                    local success, msg = performAttackWithSelectedAttack(selectedActor, targetQ, targetR, selectedAttack)
                    if not success then print("Attack failed: " .. msg) end
                    attackMode = false
                    selectedAttack = nil
                    flipTargetActor = nil
                    globalHealth.previewDamage = 0
                else
                    -- Clicked elsewhere — cancel destination choice, stay in attackMode
                    flipTargetActor = nil
                end
            else
                -- Step 1: click on any adjacent character (ally or enemy) to select as flip target
                local clicked = getEntityAtHex(tq, tr)
                if clicked and clicked:isCharacter() and clicked ~= selectedActor and
                   hex:getDistance(selectedActor.q, selectedActor.r, tq, tr) == 1 then
                    flipTargetActor = clicked
                end
            end
            return
        else
            local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
            if not success then print("Attack failed: " .. msg) end
        end
        attackMode = false
        selectedAttack = nil
        globalHealth.previewDamage = 0
        return
    end

    local clicked = getEntityAtHex(tq, tr)
    if clicked and clicked.isPlayable and clicked.health > 0 then
        selectedActor = clicked
        hex.selectedQ, hex.selectedR = tq, tr
        updateAttackButtons(selectedActor)
        attackMode = false
        selectedAttack = nil
        print("Selected: " .. clicked.name .. (clicked.hasActedThisTurn and " (acted)" or ""))
        return
    end

    if selectedActor and not selectedActor.isMoving then
        local canMove = (not selectedActor.hasActedThisTurn or selectedActor.canMoveAfterAttack) and (not selectedActor.hasMovedThisTurn or selectedActor.canMoveAfterAttack)
        if canMove then
            performMove(selectedActor, tq, tr)
            hex.selectedQ, hex.selectedR = selectedActor.q, selectedActor.r
            attackMode = false
            selectedAttack = nil
        end
    end
end

function input.keypressed(key)
    if not gameActive then
        if key == "return" or key == " " or key == "r" or key == "R" then
            restartGame()
        end
        return
    end

    if key == "escape" then
        if healUI.active then
            healUI.active = false
            restoreSelectedActor()
            print("Heal cancelled")
        elseif extraMoveUI.active then
            extraMoveUI.active = false
            restoreSelectedActor()
            print("Extra Move cancelled")
        elseif windTorrentUI.active then
            windTorrentUI.active = false
            restoreSelectedActor()
            print("Wind Torrent cancelled")
        elseif flipTargetActor then
            flipTargetActor = nil
            print("Flip target cancelled")
        elseif attackMode then
            attackMode = false
            selectedAttack = nil
            print("Attack cancelled")
        end
        return
    end

    if key == "u" or key == "U" then
        if #actionHistory > 0 then undoLastAction() end
        return
    end

    if key == "e" or key == "E" then
        if turnState.phase == "player" then endTurn() end
        return
    end

    if key == "r" or key == "R" then
        restartGame()
        return
    end

    if key == "o" or key == "O" then
        showEnemyOrder = not showEnemyOrder
        print("Enemy order display: " .. (showEnemyOrder and "ON" or "OFF"))
        return
    end

    if key == "w" or key == "W" then
        if turnState.phase == "player" and windTorrent and not windTorrent.hasBeenUsed then
            windTorrentUI.active = true
            clearSelectedActor()
            print("Click on any hex to choose wind direction, or press ESC to cancel")
        elseif windTorrent and windTorrent.hasBeenUsed then
            print("Wind Torrent has already been used this game!")
        elseif turnState.phase ~= "player" then
            print("Can only use Wind Torrent during your turn!")
        else
            print("Wind Torrent not available")
        end
        return
    end

    if key == "h" or key == "H" then
        if healUI.active then
            healUI.active = false
            restoreSelectedActor()
            print("Heal cancelled")
        elseif turnState.phase ~= "player" then
            print("Can only use abilities during your turn!")
        elseif healAbility.hasBeenUsed then
            print("Heal has already been used this game!")
        else
            windTorrentUI.active = false
            extraMoveUI.active = false
            healUI.active = true
            clearSelectedActor()
            print("Click on an ally to heal, or press ESC to cancel")
        end
        return
    end

    if key == "x" or key == "X" then
        if extraMoveUI.active then
            extraMoveUI.active = false
            restoreSelectedActor()
            print("Extra Move cancelled")
        elseif turnState.phase ~= "player" then
            print("Can only use abilities during your turn!")
        elseif extraMoveAbility.hasBeenUsed then
            print("Extra Move has already been used this game!")
        else
            windTorrentUI.active = false
            healUI.active = false
            extraMoveUI.active = true
            clearSelectedActor()
            print("Click on an ally that has already attacked, or press ESC to cancel")
        end
        return
    end

    if key == "1" then
        if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving and #attackButtons >= 1 then
            selectedAttack = attackButtons[1].attack
            attackMode = true
            print("[DEBUG] Attack selected: " .. attackButtons[1].name)
        end
        return
    end

    if key == "2" then
        if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving and #attackButtons >= 2 then
            selectedAttack = attackButtons[2].attack
            attackMode = true
            print("[DEBUG] Attack selected: " .. attackButtons[2].name)
        end
        return
    end

    if key == "tab" then
        if turnState.phase == "player" then
            local actors = {}
            for _, e in ipairs(entities) do
                if e.isPlayable and e.health > 0 then
                    table.insert(actors, e)
                end
            end
            if #actors > 0 then
                local currentIdx = 1
                if selectedActor then
                    for i, a in ipairs(actors) do
                        if a == selectedActor then
                            currentIdx = i
                            break
                        end
                    end
                end
                local forward = not love.keyboard.isDown("lshift") and not love.keyboard.isDown("rshift")
                local nextIdx
                if forward then
                    nextIdx = currentIdx % #actors + 1
                else
                    nextIdx = (currentIdx - 2 + #actors) % #actors + 1
                end
                selectedActor = actors[nextIdx]
                hex.selectedQ, hex.selectedR = selectedActor.q, selectedActor.r
                updateAttackButtons(selectedActor)
                attackMode = false
                selectedAttack = nil
                print("Selected: " .. selectedActor.name)
            end
        end
        return
    end
end

function tryUseHealAbility(target)
    if turnState.phase ~= "player" then
        print("Can only use abilities during your turn!")
        return false
    end
    if healAbility.hasBeenUsed then
        print("Heal has already been used this game!")
        return false
    end
    if not target or not target.isPlayable or target.health <= 0 then
        print("No valid ally targeted!")
        return false
    end
    local hasDebuffs = #status.getEntityStatuses(target) > 0 or status.hasDigSite(target.q, target.r)
    if target.health >= target.maxHealth and not hasDebuffs then
        print(tostring(target.name) .. " is at full health with no debuffs to cure!")
        return false
    end
    target.health = target.maxHealth
    status.entityStatuses[target] = nil
    if status.hasAtHex(target.q, target.r, "fire") then
        status.removeFromHex(target.q, target.r, "fire")
        print("Fire on the ground extinguished!")
    end
    healAbility.hasBeenUsed = true
    actionHistory = {}
    print(tostring(target.name) .. " fully healed and all negative effects removed!")
    return true
end

function tryUseExtraMoveAbility(target)
    if turnState.phase ~= "player" then
        print("Can only use abilities during your turn!")
        return false
    end
    if extraMoveAbility.hasBeenUsed then
        print("Extra Move has already been used this game!")
        return false
    end
    if not target or not target.isPlayable or target.health <= 0 then
        print("No valid ally targeted!")
        return false
    end
    if not target.hasActedThisTurn then
        print(tostring(target.name) .. " hasn't attacked yet — cannot use Extra Move!")
        return false
    end
    target.canMoveAfterAttack = true
    extraMoveAbility.hasBeenUsed = true
    actionHistory = {}
    print(tostring(target.name) .. " can now move after attacking!")
    return true
end

return input
