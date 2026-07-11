local creature_lab = {}
local enemy_generator = require("system.enemy_generator")
local boss_generator = require("system.boss_generator")
local fonts = require("util.fonts")

local currentCreature = nil
local activeTab = "enemy"
local enemyBudget = 10
local bossBudget = 15
local layout = {}

function creature_lab.init()
    activeTab = "enemy"
    currentCreature = enemy_generator.generate(enemyBudget)
end

local function currentBudget()
    return activeTab == "enemy" and enemyBudget or bossBudget
end

local function setBudget(val)
    if activeTab == "enemy" then enemyBudget = val else bossBudget = val end
end

local function generate()
    if activeTab == "enemy" then
        currentCreature = enemy_generator.generate(enemyBudget)
    else
        currentCreature = boss_generator.generate(bossBudget)
    end
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
    y = y + titleFont:getHeight() + 14
    
    local tabW = math.floor(contentW / 2)
    local tabH = 30
    l.tabs = {
        {key = "enemy", label = "Enemy", x = cx, y = y, w = tabW, h = tabH},
        {key = "boss", label = "Boss", x = cx + tabW, y = y, w = tabW, h = tabH},
    }
    y = y + tabH + 14
    
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

local function drawCreatureCard(l, creature, gen)
    love.graphics.setColor(0.12, 0.12, 0.18, 0.95)
    love.graphics.rectangle("fill", l.cx, l.cardY, l.contentW, l.cardH, 8)
    love.graphics.setColor(0.4, 0.4, 0.6, 0.6)
    love.graphics.rectangle("line", l.cx, l.cardY, l.contentW, l.cardH, 8)
    
    local spriteSize = 64
    local spriteX = l.cx + 20
    local spriteY = l.cardY + 20
    love.graphics.setColor(creature.color[1], creature.color[2], creature.color[3], 1)
    love.graphics.circle("fill", spriteX + spriteSize/2, spriteY + spriteSize/2, spriteSize/2)
    if creature.mobility == "hovering" then
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", spriteX + spriteSize/2, spriteY + spriteSize/2, spriteSize/2)
        love.graphics.setLineWidth(1)
    elseif creature.mobility == "teleport" then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.setLineWidth(2)
        for i = 1, 3 do
            love.graphics.circle("line", spriteX + spriteSize/2, spriteY + spriteSize/2, spriteSize/2 - i*8)
        end
        love.graphics.setLineWidth(1)
    end
    
    local textX = spriteX + spriteSize + 20
    local textY = l.cardY + 20
    
    love.graphics.setFont(l.cardFont)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(creature.name, textX, textY, l.contentW - spriteSize - 60, "left")
    textY = textY + 25
    
    love.graphics.setFont(l.smallFont)
    love.graphics.setColor(0.7, 0.7, 0.7, 0.9)
    love.graphics.printf(string.format("Health: %d", creature.health), textX, textY, 200, "left")
    textY = textY + 18
    love.graphics.printf(string.format("Move Range: %s", tostring(creature.moveRange)), textX, textY, 200, "left")
    textY = textY + 18
    love.graphics.printf(string.format("Mobility: %s", creature.mobility), textX, textY, 200, "left")
    textY = textY + 18
    love.graphics.printf(string.format("Attack: %s", creature.attack.name), textX, textY, 200, "left")
    textY = textY + 18
    love.graphics.printf(string.format("Aura: %s", creature.aura), textX, textY, 200, "left")
    textY = textY + 18
    
    local aiName = creature.aiModel
    for _, model in ipairs(gen.getAIModels()) do
        if model.id == creature.aiModel then
            aiName = model.name
            break
        end
    end
    love.graphics.printf(string.format("AI: %s", aiName), textX, textY, 200, "left")
    textY = textY + 25
    
    love.graphics.setColor(0.9, 0.9, 0.3, 1)
    love.graphics.printf(string.format("Cost: %d / %d", creature.cost, creature.budget), textX, textY, 200, "left")
end

