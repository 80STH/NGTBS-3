-- src/assets/sprites/terrain.lua
-- Terrain tiles (hex-shaped). Loads assets/png/terrain_<id>.png if present;
-- otherwise builds a hex-shaped procedural canvas. Renderer draws it scaled to
-- the grid's hex size.

local common = require("src.assets.sprites.common")
local hexmath = require("src.core.hex")
local terrainDefs = require("src.content.terrain")
local terrain = {}

local S0 = 64                  -- reference hex size (centre -> vertex)
local CW, CH = 128, 148        -- canvas size
local CX, CY = 64, 70          -- hex centre in canvas

local function hexPath(size)
    local pts = hexmath.corners(CX, CY, size)
    local flat = {}
    for _, p in ipairs(pts) do table.insert(flat, p.x); table.insert(flat, p.y) end
    return flat
end

local patterns = {
    grass = function()
        love.graphics.setColor(0.22, 0.45, 0.18, 1)
        for _ = 1, 26 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.8
            local x, y = CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6
            love.graphics.line(x, y, x, y - 4)
        end
    end,
    dirt = function()
        love.graphics.setColor(0.35, 0.26, 0.16, 1)
        for _ = 1, 20 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.75
            love.graphics.circle("fill", CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6, 2)
        end
    end,
    sand = function()
        love.graphics.setColor(0.85, 0.78, 0.55, 1)
        for _ = 1, 24 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.75
            love.graphics.circle("fill", CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6, 1.5)
        end
    end,
    stone = function()
        love.graphics.setColor(0.35, 0.35, 0.40, 1)
        love.graphics.line(CX - 20, CY - 10, CX + 10, CY + 18)
        love.graphics.line(CX + 5, CY - 22, CX - 8, CY + 12)
    end,
    snow = function()
        love.graphics.setColor(1, 1, 1, 0.9)
        for _ = 1, 14 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.7
            love.graphics.circle("fill", CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6, 1.5)
        end
    end,
    swamp = function()
        love.graphics.setColor(0.2, 0.35, 0.25, 1)
        for _ = 1, 10 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.7
            love.graphics.circle("line", CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6, 3)
        end
    end,
    water = function()
        love.graphics.setColor(0.55, 0.75, 1, 0.5)
        for i = -2, 2 do
            love.graphics.line(CX - 28, CY + i * 14, CX + 28, CY + i * 14 + 4)
        end
    end,
    underwater_mines = function()
        love.graphics.setColor(0.1, 0.2, 0.4, 1)
        for _ = 1, 5 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.6
            local x, y = CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6
            love.graphics.circle("fill", x, y, 4)
            love.graphics.setColor(1, 0.3, 0.2, 1); love.graphics.circle("fill", x, y, 1.5)
            love.graphics.setColor(0.1, 0.2, 0.4, 1)
        end
    end,
    lava = function()
        love.graphics.setColor(1, 0.6, 0.1, 0.8)
        for _ = 1, 6 do
            local a = love.math.random() * math.pi * 2
            local d = love.math.random() * S0 * 0.6
            love.graphics.circle("fill", CX + math.cos(a) * d, CY + math.sin(a) * d * 0.6, love.math.random(3, 6))
        end
    end,
    railway = function()
        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.line(CX - 30, CY - 18, CX + 30, CY - 18)
        love.graphics.line(CX - 30, CY + 18, CX + 30, CY + 18)
        love.graphics.setColor(0.5, 0.4, 0.3, 1)
        for i = -2, 2 do love.graphics.rectangle("fill", CX + i * 14 - 2, CY - 22, 4, 44) end
    end,
    emptiness = function() end,
}

local cache = {}

local function fallback(id)
    if cache[id] then return cache[id] end
    local t = terrainDefs.get(id)
    local c = common.newCanvas(CW, CH)
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(t.color[1], t.color[2], t.color[3], 1)
    love.graphics.polygon("fill", hexPath(S0))
    -- subtle vertical gradient for depth
    love.graphics.setColor(0, 0, 0, 0.12)
    love.graphics.polygon("fill", hexPath(S0))
    love.graphics.setColor(t.color[1] * 1.15, t.color[2] * 1.15, t.color[3] * 1.15, 1)
    love.graphics.polygon("fill", hexPath(S0 * 0.6))
    local pat = patterns[id]
    if pat then pat() end
    love.graphics.setCanvas()
    cache[id] = c
    return c
end

function terrain.get(id)
    return common.loadPNG("terrain_" .. id) or fallback(id)
end

-- reference size, so renderer can compute the draw scale
terrain.refSize = S0
terrain.canvasW = CW
terrain.canvasH = CH
terrain.CX = CX
terrain.CY = CY

return terrain
