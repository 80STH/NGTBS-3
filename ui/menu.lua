local menu = {}
local shop = require("ui.shop")
local fonts = require("util.fonts")
local heroDefs = require("entity.environment")

-- Healing pool: menu picks one heal ability for the whole run. `name` is the
-- ability name used in-game ("Heal" = the global all-ally heal).
local healList = {
    { name = "Flash Heal", desc = "+1 HP one ally, free" },
    { name = "Heal", desc = "+1 HP all allies, 1 mana" },
    { name = "Stim Pack", desc = "+1 move this turn, free" },
    { name = "Armor Pack", desc = "+2 HP & max HP, 1 mana" },
}

-- Starting-spell pool (Heal/Revive are base spells, excluded). name + one-line description.
local spellList = {
    { name = "Extra Move", desc = "Cleanse and shift an ally 1 cell" },
    { name = "Wind Torrent", desc = "Push all units away from a hex" },
    { name = "Unearth", desc = "Enemies in dig sites emerge now" },
    { name = "Mind Control", desc = "Move an enemy 1 cell" },
    { name = "Accelerate Decay", desc = "Decay activates 1 turn sooner" },
    { name = "Force Attack", desc = "Enemy attacks first in turn order" },
    { name = "Rage", desc = "1-damage attacks become fatal (1 turn)" },
    { name = "The Big One", desc = "Fatal damage in a triangle sector" },
    { name = "Air Strike", desc = "1 damage in a straight line" },
    { name = "Jumping Strike", desc = "1 damage to every other cell in line" },
    { name = "Overload", desc = "Fatal damage to ally + adjacent units" },
    { name = "Chain Lightning", desc = "1 dmg, fatal to adjacent 2nd target" },
    { name = "Invulnerability", desc = "Immune to damage, cleanse debuffs" },
    { name = "Vortex", desc = "Rotate units 60 deg around a cell" },
    { name = "Hex", desc = "Turn an enemy into a cowardly beast" },
    { name = "Upside Down", desc = "Kill a creature; corpse falls later" },
    { name = "Teleport", desc = "Ally teleports anywhere this battle" },
    { name = "Speed Boost", desc = "+1 move for an ally (free)" },
    { name = "Void", desc = "Turn a cell into emptiness" },
    { name = "Infest", desc = "1 dmg; lethal spawns an Infested ally" },
}

local function loadMapList()
    local items = love.filesystem.getDirectoryItems("maps")
    local list = {}
    for _, file in ipairs(items) do
        if file:match("%.lua$") and file ~= "units_workaround.lua" then
            table.insert(list, "maps/" .. file)
        end
    end
    table.sort(list)
    return list
end

local mapList = loadMapList()

function menu.getMapList()
    return mapList
end

local defaultsSet = false
local function ensureDefaults()
    if defaultsSet then return end
    defaultsSet = true
    if not selectedHero then selectedHero = 1 end
    if not healSpell then healSpell = "Heal" end
    if not startingSpell then startingSpell = "Infest" end
end

-- Cached layout data (computed on draw, reused on click)
local layout = {}