function creature_lab.draw()
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
    love.graphics.printf("CREATURE LAB", 0, l.titleY, w, "center")
    
    for _, tab in ipairs(l.tabs) do
        local hover = mx >= tab.x and mx <= tab.x + tab.w and my >= tab.y and my <= tab.y + tab.h
        local sel = activeTab == tab.key
        love.graphics.setColor(hover and 0.2 or 0.12, hover and 0.2 or 0.16, hover and 0.3 or 0.22, 0.95)
        love.graphics.rectangle("fill", tab.x, tab.y, tab.w, tab.h, 4)
        if sel then
            love.graphics.setColor(0.5, 0.4, 0.8, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", tab.x, tab.y, tab.w, tab.h, 4)
            love.graphics.setLineWidth(1)
        else
            love.graphics.setColor(0.3, 0.3, 0.4, 0.4)
            love.graphics.rectangle("line", tab.x, tab.y, tab.w, tab.h, 4)
        end
        love.graphics.setColor(1, 1, 1, sel and 1 or 0.6)
        love.graphics.setFont(l.cardFont)
        love.graphics.printf(tab.label, tab.x, tab.y + 6, tab.w, "center")
    end
    
    if currentCreature then
        local gen = activeTab == "enemy" and enemy_generator or boss_generator
        drawCreatureCard(l, currentCreature, gen)
    end
    
    local b = currentBudget()
    local budgetMin = activeTab == "enemy" and 5 or 10
    local budgetMax = activeTab == "enemy" and 20 or 30
    
    love.graphics.setFont(l.smallFont)
    love.graphics.setColor(0.8, 0.8, 0.8, 0.9)
    love.graphics.printf(string.format("Budget: %d", b), l.cx, l.sliderLabelY, l.contentW, "left")
    
    love.graphics.setColor(0.2, 0.2, 0.3, 0.9)
    love.graphics.rectangle("fill", l.cx, l.sliderY, l.sliderW, l.sliderH, 4)
    love.graphics.setColor(0.4, 0.6, 0.8, 0.8)
    local fillW = (b - budgetMin) / (budgetMax - budgetMin) * l.sliderW
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

local function spawnCreature()
    if not currentCreature then return end
    if activeTab == "enemy" then
        _G.pendingGeneratedEnemy = currentCreature
    else
        _G.pendingGeneratedBoss = currentCreature
    end
    
    if not selectedCommander then
        local commanders = require("system.commanders")
        local names = {}
        for name, _ in pairs(commanders.list) do table.insert(names, name) end
        selectedCommander = names[1]
    end
    if not selectedSquad then selectedSquad = 1 end
    global_abilities.initWithCommander(selectedCommander)
    restartGame("maps/map1.lua")
    
    local params = activeTab == "enemy" and _G.pendingGeneratedEnemy or _G.pendingGeneratedBoss
    _G.pendingGeneratedEnemy = nil
    _G.pendingGeneratedBoss = nil
    
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
        local creature = environment.createGeneratedEnemy(params, spot.q, spot.r)
        if activeTab == "boss" then
            creature.isLeader = true
        end
        table.insert(entities, creature)
        rebuildEntityIndex()
    end
end

function creature_lab.mousepressed(x, y)
    local w = logicalW
    local h = logicalH
    computeLayout(w, h)
    local l = layout
    
    for _, tab in ipairs(l.tabs) do
        if x >= tab.x and x <= tab.x + tab.w and y >= tab.y and y <= tab.y + tab.h then
            activeTab = tab.key
            generate()
            return true
        end
    end
    
    local budgetMin = activeTab == "enemy" and 5 or 10
    local budgetMax = activeTab == "enemy" and 20 or 30
    
    if y >= l.sliderY and y <= l.sliderY + l.sliderH and x >= l.cx and x <= l.cx + l.sliderW then
        local ratio = (x - l.cx) / l.sliderW
        local val = math.floor(budgetMin + ratio * (budgetMax - budgetMin) + 0.5)
        val = math.max(budgetMin, math.min(budgetMax, val))
        setBudget(val)
        return true
    end
    
    for _, btn in ipairs(l.btns) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.key == "generate" then
                generate()
                return true
            elseif btn.key == "spawn" then
                spawnCreature()
                return true
            elseif btn.key == "back" then
                gamePhase = "menu"
                return true
            end
        end
    end
    
    return false
end

return creature_lab
