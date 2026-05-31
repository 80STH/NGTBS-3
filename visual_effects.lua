-- visual_effects.lua
local visual = {}

visual.effects = {}

function visual.addEffect(x, y, effectType, duration)
    duration = duration or 0.5
    table.insert(visual.effects, {
        x = x, y = y,
        timer = 0,
        duration = duration,
        type = effectType or "hit"
    })
end

function visual.update(dt)
    for i = #visual.effects, 1, -1 do
        local e = visual.effects[i]
        e.timer = e.timer + dt
        if e.timer >= e.duration then
            table.remove(visual.effects, i)
        end
    end
end

function visual.draw()
    for _, e in ipairs(visual.effects) do
        local t = e.timer / e.duration
        local alpha = 1 - t

        if e.type == "hit" or e.type == "collision" then
            local radius = 10 + t * 15
            love.graphics.setColor(1, 0.8, 0.2, alpha * 0.9)
            love.graphics.circle("line", e.x, e.y, radius)
            love.graphics.setColor(1, 0.5, 0, alpha)
            love.graphics.circle("fill", e.x, e.y, radius * 0.5)
        
        elseif e.type == "slam" then
            love.graphics.setColor(1, 0.3, 0.3, alpha)
            love.graphics.circle("fill", e.x, e.y, 12 * (1 - t))
            love.graphics.setColor(1, 0.8, 0.2, alpha)
            love.graphics.circle("line", e.x, e.y, 18 * t)
        
        elseif e.type == "drown" then
            love.graphics.setColor(0.2, 0.6, 0.9, alpha)
            for i = 1, 12 do   -- было 6
                local angle = (i / 12) * math.pi * 2 + e.timer * 15
                local r = 25 * t   -- было 15
                local dx = math.cos(angle) * r
                local dy = math.sin(angle) * r - 12 * t   -- было -8*t
                love.graphics.circle("fill", e.x + dx, e.y + dy, 5)   -- было 3
            end
            love.graphics.setColor(0.3, 0.7, 1, alpha)
            love.graphics.circle("fill", e.x, e.y, 15 * (1 - t))   -- было 10
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return visual