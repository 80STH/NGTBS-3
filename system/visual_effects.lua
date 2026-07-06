-- visual_effects.lua
local visual = {}
local visual_shaders = require("system.visual_shaders")

visual.effects = {}
visual.shadersInitialized = false

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
    if not visual.shadersInitialized then
        visual_shaders.init()
        visual.shadersInitialized = true
    end
    
    local effects = visual.effects
    local n = #effects
    local i = 1
    while i <= n do
        local e = effects[i]
        e.timer = e.timer + dt
        if e.timer >= e.duration then
            effects[i] = effects[n]
            effects[n] = nil
            n = n - 1
        else
            i = i + 1
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
            visual_shaders.drawDrown(e.x, e.y, 25, t)

        elseif e.type == "push" then
            visual_shaders.drawPushEffect(e.fromX, e.fromY, e.endX, e.endY, 20, t, 1.0)

        elseif e.type == "collision" then
            visual_shaders.drawUnitCollision(e.x, e.y, 25, t, 1.0)

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
        ctrlX = midX
        ctrlY = midY - 40
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
    visual_shaders.drawShockwave(e.x, e.y, e.radius, t, e.radius)

 elseif e.type == "sparks" then
    visual_shaders.drawSparks(e.x, e.y, 20, t, e.count)

 elseif e.type == "blood" then
    visual_shaders.drawBlood(e.x, e.y, 15, t)

 elseif e.type == "magic_explosion" then
    visual_shaders.drawMagicExplosion(e.x, e.y, 20, t, e.r, e.g, e.b)

 elseif e.type == "ghost_hit" then
    visual_shaders.drawGhostHit(e.x, e.y, 16, t)

 elseif e.type == "lightning" then
    visual_shaders.drawLightning(e.x, e.y, t, 1.0)

elseif e.type == "ground_slam" then
    local t = e.timer / e.duration
    local alpha = 1 - t
    local sink = 8 * math.sin(t * math.pi)
    local verts = e.hex:drawHexagon(e.x, e.y + sink, e.hex.radius)
    -- Compressed dark hex
    love.graphics.setColor(0.3, 0.2, 0.1, alpha * 0.4)
    love.graphics.polygon("fill", verts)
    -- Pulsating outline
    local pulse = 8 * math.sin(t * math.pi)
    local pulseVerts = e.hex:drawHexagon(e.x, e.y, e.hex.radius + pulse)
    love.graphics.setColor(0.9, 0.6, 0.2, alpha * 0.6)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", pulseVerts)
    love.graphics.setLineWidth(1)
end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- ============================================================
-- NEW EFFECTS FOR ATTACKS
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
        ctrlX = ctrlX,   -- optional control point
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

function visual.addGroundSlam(x, y, hex)
    table.insert(visual.effects, {
        type = "ground_slam",
        x = x, y = y,
        hex = hex,
        timer = 0, duration = 0.35
    })
end

function visual.addLightning(x, y, duration)
    table.insert(visual.effects, {
        type = "lightning",
        x = x, y = y,
        timer = 0, duration = duration or 0.3
    })
end

-- Add drawing of new blocks to the visual.draw() function
-- (need to modify existing visual.draw)

return visual