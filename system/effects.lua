-- effects.lua
-- Centralized processing of environmental effects (water, fire, acid)
local effects = {}
local status = require("system.status")
local log = require("util.log")

-- Apply ALL cell effects to entity (statuses + drowning)
-- Returns: true if entity died (animation started)
function effects.applyAllCellEffects(entity, q, r, terrainMap, entities)
    if not entity or not entity.health or entity.health <= 0 then
        return false
    end

    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
    local died = false

    -- 1. Water extinguishes fire
    if terrain == "water" and status.hasEntityStatus(entity, "fire") then
        status.removeFromEntity(entity, "fire")
        log.infof("effects", "%s stepped into water, fire extinguished!", entity.name)
    end

    -- 2. Fire from the cell ignites the character
    if status.hasAtHex(q, r, "fire") and not status.hasEntityStatus(entity, "fire") then
        status.applyToEntity(entity, "fire")
        log.infof("effects", "%s caught fire from cell!", entity.name)
    end

    -- 3. Acid from the cell applies acid effect and disappears from the ground
    if status.hasAtHex(q, r, "acid") and not status.hasEntityStatus(entity, "acid") then
        status.applyToEntity(entity, "acid")
        status.removeFromHex(q, r, "acid")
        log.infof("effects", "%s covered in acid from cell, ground acid consumed!", entity.name)
    end

    -- 4. Drowning in water (only for characters, not obstacles, not for flying/hovering)
    if terrain == "water" and entity:isCharacter() and not entity.flying and not entity.hovering then
        log.infof("effects", "%s drowns in water!", entity.name)
        sounds.play("collision")
        entity.health = 0
        entity:startDeath()
        died = true
    end

    return died
end

-- Apply end of turn: fire damage, re-drowning
-- Now immediately triggers death animation, returns nothing
function effects.applyEndOfTurnEffects(entities, terrainMap)
    for _, entity in ipairs(entities) do
        if entity.health and entity.health > 0 and not entity.isDying then
            -- Fire deals damage at end of turn (if not on water)
            if status.hasEntityStatus(entity, "fire") then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain ~= "water" then
                    local damage = 1
                    log.infof("effects", "%s burns for %d damage!", entity.name, damage)
                    local wasDestroyed = entity:takeDamage(damage)
                    sounds.play("fire")
                    if wasDestroyed then
                        entity:startDeath()
                    end
                else
                    status.removeFromEntity(entity, "fire")
                end

            end

            -- ===== ADD DECAY HANDLING =====
            if status.hasEntityStatus(entity, "decay") then
                local damage = 1
                log.infof("effects", "%s decays for %d damage!", entity.name, damage)
                local wasDestroyed = entity:takeDamage(damage)
                sounds.play("decay")
                if wasDestroyed then
                    entity:startDeath()
                end
            end
            -- ====================================

            -- Rage expires at end of turn
            if status.hasEntityStatus(entity, "rage") then
                status.removeFromEntity(entity, "rage")
                log.infof("effects", "%s's rage fades", entity.name)
            end

            -- Drowning check (if character is on water and not dead, not flying/hovering)
            if entity:isCharacter() and not entity.flying and not entity.hovering then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain == "water" and entity.health > 0 then
                    log.infof("effects", "%s drowns at end of turn!", entity.name)
                    sounds.play("collision")
                    entity.health = 0
                    entity:startDeath()
                end
            end
        end
    end
end

return effects
