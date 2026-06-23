-- shop.lua
-- Reworked: three random buff slots (unit upgrade, commander artifact, unit artifact, ability)
-- Reroll button for testing, no gold/categories

local shop = {}
local fonts = require("util.fonts")
local log = require("util.log")

shop.isOpen = false
shop.slots = {}  -- { {type, id, name, desc, icon, taken}, ... }
shop.autoOpened = false  -- true when shop opens after map completion

-- Ensure slots are populated
local function ensureSlots()
    if #shop.slots == 0 then
        shop.reroll()
    end
end

-- Build pool of available buffs
local function buildPool()
    local pool = {}
    local takenCommander = _G.commanderArtifacts or {}
    local takenArtifacts = _G.artifacts or {}
    local takenUpgrades = _G.unitUpgrades or {}
    local takenAbilities = {}
    for name, unlocked in pairs((_G.global_abilities and _G.global_abilities.unlocked) or {}) do
        takenAbilities[name] = true
    end

    -- Unit upgrades (per squad unit type)
    if _G.selectedSquad then
        local squad = require("system.commanders")
        local squads = _G.menu and _G.menu.getSquads() or {}
        local squadDef = squads[_G.selectedSquad]
        if squadDef then
            for _, unitDef in ipairs(squadDef.units) do
                local choices = (_G.UPGRADE_CHOICES or {})[unitDef.name]
                if choices then
                    local data = takenUpgrades[unitDef.name] or { choices = {} }
                    for _, ch in ipairs(choices) do
                        local already = false
                        for _, c in ipairs(data.choices) do
                            if c == ch.id then already = true; break end
                        end
                        if not already then
                            table.insert(pool, { type = "upgrade", id = unitDef.name .. "|" .. ch.id, name = ch.name .. " (" .. unitDef.name .. ")", desc = ch.desc, icon = "⚔", sourceType = "unit" })
                        end
                    end
                end
            end
        end
    end

    -- Commander artifacts
    if _G.selectedCommander then
        local cmdMod = require("system.commanders")
        local cmd = cmdMod.get(_G.selectedCommander)
        if cmd and cmd.exclusiveArtifacts then
            for _, cart in ipairs(cmd.exclusiveArtifacts) do
                local already = false
                for _, a in ipairs(takenCommander) do
                    if a == cart.id then already = true; break end
                end
                if not already then
                    table.insert(pool, { type = "commander_artifact", id = cart.id, name = cart.name, desc = cart.desc, icon = "★", apply = cart.apply, sourceType = "commander" })
                end
            end
        end
    end

    -- Unit artifacts
    for _, art in ipairs(_G.ARTIFACT_CHOICES or {}) do
        local already = false
        for _, a in ipairs(takenArtifacts) do
            if a == art.id then already = true; break end
        end
        if not already then
            table.insert(pool, { type = "artifact", id = art.id, name = art.name, desc = art.desc, icon = "◆", sourceType = "unit" })
        end
    end

    -- Abilities
    if _G.global_abilities then
        for _, abName in ipairs(_G.global_abilities.abilityOrder or {}) do
            if not _G.global_abilities.unlocked[abName] then
                table.insert(pool, { type = "ability", id = abName, name = abName, desc = "Unlocks the " .. abName .. " ability for your commander.", icon = "~", sourceType = "ability" })
            end
        end
    end

    return pool
end

