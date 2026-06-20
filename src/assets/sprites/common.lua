-- src/assets/sprites/common.lua
-- Shared helpers for sprite loading + procedural fallbacks.

local common = {}

common.cache = {}

-- Try to load a PNG from assets/png/<name>.png. Returns Image or nil.
function common.loadPNG(name)
    local path = "assets/png/" .. name .. ".png"
    local info = love.filesystem.getInfo(path)
    if not info then return nil end
    if common.cache[path] then return common.cache[path] end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
        img:setFilter("linear", "linear")
        common.cache[path] = img
        return img
    end
    return nil
end

function common.newCanvas(w, h)
    local c = love.graphics.newCanvas(w, h)
    c:setFilter("linear", "linear")
    return c
end

-- draw a rounded-rect body silhouette (creature placeholder) onto current canvas
function common.drawCreatureBody(w, h, color, emblem)
    local cx, cy = w / 2, h / 2 + 1
    local r = math.min(w, h) / 2 - 3
    -- shadow
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", cx, h - 4, r * 0.8, r * 0.28)
    -- body
    love.graphics.setColor(color[1] * 0.7, color[2] * 0.7, color[3] * 0.7, 1)
    love.graphics.circle("fill", cx, cy + 1, r)
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.circle("fill", cx, cy, r)
    -- top highlight
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.ellipse("fill", cx, cy - r * 0.4, r * 0.6, r * 0.3)
    -- outline
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", cx, cy, r)
    love.graphics.setLineWidth(1)
    -- eyes
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", cx - r * 0.35, cy - r * 0.1, r * 0.16)
    love.graphics.circle("fill", cx + r * 0.35, cy - r * 0.1, r * 0.16)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", cx - r * 0.35, cy - r * 0.08, r * 0.07)
    love.graphics.circle("fill", cx + r * 0.35, cy - r * 0.08, r * 0.07)
    -- emblem
    if emblem then emblem(w, h, cx, cy, r) end
end

return common
