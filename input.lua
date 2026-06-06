-- input.lua
-- Обработка ввода (мышь, клавиатура). Использует глобалы, как и остальные модули.
local input = {}

function input.mousepressed(x, y, button)
    if button ~= 1 then return end

    if not gameActive then
        local width = love.graphics.getWidth()
        local height = love.graphics.getHeight()
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

    if x >= 10 and x <= 130 and y >= 200 and y <= 230 then
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
        print("[DEBUG] Attack mode active, attempting attack at hex", tq, tr)
        local success, msg = performAttackWithSelectedAttack(selectedActor, tq, tr, selectedAttack)
        attackMode = false
        selectedAttack = nil
        if not success then
            print("Attack failed: " .. msg)
        end
        return
    end

    local clicked = getEntityAtHex(tq, tr)
    if clicked and clicked.isPlayable and clicked.health > 0 then
        if not clicked.hasActedThisTurn then
            selectedActor = clicked
            hex.selectedQ, hex.selectedR = tq, tr
            updateAttackButtons(selectedActor)
            attackMode = false
            selectedAttack = nil
            print("Selected: " .. clicked.name)
        end
        return
    end

    if selectedActor and not selectedActor.hasActedThisTurn and not selectedActor.hasMovedThisTurn and not selectedActor.isMoving then
        performMove(selectedActor, tq, tr)
        hex.selectedQ, hex.selectedR = selectedActor.q, selectedActor.r
        attackMode = false
        selectedAttack = nil
    end
end

function input.keypressed(key)
    if key == "u" or key == "U" then
        if #actionHistory > 0 then undoLastAction() end
    elseif key == "e" or key == "E" then
        if turnState.phase == "player" then endTurn() end
    elseif key == "escape" then
        if windTorrentUI.active then
            windTorrentUI.active = false
            restoreSelectedActor()
            print("Wind Torrent cancelled")
            return
        end
    end
end

return input
