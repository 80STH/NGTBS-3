-- input.lua
-- Input processing (mouse, keyboard). Uses globals, like other modules.
local input = {}
local global_abilities = require("system.global_abilities")
local turnManager = require("core.turn_manager")
local hex_utils = require("grid.hex_utils")
local log = require("util.log")

-- Guard to prevent undo from being triggered twice by both mouse and keyboard
-- release handlers in the same event cycle
local undoTriggeredThisCycle = false
-- Tracks whether the current undo hold was initiated by keyboard (U key) vs mouse
-- Prevents mousereleased from stealing a keyboard-initiated undo on an unrelated click
local undoHeldByKeyboard = false

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

    local tq, tr = hex:pixelToHex(x, y)
    if not hex or not hex:isValidHex(tq, tr) then return end
    if not hex:isActiveHex(tq, tr) then return end
    if tq > 3 then return end

    -- Check if deploying entity has deployAnywhere (Warrior lvl2)
    local deployingEntity = nil
    if deploySelectedIdx and placedAllies[deploySelectedIdx] then
        deployingEntity = placedAllies[deploySelectedIdx]
    elseif #unplacedAllies > 0 and unplacedAllies[1] then
        deployingEntity = unplacedAllies[1]
    end
    local canDeployAnywhere = deployingEntity and deployingEntity.deployAnywhere

    if not canDeployAnywhere then
        if terrainMap and terrainMap[tq] and terrainMap[tq][tr] == "water" then return end
        local occupant = getEntityAtHex(tq, tr)
        if occupant and not occupant.isPlayable then return end
    end

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
    elseif not getEntityAtHex(tq, tr) then
        if deploySelectedIdx then
            placedAllies[deploySelectedIdx].q = tq
            placedAllies[deploySelectedIdx].r = tr
            deploySelectedIdx = nil
        elseif #unplacedAllies > 0 then
            local ally = table.remove(unplacedAllies, 1)
            ally.q = tq
            ally.r = tr
            table.insert(placedAllies, ally)
            if ally.empowerAtStart then
                status.applyToEntity(ally, "empowered")
            end
        end
    end
    return
