local hex_demo = {}

local grassImg

function hex_demo.init()
    if not grassImg then
        grassImg = love.graphics.newImage("assets/png/hex_grass.png")
        grassImg:setFilter("nearest", "nearest")
    end
end

function hex_demo.draw()
    hex_demo.init()
    local w = logicalW
    local h = logicalH
    local time = love.timer.getTime()
    local fonts = require("util.fonts")

    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.get(24))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("HEX GRASS TEXTURE", 0, 20, w, "center")

    love.graphics.setFont(fonts.get(12))
    love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
    love.graphics.printf("Press ESC or click Back to return", 0, 50, w, "center")

    local imgW, imgH = grassImg:getDimensions()
    local scale = math.min(w * 0.6 / imgW, h * 0.6 / imgH)
    local ix = w / 2 - imgW * scale / 2
    local iy = h / 2 - imgH * scale / 2 + 20

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(grassImg, ix, iy, 0, scale, scale)

    love.graphics.setFont(fonts.get(14))
    love.graphics.setColor(0.6, 0.8, 0.4, 0.8)
    love.graphics.printf("hex_grass.png  |  " .. imgW .. "x" .. imgH, 0, iy + imgH * scale + 15, w, "center")

    local btnW = 120
    local btnH = 40
    local btnX = w / 2 - btnW / 2
    local btnY = h - 60

    local mx, my = love.mouse.getPosition()
    mx = mx / (dpiScale or 1)
    my = my / (dpiScale or 1)

    local hover = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH

    love.graphics.setColor(hover and 0.3 or 0.2, hover and 0.3 or 0.2, hover and 0.4 or 0.3, 0.9)
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 5)
    love.graphics.setColor(0.5, 0.5, 0.7, hover and 0.8 or 0.5)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.get(14))
    love.graphics.printf("Back", btnX, btnY + 10, btnW, "center")

    hex_demo.backBtn = { x = btnX, y = btnY, w = btnW, h = btnH }
end

function hex_demo.mousepressed(x, y)
    if hex_demo.backBtn then
        local btn = hex_demo.backBtn
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            gamePhase = "menu"
            return true
        end
    end
    return false
end

function hex_demo.keypressed(key)
    if key == "escape" then
        gamePhase = "menu"
        return true
    end
    return false
end

return hex_demo
