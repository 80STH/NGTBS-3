local grid_test = {}

local hexTest
local gridW, gridH = 15, 15
local hexRadius = 56

local function rebuildGrid()
    local HexGrid = require("grid.hexgrid")
    hexTest = HexGrid.new(hexRadius, gridW, gridH)
    hexTest.offsetX = 0
    hexTest.offsetY = 0
    hexTest:centerOnScreen(logicalW or 800, logicalH or 1280)
end

function grid_test.init()
    rebuildGrid()
end

function grid_test.draw()
    local w, h = logicalW, logicalH
    local fonts = require("util.fonts")

    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.push()
    love.graphics.scale(dpiScale)

    if hexTest then
        for q = 0, gridW - 1 do
            for r = 0, gridH - 1 do
                local x, y = hexTest:hexToPixel(q, r)
                local terrain = "grass"
                if (q + r) % 3 == 0 then terrain = "stone" end
                if (q * r) % 5 == 0 then terrain = "water" end
                if (q - r) % 4 == 0 then terrain = "lava" end
                hexTest:drawTerrainHex(q, r, terrain, x, y)
            end
        end
    end

    love.graphics.pop()

    love.graphics.setFont(fonts.get(24))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("GRID PERFORMANCE TEST", 0, 15, w, "center")

    love.graphics.setFont(fonts.get(11))
    love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
    love.graphics.printf("ESC: back  |  FPS: " .. love.timer.getFPS() .. "  |  Grid: " .. gridW .. "x" .. gridH .. " (" .. (gridW * gridH) .. " hexes)", 0, 42, w, "center")

    love.graphics.setFont(fonts.get(10))
    love.graphics.setColor(0.4, 0.4, 0.4, 0.5)
    love.graphics.printf("Arrow keys to scroll  |  +/- to zoom", 0, 58, w, "center")

    local mx, my = love.mouse.getPosition()
    mx = mx / (dpiScale or 1)
    my = my / (dpiScale or 1)

    local btnW, btnH = 120, 40
    local btnX = w / 2 - btnW / 2
    local btnY = h - 55

    local hover = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH
    love.graphics.setColor(hover and 0.3 or 0.2, hover and 0.3 or 0.2, hover and 0.4 or 0.3, 0.9)
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 5)
    love.graphics.setColor(0.5, 0.5, 0.7, hover and 0.8 or 0.5)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.get(14))
    love.graphics.printf("Back", btnX, btnY + 10, btnW, "center")

    grid_test.backBtn = { x = btnX, y = btnY, w = btnW, h = btnH }
end

function grid_test.mousepressed(x, y)
    if grid_test.backBtn and x >= grid_test.backBtn.x and x <= grid_test.backBtn.x + grid_test.backBtn.w and y >= grid_test.backBtn.y and y <= grid_test.backBtn.y + grid_test.backBtn.h then
        gamePhase = "menu"
        return true
    end
    return false
end

function grid_test.keypressed(key)
    if key == "escape" then
        gamePhase = "menu"
        return true
    end
    return false
end

return grid_test
