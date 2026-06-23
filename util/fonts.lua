local cache = {}
local fonts = {}

function fonts.get(size)
    local f = cache[size]
    if not f then
        f = love.graphics.newFont(size)
        cache[size] = f
    end
    return f
end

function fonts.clear()
    cache = {}
end

return fonts
