-- system/deploy_effects.lua
-- Landing effects applied when a unit is deployed onto the battlefield
-- (at deploy confirm). Each entity may carry a `deployEffect` table:
--   { type = "damage_nearby", damage = 1, radius = 1 }
-- Register new effect types with deploy_effects.register(type, fn(eff, entity, q, r)).

local deploy_effects = {}
local log = require("util.log")

local registry = {}

function deploy_effects.register(effectType, fn)
    registry[effectType] = fn
end

-- Apply the landing effect of an entity at its deployed cell. No-op without deployEffect.
function deploy_effects.apply(entity, q, r)
    local eff = entity and entity.deployEffect
    if not eff then return end
    local fn = registry[eff.type]
    if not fn then
        log.warnf("deploy", "Unknown deploy effect '%s'", tostring(eff.type))
        return
    end
    fn(eff, entity, q, r)
end

-- Built-in: damage every enemy within `radius` cells of the landing spot.
deploy_effects.register("damage_nearby", function(eff, entity, q, r)
    local radius = eff.radius or 1
    local damage = eff.damage or 1
    local visual = require("system.visual_effects")
    local hit = 0
    for _, e in ipairs(_G.entities or {}) do
        if e ~= entity and e:isCharacter() and not e.isPlayable
            and e.health > 0 and not e.isDying then
            if _G.hex and _G.hex:getDistance(q, r, e.q, e.r) <= radius then
                local died = e:takeDamage(damage)
                if died then e:startDeath() end
                local x, y = _G.getDrawCoords(e.q, e.r)
                visual.addEffect(x, y, "hit", 0.3)
                hit = hit + 1
            end
        end
    end
    if hit > 0 then
        local x, y = _G.getDrawCoords(q, r)
        visual.addShockwave(x, y, 20)
        log.infof("deploy", "%s lands and hits %d enemies!", entity.name, hit)
    end
end)

return deploy_effects
