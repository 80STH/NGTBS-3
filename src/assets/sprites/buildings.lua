-- src/assets/sprites/buildings.lua
-- Sprites for buildings, obstacles and train cars.
-- Loads assets/png/<id>.png; falls back to a procedural canvas.

local common = require("src.assets.sprites.common")
local buildings = {}

local SIZE = 96

local function rect(x, y, w, h) love.graphics.rectangle("fill", x, y, w, h) end

local defs = {
    SuperMountain = function(S)
        love.graphics.setColor(0.45, 0.40, 0.35, 1)
        love.graphics.polygon("fill", 6, S - 6, S / 2, 8, S - 6, S - 6)
        love.graphics.setColor(0.58, 0.52, 0.46, 1)
        love.graphics.polygon("fill", 6, S - 6, S / 2, 8, S / 2, S - 6)
        love.graphics.setColor(0.95, 0.95, 1, 1)
        love.graphics.polygon("fill", S / 2 - 6, 8, S / 2 + 6, 8, S / 2, 22)
    end,
    WeakMountain = function(S)
        love.graphics.setColor(0.5, 0.45, 0.35, 1)
        love.graphics.polygon("fill", 8, S - 8, S / 2, 14, S - 8, S - 8)
        love.graphics.setColor(0.6, 0.55, 0.45, 1)
        love.graphics.polygon("fill", 8, S - 8, S / 2, 14, S / 2, S - 8)
        love.graphics.setColor(0.35, 0.3, 0.25, 1)
        rect(6, S - 10, S - 12, 4)
    end,
    SmallBuilding = function(S)
        love.graphics.setColor(0.7, 0.55, 0.35, 1); rect(12, 30, S - 24, S - 36)
        love.graphics.setColor(0.6, 0.25, 0.15, 1)
        love.graphics.polygon("fill", 8, 30, S / 2, 16, S - 8, 30)
        love.graphics.setColor(0.85, 0.9, 1, 1); rect(20, 40, 10, 12)
    end,
    BigBuilding = function(S)
        love.graphics.setColor(0.5, 0.55, 0.6, 1); rect(8, 24, S - 16, S - 30)
        love.graphics.setColor(0.4, 0.45, 0.5, 1); rect(8, 20, S - 16, 8)
        love.graphics.setColor(0.8, 0.85, 1, 1)
        for row = 0, 1 do for col = 0, 2 do rect(18 + col * 20, 36 + row * 22, 10, 12) end end
    end,
    Tower = function(S)
        love.graphics.setColor(0.55, 0.5, 0.45, 1); rect(S / 4, 20, S / 2, S - 26)
        love.graphics.setColor(0.45, 0.4, 0.35, 1); rect(S / 4 - 4, 20, S / 2 + 8, 8)
        love.graphics.setColor(0.6, 0.55, 0.5, 1); rect(S / 4 - 6, 16, S / 2 + 12, 6)
        love.graphics.setColor(1, 0.7, 0.3, 1); love.graphics.circle("fill", S / 2, S / 2, 6)
    end,
    Locomotive = function(S)
        love.graphics.setColor(0.3, 0.15, 0.1, 1); rect(10, 30, S - 20, S - 40)
        love.graphics.setColor(0.5, 0.2, 0.1, 1); rect(10, 26, S - 20, 8)
        love.graphics.setColor(1, 0.8, 0.2, 1); rect(S / 2 - 10, 38, 20, 12)
        love.graphics.setColor(0.2, 0.2, 0.2, 1); love.graphics.circle("fill", 20, S - 12, 7)
        love.graphics.circle("fill", S - 20, S - 12, 7)
    end,
    TrainCar = function(S)
        love.graphics.setColor(0.6, 0.2, 0.15, 1); rect(8, 30, S - 16, S - 40)
        love.graphics.setColor(0.4, 0.12, 0.08, 1); rect(6, 28, S - 12, 6)
        love.graphics.setColor(0.8, 0.6, 0.4, 1); rect(18, 40, 12, 12); rect(S - 30, 40, 12, 12)
        love.graphics.setColor(0.3, 0.1, 0.05, 1); love.graphics.circle("fill", 18, S - 12, 6)
        love.graphics.circle("fill", S - 18, S - 12, 6)
    end,
}

local fallbackCache = {}

local function fallback(id)
    if fallbackCache[id] then return fallbackCache[id] end
    local draw = defs[id]
    local c = common.newCanvas(SIZE, SIZE)
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    if draw then
        draw(SIZE)
    else
        love.graphics.setColor(0.5, 0.5, 0.55, 1)
        love.graphics.rectangle("fill", 16, 16, SIZE - 32, SIZE - 32)
    end
    love.graphics.setCanvas()
    fallbackCache[id] = c
    return c
end

function buildings.get(id) return common.loadPNG(id) or fallback(id) end

return buildings
