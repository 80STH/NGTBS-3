-- shop.lua
-- 4-category upgrade system: unit upgrades, generic upgrades, spells, commander upgrades

local shop = {}
local fonts = require("util.fonts")
local log = require("util.log")

shop.isOpen = false
shop.autoOpened = false
shop.categories = {}

local function buildUnitCategory()
    local cat = { title = "UNIT UPGRADES", slots = {}, taken = false }
    if not _G.selectedSquad then return cat end
    local squads = _G.menu and _G.menu.getSquads() or {}
    local squadDef = squads[_G.selectedSquad]
    if not squadDef then return cat end
    local takenUpgrades = _G.unitUpgrades or {}
    local available = {}
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
                    table.insert(available, { unitName = unitDef.name, id = ch.id, name = ch.name, desc = ch.desc })
                end
            end
        end
    end
    local unitsSeen = {}
    local selected = {}
    for _, item in ipairs(available) do
        if not unitsSeen[item.unitName] then unitsSeen[item.unitName] = 0 end
        if unitsSeen[item.unitName] < 2 then
            table.insert(selected, item)
            unitsSeen[item.unitName] = unitsSeen[item.unitName] + 1
        end
        if #selected >= 4 then break end
    end
    for _, item in ipairs(selected) do
        table.insert(cat.slots, {
            type = "unit",
            id = item.unitName .. "|" .. item.id,
            name = item.name .. " (" .. item.unitName .. ")",
            desc = item.desc,
            icon = "⚔",
            taken = false,
        })
    end
    return cat
end

