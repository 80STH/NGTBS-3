-- src/assets/sprites/effects.lua
-- Small icon canvases for status effects & floating UI marks.
-- Procedural (no PNG needed); override by dropping status_<id>.png in assets/png/.

local common = require("src.assets.sprites.common")
local effects = {}
local S = 32
local cache = {}

local function make(name, draw)
    if cache[name] then return cache[name] end
    local c = common.newCanvas(S, S)
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    draw()
    love.graphics.setCanvas()
    cache[name] = c
    return c
end

local drawers = {
    fire = function()
        love.graphics.setColor(1, 0.4, 0.1, 1)
        love.graphics.polygon("fill", 16, 4, 22, 24, 10, 24)
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.polygon("fill", 16, 10, 20, 24, 12, 24)
    end,
    acid = function()
        love.graphics.setColor(0.5, 0.9, 0.2, 1)
        love.graphics.circle("fill", 16, 18, 10)
        love.graphics.setColor(0.8, 1, 0.4, 1)
        love.graphics.circle("fill", 13, 15, 3)
    end,
    decay = function()
        love.graphics.setColor(0.5, 0.3, 0.5, 1)
        for i = 0, 4 do love.graphics.circle("fill", 8 + i * 4, 16 + (i % 2) * 4, 2) end
    end,
    root = function()
        love.graphics.setColor(0.45, 0.3, 0.15, 1)
        love.graphics.polygon("fill", 16, 4, 14, 28, 18, 28)
        love.graphics.setColor(0.3, 0.2, 0.1, 1)
        love.graphics.line(16, 14, 8, 24); love.graphics.line(16, 14, 24, 24)
    end,
    slow = function()
        love.graphics.setColor(0.3, 0.5, 0.9, 1)
        love.graphics.circle("line", 16, 16, 10)
        love.graphics.line(16, 16, 16, 10); love.graphics.line(16, 16, 21, 16)
    end,
    empowered = function()
        love.graphics.setColor(1, 0.85, 0.2, 1)
        love.graphics.polygon("fill", 16, 4, 19, 13, 28, 16, 19, 19, 16, 28, 13, 19, 4, 16, 13, 13)
    end,
    dig = function()
        love.graphics.setColor(0.4, 0.3, 0.2, 1)
        love.graphics.ellipse("fill", 16, 20, 12, 7)
        love.graphics.setColor(0.2, 0.15, 0.1, 1)
        love.graphics.ellipse("fill", 16, 18, 8, 4)
    end,
    heart = function()
        love.graphics.setColor(1, 0.3, 0.4, 1)
        love.graphics.polygon("fill", 16, 26, 6, 14, 10, 8, 16, 12, 22, 8, 26, 14)
    end,
    mana = function()
        love.graphics.setColor(0.4, 0.6, 1, 1)
        love.graphics.polygon("fill", 16, 4, 26, 26, 6, 26)
    end,
}

function effects.get(name)
    return common.loadPNG("status_" .. name) or make(name, drawers[name] or function() end)
end

effects.size = S
return effects
