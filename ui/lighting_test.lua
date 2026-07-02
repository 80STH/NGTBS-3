local lighting_test = {}
local fonts

local testScenarios = {
    { name = "Grid + Mouse Light", desc = "Move mouse to light hexes" },
    { name = "Fire Entities",      desc = "Burning entities emit light" },
    { name = "Mixed Terrain",      desc = "Lighting on different terrain" },
}
local scenarioIdx = 1

local hexTest
local hexRadius = 56
local gridW, gridH = 5, 5
local fireEntities = {}
local terrainMap = {}

local function rebuildGrid()
    local HexGrid = require("grid.hexgrid")
    hexTest = HexGrid.new(hexRadius, gridW, gridH)
    hexTest.offsetX = 0
    hexTest.offsetY = 0
    hexTest:centerOnScreen(logicalW or 800, logicalH or 1280)

    fireEntities = {}
    terrainMap = {}

    if scenarioIdx == 1 then
        for q = 0, gridW - 1 do
            for r = 0, gridH - 1 do
                terrainMap[q] = terrainMap[q] or {}
                terrainMap[q][r] = "grass"
            end
        end
    elseif scenarioIdx == 2 then
        local terrainTypes = {"grass", "stone", "dirt", "sand", "water", "lava", "snow", "swamp"}
        for q = 0, gridW - 1 do
            for r = 0, gridH - 1 do
                terrainMap[q] = terrainMap[q] or {}
                terrainMap[q][r] = terrainTypes[(q + r * 3) % #terrainTypes + 1]
            end
        end
        for i = 1, 3 do
            fireEntities[i] = {
                q = math.floor(gridW / 2) + (i - 2),
                r = math.floor(gridH / 2) + (i - 2),
                health = 1,
            }
        end
    elseif scenarioIdx == 3 then
        local terrainTypes = {"grass", "stone", "lava", "sand", "dirt", "snow", "swamp", "water", "railway"}
        for q = 0, gridW - 1 do
            for r = 0, gridH - 1 do
                terrainMap[q] = terrainMap[q] or {}
                terrainMap[q][r] = terrainTypes[(q * 7 + r * 13) % #terrainTypes + 1]
            end
        end
    end
end

function lighting_test.init()
    fonts = require("util.fonts")
    rebuildGrid()
end

function lighting_test.draw()
    local w, h = logicalW, logicalH
    local time = love.timer.getTime()

    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local useLighting = lighting and lighting.enabled
    if useLighting then
        lighting:beginRender()
    end

    love.graphics.push()
    love.graphics.scale(dpiScale)

    if hexTest then
        for q = 0, gridW - 1 do
            for r = 0, gridH - 1 do
                local x, y = hexTest:hexToPixel(q, r)
                local terrain = (terrainMap[q] and terrainMap[q][r]) or "grass"
                hexTest:drawTerrainHex(q, r, terrain, x, y)
            end
        end

        if scenarioIdx == 2 then
            for _, e in ipairs(fireEntities) do
                local x, y = hexTest:hexToPixel(e.q, e.r)
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.circle("fill", x, y, hexRadius * 0.5)
                love.graphics.setColor(1, 0.4, 0.1, 0.6)
                love.graphics.circle("fill", x, y, hexRadius * 0.3)
                love.graphics.setColor(1, 0.8, 0.2, 0.8)
                local flicker = 0.8 + 0.2 * math.sin(time * 8 + e.q * 3 + e.r * 7)
                love.graphics.circle("fill", x + math.sin(time * 5 + e.q) * 5, y + math.cos(time * 6 + e.r) * 5, hexRadius * 0.15 * flicker)
            end
        end
    end

    love.graphics.pop()

    if useLighting then
        local stateMock = {
            hex = hexTest,
            entities = {},
        }
        if scenarioIdx == 2 then
            stateMock.entities = fireEntities
        end
        local status_mod = require("system.status")
        local savedHexStatuses = status_mod.hexStatuses
        status_mod.hexStatuses = {}
        lighting:endRender(stateMock)
        status_mod.hexStatuses = savedHexStatuses
    end

    local mx, my = love.mouse.getPosition()
    mx = mx / (dpiScale or 1)
    my = my / (dpiScale or 1)

    love.graphics.setFont(fonts.get(24))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("LIGHTING TEST", 0, 15, w, "center")

    love.graphics.setFont(fonts.get(11))
    love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
    love.graphics.printf("ESC: back  |  TAB: scenario  |  1-4: ambient 0-50%  |  L: toggle lighting", 0, 42, w, "center")

    love.graphics.setFont(fonts.get(13))
    love.graphics.setColor(0.5, 0.8, 0.5, 0.9)
    love.graphics.printf("Scenario: " .. testScenarios[scenarioIdx].name, w / 2 - 150, 62, 300, "center")
    love.graphics.setFont(fonts.get(11))
    love.graphics.setColor(0.5, 0.5, 0.5, 0.7)
    love.graphics.printf(testScenarios[scenarioIdx].desc, w / 2 - 150, 78, 300, "center")

    local ambientPct = math.floor(lighting.ambientLight * 100)
    love.graphics.setFont(fonts.get(12))
    love.graphics.setColor(0.6, 0.6, 0.8, 0.8)
    love.graphics.printf("Ambient: " .. ambientPct .. "%  |  Lighting: " .. (lighting.enabled and "ON" or "OFF"), 10, h - 85, 300, "left")

    local btnW, btnH, gap = 120, 40, 15
    local totalW = btnW * 2 + gap
    local startX = w / 2 - totalW / 2
    local btnY = h - 50

    local buttons = {
        { label = "Back",   x = startX,             y = btnY, w = btnW, h = btnH, action = "back" },
        { label = "Next >", x = startX + btnW + gap, y = btnY, w = btnW, h = btnH, action = "next" },
    }

    for _, btn in ipairs(buttons) do
        local hover = mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
        love.graphics.setColor(hover and 0.3 or 0.2, hover and 0.3 or 0.2, hover and 0.4 or 0.3, 0.9)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(0.5, 0.5, 0.7, hover and 0.8 or 0.5)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(fonts.get(14))
        love.graphics.printf(btn.label, btn.x, btn.y + 10, btn.w, "center")
    end

    lighting_test.buttons = buttons
    lighting_test.btnY = btnY
end

function lighting_test.mousepressed(x, y)
    for _, btn in ipairs(lighting_test.buttons or {}) do
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            if btn.action == "back" then
                gamePhase = "menu"
            elseif btn.action == "next" then
                scenarioIdx = scenarioIdx % #testScenarios + 1
                rebuildGrid()
            end
            return true
        end
    end
    return false
end

function lighting_test.keypressed(key)
    if key == "escape" then
        gamePhase = "menu"
        return true
    elseif key == "tab" then
        scenarioIdx = scenarioIdx % #testScenarios + 1
        rebuildGrid()
        return true
    elseif key == "l" then
        if lighting then lighting.enabled = not lighting.enabled end
        return true
    elseif key == "1" then
        lighting.ambientLight = 0
        return true
    elseif key == "2" then
        lighting.ambientLight = 0.12
        return true
    elseif key == "3" then
        lighting.ambientLight = 0.25
        return true
    elseif key == "4" then
        lighting.ambientLight = 0.5
        return true
    end
    return false
end

return lighting_test