local function buildGenericCategory()
    local cat = { title = "GENERIC", slots = {}, taken = false }
    local takenGeneric = _G.genericUpgrades or {}
    local takenSet = {}
    for _, g in ipairs(takenGeneric) do takenSet[g] = true end
    local pool = {
        { id = "fireImmune", name = "Fire Immunity", desc = "All units immune to fire", icon = "🔥" },
        { id = "acidImmune", name = "Acid Immunity", desc = "All units immune to acid", icon = "☣" },
        { id = "rootImmune", name = "Iron Will", desc = "All units immune to roots/slowing auras", icon = "◆" },
        { id = "armor", name = "Fortress", desc = "All units take -1 damage", icon = "🛡" },
        { id = "moveSpeed", name = "Swift Boots", desc = "All units gain +1 move range", icon = "👢" },
        { id = "deployAnywhere", name = "Scout", desc = "All units deploy on any terrain", icon = "👁" },
        { id = "canMoveAfterAttack", name = "Hit & Run", desc = "All units move after attacking", icon = "↔" },
        { id = "phaseThroughEnemies", name = "Ghost Cloak", desc = "All units phase through enemies", icon = "👻" },
    }
    local available = {}
    for _, item in ipairs(pool) do
        if not takenSet[item.id] then
            table.insert(available, item)
        end
    end
    for i = #available, 2, -1 do
        local j = love.math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end
    for i = 1, math.min(3, #available) do
        local item = available[i]
        table.insert(cat.slots, {
            type = "generic",
            id = item.id,
            name = item.name,
            desc = item.desc,
            icon = item.icon,
            taken = false,
        })
    end
    return cat
end

local function buildSpellCategory()
    local cat = { title = "SPELLS", slots = {}, taken = false }
    if not _G.global_abilities then return cat end
    local available = {}
    for _, abName in ipairs(_G.global_abilities.abilityOrder or {}) do
        if not _G.global_abilities.unlocked[abName] then
            table.insert(available, abName)
        end
    end
    for i = #available, 2, -1 do
        local j = love.math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end
    for i = 1, math.min(3, #available) do
        local name = available[i]
        table.insert(cat.slots, {
            type = "spell",
            id = name,
            name = name,
            desc = "Unlocks the " .. name .. " ability.",
            icon = "~",
            taken = false,
        })
    end
    return cat
end

local function buildCommanderCategory()
    local cat = { title = "COMMANDER", slots = {}, taken = false }
    if not _G.selectedCommander then return cat end
    local commanders = require("system.commanders")
    local cmd = commanders.get(_G.selectedCommander)
    if not cmd or not cmd.exclusiveArtifacts then return cat end
    local takenCmd = _G.commanderArtifacts or {}
    for _, cart in ipairs(cmd.exclusiveArtifacts) do
        local already = false
        for _, a in ipairs(takenCmd) do
            if a == cart.id then already = true; break end
        end
        if not already then
            table.insert(cat.slots, {
                type = "commander",
                id = cart.id,
                name = cart.name,
                desc = cart.desc,
                icon = "★",
                apply = cart.apply,
                taken = false,
            })
        end
    end
    return cat
end

local function ensureCategories()
    if not shop.categories.unit then
        shop.reroll()
    end
end

function shop.reroll()
    shop.categories = {
        unit = buildUnitCategory(),
        generic = buildGenericCategory(),
        spell = buildSpellCategory(),
        commander = buildCommanderCategory(),
    }
    log.debugf("shop", "Rerolled: unit=%d generic=%d spell=%d commander=%d",
        #shop.categories.unit.slots, #shop.categories.generic.slots,
        #shop.categories.spell.slots, #shop.categories.commander.slots)
end

function shop.open()
    shop.autoOpened = false
    shop.reroll()
    shop.isOpen = true
end

function shop.openForProgression()
    shop.autoOpened = true
    shop.reroll()
    shop.isOpen = true
end

local function applyTake(slot, catKey)
    if slot.type == "unit" then
        local pipePos = slot.id:find("|")
        if pipePos then
            local unitName = slot.id:sub(1, pipePos - 1)
            local choiceId = slot.id:sub(pipePos + 1)
            local data = (_G.unitUpgrades or {})[unitName] or { choices = {} }
            table.insert(data.choices, choiceId)
            _G.unitUpgrades[unitName] = data
            log.infof("shop", "Upgrade applied: %s -> %s", unitName, choiceId)
        end
    elseif slot.type == "generic" then
        _G.genericUpgrades = _G.genericUpgrades or {}
        table.insert(_G.genericUpgrades, slot.id)
        log.infof("shop", "Generic upgrade applied: %s", slot.id)
    elseif slot.type == "spell" then
        if _G.global_abilities then
            _G.global_abilities.unlocked[slot.id] = true
            log.infof("shop", "Spell unlocked: %s", slot.id)
        end
    elseif slot.type == "commander" then
        table.insert(_G.commanderArtifacts, slot.id)
        if slot.apply then slot.apply() end
        log.infof("shop", "Commander upgrade applied: %s", slot.name)
    end
    shop.categories[catKey].taken = true
end

function shop.update(dt)
end

local function getLayout(w, h)
    local panelW = 560
    local panelH = math.min(h - 60, 700)
    local panelX = w / 2 - panelW / 2
    local panelY = 30
    local contentX = panelX + 20
    local contentW = panelW - 40
    local y = panelY + 45
    return panelW, panelH, panelX, panelY, contentX, contentW, y
end

function shop.draw()
    if not shop.isOpen then return end
    ensureCategories()
    local w, h = logicalW, logicalH
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale; my = my / dpiScale

    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panelW, panelH, panelX, panelY, contentX, contentW, y = getLayout(w, h)

    love.graphics.setColor(0.1, 0.1, 0.16, 0.96)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 12)
    love.graphics.setColor(0.4, 0.6, 0.3, 0.5)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 12)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.get(20))
    love.graphics.printf("Upgrades", panelX, panelY + 12, panelW, "center")

    local closeX = panelX + panelW - 36
    local closeY = panelY + 8
    local closeHover = mx >= closeX and mx <= closeX + 28 and my >= closeY and my <= closeY + 28
    love.graphics.setColor(closeHover and 0.8 or 0.4, closeHover and 0.2 or 0.2, closeHover and 0.2 or 0.2, 0.9)
    love.graphics.rectangle("fill", closeX, closeY, 28, 28, 6)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setFont(fonts.get(16))
    love.graphics.printf("X", closeX, closeY + 4, 28, "center")

    local catOrder = { "unit", "generic", "spell", "commander" }
    local catColors = {
        unit = {0.8, 0.8, 0.4},
        generic = {0.5, 0.9, 0.5},
        spell = {0.8, 0.5, 1.0},
        commander = {0.4, 0.8, 1.0},
    }

    for _, catKey in ipairs(catOrder) do
        local cat = shop.categories[catKey]
        if not cat then goto continue end
        local color = catColors[catKey]

        love.graphics.setColor(color[1], color[2], color[3], 0.9)
        love.graphics.setFont(fonts.get(13))
        love.graphics.print(cat.title, contentX, y)
        y = y + 22

        if #cat.slots == 0 then
            love.graphics.setColor(0.4, 0.4, 0.4, 0.4)
            love.graphics.setFont(fonts.get(11))
            love.graphics.print("(none available)", contentX, y)
            y = y + 24
        elseif catKey == "unit" then
            local cardW = (contentW - 10) / 2
            local cardH = 70
            for i, slot in ipairs(cat.slots) do
                local col = ((i - 1) % 2)
                local row = math.floor((i - 1) / 2)
                local cx = contentX + col * (cardW + 10)
                local cy = y + row * (cardH + 8)

                local bg = slot.taken and {0.08, 0.12, 0.08} or {0.14, 0.16, 0.22}
                love.graphics.setColor(bg[1], bg[2], bg[3], 0.95)
                love.graphics.rectangle("fill", cx, cy, cardW, cardH, 6)

                love.graphics.setColor(color[1], color[2], color[3], slot.taken and 0.3 or 0.8)
                love.graphics.setFont(fonts.get(18))
                love.graphics.print(slot.icon, cx + 8, cy + 6)

                love.graphics.setColor(slot.taken and 0.4 or 1, slot.taken and 0.4 or 1, slot.taken and 0.4 or 1, slot.taken and 0.5 or 1)
                love.graphics.setFont(fonts.get(12))
                love.graphics.print(slot.name, cx + 8, cy + 30)

                love.graphics.setColor(slot.taken and 0.3 or 0.6, slot.taken and 0.3 or 0.6, slot.taken and 0.3 or 0.6, slot.taken and 0.4 or 0.7)
                love.graphics.setFont(fonts.get(9))
                love.graphics.printf(slot.desc, cx + 8, cy + 46, cardW - 16, "left")

                if not slot.taken then
                    local btnW = 50
                    local btnH = 22
                    local btnX = cx + cardW - btnW - 6
                    local btnY = cy + cardH - btnH - 6
                    local hover = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH
                    love.graphics.setColor(hover and 0.25 or 0.15, hover and 0.5 or 0.3, hover and 0.3 or 0.18, 0.9)
                    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4)
                    love.graphics.setColor(0.3, 0.9, 0.4, hover and 1 or 0.7)
                    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 4)
                    love.graphics.setColor(0.3, 0.9, 0.4, hover and 1 or 0.7)
                    love.graphics.setFont(fonts.get(10))
                    love.graphics.printf("Take", btnX, btnY + 4, btnW, "center")
                else
                    local btnW = 50
                    local btnH = 22
                    local btnX = cx + cardW - btnW - 6
                    local btnY = cy + cardH - btnH - 6
                    love.graphics.setColor(0.2, 0.5, 0.2, 0.7)
                    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4)
                    love.graphics.setColor(0.3, 0.8, 0.3, 0.7)
                    love.graphics.setFont(fonts.get(10))
                    love.graphics.printf("Taken", btnX, btnY + 4, btnW, "center")
                end
            end
            local rows = math.ceil(#cat.slots / 2)
            y = y + rows * 78 + 8
        else
            local rowH = 36
            for _, slot in ipairs(cat.slots) do
                local bg = slot.taken and {0.08, 0.12, 0.08} or {0.14, 0.16, 0.22}
                love.graphics.setColor(bg[1], bg[2], bg[3], 0.95)
                love.graphics.rectangle("fill", contentX, y, contentW, rowH, 6)

                love.graphics.setColor(color[1], color[2], color[3], slot.taken and 0.3 or 0.8)
                love.graphics.setFont(fonts.get(14))
                love.graphics.print(slot.icon, contentX + 8, y + 8)

                love.graphics.setColor(slot.taken and 0.4 or 1, slot.taken and 0.4 or 1, slot.taken and 0.4 or 1, slot.taken and 0.5 or 1)
                love.graphics.setFont(fonts.get(12))
                love.graphics.print(slot.name, contentX + 30, y + 4)

                love.graphics.setColor(slot.taken and 0.3 or 0.5, slot.taken and 0.3 or 0.5, slot.taken and 0.3 or 0.5, slot.taken and 0.4 or 0.6)
                love.graphics.setFont(fonts.get(9))
                love.graphics.print(slot.desc, contentX + 30, y + 20)

                if not slot.taken then
                    local btnW = 60
                    local btnH = 24
                    local btnX = contentX + contentW - btnW - 6
                    local btnY = y + (rowH - btnH) / 2
                    local hover = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH
                    love.graphics.setColor(hover and 0.25 or 0.15, hover and 0.5 or 0.3, hover and 0.3 or 0.18, 0.9)
                    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4)
                    love.graphics.setColor(0.3, 0.9, 0.4, hover and 1 or 0.7)
                    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 4)
                    love.graphics.setColor(0.3, 0.9, 0.4, hover and 1 or 0.7)
                    love.graphics.setFont(fonts.get(10))
                    love.graphics.printf("Take", btnX, btnY + 5, btnW, "center")
                else
                    local btnW = 60
                    local btnH = 24
                    local btnX = contentX + contentW - btnW - 6
                    local btnY = y + (rowH - btnH) / 2
                    love.graphics.setColor(0.2, 0.5, 0.2, 0.7)
                    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4)
                    love.graphics.setColor(0.3, 0.8, 0.3, 0.7)
                    love.graphics.setFont(fonts.get(10))
                    love.graphics.printf("Taken", btnX, btnY + 5, btnW, "center")
                end
                y = y + rowH + 4
            end
            y = y + 8
        end
        ::continue::
    end

    local btnAreaW = 280
    local btnH = 36
    local btnY = y + 5
    local rW = 130
    local rX = contentX
    local rHover = mx >= rX and mx <= rX + rW and my >= btnY and my <= btnY + btnH
    love.graphics.setColor(rHover and 0.3 or 0.18, rHover and 0.2 or 0.12, rHover and 0.4 or 0.25, 0.9)
    love.graphics.rectangle("fill", rX, btnY, rW, btnH, 6)
    love.graphics.setColor(0.6, 0.5, 0.9, rHover and 0.9 or 0.6)
    love.graphics.rectangle("line", rX, btnY, rW, btnH, 6)
    love.graphics.setColor(0.7, 0.6, 1.0, rHover and 1 or 0.7)
    love.graphics.setFont(fonts.get(12))
    love.graphics.printf("Reroll", rX, btnY + 10, rW, "center")

    local dW = 130
    local dX = contentX + btnAreaW - dW
    local dHover = mx >= dX and mx <= dX + dW and my >= btnY and my <= btnY + btnH
    love.graphics.setColor(dHover and 0.2 or 0.12, dHover and 0.5 or 0.3, dHover and 0.25 or 0.15, 0.9)
    love.graphics.rectangle("fill", dX, btnY, dW, btnH, 6)
    love.graphics.setColor(0.3, 0.9, 0.4, dHover and 0.9 or 0.6)
    love.graphics.rectangle("line", dX, btnY, dW, btnH, 6)
    love.graphics.setColor(0.3, 0.9, 0.4, dHover and 1 or 0.7)
    love.graphics.setFont(fonts.get(12))
    love.graphics.printf("Done", dX, btnY + 10, dW, "center")
