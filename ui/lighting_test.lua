local lighting_test = {}
local fonts

local testScenarios = {
    { name = "Grid + Sun Light",   desc = "Day cycle moves sun across the grid" },
    { name = "Mixed Terrain",      desc = "Lighting on different terrain" },
}
local scenarioIdx = 1

local hexTest
local hexRadius = 56
local gridW, gridH = 5, 5
local terrainMap = {}

local dayCycleActive = false
local dayCycleTime = 0
local dayCycleSpeed = 0.15

local function rebuildGrid()
    local HexGrid = require("grid.hexgrid")
    hexTest = HexGrid.new(hexRadius, gridW, gridH)
    hexTest.offsetX = 0
    hexTest.offsetY = 0
    hexTest:centerOnScreen(logicalW or 800, logicalH or 1280)

    terrainMap = {}

    if scenarioIdx == 1 then
        for q = 0, gridW - 1 do
            terrainMap[q] = terrainMap[q] or {}
            for r = 0, gridH - 1 do
                terrainMap[q][r] = "grass"
            end
        end
    elseif scenarioIdx == 2 then
        local terrainTypes = {"grass", "stone", "lava", "sand", "dirt", "snow", "swamp", "water", "railway"}
        for q = 0, gridW - 1 do
            terrainMap[q] = terrainMap[q] or {}
            for r = 0, gridH - 1 do
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
    local dt = love.timer.getDelta()

    if dayCycleActive then
        dayCycleTime = dayCycleTime + dt * dayCycleSpeed
    end

    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if dayCycleActive then
        local phase = dayCycleTime % 1
        local t = phase
        local sunX = w * 0.1 + w * 0.8 * t
        local sunY = h * 0.6 - math.sin(t * math.pi) * h * 0.4

        lighting.sun.pos = {sunX, sunY}
        lighting.sun.radius = 400
        lighting.sun.color = {1.0, 0.95, 0.8}
        lighting.sun.softness = 0.5

        local edgeFade = math.min(t / 0.1, (1 - t) / 0.1, 1)
        lighting.ambientLight = 0.05 + 0.2 * edgeFade
    end

    local useLighting = lighting and lighting.enabled
    if useLighting then
        lighting:beginRender()
    end

    if hexTest then
        for q = 0, gridW - 1 do
            for r = 0, gridH - 1 do
                local x, y = hexTest:hexToPixel(q, r)
                local terrain = (terrainMap[q] and terrainMap[q][r]) or "grass"
                hexTest:drawTerrainHex(q, r, terrain, x, y)
            end
        end
    end

    if useLighting then
        local stateMock = {
            hex = hexTest,
            entities = {},
        }
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
    love.graphics.printf("ESC: back  |  TAB: scenario  |  1-4: ambient  |  L: toggle lighting  |  D: day cycle", 0, 42, w, "center")

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
    local totalW = btnW * 3 + gap * 2
    local startX = w / 2 - totalW / 2
    local btnY = h - 50

    local buttons = {
        { label = "Back",   x = startX,             y = btnY, w = btnW, h = btnH, action = "back" },
        { label = "Next >", x = startX + btnW + gap, y = btnY, w = btnW, h = btnH, action = "next" },
        { label = dayCycleActive and "Day: ON" or "Day: OFF", x = startX + (btnW + gap) * 2, y = btnY, w = btnW, h = btnH, action = "daycycle" },
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
            elseif btn.action == "daycycle" then
                dayCycleActive = not dayCycleActive
                if not dayCycleActive then
                    lighting.sun.radius = 0
                    lighting.ambientLight = 0.25
                end
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
    elseif key == "d" then
        dayCycleActive = not dayCycleActive
        if not dayCycleActive then
            lighting.sun.radius = 0
            lighting.ambientLight = 0.25
        end
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
