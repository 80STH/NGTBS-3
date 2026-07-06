local pause_menu = {}
local fonts = require("util.fonts")

pause_menu.isOpen = false

local buttons = {
    { key = "continue",  label = "Continue",      r = 0.2, g = 0.6, b = 0.3 },
    { key = "restart",   label = "Restart Game",   r = 0.7, g = 0.5, b = 0.2 },
    { key = "mainmenu",  label = "Main Menu",      r = 0.3, g = 0.5, b = 0.8 },
    { key = "exit",      label = "Exit",           r = 0.7, g = 0.2, b = 0.2 },
}

local function getButtonRects(w, h)
    local btnW, btnH = 240, 46
    local gap = 12
    local totalH = #buttons * btnH + (#buttons - 1) * gap
    local startY = h / 2 - totalH / 2
    local startX = w / 2 - btnW / 2
    local rects = {}
    for i, btn in ipairs(buttons) do
        rects[i] = {
            key = btn.key,
            label = btn.label,
            r = btn.r, g = btn.g, b = btn.b,
            x = startX,
            y = startY + (i - 1) * (btnH + gap),
            w = btnW,
            h = btnH,
        }
    end
    return rects
end

function pause_menu.open()
    pause_menu.isOpen = true
end

function pause_menu.close()
    pause_menu.isOpen = false
end

function pause_menu.draw()
    if not pause_menu.isOpen then return end
    local w, h = logicalW, logicalH

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local titleFont = fonts.get(28)
    love.graphics.setFont(titleFont)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("PAUSED", 0, h / 2 - 120, w, "center")

    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    local rects = getButtonRects(w, h)
    local btnFont = fonts.get(16)
    love.graphics.setFont(btnFont)

    for _, btn in ipairs(rects) do
        local hover = mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
        love.graphics.setColor(hover and btn.r * 0.7 or btn.r * 0.35, hover and btn.g * 0.7 or btn.g * 0.35, hover and btn.b * 0.7 or btn.b * 0.35, 0.95)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(btn.r, btn.g, btn.b, hover and 0.9 or 0.5)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(btn.label, btn.x + 6, btn.y + btn.h / 2 - 8, btn.w - 12, "center")
    end
end

function pause_menu.mousepressed(x, y)
    if not pause_menu.isOpen then return false end
    local w, h = logicalW, logicalH
    local rects = getButtonRects(w, h)

    for _, btn in ipairs(rects) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.key == "continue" then
                pause_menu.close()
                gamePhase = "playing"
            elseif btn.key == "restart" then
                pause_menu.close()
                restartGame()
            elseif btn.key == "mainmenu" then
                pause_menu.close()
                gamePhase = "menu"
            elseif btn.key == "exit" then
                love.event.quit()
            end
            return true
        end
    end
    return false
end

function pause_menu.keypressed(key)
    if not pause_menu.isOpen then return false end
    if key == "escape" then
        pause_menu.close()
        gamePhase = "playing"
        return true
    end
    return false
end

return pause_menu
