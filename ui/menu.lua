local menu = {}
local shop = require("ui.shop")
local commanders = require("system.commanders")
local fonts = require("util.fonts")

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

local squads = {
    {
        name = "Old Guard",
        units = {
            { name = "Warrior", maxHealth = 2, moveRange = 3, attacks = "warrior" },
            { name = "Puncher", maxHealth = 2, moveRange = 3, attacks = "puncher" },
            { name = "Rogue",   maxHealth = 2, moveRange = 3, attacks = "rogue" },
        }
    },
    {
        name = "Disruptors",
        units = {
            { name = "Warrior", maxHealth = 2, moveRange = 3, attacks = "vortex" },
            { name = "Puncher", maxHealth = 2, moveRange = 3, attacks = "hooks" },
            { name = "Rogue",   maxHealth = 2, moveRange = 3, attacks = "area" },
        }
    },
    {
        name = "New Blood",
        units = {
            { name = "Summoner", maxHealth = 2, moveRange = 3, attacks = "summoner" },
            { name = "Divider",  maxHealth = 2, moveRange = 3, attacks = "divider" },
        }
    },
    {
        name = "Wildbond",
        units = {
            { name = "Colossus", maxHealth = 2, moveRange = 3, attacks = "colossus" },
            { name = "Keeper",   maxHealth = 1, moveRange = 2, attacks = "keeper" },
            { name = "Provoker", maxHealth = 1, moveRange = 2, attacks = "provoker" },
        }
    },
    {
        name = "Attack Test",
        units = {
            { name = "AttackTest", maxHealth = 2, moveRange = 3, attacks = "all" },
        }
    },
}

local squadAttackNames = {}
local function getSquadAttackNames(squadIdx)
    if squadAttackNames[squadIdx] then return squadAttackNames[squadIdx] end
    local names = {}
    local squad = squads[squadIdx]
    if squad then
        for _, u in ipairs(squad.units) do
            local atkSet = environment and environment.getAttacks and environment.getAttacks(u.attacks)
            if atkSet then
                for _, a in ipairs(atkSet) do
                    table.insert(names, a.name)
                end
            end
        end
    end
    squadAttackNames[squadIdx] = names
    return names
end

function menu.getMapList()
    return mapList
end

function menu.getSquads()
    return squads
end

local defaultsSet = false
local function ensureDefaults()
    if defaultsSet then return end
    defaultsSet = true
    if not selectedCommander then
        local names = {}
        for name, _ in pairs(commanders.list) do table.insert(names, name) end
        table.sort(names)
        if #names > 0 then selectedCommander = names[1] end
    end
    if not selectedSquad then selectedSquad = 1 end
end

-- Cached layout data (computed on draw, reused on click)
local layout = {}

