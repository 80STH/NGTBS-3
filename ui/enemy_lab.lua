local enemy_lab = {}
local enemy_generator = require("system.enemy_generator")
local fonts = require("util.fonts")

local currentEnemy = nil
local budget = 10
local layout = {}

function enemy_lab.init()
    currentEnemy = enemy_generator.generate(budget)
end

local function computeLayout(w, h)
    local l = {}
    local pad = 20
    local contentW = math.min(w - 2 * pad, 500)
    local cx = math.floor((w - contentW) / 2)
    l.cx = cx
    l.contentW = contentW
    
    local y = 20
    local titleFont = fonts.get(math.max(16, math.floor(h * 0.03)))
    l.titleFont = titleFont
    l.titleY = y
    y = y + titleFont:getHeight() + 20
    
    local cardFont = fonts.get(14)
    local smallFont = fonts.get(11)
    l.cardFont = cardFont
    l.smallFont = smallFont
    
    l.cardY = y
    l.cardH = 180
    y = y + l.cardH + 20
    
    l.sliderLabelY = y
    y = y + 20
    l.sliderY = y
    l.sliderW = contentW
    l.sliderH = 20
    y = y + l.sliderH + 30
    
    local btnH = 50
    local btnGap = 10
    local btnW = math.floor((contentW - btnGap) / 3)
    l.btns = {
        {key = "generate", label = "Generate", x = cx, y = y, w = btnW, h = btnH, r = 0.3, g = 0.6, b = 0.8},
        {key = "spawn", label = "Spawn", x = cx + btnW + btnGap, y = y, w = btnW, h = btnH, r = 0.3, g = 0.8, b = 0.3},
        {key = "back", label = "Back", x = cx + 2*(btnW + btnGap), y = y, w = btnW, h = btnH, r = 0.7, g = 0.3, b = 0.3},
    }
    y = y + btnH + 10
    
    layout = l
end

function enemy_lab.draw()
    local w = logicalW
    local h = logicalH
    
    love.graphics.setColor(0.08, 0.08, 0.12, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    
    computeLayout(w, h)
    local l = layout
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale
    
    love.graphics.setFont(l.titleFont)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("ENEMY LAB", 0, l.titleY, w, "center")
    
    if currentEnemy then
        local cardX = l.cx
        local cardY = l.cardY
        local cardW = l.contentW
        local cardH = l.cardH
        
        love.graphics.setColor(0.12, 0.12, 0.18, 0.95)
        love.graphics.rectangle("fill", cardX, cardY, cardW, cardH, 8)
        love.graphics.setColor(0.4, 0.4, 0.6, 0.6)
        love.graphics.rectangle("line", cardX, cardY, cardW, cardH, 8)
        
        local spriteSize = 64
        local spriteX = cardX + 20
        local spriteY = cardY + 20
        love.graphics.setColor(currentEnemy.color[1], currentEnemy.color[2], currentEnemy.color[3], 1)
        love.graphics.circle("fill", spriteX + spriteSize/2, spriteY + spriteSize/2, spriteSize/2)
        if currentEnemy.mobility == "hovering" then
            love.graphics.setColor(1, 1, 1, 0.4)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", spriteX + spriteSize/2, spriteY + spriteSize/2, spriteSize/2)
            love.graphics.setLineWidth(1)
        end
        
        local textX = spriteX + spriteSize + 20
        local textY = cardY + 20
        
        love.graphics.setFont(l.cardFont)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(currentEnemy.name, textX, textY, cardW - spriteSize - 60, "left")
        textY = textY + 25
        
        love.graphics.setFont(l.smallFont)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.9)
        love.graphics.printf(string.format("Health: %d", currentEnemy.health), textX, textY, 200, "left")
        textY = textY + 18
        love.graphics.printf(string.format("Move Range: %d", currentEnemy.moveRange), textX, textY, 200, "left")
        textY = textY + 18
        love.graphics.printf(string.format("Mobility: %s", currentEnemy.mobility), textX, textY, 200, "left")
        textY = textY + 18
        love.graphics.printf(string.format("Attack: %s", currentEnemy.attack.name), textX, textY, 200, "left")
        textY = textY + 18
        love.graphics.printf(string.format("Aura: %s", currentEnemy.aura), textX, textY, 200, "left")
        textY = textY + 18
        
        local aiName = currentEnemy.aiModel
        for _, model in ipairs(enemy_generator.getAIModels()) do
            if model.id == currentEnemy.aiModel then
                aiName = model.name
                break
            end
        end
        love.graphics.printf(string.format("AI: %s", aiName), textX, textY, 200, "left")
        textY = textY + 25
        
        love.graphics.setColor(0.9, 0.9, 0.3, 1)
        love.graphics.printf(string.format("Cost: %d / %d", currentEnemy.cost, currentEnemy.budget), textX, textY, 200, "left")
    end
    
    love.graphics.setFont(l.smallFont)
    love.graphics.setColor(0.8, 0.8, 0.8, 0.9)
    love.graphics.printf(string.format("Budget: %d", budget), l.cx, l.sliderLabelY, l.contentW, "left")
    
    love.graphics.setColor(0.2, 0.2, 0.3, 0.9)
    love.graphics.rectangle("fill", l.cx, l.sliderY, l.sliderW, l.sliderH, 4)
    love.graphics.setColor(0.4, 0.6, 0.8, 0.8)
    local fillW = (budget - 5) / 15 * l.sliderW
    love.graphics.rectangle("fill", l.cx, l.sliderY, fillW, l.sliderH, 4)
    love.graphics.setColor(0.6, 0.8, 1, 0.9)
    love.graphics.rectangle("line", l.cx, l.sliderY, l.sliderW, l.sliderH, 4)
    
    for _, btn in ipairs(l.btns) do
        local hover = mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
        love.graphics.setColor(hover and btn.r*0.6 or btn.r*0.3, hover and btn.g*0.6 or btn.g*0.3, hover and btn.b*0.6 or btn.b*0.3, 0.9)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(btn.r, btn.g, btn.b, hover and 0.85 or 0.45)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(l.smallFont)
        love.graphics.printf(btn.label, btn.x + 6, btn.y + btn.h/2 - 7, btn.w - 12, "center")
    end
