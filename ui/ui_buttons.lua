-- ui_buttons.lua
-- Right column: Abilities toggle, Order, Undo (vertical stack)
-- Bottom center: End Turn
-- Left column: Attacks OR Abilities (toggled)
return function(ui)
    local fonts = require("util.fonts")
    local buttonFont = fonts.get(14)
    local icon_cache = require("ui.icon_cache")
    local combat = require("combat.combat")
    local config = require("core.config")

    local rightCol = { x = 0, w = 190, btnH = 56, gap = 6, margin = 10, lift = 84 }
    -- Bottom-left "ability block": a row of square ability buttons whose top sits
    -- under the Abilities toggle button.
    local abBlock  = { x = 10, square = 84, gap = 10, toggleW = 190, toggleH = 42, toggleGap = 10, margin = 12 }

    -- Unit buttons: slot 1 (the hero) is double width so Gentle Touch lives on
    -- its right half; the other slots are single-width.
    local UNIT_DOUBLE = 2

    -- Left-to-right x of unit button #index. Only the hero (index 1) is double
    -- width, so every slot after it shifts right by one extra single slot.
    local function unitRectX(index)
        local single = abBlock.square + abBlock.gap
        local extra = index > 1 and (UNIT_DOUBLE - 1) * single or 0
        return abBlock.x + (index - 1) * single + extra
    end

    function ui.getRightBtnRect(index)
        -- index: 1=Undo, 2=Order, 3=Abilities (bottom→top). The stack sits above
        -- the End Turn button, which owns the bottom-right corner.
        local cb = rightCol
        cb.x = logicalW - cb.w - cb.margin
        local baseY = logicalH - cb.margin - cb.lift
        return {
            x = cb.x,
            y = baseY - cb.btnH * index - cb.gap * (index - 1),
            w = cb.w,
            h = cb.btnH,
        }
    end

    -- Temporary summons (e.g. Infest's Infested) get their own small squares on
    -- the right, stacked above the right-button column, so they never displace
    -- the hero / real summons in the bottom-left selector.
    function ui.getTempUnitRect(index)
        local w = 84
        local h = 84
        local gap = 10
        local x = logicalW - rightCol.margin - w
        local y = 100 + (index - 1) * (h + gap)
        return { x = x, y = y, w = w, h = h }
    end

    ui.endTurnHoldTime = 0.7

    -- Shared: does the player still have anything to do this turn?
    -- hasActiveUnits = an unmoved/unacted unit; canUseAbility = an affordable,
    -- unused ability. Used by both the button and its click handling.
    function ui.getEndTurnActionState(entities, state)
        local hasActiveUnits = false
        for _, e in ipairs(entities or {}) do
            local done = e.hasActedThisTurn and not (e.multiAction and (e.movesLeft or 0) > 0 and (e.attacksLeft or 0) > 0)
            if e.isPlayable and e.health > 0 and not done then
                hasActiveUnits = true
                break
            end
        end
        local canUseAbility = false
        if state and global_abilities then
            for _, name in ipairs(global_abilities.getDisplayOrder(state)) do
                local ab = global_abilities.registry[name]
                if ab and not ab.hasBeenUsed and not global_abilities.abilityUsedThisTurn
                    and global_abilities.mana >= ab.manaCost
                    and (not ab.isEffective or ab:isEffective(state)) then
                    canUseAbility = true
                    break
                end
            end
        end
        return {
            hasActiveUnits = hasActiveUnits,
            canUseAbility = canUseAbility,
            nothingLeft = not hasActiveUnits and not canUseAbility,
        }
    end

    -- End Turn: bottom-right corner of the screen.
    function ui.getEndTurnRect()
        local w, h = 220, 64
        return {
            x = math.floor(logicalW - w - rightCol.margin),
            y = math.floor(logicalH - h - rightCol.margin),
            w = w,
            h = h,
        }
    end

    -- Bottom-left selector stack (3 rows up from the attack row):
    --   row 1 (top):   [Abilities]
    --   row 2:         [hero][summon][summon]
    --   row 3 (bottom): attack / ability squares
    local SELECT_ROW_STEP = abBlock.square + abBlock.gap

    -- Abilities toggle: top selector row.
    function ui.getAbilitiesToggleRect()
        local y = logicalH - abBlock.margin - abBlock.square - 2 * SELECT_ROW_STEP
        return { x = abBlock.x, y = y, w = abBlock.square, h = abBlock.square }
    end

    -- Square selector button #index (1..3): hero/summons, in the middle row.
    -- The hero (index 1) is double width (Gentle Touch shares it).
    function ui.getUnitSelectRect(index)
        local y = logicalH - abBlock.margin - abBlock.square - SELECT_ROW_STEP
        local w = abBlock.square
        if index == 1 then w = abBlock.square * UNIT_DOUBLE + abBlock.gap end
        return {
            x = unitRectX(index),
            y = y,
            w = w,
            h = abBlock.square,
        }
    end

    -- Square attack/ability button #index, on the bottom row.
    function ui.getAbilitySquareRect(index)
        local y = logicalH - abBlock.margin - abBlock.square
        return {
            x = abBlock.x + (index - 1) * (abBlock.square + abBlock.gap),
            y = y,
            w = abBlock.square,
            h = abBlock.square,
        }
    end

    -- Vertical HP column (pips) drawn along a button's right inner edge.
    local function drawHPColumn(rect, health, maxHealth)
        maxHealth = math.max(1, maxHealth or 1)
        local pipH = math.floor(rect.h / maxHealth)
        for i = 1, maxHealth do
            local py = rect.y + rect.h - i * pipH
            if i <= health then
                love.graphics.setColor(0.25, 0.85, 0.3, 1)
            else
                love.graphics.setColor(0.18, 0.18, 0.18, 0.9)
            end
            love.graphics.rectangle("fill", rect.x + rect.w - 6, py + 2, 4, pipH - 4)
        end
    end

    -- Per-unit action points along the bottom of a unit button: one combined
    -- cell per action, MP as an outer shell ring wrapping an AP core bubble.
    -- Shells run as moves are spent, cores as attacks are spent.
    local function drawUnitActionBar(actor, rect)
        local apMax = actor.maxAttacks or 2
        local mpMax = actor.maxMoves or 2
        local apVal = actor.attacksLeft or 0
        local mpVal = actor.movesLeft or 0
        -- No attacks left means the actions are done, so Move is spent too.
        if apVal <= 0 then mpVal = 0 end

        local n = math.max(apMax, mpMax)
        if n < 1 then n = 1 end
        local x = rect.x + 4
        local w = rect.w - 10
        local cellH = 8
        local gap = 2
        local y = rect.y + rect.h - cellH - 3
        local cellW = (w - (n - 1) * gap) / n
        local inset = math.max(1, cellW * 0.14)
        local insetV = math.max(1, cellH * 0.22)
        local coreR = math.max(1.5, math.min(3, cellW * 0.16))

        for i = 1, n do
            local cx = x + (i - 1) * (cellW + gap)
            if i <= mpVal then
                love.graphics.setColor(0.3, 0.55, 0.95, 0.92)
                love.graphics.rectangle("fill", cx, y, cellW, cellH, 2)
                love.graphics.setColor(0.09, 0.11, 0.2, 0.95)
                love.graphics.rectangle("fill", cx + inset, y + insetV, cellW - inset * 2, cellH - insetV * 2, 2)
            else
                love.graphics.setColor(0.2, 0.2, 0.26, 0.55)
                love.graphics.rectangle("fill", cx, y, cellW, cellH, 2)
            end
            local coreOn = i <= apVal
            love.graphics.setColor(coreOn and 0.96 or 0.24, coreOn and 0.58 or 0.2,
                coreOn and 0.18 or 0.2, coreOn and 0.95 or 0.55)
            love.graphics.circle("fill", cx + cellW / 2, y + cellH / 2, coreR)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- в•ђв•ђв•ђ Unit / Abilities selector row (bottom-left, 4 squares) в•ђв•ђв•ђ
    -- [hero][summon][summon][Abilities]; unit buttons show an HP column and
    -- select that unit. The last button toggles the abilities panel.
    function ui.drawUnitSelectButtons(state, mouseX, mouseY)
        if global_abilities.showPanel == nil then return end
        local allies = {}
        local temps = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and e.isPlayable and e.health and e.health > 0 and not e.isDying then
                -- Temporary summons (Infest's Infested) do NOT take a main slot:
                -- they are shown in their own panel on the right.
                if e.diesAtEndOfTurn then
                    table.insert(temps, e)
                else
                    table.insert(allies, e)
                end
            end
        end
        -- Stable order: hero first, then by name.
        table.sort(allies, function(a, b)
            if (a == _G.hero) ~= (b == _G.hero) then return a == _G.hero end
            return (a.name or "") < (b.name or "")
        end)
        table.sort(temps, function(a, b) return (a.name or "") < (b.name or "") end)
        ui._unitSelectEntities = allies
        ui._tempUnitEntities = temps

        -- Units occupy slots 1..3; the hero (slot 1) is double width.
        for i = 1, 3 do
            local ally = allies[i]
            if ally then
                local rect = ui.getUnitSelectRect(i)
                local selectW = abBlock.square  -- clickable "select unit" width
                local hover = mouseX and mouseX >= rect.x and mouseX <= rect.x + selectW
                    and mouseY >= rect.y and mouseY <= rect.y + rect.h
                local sel = state.selectedActor == ally
                local cr, cg, cb
                if sel then cr, cg, cb = 0.3, 0.45, 0.3
                elseif hover then cr, cg, cb = 0.32, 0.28, 0.4
                else cr, cg, cb = 0.22, 0.22, 0.3 end
                love.graphics.setColor(cr, cg, cb, 0.9)
                love.graphics.rectangle("fill", rect.x, rect.y, selectW, rect.h, 5)
                love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
                love.graphics.rectangle("line", rect.x, rect.y, selectW, rect.h, 5)
                -- Sprite preview
                if ally.sprite then
                    local sw, sh = ally.sprite:getDimensions()
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(ally.sprite, rect.x + 6, rect.y + rect.h - 6, 0, 2.2, 2.2, 0, sh)
                end
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setFont(fonts.get(9))
                love.graphics.printf(ally.name, rect.x, rect.y + 2, selectW - 8, "center")
                drawHPColumn(rect, ally.health, ally.maxHealth)
                drawUnitActionBar(ally, rect)
                -- Done marker
                local done = ally.hasActedThisTurn and not (ally.multiAction and (ally.movesLeft or 0) > 0 and (ally.attacksLeft or 0) > 0)
                if done then
                    icon_cache.drawSmall("cross", rect.x + selectW - 14, rect.y + 12, 12, 1, {0.55, 0.55, 0.55})
                end
                -- Hero: right half of the double button is the Gentle Touch toggle.
                if i == 1 and ally.gentleAvailable then
                    ui.drawGentleTouchHalf(ally, rect, abBlock.square)
                end
            end
        end

        -- Abilities button (top selector row)
        local ar = ui.getAbilitiesToggleRect()
        local hover = mouseX and mouseX >= ar.x and mouseX <= ar.x + ar.w
            and mouseY >= ar.y and mouseY <= ar.y + ar.h
        local open = global_abilities.showPanel
        local cr, cg, cb = open and {0.35, 0.2, 0.6} or {0.25, 0.25, 0.4}
        love.graphics.setColor(cr, cg, cb, hover and 0.95 or 0.85)
        love.graphics.rectangle("fill", ar.x, ar.y, ar.w, ar.h, 5)
        love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
        love.graphics.rectangle("line", ar.x, ar.y, ar.w, ar.h, 5)
        local iconKey = icon_cache.keyForAbility("Heal") or "abil_heal"
        icon_cache.drawSmall(iconKey, ar.x + ar.w / 2, ar.y + ar.h / 2 - 6, 30)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(fonts.get(9))
        love.graphics.printf("Abilities", ar.x, ar.y + ar.h - 16, ar.w, "center")

        -- Temporary summons (Infest's Infested): own squares on the right, never
        -- in the main selector.
        for i, ally in ipairs(temps) do
            local rect = ui.getTempUnitRect(i)
            local hover = mouseX and mouseX >= rect.x and mouseX <= rect.x + rect.w
                and mouseY >= rect.y and mouseY <= rect.y + rect.h
            local sel = state.selectedActor == ally
            local cr, cg, cb
            if sel then cr, cg, cb = 0.5, 0.3, 0.55
            elseif hover then cr, cg, cb = 0.42, 0.28, 0.5
            else cr, cg, cb = 0.3, 0.2, 0.42 end
            love.graphics.setColor(cr, cg, cb, 0.9)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 5)
            love.graphics.setColor(1, 0.5, 0.4, hover and 0.9 or 0.6)
            love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 5)
            if ally.sprite then
                local sw, sh = ally.sprite:getDimensions()
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(ally.sprite, rect.x + rect.w / 2, rect.y + rect.h - 6, 0, 2.4, 2.4, sw / 2, sh)
            end
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(fonts.get(9))
            love.graphics.printf(ally.name, rect.x + 2, rect.y + 2, rect.w - 4, "center")
            love.graphics.setColor(1, 1, 1, 0.75)
            love.graphics.printf((ally.health or 0) .. "/" .. (ally.maxHealth or 1), rect.x + 2, rect.y + rect.h - 18, rect.w - 4, "center")
        end
    end

    -- Selector click hit-test. Returns the chosen unit index, "abilities",
    -- "gentle" (hero's Gentle Touch half), a temp-unit tag, or nil.
    function ui.unitSelectHit(mouseX, mouseY)
        local ar = ui.getAbilitiesToggleRect()
        if mouseX >= ar.x and mouseX <= ar.x + ar.w and mouseY >= ar.y and mouseY <= ar.y + ar.h then
            return "abilities"
        end
        for i = 1, 3 do
            local rect = ui.getUnitSelectRect(i)
            if mouseY >= rect.y and mouseY <= rect.y + rect.h and mouseX >= rect.x and mouseX <= rect.x + rect.w then
                -- Hero's right half is the Gentle Touch toggle.
                if i == 1 and rect.w > abBlock.square then
                    if mouseX >= rect.x + rect.w - abBlock.square then return "gentle" end
                end
                return i
            end
        end
        -- Temporary summons on the right.
        for i = 1, #(ui._tempUnitEntities or {}) do
            local rect = ui.getTempUnitRect(i)
            if mouseY >= rect.y and mouseY <= rect.y + rect.h and mouseX >= rect.x and mouseX <= rect.x + rect.w then
                return "temp", i
            end
        end
        return nil
    end

    -- в•ђв•ђв•ђ Mechanism Button (index 4, top of right column) в•ђв•ђв•ђ
    -- One press drives every environment mechanism on the map:
    -- retractable highground, teleporters, conveyor belts.
    function ui.drawMechanismButton(state)
        local hasHighground = #(_G.retractableCells or {}) > 0
        local hasConveyor = next(_G.conveyorCells or {}) ~= nil
        local hasTrap = (_G.mechanismTrapCells and #_G.mechanismTrapCells > 0)
        local hasTeleporter = require("system.teleporters").hasActivePair()
        if not (hasHighground or hasConveyor or hasTeleporter or hasTrap) then return end
        local r = ui.getRightBtnRect(3)
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
            local trapCols = { spikes = {0.8, 0.82, 0.9}, burner = {1, 0.5, 0.1}, oxidizer = {0.3, 0.95, 0.4} }
            for _, c in ipairs(_G.mechanismTrapCells or {}) do
                local col = trapCols[c.type] or {0.8, 0.8, 0.8}
                cellHint(c.q, c.r, col)
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
                                local isHole = terrain == "water" or terrain == "emptiness"
                                if not isHole or e.waterWalker or e.hovering then
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
            if hasTrap then
                local present = {}
                for _, c in ipairs(_G.mechanismTrapCells or {}) do
                    present[c.type] = true
                end
                if present.spikes then lines[#lines + 1] = "-Spikes: 1 dmg on the cell" end
                if present.burner then lines[#lines + 1] = "-Burners: ignite occupants" end
                if present.oxidizer then lines[#lines + 1] = "-Oxidizers: acidize occupants" end
            end
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

    -- в•ђв•ђв•ђ Abilities Toggle Button (bottom-left, above the square ability buttons) в•ђв•ђв•ђ
    function ui.drawAbilitiesToggleButton(state, mouseX, mouseY)
        local r = ui.getAbilitiesToggleRect()
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
        local arrow = open and "в–І" or "в–ј"
        love.graphics.printf("Abilities " .. arrow, r.x + 40, r.y + r.h / 2 - 10, r.w - 40, "center")
        love.graphics.setFont(old)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- в•ђв•ђв•ђ Order Button (index 3) в•ђв•ђв•ђ
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

    -- в•ђв•ђв•ђ Undo Button (index 1) в•ђв•ђв•ђ
    function ui.drawUndoButton(actionHistory, maxUndoCount, selectedActor)
        local canUndo = #undo.history > 1
        local count = #undo.history - 1
        local r = ui.getRightBtnRect(1)

        love.graphics.setColor(canUndo and 0.2 or 0.5, 0.2, 0.8, 0.8)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
        if undoButton.isHeld then
            -- Hold-to-undo-all: fill the button while charging.
            local hTime = config.HOLD_TIME or 0.7
            local progress = math.min((undoButton.holdTimer or 0) / hTime, 1)
            love.graphics.setColor(0.9, 0.3, 0.8, 0.5)
            love.graphics.rectangle("fill", r.x, r.y, r.w * progress, r.h, 5)
        end
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

    -- в•ђв•ђв•ђ End Turn Button (bottom center) в•ђв•ђв•ђ
    function ui.drawEndTurnButton(turnState, entities, turnCount, maxTurns, state)
        local isPlayerTurn = (turnState.phase == "player")
        local btn = endTurnButton
        local isPressed = btn.isHeld
        local pressedOffset = isPressed and 2 or 0
        local r = ui.getEndTurnRect()

        local hasActiveUnits = false
        local nothingLeft = not isPlayerTurn
        if isPlayerTurn then
            local act = ui.getEndTurnActionState(entities, state)
            hasActiveUnits = act.hasActiveUnits
            nothingLeft = act.nothingLeft
        end
        -- Nobody left to act: quick 0.7s confirm. Actions still available: long
        -- 2s confirm (to stop accidental turn skips).
        ui.endTurnHoldTime = nothingLeft and 0.7 or 2.0

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

        -- While holding End Turn with actions still available, blink a big
        -- on-screen warning so the player does not skip their turn by accident.
        if isPressed and isPlayerTurn and not nothingLeft then
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 10)
            local msg = "You still have moves available!"
            local f = fonts.get(28)
            local cx = logicalW / 2
            local cy = logicalH / 2 - 40
            local tw = f:getWidth(msg)
            love.graphics.setFont(f)
            love.graphics.setColor(0, 0, 0, 0.65 * pulse)
            love.graphics.rectangle("fill", cx - tw / 2 - 18, cy - 12, tw + 36, f:getHeight() + 24, 8)
            love.graphics.setColor(1, 0.35 + 0.4 * pulse, 0.25, 0.5 + 0.5 * pulse)
            love.graphics.print(msg, cx - tw / 2, cy)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(old)
        end

        if btn.isHovered and isPlayerTurn and hasActiveUnits then
            local unitsLeft = {}
            for _, e in ipairs(entities) do
                local done = e.hasActedThisTurn and not (e.multiAction and (e.movesLeft or 0) > 0 and (e.attacksLeft or 0) > 0)
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

    -- в•ђв•ђв•ђ Hero skill buttons (square, bottom-left row, only when abilities hidden) в•ђв•ђв•ђ
    function ui.drawAttackPanel(selectedActor, attackButtons, selectedAttack, attackMode)
        if global_abilities.showPanel then return end
        if not selectedActor or selectedActor.hasActedThisTurn then return end
        if #attackButtons == 0 then return end

        local mx, my = love.mouse.getPosition()
        mx, my = mx / (_G.dpiScale or 1), my / (_G.dpiScale or 1)
        local old = love.graphics.getFont()

        if selectedActor.chainAttack then
            love.graphics.setColor(1, 0.8, 0.2, 1)
            local cy = logicalH - abBlock.margin - abBlock.square - abBlock.toggleGap - 26
            love.graphics.print("Chain: " .. selectedActor.chainAttack, abBlock.x, cy)
        end

        for i, btn in ipairs(attackButtons) do
            local ri = ui.getAbilitySquareRect(i)
            btn.x = ri.x
            btn.y = ri.y
            btn.width = ri.w
            btn.height = ri.h
            local isSelected = (selectedAttack == btn.attack and attackMode)
            -- Delayed attacks (finishers) end the turn: dark red signals "no more actions"
            local isDelayed = combat.hasTag(btn.attack.tags, "delayed")
            local r, g, b
            if isDelayed then
                r, g, b = 0.75, 0.15, 0.25
            else
                r, g, b = 0.3, 0.7, 0.3
            end
            if isSelected then
                r, g, b = math.min(r + 0.2, 1), math.min(g + 0.2, 1), math.min(b + 0.2, 1)
            end
            love.graphics.setColor(r, g, b, 0.8)
            love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height, 5)

            local iconKey = icon_cache.keyForAttack(btn.name)
            if iconKey then
                icon_cache.drawSmall(iconKey, btn.x + btn.width / 2, btn.y + btn.height / 2 - 6, 30)
            end
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(buttonFont)
            local nameText = btn.name
            local nameW = buttonFont:getWidth(nameText)
            local labelX = btn.x + (btn.width - nameW) / 2
            if isSelected then
                icon_cache.drawSmall("check", labelX - 8, btn.y + btn.height - 38 + 9, 12, 1, {0.4, 1, 0.4})
                labelX = labelX + 4
            end
            love.graphics.print(nameText, labelX, btn.y + btn.height - 38)
            love.graphics.setFont(old)

            -- Desc tooltip on hover / when selected, drawn to the right
            local showTip = isSelected
                or (mx >= btn.x and mx <= btn.x + btn.width and my >= btn.y and my <= btn.y + btn.height)
            if showTip then
                love.graphics.setColor(1, 1, 0.5, 0.9)
                local font = love.graphics.getFont()
                local ttW = 220
                local maxW = ttW - 16
                local words = {}
                for w in (btn.name .. " вЂ” " .. btn.desc):gmatch("%S+") do table.insert(words, w) end
                local lines = {}
                for _, w in ipairs(words) do
                    if #lines == 0 then
                        table.insert(lines, w)
                    else
                        local candidate = lines[#lines] .. " " .. w
                        if font:getWidth(candidate) <= maxW then
                            lines[#lines] = candidate
                        else
                            table.insert(lines, w)
                        end
                    end
                end
                local ttH = 16 + #lines * 15
                local ttx = btn.x + btn.width + 8
                local tty = btn.y
                if ttx + ttW > logicalW - 10 then ttx = btn.x - ttW - 8 end
                love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
                love.graphics.rectangle("fill", ttx, tty, ttW, ttH, 6)
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                love.graphics.rectangle("line", ttx, tty, ttW, ttH, 6)
                love.graphics.setColor(1, 1, 0.6, 1)
                for l, line in ipairs(lines) do
                    love.graphics.print(line, ttx + 8, tty + 8 + (l - 1) * 15)
                end
            end
        end

        -- Passive info (informational only): listed to the right of the attack
        -- squares for the selected actor. Never affects combat.
        local passives = selectedActor.passives
        if passives and #passives > 0 then
            local small = fonts.get(11)
            local titleFont = fonts.get(12)
            local boxW = 250
            local pad = 8
            local lineH = 14
            local bx = abBlock.x + #attackButtons * (abBlock.square + abBlock.gap) + 16
            local by = logicalH - abBlock.margin - abBlock.square
            if bx + boxW > logicalW - 10 then bx = logicalW - boxW - 10 end

            -- Wrap each passive into "Name: desc" lines.
            local lines = {}
            love.graphics.setFont(small)
            for _, p in ipairs(passives) do
                local text = p.name .. ": " .. (p.desc or "")
                local cur = ""
                for word in text:gmatch("%S+") do
                    local cand = (cur == "") and word or (cur .. " " .. word)
                    if small:getWidth(cand) <= boxW - 2 * pad then
                        cur = cand
                    else
                        table.insert(lines, cur)
                        cur = word
                    end
                end
                if cur ~= "" then table.insert(lines, cur) end
            end

            local boxH = 24 + #lines * lineH
            love.graphics.setColor(0.08, 0.1, 0.16, 0.92)
            love.graphics.rectangle("fill", bx, by, boxW, boxH, 6)
            love.graphics.setColor(0.45, 0.55, 0.75, 0.8)
            love.graphics.rectangle("line", bx, by, boxW, boxH, 6)
            love.graphics.setFont(titleFont)
            love.graphics.setColor(0.6, 0.85, 1, 1)
            love.graphics.print("Passives", bx + pad, by + 5)
            love.graphics.setFont(small)
            love.graphics.setColor(0.85, 0.9, 0.85, 1)
            for l, line in ipairs(lines) do
                love.graphics.print(line, bx + pad, by + 22 + (l - 1) * lineH)
            end
            love.graphics.setFont(old)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- в•ђв•ђв•ђ Gentle Touch toggle (Blade): free, unlimited, modifies attacks в•ђв•ђв•ђ
    -- Merged into the hero's double-width unit button: right half toggles it.
    function ui.gentleTouchRect(unitRect)
        if not unitRect then return nil end
        return { x = unitRect.x + unitRect.w - abBlock.square, y = unitRect.y,
                 w = abBlock.square, h = unitRect.h }
    end

    function ui.drawGentleTouchHalf(actor, unitRect, unitW)
        local gc = ui.gentleTouchRect(unitRect)
        actor._gentleRect = gc
        local on = actor.gentleTouch
        local mx, my = love.mouse.getPosition()
        mx, my = mx / (_G.dpiScale or 1), my / (_G.dpiScale or 1)
        local hover = mx >= gc.x and mx <= gc.x + gc.w and my >= gc.y and my <= gc.y + gc.h
        love.graphics.setColor(on and 0.62 or 0.2, on and 0.42 or 0.18, on and 0.16 or 0.2, on and 0.95 or 0.7)
        love.graphics.rectangle("fill", gc.x, gc.y, gc.w, gc.h, 5)
        if hover then
            love.graphics.setColor(on and 1 or 0.9, on and 0.8 or 0.85, on and 0.5 or 0.5, 1)
            love.graphics.rectangle("line", gc.x - 2, gc.y - 2, gc.w + 4, gc.h + 4, 6)
        else
            love.graphics.setColor(on and 0.9 or 0.5, on and 0.7 or 0.5, on and 0.4 or 0.5, 0.6)
            love.graphics.rectangle("line", gc.x, gc.y, gc.w, gc.h, 5)
        end
        love.graphics.setColor(1, on and 0.85 or 0.6, on and 0.5 or 0.5, 1)
        love.graphics.setFont(fonts.get(9))
        love.graphics.printf((on and "Gentle ON" or "Gentle off"), gc.x, gc.y + gc.h / 2 - 8, gc.w, "center")
    end

    -- в•ђв•ђв•ђ Ability buttons (square, grouped in a bottom row when panel open) в•ђв•ђв•ђ
    function ui.drawAbilityButtons(state)
        if not global_abilities.showPanel then return end
        state.previewManaSpend = 0
        local displayOrder = global_abilities.getDisplayOrder(state)
        if #displayOrder == 0 then return end

        local mx, my = love.mouse.getPosition()
        mx, my = mx / (state.dpiScale or 1), my / (state.dpiScale or 1)
        local old = love.graphics.getFont()

        for i, name in ipairs(displayOrder) do
            local ab = global_abilities.registry[name]
            if ab then
                local ri = ui.getAbilitySquareRect(i)
                ab.button.x = ri.x
                ab.button.y = ri.y
                ab.button.width = ri.w
                ab.button.height = ri.h

                local unlimited = state.unlimitedAbilities
                local effective = not ab.isEffective or ab:isEffective(state)
                local available = (state.turnState.phase == "player"
                    and effective
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
                icon_cache.drawSmall(iconKey, ri.x + ri.w / 2, ri.y + ri.h / 2 - 7, 30)

                love.graphics.setFont(buttonFont)
                love.graphics.setColor(1, 1, 1, (global_abilities.mana >= ab.manaCost) and 1 or 0.4)
                love.graphics.print(ab.manaCost, ri.x + ri.w / 2 - 5, ri.y + ri.h - 18)
                love.graphics.setFont(old)
                love.graphics.setColor(1, 1, 1, 1)

                -- Tooltip to the right of the square
                if mx >= ri.x and mx <= ri.x + ri.w and my >= ri.y and my <= ri.y + ri.h then
                    -- Hovering an affordable, unused ability previews its mana cost
                    -- so the top bar can blink the cells it would spend.
                    if available then state.previewManaSpend = ab.manaCost or 0 end
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
            end
        end
    end
end
