-- src/assets/sprites/allies.lua
-- Ally sprites. Loads assets/png/<id>.png; falls back to a procedural canvas.
-- To add a sprite: drop <id>.png in assets/png/, or add a fallback entry here.

local common = require("src.assets.sprites.common")
local allies = {}

local SIZE = 96

local defs = {
    Warrior   = { color = { 0.85, 0.35, 0.25 }, emblem = function(w, h, cx, cy, r)
        -- sword
        love.graphics.setColor(0.9, 0.9, 0.95, 1)
        love.graphics.rectangle("fill", cx + r * 0.5, cy - r * 0.7, 2, r * 1.2)
        love.graphics.rectangle("fill", cx + r * 0.4, cy + r * 0.4, 6, 2)
    end },
    Puncher   = { color = { 0.25, 0.80, 0.35 }, emblem = function(w, h, cx, cy, r)
        -- big fist
        love.graphics.setColor(0.9, 0.85, 0.7, 1)
        love.graphics.circle("fill", cx - r * 0.5, cy + r * 0.2, r * 0.32)
    end },
    Rogue     = { color = { 0.25, 0.50, 0.85 }, emblem = function(w, h, cx, cy, r)
        -- hood
        love.graphics.setColor(0.15, 0.25, 0.5, 1)
        love.graphics.arc("fill", cx, cy - r * 0.2, r * 0.9, math.pi, 2 * math.pi)
        -- dagger
        love.graphics.setColor(0.9, 0.9, 0.95, 1)
        love.graphics.polygon("fill", cx + r * 0.4, cy, cx + r * 0.7, cy + r * 0.1, cx + r * 0.4, cy + r * 0.15)
    end },
    Summoner  = { color = { 0.80, 0.25, 0.80 }, emblem = function(w, h, cx, cy, r)
        -- staff with orb
        love.graphics.setColor(0.4, 0.3, 0.2, 1)
        love.graphics.rectangle("fill", cx + r * 0.55, cy - r * 0.6, 2, r * 1.2)
        love.graphics.setColor(0.7, 0.5, 1, 1)
        love.graphics.circle("fill", cx + r * 0.56, cy - r * 0.7, r * 0.18)
    end },
    Summoned  = { color = { 0.60, 0.35, 0.90 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.circle("line", cx, cy, r * 0.6)
    end },
}

local fallbackCache = {}

local function fallback(id)
    if fallbackCache[id] then return fallbackCache[id] end
    local d = defs[id] or { color = { 0.7, 0.7, 0.7 } }
    local c = common.newCanvas(SIZE, SIZE)
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    common.drawCreatureBody(SIZE, SIZE, d.color, d.emblem)
    love.graphics.setCanvas()
    fallbackCache[id] = c
    return c
end

function allies.get(id) return common.loadPNG(id) or fallback(id) end

return allies
