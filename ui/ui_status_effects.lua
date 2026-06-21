-- ui_status_effects.lua
-- Visual effects for statuses (fire, acid, decay) on cells and units.
-- Do not depend on other ui.* functions (except drawCellStatusEffects -> drawFireOnHex/AcidOnHex).
-- Takes a ui-table and registers functions on it.
return function(ui)
    function ui.drawFireOnHex(x, y, radius, time)
        local t = time * 5
        love.graphics.setBlendMode("add")
        for i = 1, 5 do
            local angle = (i / 5) * math.pi * 2 + t * 2
            local lenVar = 0.5 + 0.3 * math.sin(t * 3 + i)
            local height = radius * 0.6 * lenVar
            local width = radius * 0.3 * (0.7 + 0.3 * math.sin(t * 5 + i))

            local tipX = x + math.cos(angle) * width * 0.5
            local tipY = y - height * 0.8
            local baseLeftX = x + math.cos(angle - 0.3) * width
            local baseLeftY = y + math.sin(angle - 0.3) * width * 0.5
            local baseRightX = x + math.cos(angle + 0.3) * width
            local baseRightY = y + math.sin(angle + 0.3) * width * 0.5

            local rCol = 1
            local gCol = 0.3 + 0.7 * (lenVar - 0.5) * 2
            love.graphics.setColor(rCol, gCol, 0, 0.8)
            love.graphics.polygon("fill", tipX, tipY, baseLeftX, baseLeftY, baseRightX, baseRightY)
        end
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(1, 0.6, 0, 0.9)
        love.graphics.circle("fill", x, y, radius * 0.2)
    end

    function ui.drawAcidOnHex(x, y, radius, time)
        local t = time * 2
        love.graphics.setColor(0.3, 0.8, 0.2, 0.7 + 0.3 * math.sin(t))
        love.graphics.circle("fill", x, y, radius * 0.4)
        for i = 1, 4 do
            local angle = (i * 1.5 + t) % (math.pi * 2)
            local bx = x + math.cos(angle) * radius * 0.5
            local by = y + math.sin(angle) * radius * 0.6
            local size = radius * 0.15 * (0.7 + 0.3 * math.sin(t * 3 + i))
            love.graphics.setColor(0.5, 0.9, 0.3, 0.8)
            love.graphics.circle("fill", bx, by, size)
        end
    end

    function ui.drawCellStatusEffects(x, y, radius, statuses, time)
        for _, st in ipairs(statuses) do
            if st == "fire" then
                ui.drawFireOnHex(x, y, radius, time)
            elseif st == "acid" then
                ui.drawAcidOnHex(x, y, radius, time)
            end
        end
    end

    function ui.drawFireOnEntity(x, y, radius, time)
        local t = time * 8
        love.graphics.setBlendMode("add")
        for i = 1, 3 do
            local size = radius * (0.6 + 0.2 * math.sin(t * 2 + i))
            love.graphics.setColor(1, 0.3, 0, 0.2)
            love.graphics.circle("fill", x, y, size)
        end
        for i = 1, 5 do
            local angle = (i / 5) * math.pi * 2 + t * 2
            local flicker = 0.6 + 0.4 * math.sin(t * 3 + i * 2)
            local fx = x + math.cos(angle) * radius * 0.3 * flicker
            local fy = y - radius * 0.5 * flicker - 5 + math.sin(t * 4 + i) * 3
            local fs = radius * 0.25 * flicker
            local rCol = 1
            local gCol = 0.3 + 0.5 * flicker
            love.graphics.setColor(rCol, gCol, 0, 0.7 * flicker)
            love.graphics.circle("fill", fx, fy, fs)
        end
        love.graphics.setBlendMode("alpha")
    end

    function ui.drawAcidOnEntity(x, y, radius, time)
        local t = time * 3
        love.graphics.setBlendMode("add")
        for i = 1, 4 do
            local angle = (i * 1.5 + t) % (math.pi * 2)
            local bx = x + math.cos(angle) * radius * 0.5
            local by = y + math.sin(angle) * radius * 0.6
            local size = radius * 0.15 * (0.7 + 0.3 * math.sin(t * 3 + i))
            love.graphics.setColor(0.3, 0.8, 0.2, 0.6)
            love.graphics.circle("fill", bx, by, size)
        end
        love.graphics.setBlendMode("alpha")
    end

    function ui.drawDecayOnEntity(x, y, radius, time)
        local t = time * 2
        love.graphics.setBlendMode("add")
        for i = 1, 6 do
            local angle = (i / 6) * math.pi * 2 + t * 1.5
            local dx = x + math.cos(angle) * radius * 0.6
            local dy = y + math.sin(angle) * radius * 0.6
            local ds = radius * 0.08 * (0.5 + 0.5 * math.sin(t * 4 + i * 3))
            love.graphics.setColor(0.2, 0.4, 0.1, 0.7)
            love.graphics.circle("fill", dx, dy, ds)
        end
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(0.1, 0.25, 0.05, 0.3)
        love.graphics.circle("fill", x, y, radius * 0.5)
    end

    function ui.drawEmpoweredOnEntity(x, y, radius, time)
        local t = time * 6
        love.graphics.setBlendMode("add")
        for i = 1, 6 do
            local angle = (i / 6) * math.pi * 2 + t * 2
            local len = radius * 0.5 + radius * 0.3 * math.sin(t * 3 + i)
            local ex = x + math.cos(angle) * len
            local ey = y + math.sin(angle) * len
            local es = radius * 0.1 * (0.6 + 0.4 * math.sin(t * 5 + i * 2))
            love.graphics.setColor(1, 0.9, 0.2, 0.5 + 0.3 * math.sin(t * 4 + i))
            love.graphics.circle("fill", ex, ey, es)
        end
        love.graphics.setColor(1, 1, 0.5, 0.15 + 0.1 * math.sin(t))
        love.graphics.circle("fill", x, y, radius * 0.8)
        love.graphics.setBlendMode("alpha")
    end

    function ui.drawEntityStatusEffects(x, y, entity, radius, time)
        local statuses = status.getEntityStatuses(entity)
        if #statuses == 0 then return end
        if status.hasEntityStatus(entity, "fire") then
            ui.drawFireOnEntity(x, y, radius, time)
        end
        if status.hasEntityStatus(entity, "decay") then
            ui.drawDecayOnEntity(x, y, radius, time)
        end
        if status.hasEntityStatus(entity, "acid") then
            ui.drawAcidOnEntity(x, y, radius, time)
        end
        if status.hasEntityStatus(entity, "empowered") then
            ui.drawEmpoweredOnEntity(x, y, radius, time)
        end
    end

    function ui.getEntityStatusColor(entity, time)
        local statuses = status.getEntityStatuses(entity)
        if #statuses == 0 then return nil end
        local r, g, b = 1, 1, 1
        if status.hasEntityStatus(entity, "fire") then
            r, g, b = 1, 0.3 + 0.3 * math.sin(time * 6), 0.1
        end
        if status.hasEntityStatus(entity, "decay") then
            r = (r or 1) * (0.5 + 0.3 * math.sin(time * 3))
            g = (g or 1) * (0.7 + 0.2 * math.sin(time * 4))
            b = (b or 1) * (0.3 + 0.2 * math.sin(time * 5))
        end
        if status.hasEntityStatus(entity, "acid") then
            local acidPulse = 0.5 + 0.5 * math.sin(time * 4)
            r = (r or 1) * (0.5 + acidPulse * 0.5)
            g = (g or 1) * (0.9 + acidPulse * 0.1)
            b = (b or 1) * (0.3 + acidPulse * 0.3)
        end
        return r, g, b
    end
end
