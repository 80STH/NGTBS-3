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

function visual.addPushEffect(fromX, fromY, toX, toY, duration)
    duration = duration or 0.3
    table.insert(visual.effects, {
        fromX = fromX, fromY = fromY,
        endX = toX, endY = toY,
        timer = 0,
        duration = duration,
        type = "push"
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

        if e.type == "hit" then
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
            for i = 1, 12 do
                local angle = (i / 12) * math.pi * 2 + e.timer * 15
                local r = 25 * t
                local dx = math.cos(angle) * r
                local dy = math.sin(angle) * r - 12 * t
                love.graphics.circle("fill", e.x + dx, e.y + dy, 5)
            end
            love.graphics.setColor(0.3, 0.7, 1, alpha)
            love.graphics.circle("fill", e.x, e.y, 15 * (1 - t))

        elseif e.type == "push" then
            -- ваш код для push (если есть)
            love.graphics.setColor(0.7, 0.9, 1, alpha)
            love.graphics.setLineWidth(3)
            local fromX, fromY = e.fromX, e.fromY
            local toX, toY = e.endX, e.endY
            love.graphics.line(fromX, fromY, toX, toY)
            love.graphics.setLineWidth(1)

        elseif e.type == "collision" then
            local radius = 8 + t * 20
            love.graphics.setColor(1, 0.8, 0.2, alpha)
            love.graphics.circle("line", e.x, e.y, radius)
            love.graphics.setColor(1, 0.4, 0.1, alpha)
            love.graphics.circle("fill", e.x, e.y, radius * 0.6)
            love.graphics.setLineWidth(2)
            for i = 0, 5 do
                local angle = i * math.pi * 2 / 6 + t * 12
                local x2 = e.x + math.cos(angle) * radius * 1.3
                local y2 = e.y + math.sin(angle) * radius * 1.3
                love.graphics.setColor(1, 0.9, 0.3, alpha * 0.9)
                love.graphics.line(e.x, e.y, x2, y2)
            end
            love.graphics.setLineWidth(1)
        elseif e.type == "dig" then
            local radius = 10 + t * 20
            love.graphics.setColor(0.6, 0.4, 0.2, alpha)
            love.graphics.circle("fill", e.x, e.y, radius * 0.8)
            love.graphics.setColor(0.9, 0.7, 0.3, alpha)
            for i = 1, 6 do
                local angle = (i / 6) * math.pi * 2 + e.timer * 15
                local dx = math.cos(angle) * radius * 0.7
                local dy = math.sin(angle) * radius * 0.5
                love.graphics.circle("fill", e.x + dx, e.y + dy, 5)
            end
            love.graphics.setColor(1, 1, 0.5, alpha)
            love.graphics.print("🕳️", e.x - 10, e.y - 12)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return visual