local function computeLayout(w, h)
    local l = {}
    local pad = 12
    local contentW = math.min(w - 2 * pad, 480)
    local cx = math.floor((w - contentW) / 2)
    l.cx = cx
    l.contentW = contentW

    local y = 14
    local titleFont = fonts.get(math.max(18, math.floor(h * 0.032)))
    l.titleFont = titleFont
    l.titleY = y
    y = y + titleFont:getHeight() + 18

    local cardFont = fonts.get(16)
    local tinyFont = fonts.get(13)
    l.cardFont = cardFont
    l.tinyFont = tinyFont

    -- Heroes / squads
    l.heroLabelY = y
    y = y + 24
    local heroCount = #heroDefs.getHeroes()
    local heroCardW = math.floor((contentW - (heroCount - 1) * 6) / heroCount)
    local heroCardH = 68
    l.heroCards = {}
    for i, hero in ipairs(heroDefs.getHeroes()) do
        l.heroCards[i] = {
            x = cx + (i - 1) * (heroCardW + 6),
            y = y,
            w = heroCardW,
            h = heroCardH,
        }
    end
    y = y + heroCardH + 16

    -- Healing selection (2 columns)
    l.healLabelY = y
    y = y + 24
    local healGap = 4
    local healCardH = 24
    local healColW = math.floor((contentW - healGap) / 2)
    l.healCards = {}
    for i, hp in ipairs(healList) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        l.healCards[i] = {
            name = hp.name,
            x = cx + col * (healColW + healGap),
            y = y + row * (healCardH + healGap),
            w = healColW,
            h = healCardH,
        }
    end
    y = y + math.ceil(#healList / 2) * (healCardH + healGap) + 12

    -- Starting spell selection (2 columns)
    l.spellLabelY = y
    y = y + 24
    local spellGap = 4
    local spellCardH = 24
    local spellColW = math.floor((contentW - spellGap) / 2)
    l.spellCards = {}
    for i, sp in ipairs(spellList) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        l.spellCards[i] = {
            name = sp.name,
            x = cx + col * (spellColW + spellGap),
            y = y + row * (spellCardH + spellGap),
            w = spellColW,
            h = spellCardH,
        }
    end
    y = y + math.ceil(#spellList / 2) * (spellCardH + spellGap) + 12

    -- "No starting spell" clear option
    l.noneBtn = { x = cx, y = y, w = contentW, h = 16 }
    y = y + 16 + 4

    -- Maps
    local smallFont = fonts.get(14)
    l.smallFont = smallFont
    l.mapLabelY = y
    y = y + 24
    local mapBtnH = 32
    local mapBtnGap = 4
    l.mapBtns = {}
    for i, mapPath in ipairs(mapList) do
        l.mapBtns[i] = {
            path = mapPath,
            x = cx,
            y = y,
            w = contentW,
            h = mapBtnH,
        }
        y = y + mapBtnH + mapBtnGap
    end
    y = y + 8

    -- Bottom buttons (2-column grid)
    local btnH = 54
    local btnGap = 12
    local btnColW = math.floor((contentW - btnGap) / 2)
    l.btns = {}
    local btnDefs = {
        { key = "progression", label = "Progression Test", r = 0.2, g = 0.7, b = 0.3 },
        { key = "shop",        label = "Shop",             r = 0.8, g = 0.7, b = 0.2 },
        { key = "editor",      label = "Map Editor",       r = 0.3, g = 0.5, b = 0.8 },
        { key = "creature_lab", label = "Creature Lab",    r = 0.6, g = 0.3, b = 0.8 },
        { key = "quit",        label = "Quit",             r = 0.7, g = 0.2, b = 0.2 },
    }
    local btnRows = math.ceil(#btnDefs / 2)
    for i, def in ipairs(btnDefs) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        l.btns[i] = {
            key = def.key,
            label = def.label,
            r = def.r, g = def.g, b = def.b,
            x = cx + col * (btnColW + btnGap),
            y = y + row * (btnH + btnGap),
            w = btnColW,
            h = btnH,
        }
    end
    y = y + btnRows * (btnH + btnGap) + 6

    -- Checkboxes
    local cbSize = 18
    l.cb = { x = cx, y = y, w = cbSize, h = cbSize }
    l.cbLabelX = cx + cbSize + 8
    l.cbLabelY = y
    y = y + cbSize + 8
    l.cb2 = { x = cx, y = y, w = cbSize, h = cbSize }
    l.cb2LabelX = cx + cbSize + 8
    l.cb2LabelY = y
    y = y + cbSize + 16

    -- Hint
    l.hintY = y

    layout = l
end

function menu.draw()
    ensureDefaults()
    local w = logicalW
    local h = logicalH

    love.graphics.setColor(0.08, 0.08, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    computeLayout(w, h)
    local l = layout
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    -- Title
    love.graphics.setFont(l.titleFont)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("HEX STRATEGY", 0, l.titleY, w, "center")

    -- Hero label
    love.graphics.setFont(l.cardFont)
    love.graphics.setColor(0.6, 0.8, 1, 0.9)
    love.graphics.printf("Hero (2 atk + 2 move per turn)", l.cx, l.heroLabelY, l.contentW, "center")

    -- Hero cards
    local heroes = heroDefs.getHeroes()
    for i, hero in ipairs(heroes) do
        local card = l.heroCards[i]
        local hover = mx >= card.x and mx <= card.x + card.w and my >= card.y and my <= card.y + card.h
        local sel = selectedHero == i

        love.graphics.setColor(hover and 0.2 or 0.1, hover and 0.16 or 0.12, hover and 0.3 or (sel and 0.25 or 0.15), 0.95)
        love.graphics.rectangle("fill", card.x, card.y, card.w, card.h, 5)
        if sel then
            love.graphics.setColor(0.9, 0.55, 0.2, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 5)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(0.4, 0.3, 0.25, 0.4)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 5)
        end

        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.setFont(l.cardFont)
        love.graphics.printf(hero.name, card.x + 2, card.y + 3, card.w - 4, "center")
        love.graphics.setColor(0.8, 0.7, 0.5, 0.9)
        love.graphics.setFont(l.tinyFont)
        love.graphics.printf("HP" .. hero.hp .. " Mv" .. hero.move, card.x + 2, card.y + 20, card.w - 4, "center")
        local names = {}
        for _, a in ipairs(hero.attacks()) do table.insert(names, a.name) end
        love.graphics.setColor(0.7, 0.8, 1, 0.85)
        love.graphics.setFont(fonts.get(9))
        love.graphics.printf(table.concat(names, " / "), card.x + 2, card.y + 35, card.w - 4, "center")
        local abil = hero.abilities or {}
        if #abil > 0 then
            love.graphics.setColor(0.8, 0.6, 1, 0.9)
            love.graphics.printf("Abilities: " .. table.concat(abil, " / "), card.x + 2, card.y + 50, card.w - 4, "center")
        end
    end

    -- Healing selection
    love.graphics.setFont(l.cardFont)
    love.graphics.setColor(0.6, 1.0, 0.7, 0.9)
    love.graphics.printf("Healing (always available)", l.cx, l.healLabelY, l.contentW, "center")

    for i, card in ipairs(l.healCards) do
        local hover = mx >= card.x and mx <= card.x + card.w and my >= card.y and my <= card.y + card.h
        local sel = (healSpell or "Heal") == card.name
        love.graphics.setColor(hover and 0.16 or 0.1, hover and 0.26 or 0.18, hover and 0.16 or 0.12, 0.95)
        love.graphics.rectangle("fill", card.x, card.y, card.w, card.h, 3)
        if sel then
            love.graphics.setColor(0.3, 0.9, 0.4, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 3)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(0.3, 0.5, 0.35, 0.35)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 3)
        end
        love.graphics.setFont(l.smallFont)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.print(card.name, card.x + 4, card.y + 1)
        local hp = healList[i]
        love.graphics.setFont(fonts.get(10))
        love.graphics.setColor(0.75, 0.85, 0.8, 0.85)
        love.graphics.print(hp.desc, card.x + 4, card.y + 13)
    end

    -- Starting spell selection
    love.graphics.setFont(l.cardFont)
    love.graphics.setColor(0.6, 0.8, 1, 0.9)
    love.graphics.printf("Starting Spell (optional)", l.cx, l.spellLabelY, l.contentW, "center")

    for i, card in ipairs(l.spellCards) do
        local hover = mx >= card.x and mx <= card.x + card.w and my >= card.y and my <= card.y + card.h
        local sel = startingSpell == card.name
        love.graphics.setColor(hover and 0.22 or 0.12, hover and 0.18 or 0.12, hover and 0.3 or (sel and 0.25 or 0.14), 0.95)
        love.graphics.rectangle("fill", card.x, card.y, card.w, card.h, 3)
        if sel then
            love.graphics.setColor(0.9, 0.55, 0.2, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 3)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(0.4, 0.35, 0.3, 0.35)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 3)
        end
        love.graphics.setFont(l.smallFont)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.print(card.name, card.x + 4, card.y + 1)
        local sp = spellList[i]
        love.graphics.setFont(fonts.get(10))
        love.graphics.setColor(0.75, 0.75, 0.8, 0.85)
        love.graphics.print(sp.desc, card.x + 4, card.y + 13)
    end
    -- "None" option clears the choice
    local nb = l.noneBtn
    local noneHover = mx >= nb.x and mx <= nb.x + nb.w and my >= nb.y and my <= nb.y + nb.h
    love.graphics.setFont(fonts.get(11))
    local noneActive = startingSpell == nil
    love.graphics.setColor(noneActive and (noneHover and 0.9 or 0.7) or (noneHover and 0.6 or 0.4), noneActive and (noneHover and 0.9 or 0.7) or (noneHover and 0.6 or 0.4), noneActive and 1.0 or (noneHover and 0.7 or 0.5), 0.9)
    love.graphics.print("(no starting spell)", nb.x, nb.y)

    -- Map label
    local canClickMap = selectedHero ~= nil
    love.graphics.setColor(0.6, 0.8, 1, 0.9)
    love.graphics.printf("Map", l.cx, l.mapLabelY, l.contentW, "center")

    -- Map buttons
    for i, btn in ipairs(l.mapBtns) do
        local hover = mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
        love.graphics.setColor(hover and canClickMap and 0.15 or 0.08, hover and canClickMap and 0.3 or 0.15, hover and canClickMap and 0.5 or 0.25, 0.9)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 4)
        love.graphics.setColor(0.3, 0.5, 0.7, (hover and canClickMap) and 0.6 or 0.25)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 4)

        local name = btn.path:match("/([^/]+)%.lua$") or btn.path
        love.graphics.setColor(1, 1, 1, canClickMap and 0.9 or 0.35)
        love.graphics.setFont(l.smallFont)
        love.graphics.printf(name, btn.x + 6, btn.y + btn.h/2 - 7, btn.w - 12, "center")
    end

    -- Action buttons
    for i, btn in ipairs(l.btns) do
        local hover = mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
        love.graphics.setColor(hover and btn.r*0.6 or btn.r*0.3, hover and btn.g*0.6 or btn.g*0.3, hover and btn.b*0.6 or btn.b*0.3, 0.9)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(btn.r, btn.g, btn.b, hover and 0.85 or 0.45)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(l.smallFont)
        love.graphics.printf(btn.label, btn.x + 6, btn.y + btn.h/2 - 7, btn.w - 12, "center")
    end

    -- Checkboxes
    local cb = l.cb
    local cbHover = mx >= cb.x and mx <= cb.x + 260 and my >= cb.y and my <= cb.y + cb.h
    love.graphics.setColor(0.15, 0.15, 0.2, 0.9)
    love.graphics.rectangle("fill", cb.x, cb.y, cb.w, cb.h, 3)
    love.graphics.setColor(cbHover and 0.5 or 0.35, cbHover and 0.5 or 0.35, cbHover and 0.7 or 0.5, 0.8)
    love.graphics.rectangle("line", cb.x, cb.y, cb.w, cb.h, 3)
    if spawnAllUnits then
        love.graphics.setColor(0.3, 0.8, 0.3, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(cb.x + 3, cb.y + cb.h/2, cb.x + cb.h/2, cb.y + cb.h - 3)
        love.graphics.line(cb.x + cb.h/2, cb.y + cb.h - 3, cb.x + cb.h - 3, cb.y + 3)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setFont(l.tinyFont)
    love.graphics.printf("Spawn All Units", l.cbLabelX, l.cbLabelY + 1, 160, "left")

    local cb2 = l.cb2
    local cb2Hover = mx >= cb2.x and mx <= cb2.x + 180 and my >= cb2.y and my <= cb2.y + cb2.h
    love.graphics.setColor(0.15, 0.15, 0.2, 0.9)
    love.graphics.rectangle("fill", cb2.x, cb2.y, cb2.w, cb2.h, 3)
    love.graphics.setColor(cb2Hover and 0.5 or 0.35, cb2Hover and 0.5 or 0.35, cb2Hover and 0.7 or 0.5, 0.8)
    love.graphics.rectangle("line", cb2.x, cb2.y, cb2.w, cb2.h, 3)
    if unlimitedAbilities then
        love.graphics.setColor(0.3, 0.8, 0.3, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(cb2.x + 3, cb2.y + cb2.h/2, cb2.x + cb2.h/2, cb2.y + cb2.h - 3)
        love.graphics.line(cb2.x + cb2.h/2, cb2.y + cb2.h - 3, cb2.x + cb2.h - 3, cb2.y + 3)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setFont(l.tinyFont)
    love.graphics.printf("All abilities + unlimited mana", l.cb2LabelX, l.cb2LabelY + 1, 160, "left")

    -- Hint
    love.graphics.setColor(0.4, 0.4, 0.4, 0.6)
    love.graphics.printf("Click a map to start  |  Hold R to restart", 0, l.hintY, w, "center")
end

function menu.mousepressed(x, y)
    ensureDefaults()
    local w = logicalW
    local h = logicalH
    computeLayout(w, h)
    local l = layout

    -- Heroes
    for i, card in ipairs(l.heroCards) do
        if x >= card.x and x <= card.x + card.w and y >= card.y and y <= card.y + card.h then
            selectedHero = i
            return true
        end
    end

    -- Healing selection
    for i, card in ipairs(l.healCards) do
        if x >= card.x and x <= card.x + card.w and y >= card.y and y <= card.y + card.h then
            healSpell = card.name
            return true
        end
    end

    -- Starting spell selection
    local nb = l.noneBtn
    if nb and x >= nb.x and x <= nb.x + nb.w and y >= nb.y and y <= nb.y + nb.h then
        startingSpell = nil
        return true
    end
    for i, card in ipairs(l.spellCards) do
        if x >= card.x and x <= card.x + card.w and y >= card.y and y <= card.y + card.h then
            startingSpell = card.name
            return true
        end
    end

    -- Maps
    for i, btn in ipairs(l.mapBtns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if not selectedHero then selectedHero = 1 end
            isProgressionRun = false
            soulPowerInit()
            beginCurrentMission()
            restartGame(btn.path)
            return true
        end
    end

    -- Buttons
    for _, btn in ipairs(l.btns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.key == "progression" then
                selectedHero = 1
                genericUpgrades = {}
                progressionChoices = {}
                chaosSurplus = 0
                chaosScaleBonus = 0
                isProgressionRun = true
                currentMapIndex = 1
                progressionShopOpened = false
                soulPowerInit()
                beginCurrentMission()
                restartGame("maps/map1.lua")
                return true
            elseif btn.key == "shop" then
                shop.open()
                return true
            elseif btn.key == "editor" then
                gamePhase = "editor"
                map_editor.dpiScale = dpiScale or 1
                map_editor.init()
                return true
            elseif btn.key == "creature_lab" then
                gamePhase = "creature_lab"
                enemy_lab.init()
                return true
            elseif btn.key == "quit" then
                love.event.quit()
                return true
            end
        end
    end

    -- Checkboxes
    local cb = l.cb
    if x >= cb.x and x <= cb.x + 260 and y >= cb.y and y <= cb.y + cb.h then
        spawnAllUnits = not spawnAllUnits
        return true
    end
    local cb2 = l.cb2
    if x >= cb2.x and x <= cb2.x + 180 and y >= cb2.y and y <= cb2.y + cb2.h then
        unlimitedAbilities = not unlimitedAbilities
        return true
    end

    return false
end

function menu.keypressed(key)
    if shop.keypressed(key) then return true end
    if key == "return" or key == " " then
        if #mapList > 0 then
            if not selectedHero then selectedHero = 1 end
            soulPowerInit()
            beginCurrentMission()
            restartGame(mapList[1])
            return true
        end
    end
    return false
end

return menu