function shop.reroll()
    shop.slots = {}
    local pool = buildPool()

    -- Fallback generic buffs if pool is too small
    if #pool < 3 then
        local fallbacks = {
            { type = "generic", id = "shop_generic_armor", name = "Reinforced Armor", desc = "All units take -1 damage this game.", icon = "🛡", sourceType = "generic" },
            { type = "generic", id = "shop_generic_hp", name = "Fortify", desc = "All units gain +1 max health this game.", icon = "❤", sourceType = "generic" },
            { type = "generic", id = "shop_generic_move", name = "March Orders", desc = "All units gain +1 move range this game.", icon = "🏃", sourceType = "generic" },
            { type = "generic", id = "shop_generic_mana", name = "Mana Shard", desc = "+1 max mana for your commander.", icon = "💎", sourceType = "generic" },
        }
        for _, fb in ipairs(fallbacks) do
            if #pool + #shop.slots < 3 then
                table.insert(pool, fb)
            end
        end
    end

    -- Pick 3 items (may repeat if pool < 3, but that's fine)
    for i = 1, 3 do
        if #pool == 0 then break end
        local idx = love.math.random(1, #pool)
        local item = pool[idx]
        table.insert(shop.slots, {
            type = item.type,
            id = item.id,
            name = item.name,
            desc = item.desc,
            icon = item.icon,
            apply = item.apply,
            sourceType = item.sourceType,
            taken = false,
        })
    end
    log.debugf("shop", "Rerolled %d slots from pool of %d", #shop.slots, #pool)
end

function shop.update(dt)
end

function shop.draw()
    if not shop.isOpen then return end
    ensureSlots()
    local w, h = logicalW, logicalH

    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panelW, panelH = 540, math.min(h - 80, 460)
    local panelX = w/2 - panelW/2
    local panelY = h/2 - panelH/2

    love.graphics.setColor(0.1, 0.1, 0.16, 0.96)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 12)
    love.graphics.setColor(0.4, 0.6, 0.3, 0.5)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 12)

    -- Title
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale; my = my / dpiScale

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.get(20))
    love.graphics.printf("Shop — Bonus Buffs", panelX, panelY + 12, panelW, "center")

    -- Close button
    local closeX = panelX + panelW - 36
    local closeY = panelY + 8
    local closeHover = mx >= closeX and mx <= closeX + 28 and my >= closeY and my <= closeY + 28
    love.graphics.setColor(closeHover and 0.8 or 0.4, closeHover and 0.2 or 0.2, closeHover and 0.2 or 0.2, 0.9)
    love.graphics.rectangle("fill", closeX, closeY, 28, 28, 6)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setFont(fonts.get(16))
    love.graphics.printf("X", closeX, closeY + 4, 28, "center")

    -- Slot cards
    local cardW = panelW - 40
    local cardH = 90
    local cardGap = 10
    local cardStartY = panelY + 55

    for i = 1, 3 do
        local cy = cardStartY + (i - 1) * (cardH + cardGap)
        local slot = shop.slots[i]

        local bgColor = slot and slot.taken and {0.08, 0.12, 0.08} or {0.14, 0.16, 0.22}
        love.graphics.setColor(bgColor[1], bgColor[2], bgColor[3], 0.95)
        love.graphics.rectangle("fill", panelX + 20, cy, cardW, cardH, 8)

        if slot then
            -- Icon + name
            local iconColor
            if slot.sourceType == "unit" then
                iconColor = {0.8, 0.8, 0.4}
            elseif slot.sourceType == "commander" then
                iconColor = {0.4, 0.8, 1.0}
            elseif slot.sourceType == "ability" then
                iconColor = {0.8, 0.5, 1.0}
            elseif slot.sourceType == "generic" then
                iconColor = {0.5, 0.9, 0.5}
            else
                iconColor = {0.7, 0.7, 0.7}
            end

            love.graphics.setColor(iconColor[1], iconColor[2], iconColor[3], slot.taken and 0.4 or 1)
            love.graphics.setFont(fonts.get(28))
            love.graphics.print(slot.icon, panelX + 30, cy + 24)

            love.graphics.setColor(slot.taken and 0.4 or 1, slot.taken and 0.4 or 1, slot.taken and 0.4 or 1, slot.taken and 0.5 or 1)
            love.graphics.setFont(fonts.get(15))
            love.graphics.print(slot.name, panelX + 70, cy + 12)

            love.graphics.setColor(slot.taken and 0.3 or 0.6, slot.taken and 0.3 or 0.6, slot.taken and 0.3 or 0.6, slot.taken and 0.4 or 0.7)
            love.graphics.setFont(fonts.get(11))
            love.graphics.printf(slot.desc, panelX + 70, cy + 34, cardW - 80, "left")

            -- Take / Taken button
            local btnX = panelX + cardW - 20 - 90
            local btnY = cy + 24
            local btnW = 90
            local btnH = 36
            local hoverTake = not slot.taken and mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH

            if slot.taken then
                love.graphics.setColor(0.2, 0.5, 0.2, 0.7)
                love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 5)
                love.graphics.setColor(0.3, 0.8, 0.3, 0.7)
                love.graphics.setFont(fonts.get(12))
                love.graphics.printf("Taken", btnX, btnY + 9, btnW, "center")
            else
                love.graphics.setColor(hoverTake and 0.25 or 0.15, hoverTake and 0.5 or 0.3, hoverTake and 0.3 or 0.18, 0.9)
                love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 5)
                love.graphics.setColor(0.3, 0.9, 0.4, hoverTake and 1 or 0.7)
                love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 5)
                love.graphics.setColor(0.3, 0.9, 0.4, hoverTake and 1 or 0.7)
                love.graphics.setFont(fonts.get(12))
                love.graphics.printf("Take", btnX, btnY + 9, btnW, "center")
            end
        else
            -- Empty slot
            love.graphics.setColor(0.2, 0.2, 0.25, 0.5)
            love.graphics.rectangle("fill", panelX + 20, cy, cardW, cardH, 8)
            love.graphics.setColor(0.4, 0.4, 0.5, 0.3)
            love.graphics.setFont(fonts.get(11))
            love.graphics.printf("(empty)", panelX + cardW/2 - 40, cy + 36, 80, "center")
        end
    end

    -- Reroll button
    local rY = cardStartY + 3 * (cardH + cardGap) + 10
    local rW = 180
    local rX = panelX + panelW/2 - rW/2
    local rHover = mx >= rX and mx <= rX + rW and my >= rY and my <= rY + 36
    love.graphics.setColor(rHover and 0.3 or 0.18, rHover and 0.2 or 0.12, rHover and 0.4 or 0.25, 0.9)
    love.graphics.rectangle("fill", rX, rY, rW, 36, 6)
    love.graphics.setColor(0.6, 0.5, 0.9, rHover and 0.9 or 0.6)
    love.graphics.rectangle("line", rX, rY, rW, 36, 6)
    love.graphics.setColor(0.7, 0.6, 1.0, rHover and 1 or 0.7)
    love.graphics.setFont(fonts.get(12))
    love.graphics.printf("Reroll (test)", rX, rY + 10, rW, "center")