end

function enemy_lab.mousepressed(x, y)
    local w = logicalW
    local h = logicalH
    computeLayout(w, h)
    local l = layout
    
    if y >= l.sliderY and y <= l.sliderY + l.sliderH and x >= l.cx and x <= l.cx + l.sliderW then
        local ratio = (x - l.cx) / l.sliderW
        budget = math.floor(5 + ratio * 15 + 0.5)
        budget = math.max(5, math.min(20, budget))
        return true
    end
    
    for _, btn in ipairs(l.btns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.key == "generate" then
                currentEnemy = enemy_generator.generate(budget)
                return true
            elseif btn.key == "spawn" then
                if currentEnemy then
                    _G.pendingGeneratedEnemy = currentEnemy
                    if not selectedCommander then
                        local commanders = require("system.commanders")
                        local names = {}
                        for name, _ in pairs(commanders.list) do table.insert(names, name) end
                        selectedCommander = names[1]
                    end
                    if not selectedSquad then selectedSquad = 1 end
                    global_abilities.initWithCommander(selectedCommander)
                    restartGame("maps/map1.lua")
                    
                    local params = _G.pendingGeneratedEnemy
                    _G.pendingGeneratedEnemy = nil
                    
                    local spots = {}
                    for dq = -3, 3 do
                        for dr = -3, 3 do
                            local testQ, testR = hex.centerQ + dq, hex.centerR + dr
                            if hex:isValidHex(testQ, testR) and hex:isActiveHex(testQ, testR) then
                                local occupied = false
                                for _, e in ipairs(entities) do
                                    if e.q == testQ and e.r == testR and e.health > 0 then
                                        occupied = true
                                        break
                                    end
                                end
                                if not occupied then
                                    table.insert(spots, {q = testQ, r = testR})
                                end
                            end
                        end
                    end
                    
                    if #spots > 0 then
                        local spot = spots[love.math.random(1, #spots)]
                        local enemy = environment.createGeneratedEnemy(params, spot.q, spot.r)
                        table.insert(entities, enemy)
                        rebuildEntityIndex()
                    end
                end
                return true
            elseif btn.key == "back" then
                gamePhase = "menu"
                return true
            end
        end
    end
    
    return false
end

return enemy_lab
