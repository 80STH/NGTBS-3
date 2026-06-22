local menu = {}
local shop = require("ui.shop")
local commanders = require("system.commanders")

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
        name = "New Blood",
        units = {
            { name = "Summoner", maxHealth = 2, moveRange = 3, attacks = "summoner" },
            { name = "Divider",  maxHealth = 2, moveRange = 3, attacks = "divider" },
        }
    },
    {
        name = "Attack Test",
        units = {
            { name = "AttackTest", maxHealth = 2, moveRange = 3, attacks = "all" },
        }
    },
}

function menu.getMapList()
    return mapList
end

function menu.getSquads()
    return squads
end

function menu.draw()
    local w = logicalW
    local h = logicalH

    love.graphics.setColor(0.08, 0.08, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local titleFont = love.graphics.newFont(math.max(16, math.floor(h * 0.03)))
    local smallFont = love.graphics.newFont(11)
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    -- ============================================================
    -- COMMANDER SELECTION
    -- ============================================================
    local cmdStartY = h * 0.04
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Select Commander", 0, cmdStartY, w, "center")

    local cbw, cbh = w - 40, 70
    local cbx = 20
    local cmdNames = {}
    for name, _ in pairs(commanders.list) do table.insert(cmdNames, name) end
    table.sort(cmdNames)

    for i, name in ipairs(cmdNames) do
        local cmd = commanders.get(name)
        local cby = cmdStartY + 35 + (i - 1) * (cbh + 6)
        local hover = mx >= cbx and mx <= cbx + cbw and my >= cby and my <= cby + cbh
        local isSelected = selectedCommander == name

        love.graphics.setColor(hover and 0.25 or 0.15, hover and 0.35 or 0.2, hover and 0.5 or 0.3, 0.9)
        love.graphics.rectangle("fill", cbx, cby, cbw, cbh, 8)
        if isSelected then
            love.graphics.setColor(cmd.color[1], cmd.color[2], cmd.color[3], 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", cbx, cby, cbw, cbh, 8)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(cmd.color[1] * 0.5, cmd.color[2] * 0.5, cmd.color[3] * 0.5, 0.4)
            love.graphics.rectangle("line", cbx, cby, cbw, cbh, 8)
        end

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(13))
        love.graphics.printf(cmd.name, cbx + 10, cby + 4, cbw - 20, "left")
        love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
        love.graphics.setFont(smallFont)
        local abNames = {}
        for _, aid in ipairs(cmd.startAbilities) do table.insert(abNames, aid) end
        love.graphics.printf("Starts with: " .. table.concat(abNames, ", "), cbx + 10, cby + 28, cbw - 20, "left")
        love.graphics.printf(cmd.desc, cbx + 10, cby + 48, cbw - 20, "left")
    end

    -- ============================================================
    -- MAP SELECTION
    -- ============================================================
    local mapStartY = cmdStartY + 35 + #cmdNames * (cbh + 6) + 20
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(titleFont)
    love.graphics.printf("Select Map", 0, mapStartY, w, "center")

    local bw, bh = 260, 50
    local bx = w/2 - bw/2
    local mapButtonsY = mapStartY + 35

    for i, mapPath in ipairs(mapList) do
        local by = mapButtonsY + (i - 1) * (bh + 10)
        local hover = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
        local canClick = selectedCommander ~= nil

        love.graphics.setColor(hover and canClick and 0.3 or 0.15, hover and canClick and 0.5 or 0.25, hover and canClick and 0.7 or 0.35, 0.9)
        love.graphics.rectangle("fill", bx, by, bw, bh, 8)
        love.graphics.setColor(0.4, 0.6, 0.8, (hover and canClick) and 0.8 or 0.4)
        love.graphics.rectangle("line", bx, by, bw, bh, 8)

        local name = mapPath:match("/([^/]+)%.lua$") or mapPath
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(13))
        love.graphics.printf(name, bx + 10, by + bh/2 - 8, bw - 20, "center")
    end

    if not selectedCommander then
        love.graphics.setFont(smallFont)
        love.graphics.setColor(0.8, 0.5, 0.2, 1)
        love.graphics.printf("Select a commander first", 0, mapButtonsY - 16, w, "center")
    end

    -- ============================================================
    -- SQUAD SELECTION + EXTRAS
    -- ============================================================
    local squadStartY = mapButtonsY + #mapList * (bh + 10) + 50
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(titleFont)
    love.graphics.printf("Select Squad", 0, squadStartY, w, "center")

    local sbw, sbh = 200, 40
    local sbx = w/2 - sbw/2

    for i, squad in ipairs(squads) do
        local sby = squadStartY + 35 + (i - 1) * (sbh + 8)
        local hover = mx >= sbx and mx <= sbx + sbw and my >= sby and my <= sby + sbh
        local isSelected = selectedSquad == i
        local canSelect = selectedCommander ~= nil

        love.graphics.setColor(hover and canSelect and 0.35 or 0.2, hover and canSelect and 0.25 or 0.15, isSelected and 0.5 or 0.2, 0.9)
        love.graphics.rectangle("fill", sbx, sby, sbw, sbh, 6)
        love.graphics.setColor(isSelected and 0.5 or 0.3, isSelected and 0.4 or 0.3, isSelected and 0.9 or 0.4, isSelected and 0.9 or 0.5)
        love.graphics.rectangle("line", sbx, sby, sbw, sbh, 6)

        local unitNames = ""
        for j, u in ipairs(squad.units) do
            if j > 1 then unitNames = unitNames .. ", " end
            unitNames = unitNames .. u.name
        end

        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setFont(love.graphics.newFont(12))
        love.graphics.printf(squad.name, sbx + 6, sby + 2, sbw - 12, "left")
        love.graphics.setColor(0.7, 0.7, 0.7, 0.7)
        love.graphics.setFont(love.graphics.newFont(10))
        love.graphics.printf(unitNames, sbx + 6, sby + 20, sbw - 12, "left")
    end

    -- Disable enemy spawn checkbox
    local cbY = squadStartY + 35 + #squads * (sbh + 8) + 20
    local cbSize = 18
    local cbX = w/2 - 120
    local cbHover = mx >= cbX and mx <= cbX + cbSize and my >= cbY and my <= cbY + cbSize

    love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
    love.graphics.rectangle("fill", cbX, cbY, cbSize, cbSize, 3)
    love.graphics.setColor(cbHover and 0.6 or 0.4, cbHover and 0.6 or 0.4, cbHover and 0.8 or 0.6, cbHover and 0.9 or 0.7)
    love.graphics.rectangle("line", cbX, cbY, cbSize, cbSize, 3)
    if disableEnemySpawn then
        love.graphics.setColor(0.3, 0.8, 0.3, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(cbX + 3, cbY + cbSize/2, cbX + cbSize/2, cbY + cbSize - 3)
        love.graphics.line(cbX + cbSize/2, cbY + cbSize - 3, cbX + cbSize - 3, cbY + 3)
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.printf("Disable Enemy Spawn", cbX + cbSize + 10, cbY + 2, 200, "left")

    -- Progression Test button
    local ptY = cbY + 50
    local ptHover = mx >= bx and mx <= bx + bw and my >= ptY and my <= ptY + bh
    local canProgress = selectedCommander ~= nil
    love.graphics.setColor(ptHover and canProgress and 0.3 or 0.15, ptHover and canProgress and 0.5 or 0.25, ptHover and canProgress and 0.2 or 0.1, 0.9)
    love.graphics.rectangle("fill", bx, ptY, bw, bh, 8)
    love.graphics.setColor(0.2, 0.8, 0.4, (ptHover and canProgress) and 0.8 or 0.4)
    love.graphics.rectangle("line", bx, ptY, bw, bh, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(13))
    love.graphics.printf("Progression Test", bx + 10, ptY + bh/2 - 8, bw - 20, "center")

    -- Shop button
    local shopY = ptY + bh + 16
    local shopHover = mx >= bx and mx <= bx + bw and my >= shopY and my <= shopY + bh
    love.graphics.setColor(shopHover and 0.4 or 0.2, shopHover and 0.35 or 0.18, shopHover and 0.2 or 0.1, 0.9)
    love.graphics.rectangle("fill", bx, shopY, bw, bh, 8)
    love.graphics.setColor(0.8, 0.7, 0.2, shopHover and 0.8 or 0.4)
    love.graphics.rectangle("line", bx, shopY, bw, bh, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(13))
    love.graphics.printf("Shop", bx + 10, shopY + bh/2 - 8, bw - 20, "center")

    -- Editor button
    local editorY = shopY + bh + 16
    local editorHover = mx >= bx and mx <= bx + bw and my >= editorY and my <= editorY + bh
    love.graphics.setColor(editorHover and 0.3 or 0.15, editorHover and 0.4 or 0.25, editorHover and 0.6 or 0.35, 0.9)
    love.graphics.rectangle("fill", bx, editorY, bw, bh, 8)
    love.graphics.setColor(0.3, 0.5, 0.8, editorHover and 0.8 or 0.4)
    love.graphics.rectangle("line", bx, editorY, bw, bh, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(13))
    love.graphics.printf("Map Editor", bx + 10, editorY + bh/2 - 8, bw - 20, "center")

    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Click a map to start  |  Hold R to restart", 0, editorY + bh + 12, w, "center")
end

function menu.mousepressed(x, y)
    local w = logicalW
    local h = logicalH

    -- Commander selection
    local cmdStartY = h * 0.04
    local cbw, cbh = w - 40, 70
    local cbx = 20
    local cmdNames = {}
    for name, _ in pairs(commanders.list) do table.insert(cmdNames, name) end
    table.sort(cmdNames)

    for i, name in ipairs(cmdNames) do
        local cby = cmdStartY + 35 + (i - 1) * (cbh + 6)
        if x >= cbx and x <= cbx + cbw and y >= cby and y <= cby + cbh then
            selectedCommander = name
            return true
        end
    end

    -- Map selection (requires commander)
    local bw, bh = 260, 50
    local bx = w/2 - bw/2
    local mapStartY = cmdStartY + 35 + #cmdNames * (cbh + 6) + 20
    local mapButtonsY = mapStartY + 35

    for i, mapPath in ipairs(mapList) do
        local by = mapButtonsY + (i - 1) * (bh + 10)
        if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
            if not selectedCommander then return true end
            if not selectedSquad then selectedSquad = 1 end
            isProgressionRun = false
            global_abilities.initWithCommander(selectedCommander)
            restartGame(mapPath)
            return true
        end
    end

    -- Squad selection
    local sbw, sbh = 200, 40
    local squadStartY = mapButtonsY + #mapList * (bh + 10) + 50
    local sbx = w/2 - sbw/2

    for i in ipairs(squads) do
        local sby = squadStartY + 35 + (i - 1) * (sbh + 8)
        if x >= sbx and x <= sbx + sbw and y >= sby and y <= sby + sbh then
            if not selectedCommander then return true end
            selectedSquad = i
            return true
        end
    end

    -- Disable enemy spawn checkbox
    local cbY = squadStartY + 35 + #squads * (sbh + 8) + 20
    local cbSize = 18
    local cbX = w/2 - 120
    if x >= cbX and x <= cbX + cbSize and y >= cbY and y <= cbY + cbSize then
        disableEnemySpawn = not disableEnemySpawn
        return true
    end

    -- Progression Test button
    local ptY = cbY + 50
    if x >= bx and x <= bx + bw and y >= ptY and y <= ptY + bh then
        if not selectedCommander then return true end
        if not selectedSquad then selectedSquad = 1 end
        unitUpgrades = {}
        artifacts = {}
        commanderArtifacts = {}
        isProgressionRun = true
        currentMapIndex = 1
        global_abilities.initWithCommander(selectedCommander)
        restartGame("maps/map1.lua")
        return true
    end

    -- Shop button
    local shopY = ptY + bh + 16
    if x >= bx and x <= bx + bw and y >= shopY and y <= shopY + bh then
        shop.isOpen = true
        return true
    end

    -- Editor button
    local editorY = shopY + bh + 16
    if x >= bx and x <= bx + bw and y >= editorY and y <= editorY + bh then
        gamePhase = "editor"
        map_editor.dpiScale = dpiScale or 1
        map_editor.init()
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
