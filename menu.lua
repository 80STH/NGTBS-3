-- menu.lua
local menu = {}

local mapList = {"maps/map1.lua", "maps/test_polygon_1.lua"}

function menu.getMapList()
    return mapList
end

function menu.draw()
    local w = logicalW
    local h = logicalH

    love.graphics.setColor(0.08, 0.08, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 1, 1, 1)
    local titleFont = love.graphics.newFont(math.max(18, math.floor(h * 0.05)))
    love.graphics.setFont(titleFont)
    love.graphics.printf("Select Map", 0, h * 0.2, w, "center")

    local bw, bh = 300, 60
    local totalH = #mapList * (bh + 16)
    local startY = h/2 - totalH/2
    local bx = w/2 - bw/2

    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    for i, mapPath in ipairs(mapList) do
        local by = startY + (i - 1) * (bh + 16)
        local hover = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh

        love.graphics.setColor(hover and 0.3 or 0.15, hover and 0.5 or 0.25, hover and 0.7 or 0.35, 0.9)
        love.graphics.rectangle("fill", bx, by, bw, bh, 8)
        love.graphics.setColor(0.4, 0.6, 0.8, hover and 0.8 or 0.4)
        love.graphics.rectangle("line", bx, by, bw, bh, 8)

        local name = mapPath:match("/([^/]+)%.lua$") or mapPath
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(love.graphics.newFont(14))
        love.graphics.printf(name, bx + 10, by + bh/2 - 10, bw - 20, "center")
    end

    love.graphics.setFont(love.graphics.newFont(12))
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Press Enter or click a map to start", 0, h * 0.8, w, "center")
end

function menu.mousepressed(x, y)
    local bw, bh = 300, 60
    local totalH = #mapList * (bh + 16)
    local startY = logicalH/2 - totalH/2
    local bx = logicalW/2 - bw/2

    for i, mapPath in ipairs(mapList) do
        local by = startY + (i - 1) * (bh + 16)
        if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
            restartGame(mapPath)
            return true
        end
    end
    return false
end

function menu.keypressed(key)
    if key == "return" or key == " " then
        if #mapList > 0 then
            restartGame(mapList[1])
            return true
        end
    end
    return false
end

return menu
