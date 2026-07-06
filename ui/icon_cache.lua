local icon_cache = {}
local ICON_SIZE = 48

local icon_names = {
    "wound", "heavy_wound", "fatal_wound", "fatal_wound_acid",
    "building_damage", "heavy_building_damage", "building_destruction",
    "collision_damage", "collision_no_damage",
}

function icon_cache.loadAll()
    for _, name in ipairs(icon_names) do
        local path = "icons/" .. name .. ".png"
        local info = love.filesystem.getInfo(path)
        if info then
            local img = love.graphics.newImage(path)
            img:setFilter("nearest", "nearest")
            icon_cache[name] = img
        end
    end
end

function icon_cache.get(name)
    return icon_cache[name]
end

function icon_cache.draw(name, x, y, alpha)
    local img = icon_cache[name]
    if not img then return end
    local w, h = img:getDimensions()
    local scale = ICON_SIZE / math.max(w, h)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, x, y, 0, scale, scale, w/2, h/2)
    love.graphics.setColor(1, 1, 1, 1)
end

return icon_cache
