-- src/assets/sprites/enemies.lua
-- Enemy sprites. Loads assets/png/<id>.png; falls back to a procedural canvas.

local common = require("src.assets.sprites.common")
local enemies = {}

local SIZE = 96

local defs = {
    Zombie = { color = { 0.35, 0.65, 0.25 }, emblem = function(w, h, cx, cy, r)
        -- torn mouth
        love.graphics.setColor(0.15, 0.1, 0.1, 1)
        love.graphics.rectangle("fill", cx - r * 0.3, cy + r * 0.3, r * 0.6, 3)
    end },
    PoisonousZombie = { color = { 0.45, 0.75, 0.30 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(0.7, 0.2, 0.8, 1)
        love.graphics.circle("fill", cx - r * 0.4, cy + r * 0.4, 3)
        love.graphics.circle("fill", cx + r * 0.3, cy + r * 0.5, 2)
    end },
    Ghost = { color = { 0.70, 0.45, 0.95 }, emblem = function(w, h, cx, cy, r)
        -- wisp tail
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.polygon("fill", cx - r * 0.6, cy + r * 0.5, cx + r * 0.6, cy + r * 0.5,
            cx + r * 0.4, cy + r * 0.9, cx, cy + r * 0.6, cx - r * 0.4, cy + r * 0.9)
    end },
    Lich = { color = { 0.80, 0.30, 0.80 }, emblem = function(w, h, cx, cy, r)
        -- hood
        love.graphics.setColor(0.3, 0.1, 0.3, 1)
        love.graphics.arc("fill", cx, cy - r * 0.1, r * 0.95, math.pi, 2 * math.pi)
    end },
    Brute = { color = { 0.80, 0.45, 0.20 }, emblem = function(w, h, cx, cy, r)
        -- heavy brow
        love.graphics.setColor(0.2, 0.12, 0.08, 1)
        love.graphics.rectangle("fill", cx - r * 0.6, cy - r * 0.35, r * 1.2, 4)
    end },
    Lancer = { color = { 0.55, 0.40, 0.20 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(0.9, 0.9, 0.95, 1)
        love.graphics.rectangle("fill", cx + r * 0.5, cy - r * 0.8, 2, r * 1.5)
    end },
    BogShaman = { color = { 0.30, 0.50, 0.40 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(0.2, 0.6, 0.5, 1)
        love.graphics.circle("fill", cx, cy + r * 0.3, r * 0.2)
    end },
    Raider = { color = { 0.70, 0.30, 0.30 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(0.2, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", cx - r * 0.7, cy - r * 0.1, r * 1.4, 3)
    end },
    Dervish = { color = { 0.85, 0.70, 0.25 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.circle("line", cx, cy, r * 0.7)
    end },
    Crusher = { color = { 0.50, 0.30, 0.25 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(0.2, 0.15, 0.1, 1)
        love.graphics.circle("fill", cx, cy + r * 0.2, r * 0.45)
    end },
    SummoningRod = { color = { 0.65, 0.50, 0.25 }, emblem = function(w, h, cx, cy, r)
        love.graphics.setColor(0.4, 0.3, 0.15, 1)
        love.graphics.rectangle("fill", cx - 2, cy - r * 0.8, 4, r * 1.6)
        love.graphics.setColor(0.8, 0.6, 0.3, 1)
        love.graphics.circle("fill", cx, cy - r * 0.8, r * 0.25)
    end },
    PowerLich = { color = { 0.30, 0.10, 0.35 }, emblem = function(w, h, cx, cy, r)
        -- crown
        love.graphics.setColor(0.6, 0.1, 0.15, 1)
        love.graphics.polygon("fill", cx - r * 0.5, cy - r * 0.7, cx - r * 0.3, cy - r, cx - r * 0.1, cy - r * 0.7)
        love.graphics.polygon("fill", cx + r * 0.1, cy - r * 0.7, cx + r * 0.3, cy - r, cx + r * 0.5, cy - r * 0.7)
        -- glowing eyes
        love.graphics.setColor(0.1, 0.9, 0.3, 1)
        love.graphics.rectangle("fill", cx - r * 0.35, cy - r * 0.1, r * 0.2, r * 0.12)
        love.graphics.rectangle("fill", cx + r * 0.15, cy - r * 0.1, r * 0.2, r * 0.12)
    end },
}

local fallbackCache = {}

local function fallback(id)
    if fallbackCache[id] then return fallbackCache[id] end
    local d = defs[id] or { color = { 0.8, 0.3, 0.2 } }
    local c = common.newCanvas(SIZE, SIZE)
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    common.drawCreatureBody(SIZE, SIZE, d.color, d.emblem)
    love.graphics.setCanvas()
    fallbackCache[id] = c
    return c
end

function enemies.get(id) return common.loadPNG(id) or fallback(id) end

return enemies
