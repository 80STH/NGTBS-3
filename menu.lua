local menu = {}

local playtestPhase = nil  -- nil, "select_difficulty"

local mapList = {"maps/map1.lua", "maps/test_polygon_1.lua", "maps/test_polygon_2.lua"}

local squads = {
    {
        name = "Old Guard",
        units = {
            { name = "Warrior", maxHealth = 5, moveRange = 3, attacks = "warrior" },
            { name = "Mage",    maxHealth = 3, moveRange = 4, attacks = "mage" },
            { name = "Rogue",   maxHealth = 4, moveRange = 5, attacks = "rogue" },
        }
    },
    {
        name = "New Blood",
        units = {
            { name = "Summoner", maxHealth = 3, moveRange = 3, attacks = "summoner" },
            { name = "Divider",  maxHealth = 4, moveRange = 4, attacks = "divider" },
        }
    },
    {
        name = "Attack Test",
        units = {
            { name = "AttackTest", maxHealth = 10, moveRange = 6, attacks = "all" },
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

    if playtestPhase == "select_difficulty" then
        menu.drawPlaytestDifficulty()
        return
    end

    -- Draw normal menu
    local titleFont = love.graphics.newFont(math.max(18, math.floor(h * 0.05)))
    love.graphics.setFont(titleFont)
    love.graphics.printf("Select Map", 0, h * 0.12, w, "center")

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

    -- Difficulty slider
    local slideY = squadStartY + #squads * (sbh + 8) + 20
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.printf("Difficulty Modifier", 0, slideY, w, "center")

    local sw, sh = 260, 16
    local sx = w/2 - sw/2
    local sy = slideY + 22
    local knobW = 12
    local knobX = sx + (difficultyModifier - 1) / 31 * (sw - knobW)

    love.graphics.setColor(0.3, 0.3, 0.4, 0.9)
    love.graphics.rectangle("fill", sx, sy, sw, sh, 4)
    love.graphics.setColor(0.4, 0.6, 0.8, 0.6)
    love.graphics.rectangle("line", sx, sy, sw, sh, 4)
    love.graphics.setColor(0.8, 0.4, 0.2, 0.9)
    love.graphics.rectangle("fill", knobX, sy - 2, knobW, sh + 4, 4)

    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(love.graphics.newFont(11))
    love.graphics.printf(tostring(difficultyModifier), 0, sy + sh + 4, w, "center")

    -- Grid mode toggle
    local modeY = sy + sh + 30
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.printf("Grid Mode", 0, modeY, w, "center")

    local modeBtnW, modeBtnH = 140, 28
    local modeBtnY = modeY + 20
    local modeBtn1X = w/2 - modeBtnW - 6
    local modeBtn2X = w/2 + 6

    local mode1Hover = mx >= modeBtn1X and mx <= modeBtn1X + modeBtnW and my >= modeBtnY and my <= modeBtnY + modeBtnH
    local mode2Hover = mx >= modeBtn2X and mx <= modeBtn2X + modeBtnW and my >= modeBtnY and my <= modeBtnY + modeBtnH

    love.graphics.setColor(not gridRotationMode and (mode1Hover and 0.4 or 0.25) or 0.15, not gridRotationMode and 0.3 or 0.15, not gridRotationMode and 0.5 or 0.2, 0.9)
    love.graphics.rectangle("fill", modeBtn1X, modeBtnY, modeBtnW, modeBtnH, 6)
    love.graphics.setColor(not gridRotationMode and 0.5 or 0.3, not gridRotationMode and 0.4 or 0.3, not gridRotationMode and 0.8 or 0.4, not gridRotationMode and 0.9 or 0.5)
    love.graphics.rectangle("line", modeBtn1X, modeBtnY, modeBtnW, modeBtnH, 6)
    love.graphics.setColor(1, 1, 1, not gridRotationMode and 1 or 0.5)
    love.graphics.setFont(love.graphics.newFont(11))
    love.graphics.printf("Standard", modeBtn1X, modeBtnY + 6, modeBtnW, "center")

    love.graphics.setColor(gridRotationMode and (mode2Hover and 0.4 or 0.25) or 0.15, gridRotationMode and 0.3 or 0.15, gridRotationMode and 0.5 or 0.2, 0.9)
    love.graphics.rectangle("fill", modeBtn2X, modeBtnY, modeBtnW, modeBtnH, 6)
    love.graphics.setColor(gridRotationMode and 0.5 or 0.3, gridRotationMode and 0.4 or 0.3, gridRotationMode and 0.8 or 0.4, gridRotationMode and 0.9 or 0.5)
    love.graphics.rectangle("line", modeBtn2X, modeBtnY, modeBtnW, modeBtnH, 6)
    love.graphics.setColor(1, 1, 1, gridRotationMode and 1 or 0.5)
    love.graphics.setFont(love.graphics.newFont(11))
    love.graphics.printf("Rotated", modeBtn2X, modeBtnY + 6, modeBtnW, "center")

    local bottomY = modeBtnY + modeBtnH + 12

    -- Full Playtest button
    local ptY = bottomY + 30
    local ptHover = mx >= bx and mx <= bx + bw and my >= ptY and my <= ptY + bh
    love.graphics.setColor(ptHover and 0.4 or 0.2, ptHover and 0.3 or 0.15, ptHover and 0.2 or 0.1, 0.9)
    love.graphics.rectangle("fill", bx, ptY, bw, bh, 8)
    love.graphics.setColor(0.8, 0.4, 0.2, ptHover and 0.8 or 0.4)
    love.graphics.rectangle("line", bx, ptY, bw, bh, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(13))
    love.graphics.printf("Full Playtest", bx + 10, ptY + bh/2 - 8, bw - 20, "center")

    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Click a map to start  |  R to restart", 0, ptY + bh + 12, w, "center")
end

function menu.drawPlaytestDifficulty()
    local w = logicalW
    local h = logicalH

    love.graphics.setColor(1, 1, 1, 1)
    local titleFont = love.graphics.newFont(math.max(18, math.floor(h * 0.05)))
    love.graphics.setFont(titleFont)
    love.graphics.printf("Full Playtest", 0, h * 0.20, w, "center")

    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf("Select Difficulty", 0, h * 0.28, w, "center")

    local difficulties = {
        { name = "Easy",   desc = "Spawn limit: 5", limit = 5, diff = 4 },
        { name = "Medium", desc = "Spawn limit: 6", limit = 6, diff = 12 },
        { name = "Hard",   desc = "Spawn limit: 7", limit = 7, diff = 24 },
    }

    local bw, bh = 220, 55
    local bx = w/2 - bw/2
    local startY = h * 0.38
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    for i, diff in ipairs(difficulties) do
        local by = startY + (i - 1) * (bh + 12)
        local hover = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh

        love.graphics.setColor(hover and 0.3 or 0.15, hover and 0.5 or 0.25, hover and 0.7 or 0.35, 0.9)
        love.graphics.rectangle("fill", bx, by, bw, bh, 8)
        love.graphics.setColor(0.4, 0.6, 0.8, hover and 0.8 or 0.4)
        love.graphics.rectangle("line", bx, by, bw, bh, 8)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(14))
        love.graphics.printf(diff.name, bx + 10, by + 4, bw - 20, "center")
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.setFont(love.graphics.newFont(11))
        love.graphics.printf(diff.desc, bx + 10, by + 26, bw - 20, "center")
    end

    -- Back button
    local backY = startY + #difficulties * (bh + 12) + 20
    local backHover = mx >= bx and mx <= bx + 120 and my >= backY and my <= backY + 30
    love.graphics.setColor(backHover and 0.4 or 0.2, backHover and 0.25 or 0.15, backHover and 0.2 or 0.1, 0.9)
    love.graphics.rectangle("fill", bx, backY, 120, 30, 6)
    love.graphics.setColor(0.6, 0.4, 0.2, backHover and 0.7 or 0.4)
    love.graphics.rectangle("line", bx, backY, 120, 30, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.printf("Back", bx, backY + 7, 120, "center")
end

function menu.mousepressed(x, y)
    local bw, bh = 260, 50
    local mapStartY = logicalH * 0.20
    local bx = logicalW/2 - bw/2

    if playtestPhase == "select_difficulty" then
        local difficulties = {
            { name = "Easy",   limit = 5, diff = 4 },
            { name = "Medium", limit = 6, diff = 12 },
            { name = "Hard",   limit = 7, diff = 24 },
        }
        local bw2, bh2 = 220, 55
        local bx2 = logicalW/2 - bw2/2
        local startY = logicalH * 0.38

        for i, diff in ipairs(difficulties) do
            local by = startY + (i - 1) * (bh2 + 12)
            if x >= bx2 and x <= bx2 + bw2 and y >= by and y <= by + bh2 then
                _G.playtestMode = true
                _G.playtestSpawnLimit = diff.limit
                _G.playtestEnemyTypes = { "Ghost", "Zombie", "PoisonousZombie", "Lich" }
                selectedSquad = 1
                difficultyModifier = diff.diff
                playtestPhase = nil
                restartGame("maps/map1.lua")
                return true
            end
        end

        -- Back button
        local backY = startY + #difficulties * (bh2 + 12) + 20
        if x >= bx2 and x <= bx2 + 120 and y >= backY and y <= backY + 30 then
            playtestPhase = nil
            return true
        end

        return false
    end

    for i, mapPath in ipairs(mapList) do
        local by = mapStartY + (i - 1) * (bh + 10)
        if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
            if not selectedSquad then selectedSquad = 1 end
            _G.playtestMode = nil
            _G.playtestSpawnLimit = nil
            _G.playtestEnemyTypes = nil
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

    -- Difficulty slider
    local slideY = squadStartY + #squads * (sbh + 8) + 20
    local sw, sh = 260, 16
    local sx = logicalW/2 - sw/2
    local sy = slideY + 22
    if y >= sy - 4 and y <= sy + sh + 8 and x >= sx and x <= sx + sw then
        local relX = (x - sx) / sw
        difficultyModifier = math.max(1, math.min(32, math.floor(relX * 31) + 1))
        return true
    end

    -- Grid mode toggle
    local modeY = sy + sh + 30
    local modeBtnW, modeBtnH = 140, 28
    local modeBtnY = modeY + 20
    local modeBtn1X = logicalW/2 - modeBtnW - 6
    local modeBtn2X = logicalW/2 + 6
    if y >= modeBtnY and y <= modeBtnY + modeBtnH then
        if x >= modeBtn1X and x <= modeBtn1X + modeBtnW then
            gridRotationMode = false
            return true
        elseif x >= modeBtn2X and x <= modeBtn2X + modeBtnW then
            gridRotationMode = true
            return true
        end
    end

    -- Full Playtest button
    local ptY = modeBtnY + modeBtnH + 12 + 30
    if x >= bx and x <= bx + bw and y >= ptY and y <= ptY + bh then
        playtestPhase = "select_difficulty"
        return true
    end

    return false
end

function menu.keypressed(key)
    if playtestPhase == "select_difficulty" then
        return false
    end
    if key == "return" or key == " " then
        if #mapList > 0 then
            if not selectedSquad then selectedSquad = 1 end
            _G.playtestMode = nil
            _G.playtestSpawnLimit = nil
            _G.playtestEnemyTypes = nil
            restartGame(mapList[1])
            return true
        end
    end
    return false
end

return menu