end

    if not gameActive then
        if isProgressionRun and win then return end
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

    if global_abilities.handleClick(x, y, state) then return end

    local btnH = 50
    local margin = 10
    local gap = 10
    local thirdW = math.floor((logicalW - margin * 2 - gap * 2) / 3)
    local btnY = logicalH - btnH - 10

    -- Undo button (middle third)
    local undoX = margin + thirdW + gap
    if x >= undoX and x <= undoX + thirdW and y >= btnY and y <= btnY + btnH then
        if #undo.history > 1 then
            undoButton.isHeld = true
            undoButton.holdTimer = 0
            undoTriggeredThisCycle = false
            undoHeldByKeyboard = false
        else
            sounds.play("cant")
        end
        return
    end

    -- End turn button (right third)
    local endX = margin + (thirdW + gap) * 2
    if x >= endX and x <= endX + thirdW and y >= btnY and y <= btnY + btnH then
        if turnState.phase == "player" then
            local hasActive = false
            for _, e in ipairs(entities) do
                if e.isPlayable and e.health > 0 and not e.hasActedThisTurn
                    and not (status and status.hasEntityStatus and status.hasEntityStatus(e, "stasis")) then
                    hasActive = true
                    break
                end
            end
            if hasActive then
                endTurnButton.isHeld = true
                endTurnButton.holdTimer = 0
            else
                turnManager.endPlayerTurn()
            end
        else
            log.debug("input", "Not your turn")
        end
        return
    end

    if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving then
        for _, btn in ipairs(attackButtons) do
            if x >= btn.x and x <= btn.x + btn.width and y >= btn.y and y <= btn.y + btn.height then
                selectedAttack = btn.attack
                attackMode = true
                log.debugf("input", "Attack selected: %s (attackMode = true)", btn.name)
                return
            end
        end
    end

    -- Ally panel buttons
    if turnState.phase == "player" and not (selectedActor and selectedActor.isMoving) then
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
        if selectedAttack.name == "Mighty Throw" then
            if mightyThrowTarget then
                local stepX, stepY, stepZ = selectedAttack:getLineDirection(selectedActor.q, selectedActor.r, tq, tr, hex)
                if stepX then
                    selectedAttack._throwDir = {x = stepX, y = stepY, z = stepZ}
                    local success, msg = performAttackWithSelectedAttack(selectedActor, mightyThrowTarget.q, mightyThrowTarget.r, selectedAttack)
                    if not success then log.warnf("input", "Attack failed: %s", msg) end
                    attackMode = false
                    selectedAttack = nil
                end
                mightyThrowTarget = nil
            else
                local clicked = getEntityAtHex(tq, tr)
                if clicked and clicked:isCharacter() and clicked ~= selectedActor and
                   hex:getDistance(selectedActor.q, selectedActor.r, tq, tr) == 1 and
                   clicked.isPushable ~= false and clicked.health > 0 then
                    mightyThrowTarget = clicked
                end
            end
            return
        elseif selectedAttack.name == "Flip" then
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
                    if not success then log.warnf("input", "Attack failed: %s", msg) end
                    attackMode = false
                    selectedAttack = nil
                    flipTargetActor = nil
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
                        if not success then log.warnf("input", "Attack failed: %s", msg) end
                        isValidDest = true
                        break
                    end
                end
                if isValidDest then
                    attackMode = false
                    selectedAttack = nil

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
                        if not success then log.warnf("input", "Attack failed: %s", msg) end
                        isValidDest = true
                        break
                    end
                end
                if isValidDest then
                    attackMode = false
                    selectedAttack = nil

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
                            if not success then log.warnf("input", "Attack failed: %s", msg) end
                            isValid = true
                            break
                        end
                    end
                    if isValid then
                        attackMode = false
                        selectedAttack = nil
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
            elseif (selectedAttack.name == "Heavy Punch" or selectedAttack.name == "Empower Punch") and selectedActor.choosePushDir then
            if pushDirTargetCell then
                -- Second click: choose push direction cell
                local stepX, stepY, stepZ = selectedAttack:getLineDirection(selectedActor.q, selectedActor.r, pushDirTargetCell.q, pushDirTargetCell.r, hex)
                if stepX then
                    local dirs = getPushDirChoices(stepX, stepY, stepZ)
                    local chosen = nil
                    for _, d in ipairs(dirs) do
                        local pushQ, pushR = hex_utils.applyCubeStep(pushDirTargetCell.q, pushDirTargetCell.r, d.x, d.y, d.z)
                        if pushQ == tq and pushR == tr then
                            chosen = d
                            break
                        end
                    end
                    if chosen then
                        selectedAttack._pushDirOverride = {x = chosen.x, y = chosen.y, z = chosen.z}
                        local success, msg = performAttackWithSelectedAttack(selectedActor, pushDirTargetCell.q, pushDirTargetCell.r, selectedAttack)
                        if not success then log.warnf("input", "Attack failed: %s", msg) end
                    end
                end
                attackMode = false
                selectedAttack = nil
                pushDirTargetCell = nil
            else
                -- First click: select attack target
                local clicked = getEntityAtHex(tq, tr)
                if clicked and clicked:isCharacter() and clicked ~= selectedActor and
                   hex:getDistance(selectedActor.q, selectedActor.r, tq, tr) == 1 then
                    pushDirTargetCell = {q = tq, r = tr}
                end
            end
            return
        elseif selectedAttack.name == "Electric Hook" then
            local dist = hex:getDistance(selectedActor.q, selectedActor.r, tq, tr)
            if dist >= 2 then
                local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
                if not success then log.warnf("input", "Attack failed: %s", msg) end
                attackMode = false
                selectedAttack = nil

            end
            return
        else
            local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
            if not success then log.warnf("input", "Attack failed: %s", msg) end
        end
        attackMode = false
        selectedAttack = nil

        return
    end

    local clicked = getEntityAtHex(tq, tr)
    local inStasis = clicked and status and status.hasEntityStatus and status.hasEntityStatus(clicked, "stasis")
    if clicked and (clicked.health > 0 or inStasis) then
        selectedActor = clicked
        hex.selectedQ, hex.selectedR = tq, tr
        updateAttackButtons(selectedActor)
        attackMode = false
        selectedAttack = nil
        mightyThrowTarget = nil
        log.debugf("input", "Selected: %s%s", clicked.name, (clicked.hasActedThisTurn and " (acted)" or ""))
        return
    end

    if selectedActor and not selectedActor.isMoving then
        local isRooted = status and status.hasEntityStatus and status.hasEntityStatus(selectedActor, "rooted") and not selectedActor.rootImmune
        local isStasis = status and status.hasEntityStatus and status.hasEntityStatus(selectedActor, "stasis")
        local canMove = not isRooted and not isStasis and (not selectedActor.hasActedThisTurn or selectedActor.canMoveAfterAttack) and (not selectedActor.hasMovedThisTurn or selectedActor.canMoveAfterAttack)
        if canMove then
            performMove(selectedActor, tq, tr)
            hex.selectedQ, hex.selectedR = selectedActor.q, selectedActor.r
            attackMode = false
            selectedAttack = nil
            mightyThrowTarget = nil
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
            if isProgressionRun and win then return end
            restartGame()
        end
        return
    end

    if not gameActive then
        if isProgressionRun and win then return end
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
            log.debug("input", "Flip target cancelled")
        elseif mightyThrowTarget then
            mightyThrowTarget = nil
            log.debug("input", "Mighty Throw target cancelled")
        elseif vortexTargetCell then
            vortexTargetCell = nil
            log.debug("input", "Vortex target cancelled")
        elseif pullHookTargetCell then
            pullHookTargetCell = nil
            log.debug("input", "Pull Hook cancelled")
        elseif pushDirTargetCell then
            pushDirTargetCell = nil
            log.debug("input", "Push dir cancelled")
        elseif attackMode then
            attackMode = false
            selectedAttack = nil
            log.debug("input", "Attack cancelled")
        elseif gamePhase == "playing" and gameActive then
            pause_menu.open()
        end
        return
    end

    if key == "u" or key == "U" then
        if turnState.phase == "player" and #undo.history > 1 then
            undoButton.isHeld = true
            undoButton.holdTimer = 0
            undoTriggeredThisCycle = false
            undoHeldByKeyboard = true
        end
        return
    end

    if key == "e" or key == "E" then
        if turnState.phase == "player" then turnManager.endPlayerTurn() end
        return
    end

    if key == "t" or key == "T" then
        testViewActive = not testViewActive
        if not testViewActive then testViewOffsetY = 0 end
        log.debugf("input", "Test view: %s", (testViewActive and "ON" or "OFF"))
        return
    end

    if key == "r" or key == "R" then
        restartGame()
        return
    end

    if key == "o" or key == "O" then
        showEnemyOrder = true
        log.debugf("input", "Enemy order display: ON")
        return
    end

    if key == "p" or key == "P" then
        _G.shop.isOpen = not _G.shop.isOpen
        log.debugf("input", "Shop: %s", (_G.shop.isOpen and "OPEN" or "CLOSED"))
        return
    end

    if key == "1" then
        if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving and #attackButtons >= 1 then
            selectedAttack = attackButtons[1].attack
            attackMode = true
            log.debugf("input", "Attack selected: %s", attackButtons[1].name)
        end
        return
    end

    if key == "2" then
        if turnState.phase == "player" and selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.isMoving and #attackButtons >= 2 then
            selectedAttack = attackButtons[2].attack
            attackMode = true
            log.debugf("input", "Attack selected: %s", attackButtons[2].name)
        end
        return
    end

    if key == "tab" then
        if turnState.phase == "player" and (not selectedActor or not selectedActor.isMoving) then
            local actors = {}
            for _, e in ipairs(entities) do
                if e.isPlayable and (e.health > 0 or (status and status.hasEntityStatus and status.hasEntityStatus(e, "stasis"))) then
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
                log.debugf("input", "Selected: %s", selectedActor.name)
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
    if undoButton.isHeld and not undoTriggeredThisCycle and not undoHeldByKeyboard then
        local wasHeld = undoButton.holdTimer >= (config.HOLD_TIME or 0.7)
        undoButton.isHeld = false
        undoButton.holdTimer = 0
        undoHeldByKeyboard = false
        if not wasHeld and #undo.history > 1 then
            log.info("input", "MOUSE undo triggered")
            undoTriggeredThisCycle = true
            undo.undoLast()
            sounds.play("undo")
        end
    end
end

function input.keyreleased(key)
    if key == "o" or key == "O" then
        showEnemyOrder = false
        log.debugf("input", "Enemy order display: OFF")
    end
    if key == "u" or key == "U" then
        if undoButton.isHeld and not undoTriggeredThisCycle and undoHeldByKeyboard then
            local wasHeld = undoButton.holdTimer >= (config.HOLD_TIME or 0.7)
            undoButton.isHeld = false
            undoButton.holdTimer = 0
            undoHeldByKeyboard = false
            if not wasHeld and #undo.history > 1 then
                log.info("input", "KEYBOARD undo triggered")
                undoTriggeredThisCycle = true
                undo.undoLast()
                sounds.play("undo")
            end
        end
    end
end

return input
