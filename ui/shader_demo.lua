-- shader_demo.lua
-- Демонстрация всех шейдеров в действии
local shader_demo = {}

local visual_shaders = require("system.visual_shaders")
local status_shaders = require("system.status_shaders")
local fire_shader = require("ui.fire_shader")

local shadersInitialized = false

-- Список всех шейдеров для демонстрации
local shaderList = {
    { name = "Fire", draw = function(x, y, r, t) fire_shader.drawFireOnHex(x, y, r, t) end },
    { name = "Acid", draw = function(x, y, r, t) status_shaders.drawAcid(x, y, r, t, 1.0) end },
    { name = "Decay", draw = function(x, y, r, t) status_shaders.drawDecay(x, y, r, t, 1.0) end },
    { name = "Empowered", draw = function(x, y, r, t) status_shaders.drawEmpowered(x, y, r, t, 1.0) end },
    { name = "Rooted", draw = function(x, y, r, t) status_shaders.drawRooted(x, y, r, t, 1.0) end },
    { name = "Shockwave", draw = function(x, y, r, t) 
        local progress = (t % 1.5) / 1.5
        visual_shaders.drawShockwave(x, y, r, progress, r * 2) 
    end },
    { name = "Sparks", draw = function(x, y, r, t) 
        local progress = (t % 1.0) / 1.0
        visual_shaders.drawSparks(x, y, r, progress, 8) 
    end },
    { name = "Blood", draw = function(x, y, r, t) 
        local progress = (t % 1.2) / 1.2
        visual_shaders.drawBlood(x, y, r, progress) 
    end },
    { name = "Magic Explosion", draw = function(x, y, r, t) 
        local progress = (t % 1.5) / 1.5
        visual_shaders.drawMagicExplosion(x, y, r, progress, 0.6, 0.2, 1.0) 
    end },
    { name = "Lightning", draw = function(x, y, r, t) 
        local progress = (t % 0.8) / 0.8
        visual_shaders.drawLightning(x, y - r, progress, 1.0) 
    end },
    { name = "Ghost Hit", draw = function(x, y, r, t) 
        local progress = (t % 1.2) / 1.2
        visual_shaders.drawGhostHit(x, y, r, progress) 
    end },
    { name = "Drown", draw = function(x, y, r, t) 
        local progress = (t % 2.0) / 2.0
        visual_shaders.drawDrown(x, y, r, progress) 
    end },
    { name = "Unit Collision", draw = function(x, y, r, t) 
        local progress = (t % 0.8) / 0.8
        visual_shaders.drawUnitCollision(x, y, r, progress, 1.0) 
    end },
    { name = "Push Effect", draw = function(x, y, r, t) 
        local progress = (t % 1.2) / 1.2
        local fromX = x - r * 0.8
        local fromY = y
        local toX = x + r * 0.8
        local toY = y
        visual_shaders.drawPushEffect(fromX, fromY, toX, toY, r * 0.6, progress, 1.0) 
    end },
}

function shader_demo.init()
    if not shadersInitialized then
        visual_shaders.init()
        status_shaders.init()
        shadersInitialized = true
    end
end

function shader_demo.draw()
    shader_demo.init()
    
    local w = logicalW
    local h = logicalH
    local time = love.timer.getTime()
    
    -- Тёмный фон
    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    -- Заголовок
    local fonts = require("util.fonts")
    love.graphics.setFont(fonts.get(24))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("SHADER DEMO", 0, 20, w, "center")
    
    love.graphics.setFont(fonts.get(12))
    love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
    love.graphics.printf("Press ESC or click Back to return", 0, 50, w, "center")
    
    -- Сетка шейдеров
    local cols = 4
    local rows = math.ceil(#shaderList / cols)
    local padding = 20
    local topOffset = 80
    local bottomOffset = 60
    
    local cellW = (w - padding * (cols + 1)) / cols
    local cellH = (h - topOffset - bottomOffset - padding * (rows + 1)) / rows
    local radius = math.min(cellW, cellH) * 0.3
    
    for i, shader in ipairs(shaderList) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        
        local cx = padding + col * (cellW + padding) + cellW / 2
        local cy = topOffset + padding + row * (cellH + padding) + cellH / 2
        
        -- Фон ячейки
        love.graphics.setColor(0.1, 0.1, 0.15, 0.8)
        love.graphics.rectangle("fill", 
            cx - cellW/2, cy - cellH/2, 
            cellW, cellH, 8)
        
        -- Рамка
        love.graphics.setColor(0.3, 0.3, 0.4, 0.5)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", 
            cx - cellW/2, cy - cellH/2, 
            cellW, cellH, 8)
        
        -- Рисуем шейдер
        shader.draw(cx, cy, radius, time)
        
        -- Название
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.setFont(fonts.get(11))
        love.graphics.printf(shader.name, 
            cx - cellW/2, cy + cellH/2 - 20, 
            cellW, "center")
    end
    
    -- Кнопка "Back"
    local btnW = 120
    local btnH = 40
    local btnX = w / 2 - btnW / 2
    local btnY = h - bottomOffset + 10
    
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
    
    -- Сохраняем координаты кнопки для клика
    shader_demo.backBtn = { x = btnX, y = btnY, w = btnW, h = btnH }
end

function shader_demo.mousepressed(x, y)
    if shader_demo.backBtn then
        local btn = shader_demo.backBtn
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            gamePhase = "menu"
            return true
        end
    end
    return false
end

function shader_demo.keypressed(key)
    if key == "escape" then
        gamePhase = "menu"
        return true
    end
    return false
end

return shader_demo
