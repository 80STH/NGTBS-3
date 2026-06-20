-- src/game/input.lua
-- Player interaction on the hex grid (playing + deploy phases).
-- Coordinates passed in are design-space (already scaled by camera).

local abilities = require("src.content.abilities")

local input = {}

local function hexAt(game, dx, dy)
    if not game.grid then return nil end
    local q, r = game.grid:pixelToHex(dx, dy)
    if game.grid:isActiveHex(q, r) then return q, r end
    return nil
end

-- Playing-phase press. Returns true if handled.
function input.handlePress(game, dx, dy)
    if game.phase ~= "playing" then return false end
    if game.turn.phase ~= "player" then return false end
    if game:anyBusy() then return false end

    local q, r = hexAt(game, dx, dy)
    -- active ability targeting takes priority
    if abilities.activeAbility then
        if q then
            abilities.handleClick(q, r, game)
        else
            abilities.activeAbility:onDeactivate(game)
            abilities.activeAbility = nil
        end
        return true  -- always consume the click while an ability is active
    end

    if not q then
        game:clearSelection()
        return false
    end

    local e = game:entityAt(q, r)

    -- attacking
    if game.attackMode and game.selectedActor and not game.selectedActor.hasActedThisTurn then
        if game.attackTargets[q .. "," .. r] then
            game:tryAttack(q, r)
            return true
        end
        -- tapping the selected actor while in attack mode: cycle attack
        if e == game.selectedActor then
            game:switchAttack()
            return true
        end
        -- tapping elsewhere cancels attack mode
        game.attackMode = false
        game.selectedAttackId = nil
        game.attackTargets = {}
        return true
    end

    -- moving
    if game.selectedActor and not game.selectedActor.hasMovedThisTurn and game.moveTargets[q .. "," .. r] then
        game:tryMove(q, r)
        return true
    end

    -- selecting an ally
    if e and e:isAlly() and e:isAlive() then
        if e == game.selectedActor and not e.hasActedThisTurn then
            -- enter attack mode with current attack
            game:selectAttack(e:getCurrentAttackId())
        else
            game:selectActor(e)
        end
        return true
    end

    game:clearSelection()
    return false
end

-- Deploy-phase press.
function input.handleDeployPress(game, dx, dy)
    if game.phase ~= "deploy" then return false end
    local q, r = hexAt(game, dx, dy)
    if not q then return false end
    return game:placeAlly(q, r)
end

return input
