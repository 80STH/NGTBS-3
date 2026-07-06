-- ui_status_effects.lua
-- Visual effects for statuses (fire, acid, decay) on cells and units.
-- Do not depend on other ui.* functions (except drawCellStatusEffects -> drawFireOnHex/AcidOnHex).
-- Takes a ui-table and registers functions on it.
return function(ui)
    local fire_shader = require("ui.fire_shader")
    local status_shaders = require("system.status_shaders")
    local shadersInitialized = false

    local function initShaders()
        if not shadersInitialized then
            status_shaders.init()
            shadersInitialized = true
        end
    end

    function ui.drawFireOnHex(x, y, radius, time)
        fire_shader.drawFireOnHex(x, y, radius, time)
    end

    function ui.drawAcidOnHex(x, y, radius, time)
        initShaders()
        status_shaders.drawAcid(x, y, radius * 0.5, time, 1.0)
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
        fire_shader.drawFireOnEntity(x, y, radius, time)
    end

    function ui.drawAcidOnEntity(x, y, radius, time)
        initShaders()
        status_shaders.drawAcid(x, y, radius * 0.6, time, 0.8)
    end

    function ui.drawDecayOnEntity(x, y, radius, time)
        initShaders()
        status_shaders.drawDecay(x, y, radius * 0.7, time, 0.9)
    end

    function ui.drawEmpoweredOnEntity(x, y, radius, time)
        initShaders()
        status_shaders.drawEmpowered(x, y, radius * 0.8, time, 1.0)
    end

    function ui.drawRootedOnEntity(x, y, radius, time)
        initShaders()
        status_shaders.drawRooted(x, y, radius * 0.8, time, 0.9)
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
        if status.hasEntityStatus(entity, "rooted") then
            ui.drawRootedOnEntity(x, y, radius, time)
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
