local menu = {}

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

    -- Draw normal menu
    local titleFont = love.graphics.newFont(math.max(16, math.floor(h * 0.03)))
    love.graphics.setFont(titleFont)
    love.graphics.printf("Select Map", 0, h * 0.10, w, "center")

    local bw, bh = 260, 50
    local mapStartY = h * 0.20
    local bx = w/2 - bw/2

    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    for i, mapPath in ipairs(mapList) do
        local by = mapStartY + (i - 1) * (bh + 10)
        local hover = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh

        love.graphics.setColor(hover and 0.3 or 0.15, hover and 0.5 or 0.25, hover and 0.7 or 0.35, 0.9)
        love.graphics.rectangle("fill", bx, by, bw, bh, 8)
        love.graphics.setColor(0.4, 0.6, 0.8, hover and 0.8 or 0.4)
        love.graphics.rectangle("line", bx, by, bw, bh, 8)

        local name = mapPath:match("/([^/]+)%.lua$") or mapPath
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(13))
        love.graphics.printf(name, bx + 10, by + bh/2 - 8, bw - 20, "center")
    end

    local squadStartY = mapStartY + #mapList * (bh + 10) + 160
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(titleFont)
    love.graphics.printf("Select Squad", 0, squadStartY - 80, w, "center")

    local sbw, sbh = 200, 40
    local sbx = w/2 - sbw/2

    for i, squad in ipairs(squads) do
        local sby = squadStartY + (i - 1) * (sbh + 8)
        local hover = mx >= sbx and mx <= sbx + sbw and my >= sby and my <= sby + sbh
        local isSelected = selectedSquad == i

        love.graphics.setColor(hover and 0.35 or 0.2, hover and 0.25 or 0.15, isSelected and 0.5 or 0.2, 0.9)
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
    local cbY = squadStartY + #squads * (sbh + 8) + 20
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

    -- Metaprogression Test button
    local ptY = cbY + 50
    local ptHover = mx >= bx and mx <= bx + bw and my >= ptY and my <= ptY + bh
    love.graphics.setColor(ptHover and 0.3 or 0.15, ptHover and 0.5 or 0.25, ptHover and 0.2 or 0.1, 0.9)
    love.graphics.rectangle("fill", bx, ptY, bw, bh, 8)
    love.graphics.setColor(0.2, 0.8, 0.4, ptHover and 0.8 or 0.4)
    love.graphics.rectangle("line", bx, ptY, bw, bh, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(13))
    love.graphics.printf("Metaprogression Test", bx + 10, ptY + bh/2 - 8, bw - 20, "center")

    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Click a map to start  |  Hold R to restart", 0, ptY + bh + 12, w, "center")
end

function menu.mousepressed(x, y)
    local bw, bh = 260, 50
    local mapStartY = logicalH * 0.20
    local bx = logicalW/2 - bw/2

    for i, mapPath in ipairs(mapList) do
        local by = mapStartY + (i - 1) * (bh + 10)
        if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
            if not selectedSquad then selectedSquad = 1 end
            isMetaprogressionRun = false
            global_abilities.resetUnlocks()
            restartGame(mapPath)
            return true
        end
    end

    local sbw, sbh = 200, 40
    local squadStartY = mapStartY + #mapList * (bh + 10) + 160
    local sbx = logicalW/2 - sbw/2

    for i in ipairs(squads) do
        local sby = squadStartY + (i - 1) * (sbh + 8)
        if x >= sbx and x <= sbx + sbw and y >= sby and y <= sby + sbh then
            selectedSquad = i
            return true
        end
    end

    -- Disable enemy spawn checkbox
    local cbY = squadStartY + #squads * (sbh + 8) + 20
    local cbSize = 18
    local cbX = logicalW/2 - 120
    if x >= cbX and x <= cbX + cbSize and y >= cbY and y <= cbY + cbSize then
        disableEnemySpawn = not disableEnemySpawn
        return true
    end

    -- Metaprogression Test button
    local ptY = cbY + 50
    if x >= bx and x <= bx + bw and y >= ptY and y <= ptY + bh then
        if not selectedSquad then selectedSquad = 1 end
        global_abilities.resetUnlocks()
        isMetaprogressionRun = true
        currentMapIndex = 1
        restartGame("maps/map1.lua")
        return true
    end

    return false
end

function menu.keypressed(key)
    if key == "return" or key == " " then
        if #mapList > 0 then
            if not selectedSquad then selectedSquad = 1 end
            restartGame(mapList[1])
            return true
        end
    end
    return false
end

return menu