local function computeLayout(w, h)
    local l = {}
    local pad = 12
    local contentW = math.min(w - 2 * pad, 420)
    local cx = math.floor((w - contentW) / 2)
    l.cx = cx
    l.contentW = contentW

    local cmdNames = {}
    for name, _ in pairs(commanders.list) do table.insert(cmdNames, name) end
    table.sort(cmdNames)
    l.cmdNames = cmdNames

    local y = 10
    local titleFont = fonts.get(math.max(14, math.floor(h * 0.025)))
    l.titleFont = titleFont
    l.titleY = y
    y = y + titleFont:getHeight() + 14

    -- Commanders (horizontal row of compact cards)
    local cardFont = fonts.get(12)
    local tinyFont = fonts.get(10)
    l.cardFont = cardFont
    l.tinyFont = tinyFont

    l.cmdLabelY = y
    y = y + 18
    local cmdCardW = math.floor((contentW - (#cmdNames - 1) * 6) / #cmdNames)
    local cmdCardH = 40
    l.cmdCards = {}
    for i, name in ipairs(cmdNames) do
        l.cmdCards[i] = {
            name = name,
            x = cx + (i - 1) * (cmdCardW + 6),
            y = y,
            w = cmdCardW,
            h = cmdCardH,
        }
    end
    y = y + cmdCardH + 10

    -- Squads (horizontal row of compact cards)
    l.squadLabelY = y
    y = y + 18
    local squadCardW = math.floor((contentW - (#squads - 1) * 6) / #squads)
    local squadCardH = 40
    l.squadCards = {}
    for i, squad in ipairs(squads) do
        l.squadCards[i] = {
            x = cx + (i - 1) * (squadCardW + 6),
            y = y,
            w = squadCardW,
            h = squadCardH,
        }
    end
    y = y + squadCardH + 14

    -- Maps
    local smallFont = fonts.get(11)
    l.smallFont = smallFont
    l.mapLabelY = y
    y = y + 18
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
    y = y + 6

    -- Bottom buttons (2-column grid)
    local btnH = 50
    local btnGap = 10
    local btnColW = math.floor((contentW - btnGap) / 2)
    l.btns = {}
    local btnDefs = {
        { key = "progression", label = "Progression Test", r = 0.2, g = 0.7, b = 0.3 },
        { key = "shop",        label = "Shop",             r = 0.8, g = 0.7, b = 0.2 },
        { key = "editor",      label = "Map Editor",       r = 0.3, g = 0.5, b = 0.8 },
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
    y = y + btnRows * (btnH + btnGap) + 4

    -- Checkboxes
    local cbSize = 14
    l.cb = { x = cx, y = y, w = cbSize, h = cbSize }
    l.cbLabelX = cx + cbSize + 6
    l.cbLabelY = y
    y = y + cbSize + 6
    l.cb2 = { x = cx, y = y, w = cbSize, h = cbSize }
    l.cb2LabelX = cx + cbSize + 6
    l.cb2LabelY = y
    y = y + cbSize + 12

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

    -- Commander label
    love.graphics.setFont(l.cardFont)
    love.graphics.setColor(0.6, 0.8, 1, 0.9)
    love.graphics.printf("Commander", l.cx, l.cmdLabelY, l.contentW, "center")

    -- Commander cards
    for i, card in ipairs(l.cmdCards) do
        local cmd = commanders.get(card.name)
        local hover = mx >= card.x and mx <= card.x + card.w and my >= card.y and my <= card.y + card.h
        local sel = selectedCommander == card.name

        love.graphics.setColor(hover and 0.2 or 0.12, hover and 0.28 or 0.16, hover and 0.4 or 0.25, 0.95)
        love.graphics.rectangle("fill", card.x, card.y, card.w, card.h, 5)
        if sel then
            love.graphics.setColor(cmd.color[1], cmd.color[2], cmd.color[3], 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 5)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(cmd.color[1] * 0.4, cmd.color[2] * 0.4, cmd.color[3] * 0.4, 0.3)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 5)
        end

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(l.cardFont)
        love.graphics.printf(cmd.name, card.x + 6, card.y + 3, card.w - 12, "center")
        love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
        love.graphics.setFont(l.tinyFont)
        love.graphics.printf(table.concat(cmd.startAbilities, ", "), card.x + 6, card.y + 19, card.w - 12, "center")
    end

    -- Squad label
    love.graphics.setFont(l.cardFont)
    love.graphics.setColor(0.6, 0.8, 1, 0.9)
    love.graphics.printf("Squad", l.cx, l.squadLabelY, l.contentW, "center")

    -- Squad cards
    for i, squad in ipairs(squads) do
        local card = l.squadCards[i]
        local hover = mx >= card.x and mx <= card.x + card.w and my >= card.y and my <= card.y + card.h
        local sel = selectedSquad == i

        love.graphics.setColor(hover and 0.2 or 0.1, hover and 0.18 or 0.12, sel and 0.3 or (hover and 0.25 or 0.15), 0.95)
        love.graphics.rectangle("fill", card.x, card.y, card.w, card.h, 5)
        if sel then
            love.graphics.setColor(0.4, 0.35, 0.8, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 5)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(0.3, 0.3, 0.4, 0.4)
            love.graphics.rectangle("line", card.x, card.y, card.w, card.h, 5)
        end

        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.setFont(l.cardFont)
        love.graphics.printf(squad.name, card.x + 6, card.y + 3, card.w - 12, "center")

        local unitNames = ""
        for j, u in ipairs(squad.units) do
            if j > 1 then unitNames = unitNames .. ", " end
            unitNames = unitNames .. u.name
        end
        love.graphics.setColor(0.7, 0.7, 0.7, 0.7)
        love.graphics.setFont(l.tinyFont)
        love.graphics.printf(unitNames, card.x + 6, card.y + 19, card.w - 12, "center")
    end

    -- Map label
    local canClickMap = selectedCommander ~= nil
    love.graphics.setFont(l.cardFont)
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
    local cbHover = mx >= cb.x and mx <= cb.x + 180 and my >= cb.y and my <= cb.y + cb.h
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

    -- Commanders
    for i, card in ipairs(l.cmdCards) do
        if x >= card.x and x <= card.x + card.w and y >= card.y and y <= card.y + card.h then
            selectedCommander = card.name
            return true
        end
    end

    -- Squads
    for i, card in ipairs(l.squadCards) do
        if x >= card.x and x <= card.x + card.w and y >= card.y and y <= card.y + card.h then
            if not selectedCommander then return true end
            selectedSquad = i
            return true
        end
    end

    -- Maps
    for i, btn in ipairs(l.mapBtns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if not selectedCommander then return true end
            if not selectedSquad then selectedSquad = 1 end
            isProgressionRun = false
            global_abilities.initWithCommander(selectedCommander)
            restartGame(btn.path)
            return true
        end
    end

    -- Buttons
    for _, btn in ipairs(l.btns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.key == "progression" then
                if not selectedCommander then return true end
                if not selectedSquad then selectedSquad = 1 end
                unitUpgrades = {}
                artifacts = {}
                commanderArtifacts = {}
                genericUpgrades = {}
                progressionChoices = {}
                chaosSurplus = 0
                chaosScaleBonus = 0
                isProgressionRun = true
                currentMapIndex = 1
                progressionShopOpened = false
                global_abilities.initWithCommander(selectedCommander)
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
            elseif btn.key == "quit" then
                love.event.quit()
                return true
            end
        end
    end

    -- Checkboxes
    local cb = l.cb
    if x >= cb.x and x <= cb.x + 180 and y >= cb.y and y <= cb.y + cb.h then
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
            if not selectedCommander then return true end
            if not selectedSquad then selectedSquad = 1 end
            global_abilities.initWithCommander(selectedCommander)
            restartGame(mapList[1])
            return true
        end
    end
    return false
end

return menu
