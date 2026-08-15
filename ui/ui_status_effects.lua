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

    function ui.drawCellStatusEffects(x, y, radius, statuses, time)
        for _, st in ipairs(statuses) do
            if st == "fire" then
                fire_shader.drawFireOnHex(x, y, radius, time)
            elseif st == "acid" then
                initShaders()
                status_shaders.drawAcid(x, y, radius * 0.5, time, 1.0)
            end
        end
    end

    function ui.drawEntityStatusEffects(x, y, entity, radius, time)
        local statuses = status.getEntityStatuses(entity)
        if #statuses == 0 then return end
        if status.hasEntityStatus(entity, "fire") then
            fire_shader.drawFireOnEntity(x, y, radius, time)
        end
        if status.hasEntityStatus(entity, "decay") then
            initShaders()
            status_shaders.drawDecay(x, y, radius * 0.7, time, 0.9)
        end
        if status.hasEntityStatus(entity, "acid") then
            initShaders()
            status_shaders.drawAcid(x, y, radius * 0.6, time, 0.8)
        end
        if status.hasEntityStatus(entity, "empowered") then
            initShaders()
            status_shaders.drawEmpowered(x, y, radius * 0.8, time, 1.0)
        end
        if status.hasEntityStatus(entity, "rooted") then
            initShaders()
            status_shaders.drawRooted(x, y, radius * 0.8, time, 0.9)
        end
    end
end
