-- input.lua
-- Обработка ввода (мышь, клавиатура). Использует глобалы, как и остальные модули.
local input = {}
local global_abilities = require("global_abilities")

function input.mousepressed(x, y, button)
    if button ~= 1 then return end

    if gamePhase == "deploy" then
        if state and state.deployConfirmBtn and #unplacedAllies == 0 then
            local btn = state.deployConfirmBtn
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                confirmDeploy()
                return
            end
        end

        if x >= restartButton.x and x <= restartButton.x + restartButton.width and
           y >= restartButton.y and y <= restartButton.y + restartButton.height then
            restartGame()
            return
        end

    if turnState.phase ~= "player" then return end

    local tq, tr = hex:pixelToHex(x, y)
        if not hex or not hex:isValidHex(tq, tr) then return end
        if not hex:isActiveHex(tq, tr) then return end

        if terrainMap and terrainMap[tq] and terrainMap[tq][tr] == "water" then return end

        local occupant = getEntityAtHex(tq, tr)
        if occupant and not occupant.isPlayable then return end

        local placedIdx = nil
        for i, ally in ipairs(placedAllies) do
            if ally.q == tq and ally.r == tr then
                placedIdx = i
                break
            end
        end

        if placedIdx then
            if deploySelectedIdx then
                if deploySelectedIdx == placedIdx then
                    deploySelectedIdx = nil
                else
                    local a = placedAllies[deploySelectedIdx]
                    local b = placedAllies[placedIdx]
                    a.q, b.q = b.q, a.q
                    a.r, b.r = b.r, a.r
                    deploySelectedIdx = nil
                end
            else
                deploySelectedIdx = placedIdx
            end
        elseif not occupant then
            if deploySelectedIdx then
                placedAllies[deploySelectedIdx].q = tq
                placedAllies[deploySelectedIdx].r = tr
                deploySelectedIdx = nil
            elseif #unplacedAllies > 0 then
                local ally = table.remove(unplacedAllies, 1)
                ally.q = tq
                ally.r = tr
                table.insert(placedAllies, ally)
            end
        end
        return
    end

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

    if global_abilities.handleButtonClick(x, y, state) then return end

    if x >= restartButton.x and x <= restartButton.x + restartButton.width and
       y >= restartButton.y and y <= restartButton.y + restartButton.height then
        restartGame()
        return
    end

    if global_abilities.handleClick(x, y, state) then return end

    if x >= 10 and x <= 130 and y >= 190 and y <= 220 then
        if #actionHistory > 0 then
            undoLastAction()
        else
            print("No actions to undo!")
        end
        return
    end

    -- Test view button
    local tw, th = 120, 22
    local tx, ty = logicalW - 130, 10
    if x >= tx and x <= tx + tw and y >= ty and y <= ty + th then
        testViewActive = not testViewActive
        print("Test view: " .. (testViewActive and "ON" or "OFF"))
        return
    end

    if x >= endTurnButton.x and x <= endTurnButton.x + endTurnButton.width and
       y >= endTurnButton.y and y <= endTurnButton.y + endTurnButton.height then
        if turnState.phase == "player" then
            local hasActive = false
            for _, e in ipairs(entities) do
                if e.isPlayable and e.health > 0 and not e.hasActedThisTurn then
                    hasActive = true
                    break
                end
            end
            if hasActive then
                endTurnButton.isHeld = true
                endTurnButton.holdTimer = 0
            else
                endTurn()
            end
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

    -- Ally panel buttons
    if turnState.phase == "player" then
        for _, btn in ipairs(allyPanelButtons) do
            if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
                selectedActor = btn.entity
                hex.selectedQ, hex.selectedR = btn.entity.q, btn.entity.r
                updateAttackButtons(selectedActor)
                attackMode = false
                selectedAttack = nil
                return
            end
        end
    end

    if turnState.phase ~= "player" then return end

    local tq, tr = hex:pixelToHex(x, y)
    if not hex:isValidHex(tq, tr) then
        return
    end

    if attackMode and selectedAttack and selectedActor and not selectedActor.hasActedThisTurn then
        if selectedAttack.name == "Flip" then
            if flipTargetActor then
                local destQ, destR = tq, tr
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
                    flipTargetActor = nil
                end
            else
                local clicked = getEntityAtHex(tq, tr)
                if clicked and clicked:isCharacter() and clicked ~= selectedActor and
                   hex:getDistance(selectedActor.q, selectedActor.r, tq, tr) == 1 then
                    flipTargetActor = clicked
                end
            end
            return
        elseif selectedAttack.name == "Vortex Strike" then
            if vortexTargetCell then
                local destCells = selectedAttack:getShiftDestinations(selectedActor, vortexTargetCell.q, vortexTargetCell.r, hex)
                local isValidDest = false
                for _, dc in ipairs(destCells) do
                    if dc.q == tq and dc.r == tr then
                        selectedAttack._vortexDestCell = {q = dc.q, r = dc.r, dir = dc.dir}
                        local success, msg = performAttackWithSelectedAttack(selectedActor, vortexTargetCell.q, vortexTargetCell.r, selectedAttack)
                        if not success then print("Attack failed: " .. msg) end
                        isValidDest = true
                        break
                    end
                end
                if isValidDest then
                    attackMode = false
                    selectedAttack = nil
                    globalHealth.previewDamage = 0
                end
                vortexTargetCell = nil
            else
                local target = selectedAttack:getLineTarget(selectedActor, tq, tr, hex, entities)
                if target then
                    vortexTargetCell = {q = target.q, r = target.r}
                end
            end
            return
        elseif selectedAttack.name == "Wide Vortex" then
            if vortexTargetCell then
                local dests = selectedAttack:getShiftDestinations(selectedActor, vortexTargetCell.q, vortexTargetCell.r, hex)
                local isValidDest = false
                for _, dc in ipairs(dests) do
                    if dc.q == tq and dc.r == tr then
                        selectedAttack._vortexShiftDir = dc.dir
                        local success, msg = performAttackWithSelectedAttack(selectedActor, vortexTargetCell.q, vortexTargetCell.r, selectedAttack)
                        if not success then print("Attack failed: " .. msg) end
                        isValidDest = true
                        break
                    end
                end
                if isValidDest then
                    attackMode = false
                    selectedAttack = nil
                    globalHealth.previewDamage = 0
                end
                vortexTargetCell = nil
            else
                local target = selectedAttack:getLineTarget(selectedActor, tq, tr, hex, entities)
                if target then
                    vortexTargetCell = {q = target.q, r = target.r}
                end
            end
            return
        elseif selectedAttack.name == "Pull Hook" then
            if pullHookTargetCell then
                local stepX, stepY, stepZ = selectedAttack:getLineDirection(selectedActor.q, selectedActor.r, pullHookTargetCell.q, pullHookTargetCell.r, hex)
                if stepX then
                    local moveCells = selectedAttack:getPullHookMoveCells(selectedActor, stepX, stepY, stepZ, pullHookTargetCell.q, pullHookTargetCell.r, hex, entities)
                    local isValid = false
                    for _, c in ipairs(moveCells) do
                        if c.q == tq and c.r == tr then
                            selectedAttack._pullHookTarget = {q = pullHookTargetCell.q, r = pullHookTargetCell.r}
                            local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
                            if not success then print("Attack failed: " .. msg) end
                            isValid = true
                            break
                        end
                    end
                    if isValid then
                        attackMode = false
                        selectedAttack = nil
                        globalHealth.previewDamage = 0
                    end
                end
                pullHookTargetCell = nil
            else
                local target = selectedAttack:getLineTarget(selectedActor, tq, tr, hex, entities)
                if target then
                    pullHookTargetCell = {q = target.q, r = target.r, entity = target.entity}
                end
            end
            return
        elseif selectedAttack.name == "Electric Hook" then
            local dist = hex:getDistance(selectedActor.q, selectedActor.r, tq, tr)
            if dist >= 2 then
                local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
                if not success then print("Attack failed: " .. msg) end
                attackMode = false
                selectedAttack = nil
                globalHealth.previewDamage = 0
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
    if gamePhase == "deploy" then
        if (key == "return" or key == " ") and #unplacedAllies == 0 then
            confirmDeploy()
        elseif key == "escape" then
            deploySelectedIdx = nil
        elseif key == "r" or key == "R" then
            restartGame()
        end
        return
    end

    if not gameActive then
        if key == "return" or key == " " or key == "r" or key == "R" then
            restartGame()
        end
        return
    end

    if key == "escape" then
        if global_abilities.activeAbility then
            global_abilities.activeAbility:onDeactivate(state)
            global_abilities.activeAbility = nil
        elseif flipTargetActor then
            flipTargetActor = nil
            print("Flip target cancelled")
        elseif vortexTargetCell then
            vortexTargetCell = nil
            print("Vortex target cancelled")
        elseif pullHookTargetCell then
            pullHookTargetCell = nil
            print("Pull Hook cancelled")
        elseif attackMode then
            attackMode = false
            selectedAttack = nil
            print("Attack cancelled")
        end
        return
    end

    if key == "u" or key == "U" then
        if turnState.phase == "player" and #actionHistory > 0 then undoLastAction() end
        return
    end

    if key == "e" or key == "E" then
        if turnState.phase == "player" then endTurn() end
        return
    end

    if key == "t" or key == "T" then
        testViewActive = not testViewActive
        if not testViewActive then testViewOffsetY = 0 end
        print("Test view: " .. (testViewActive and "ON" or "OFF"))
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

    if global_abilities.handleKey(key, state) then return end

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

function input.mousereleased(x, y, button)
    if button ~= 1 then return end
    if endTurnButton.isHeld then
        endTurnButton.isHeld = false
        endTurnButton.holdTimer = 0
    end
end

return input
