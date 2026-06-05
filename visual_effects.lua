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
        elseif e.type == "dash" then
    local t = e.timer / e.duration
    local alpha = 1 - t
    local x = e.fromX + (e.toX - e.fromX) * t
    local y = e.fromY + (e.toY - e.fromY) * t
    love.graphics.setColor(1, 0.6, 0.2, alpha)
    love.graphics.circle("fill", x, y, 8 * (1 - t) + 4)
    love.graphics.setColor(1, 1, 0.5, alpha * 0.8)
    love.graphics.circle("line", x, y, 12 * (1 - t))

elseif e.type == "arc" then
    local t = e.timer / e.duration
    local alpha = 1 - t
    local midX = (e.fromX + e.toX) / 2
    local midY = (e.fromY + e.toY) / 2
    local ctrlX, ctrlY
    if e.ctrlX and e.ctrlY then
        ctrlX, ctrlY = e.ctrlX, e.ctrlY
    else
        -- старый расчёт: перпендикуляр
        local perpX = (e.toY - e.fromY)
        local perpY = (e.fromX - e.toX)
        local len = math.sqrt(perpX*perpX + perpY*perpY)
        if len > 0.01 then
            perpX = perpX / len * 40
            perpY = perpY / len * 40
        end
        ctrlX, ctrlY = midX + perpX, midY + perpY
    end
    local function bezier(p)
        local u = 1 - p
        local x = u*u*e.fromX + 2*u*p*ctrlX + p*p*e.toX
        local y = u*u*e.fromY + 2*u*p*ctrlY + p*p*e.toY
        return x, y
    end
    for i = 0, 20 do
        local p = i / 20
        local x, y = bezier(p)
        love.graphics.setColor(e.r, e.g, e.b, alpha * (1 - math.abs(p - 0.5)*2))
        love.graphics.circle("fill", x, y, 3)
    end

elseif e.type == "line" then
    local t = e.timer / e.duration
    local alpha = (1 - t) * e.alpha
    love.graphics.setLineWidth(e.thickness)
    love.graphics.setColor(e.r, e.g, e.b, alpha)
    love.graphics.line(e.fromX, e.fromY, e.toX, e.toY)
    love.graphics.setLineWidth(1)

elseif e.type == "shockwave" then
    local t = e.timer / e.duration
    local rad = e.radius * t
    love.graphics.setColor(1, 1, 0.8, 0.7 - t)
    love.graphics.circle("line", e.x, e.y, rad)
    love.graphics.setColor(0.8, 0.5, 0.2, 0.5 - t*0.5)
    love.graphics.circle("fill", e.x, e.y, rad * 0.7)

elseif e.type == "sparks" then
    local t = e.timer / e.duration
    for i = 1, e.count do
        local angle = (i / e.count) * math.pi * 2 + e.timer * 15
        local r = 20 * t
        local dx = math.cos(angle) * r * (1 - t)
        local dy = math.sin(angle) * r * (1 - t)
        love.graphics.setColor(1, 0.6 + t*0.4, 0.2, 1 - t)
        love.graphics.circle("fill", e.x + dx, e.y + dy, 3)
    end

elseif e.type == "blood" then
    local t = e.timer / e.duration
    love.graphics.setColor(0.8, 0.1, 0.1, 1 - t)
    for i = 1, 8 do
        local angle = (i * 45) + e.timer * 10
        local dist = 12 * t
        local dx = math.cos(angle) * dist
        local dy = math.sin(angle) * dist * 0.7
        love.graphics.circle("fill", e.x + dx, e.y + dy, 3)
    end

elseif e.type == "magic_explosion" then
    local t = e.timer / e.duration
    local rad = 15 * (1 - t) + 5 * t
    love.graphics.setColor(e.r, e.g, e.b, 1 - t)
    love.graphics.circle("fill", e.x, e.y, rad)
    love.graphics.setColor(1, 1, 1, 0.8 - t)
    love.graphics.circle("line", e.x, e.y, rad + 4)
    for i = 1, 6 do
        local angle = (i / 6) * math.pi * 2 + e.timer * 20
        local dx = math.cos(angle) * rad * 1.5
        local dy = math.sin(angle) * rad * 1.5
        love.graphics.setColor(e.r, e.g, e.b, 0.7 - t)
        love.graphics.line(e.x, e.y, e.x + dx, e.y + dy)
    end

elseif e.type == "ghost_hit" then
    local t = e.timer / e.duration
    local alpha = 0.8 - t
    love.graphics.setColor(0.7, 0.3, 1, alpha)
    love.graphics.circle("fill", e.x, e.y, 12 + t*10)
    love.graphics.setColor(0.9, 0.6, 1, alpha*0.8)
    love.graphics.circle("line", e.x, e.y, 16 + t*12)
end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- НОВЫЕ ЭФФЕКТЫ ДЛЯ АТАК
-- ============================================================

function visual.addDashEffect(fromX, fromY, toX, toY)
    table.insert(visual.effects, {
        type = "dash",
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        timer = 0, duration = 0.25
    })
end

function visual.addArcEffect(fromX, fromY, toX, toY, r, g, b, duration, ctrlX, ctrlY)
    table.insert(visual.effects, {
        type = "arc",
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        r = r or 1, g = g or 1, b = b or 1,
        timer = 0, duration = duration or 0.3,
        ctrlX = ctrlX,   -- опциональная контрольная точка
        ctrlY = ctrlY
    })
end

function visual.addLineEffect(fromX, fromY, toX, toY, r, g, b, thickness, alpha)
    table.insert(visual.effects, {
        type = "line",
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        r = r, g = g, b = b,
        thickness = thickness or 2,
        alpha = alpha or 1,
        timer = 0, duration = 0.2
    })
end

function visual.addShockwave(x, y, radius)
    table.insert(visual.effects, {
        type = "shockwave",
        x = x, y = y,
        radius = radius or 15,
        timer = 0, duration = 0.3
    })
end

function visual.addSpark(x, y, count)
    table.insert(visual.effects, {
        type = "sparks",
        x = x, y = y,
        count = count or 8,
        timer = 0, duration = 0.4
    })
end

function visual.addBloodSplat(x, y)
    table.insert(visual.effects, {
        type = "blood",
        x = x, y = y,
        timer = 0, duration = 0.5
    })
end

function visual.addMagicExplosion(x, y, r, g, b)
    table.insert(visual.effects, {
        type = "magic_explosion",
        x = x, y = y,
        r = r or 0.6, g = g or 0.2, b = b or 1.0,
        timer = 0, duration = 0.4
    })
end

-- Добавляем отрисовку в функцию visual.draw() новые блоки
-- (нужно модифицировать существующую visual.draw)

return visual