end

function shop.mousepressed(x, y)
    if not shop.isOpen then return false end
    local w, h = logicalW, logicalH
    local panelW, panelH = 540, math.min(h - 80, 460)
    local panelX = w/2 - panelW/2
    local panelY = h/2 - panelH/2

    -- Close button
    local closeX = panelX + panelW - 36
    local closeY = panelY + 8
    if x >= closeX and x <= closeX + 28 and y >= closeY and y <= closeY + 28 then
        shop.isOpen = false
        if shop.autoOpened then
            -- If shop was auto-opened after map completion, close and check progression
            shop.autoOpened = false
            if _G.checkGameEnd then _G.checkGameEnd() end
        end
        return true
    end

    -- Slot cards: "Take" button
    local cardW = panelW - 40
    local cardH = 90
    local cardGap = 10
    local cardStartY = panelY + 55

    for i = 1, 3 do
        local slot = shop.slots[i]
        if slot and not slot.taken then
            local cy = cardStartY + (i - 1) * (cardH + cardGap)
            local btnX = panelX + cardW - 20 - 90
            local btnY = cy + 24
            local btnW = 90
            local btnH = 36

            if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
                slot.taken = true

                -- Apply effect based on type
                if slot.type == "upgrade" then
                    -- Parse "UnitName|choiceId"
                    local pipePos = slot.id:find("|")
                    if pipePos then
                        local unitName = slot.id:sub(1, pipePos - 1)
                        local choiceId = slot.id:sub(pipePos + 1)
                        local data = (_G.unitUpgrades or {})[unitName] or { choices = {} }
                        table.insert(data.choices, choiceId)
                        _G.unitUpgrades[unitName] = data
                        log.infof("shop", "Upgrade applied: %s -> %s", unitName, choiceId)
                    end
                elseif slot.type == "commander_artifact" then
                    table.insert(_G.commanderArtifacts, slot.id)
                    if slot.apply then slot.apply() end
                    log.infof("shop", "Commander artifact applied: %s", slot.name)
                elseif slot.type == "artifact" then
                    table.insert(_G.artifacts, slot.id)
                    log.infof("shop", "Artifact applied: %s", slot.name)
                elseif slot.type == "ability" then
                    if _G.global_abilities then
                        _G.global_abilities.unlocked[slot.id] = true
                        log.infof("shop", "Ability unlocked: %s", slot.name)
                    end
                elseif slot.type == "generic" then
                    local g = _G
                    if slot.id == "shop_generic_armor" then
                        g.squadArmorBonus = (g.squadArmorBonus or 0) + 1
                        log.info("shop", "All units take -1 damage this game!")
                    elseif slot.id == "shop_generic_hp" then
                        g.squadHpBonus = (g.squadHpBonus or 0) + 1
                        log.info("shop", "All units gain +1 max health this game!")
                    elseif slot.id == "shop_generic_move" then
                        g.squadMoveBonus = (g.squadMoveBonus or 0) + 1
                        log.info("shop", "All units gain +1 move range this game!")
                    elseif slot.id == "shop_generic_mana" then
                        if g.global_abilities then
                            g.global_abilities.maxMana = (g.global_abilities.maxMana or 3) + 1
                            g.global_abilities.mana = g.global_abilities.maxMana
                        end
                        log.info("shop", "+1 max mana for your commander!")
                    end
                end
                shop.isOpen = false
                return true
            end
        end
    end

    -- Reroll button
    local rY = cardStartY + 3 * (cardH + cardGap) + 10
    local rW = 180
    local rX = panelX + panelW/2 - rW/2
    if x >= rX and x <= rX + rW and y >= rY and y <= rY + 36 then
        shop.reroll()
        return true
    end

    return true
end

function shop.keypressed(key)
    if not shop.isOpen then return false end
    if key == "escape" then
        shop.isOpen = false
        if shop.autoOpened then
            shop.autoOpened = false
            if _G.checkGameEnd then _G.checkGameEnd() end
        end
        return true
    end
    return false
end

return shop
