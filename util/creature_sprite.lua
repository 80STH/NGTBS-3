local creature_sprite = {}

local PART_DIR = "sprites/parts/"
local partCache = {}

local function genPart(category, variant)
    local s = 16
    local c = love.graphics.newCanvas(s, s)
    c:setFilter("nearest", "nearest")
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)

    if category == "chassis" then
        if variant == "walking" then
            love.graphics.setColor(1, 1, 1)
            love.graphics.polygon("fill", 2, 9, 14, 9, 11, 15, 5, 15)
            love.graphics.setColor(0.7, 0.7, 0.7)
            love.graphics.rectangle("fill", 4, 12, 2, 3)
            love.graphics.rectangle("fill", 10, 12, 2, 3)
        elseif variant == "hovering" then
            love.graphics.setColor(1, 1, 1)
            love.graphics.polygon("fill", 1, 9, 15, 9, 12, 15, 4, 15)
            love.graphics.setColor(0.8, 0.8, 0.8, 0.6)
            love.graphics.polygon("fill", 0, 10, 3, 10, 2, 14, 0, 13)
            love.graphics.polygon("fill", 16, 10, 13, 10, 14, 14, 16, 13)
        else -- teleport
            love.graphics.setColor(1, 1, 1)
            love.graphics.polygon("fill", 2, 9, 14, 9, 11, 15, 5, 15)
            love.graphics.setColor(1, 1, 1, 0.5)
            for i = 1, 3 do
                love.graphics.circle("line", 8, 12, i * 2)
            end
        end

    elseif category == "body" then
        love.graphics.setColor(1, 1, 1)
        local size = variant == 1 and 5 or variant == 2 and 7 or 9
        local xOff = math.floor((s - size) / 2)
        local yOff = 11 - size
        love.graphics.rectangle("fill", xOff, yOff, size, size, 1)

    elseif category == "hands" then
        love.graphics.setColor(1, 1, 1)
        if variant == "ghost" then
            love.graphics.circle("fill", 2, 8, 2)
            love.graphics.circle("fill", 14, 8, 2)
            love.graphics.setColor(0.6, 0.6, 0.6, 0.5)
            love.graphics.circle("fill", 1, 7, 1.5)
            love.graphics.circle("fill", 15, 7, 1.5)
        elseif variant == "zombie" then
            love.graphics.rectangle("fill", 1, 8, 3, 3, 1)
            love.graphics.rectangle("fill", 12, 8, 3, 3, 1)
        elseif variant == "lich" then
            love.graphics.polygon("fill", 1, 11, 4, 6, 4, 11)
            love.graphics.polygon("fill", 15, 11, 12, 6, 12, 11)
        elseif variant == "brute" then
            love.graphics.rectangle("fill", 0, 7, 4, 4, 1)
            love.graphics.rectangle("fill", 12, 7, 4, 4, 1)
        elseif variant == "lancer" then
            love.graphics.polygon("fill", 0, 12, 4, 6, 5, 12)
            love.graphics.polygon("fill", 16, 12, 12, 6, 11, 12)
        elseif variant == "dervish" then
            love.graphics.polygon("fill", 0, 10, 4, 6, 5, 10)
            love.graphics.polygon("fill", 16, 10, 12, 6, 11, 10)
        end

    elseif category == "head" then
        if variant == "none" then
            love.graphics.setColor(1, 1, 1)
            love.graphics.circle("fill", 8, 3, 3)
        else -- slow
            love.graphics.setColor(0.6, 0.8, 1)
            love.graphics.circle("fill", 8, 3, 4)
            love.graphics.setColor(1, 1, 1, 0.4)
            love.graphics.circle("line", 8, 3, 1.5)
            love.graphics.circle("line", 8, 3, 3)
        end
    end

    love.graphics.setCanvas()
    return c
end

local function loadPart(category, variant)
    local key = category .. "_" .. tostring(variant)
    if partCache[key] then return partCache[key] end

    local path = PART_DIR .. key .. ".png"
    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")
        partCache[key] = img
        return img
    end

    local canvas = genPart(category, variant)
    partCache[key] = canvas
    return canvas
end

function creature_sprite.build(params)
    local s = 16
    local c = params.color or {0.5, 0.5, 0.5}

    local canvas = love.graphics.newCanvas(s, s)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.draw(loadPart("chassis", params.mobility or "walking"))

    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.draw(loadPart("body", params.health or 2))

    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.draw(loadPart("hands", (params.attack and params.attack.set) or "zombie"))

    if params.aura == "slow" then
        love.graphics.setColor(1, 1, 1)
    else
        love.graphics.setColor(c[1], c[2], c[3])
    end
    love.graphics.draw(loadPart("head", params.aura or "none"))

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    return canvas
end

function creature_sprite.clear()
    partCache = {}
end

return creature_sprite