end

local function finishProgression()
    local nextMap = (_G.currentMapIndex or 1) + 1
    local progression = _G.mapProgression or {}
    if nextMap <= #progression then
        _G.currentMapIndex = nextMap
        _G.progressionShopOpened = false
        _G.restartGame(progression[nextMap])
    else
        _G.progressionOverlay = "complete"
    end
end

function shop.mousepressed(x, y)
    if not shop.isOpen then return false end
    local w, h = logicalW, logicalH
    local panelW, panelH, panelX, panelY, contentX, contentW, startY = getLayout(w, h)
    local mx, my = x, y

    local closeX = panelX + panelW - 36
    local closeY = panelY + 8
    if mx >= closeX and mx <= closeX + 28 and my >= closeY and my <= closeY + 28 then
        shop.isOpen = false
        if shop.autoOpened then
            shop.autoOpened = false
            finishProgression()
        end
        return true
    end

    local catOrder = { "unit", "generic", "spell", "commander" }
    local y = startY
    for _, catKey in ipairs(catOrder) do
        local cat = shop.categories[catKey]
        if not cat then goto continue end
        y = y + 22
        if #cat.slots == 0 then
            y = y + 24
        elseif catKey == "unit" then
            local cardW = (contentW - 10) / 2
            local cardH = 70
            for i, slot in ipairs(cat.slots) do
                if not slot.taken then
                    local col = ((i - 1) % 2)
                    local row = math.floor((i - 1) / 2)
                    local cx = contentX + col * (cardW + 10)
                    local cy = y + row * (cardH + 8)
                    local btnW = 50
                    local btnH = 22
                    local btnX = cx + cardW - btnW - 6
                    local btnY = cy + cardH - btnH - 6
                    if mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH then
                        slot.taken = true
                        applyTake(slot, catKey)
                        return true
                    end
                end
            end
            local rows = math.ceil(#cat.slots / 2)
            y = y + rows * 78 + 8
        else
            local rowH = 36
            for _, slot in ipairs(cat.slots) do
                if not slot.taken then
                    local btnW = 60
                    local btnH = 24
                    local btnX = contentX + contentW - btnW - 6
                    local btnY = y + (rowH - btnH) / 2
                    if mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH then
                        slot.taken = true
                        applyTake(slot, catKey)
                        return true
                    end
                end
                y = y + rowH + 4
            end
            y = y + 8
        end
        ::continue::
    end

    local btnAreaW = 280
    local btnH = 36
    local btnY = y + 5
    local rW = 130
    local rX = contentX
    if mx >= rX and mx <= rX + rW and my >= btnY and my <= btnY + btnH then
        shop.reroll()
        return true
    end

    local dW = 130
    local dX = contentX + btnAreaW - dW
    if mx >= dX and mx <= dX + dW and my >= btnY and my <= btnY + btnH then
        shop.isOpen = false
        if shop.autoOpened then
            shop.autoOpened = false
            finishProgression()
        end
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
            finishProgression()
        end
        return true
    end
    return false
end

return shop
