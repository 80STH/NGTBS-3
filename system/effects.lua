-- effects.lua
-- Централизованная обработка эффектов окружения (вода, огонь, кислота)
local effects = {}
local status = require("system.status")
local log = require("util.log")

-- Применить ВСЕ эффекты клетки к сущности (статусы + утопление)
-- Возвращает: true, если сущность погибла (анимация запущена)
function effects.applyAllCellEffects(entity, q, r, terrainMap, entities)
    if not entity or not entity.health or entity.health <= 0 then
        return false
    end

    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
    local died = false

    -- 1. Вода тушит огонь
    if terrain == "water" and status.hasEntityStatus(entity, "fire") then
        status.removeFromEntity(entity, "fire")
        log.infof("effects", "%s stepped into water, fire extinguished!", entity.name)
    end

    -- 2. Огонь с клетки поджигает персонажа
    if status.hasAtHex(q, r, "fire") and not status.hasEntityStatus(entity, "fire") then
        status.applyToEntity(entity, "fire")
        log.infof("effects", "%s caught fire from cell!", entity.name)
    end

    -- 3. Кислота с клетки накладывает эффект кислоты и исчезает с земли
    if status.hasAtHex(q, r, "acid") and not status.hasEntityStatus(entity, "acid") then
        status.applyToEntity(entity, "acid")
        status.removeFromHex(q, r, "acid")
        log.infof("effects", "%s covered in acid from cell, ground acid consumed!", entity.name)
    end

    -- 4. Утопление в воде (только для персонажей, не для препятствий, не для летающих/парящих)
    if terrain == "water" and entity:isCharacter() and not entity.flying and not entity.hovering then
        log.infof("effects", "%s drowns in water!", entity.name)
        if sounds and sounds.collision then sounds.collision:play() end
        entity.health = 0
        entity:startDeath()
        died = true
    end

    -- 5. Underwater mines (убивает всех кто наступает)
    if entity:isCharacter() or entity:isBuilding() then
        local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
        if terrain == "underwater_mines" then
            log.infof("effects", "%s destroyed by underwater mines!", entity.name)
            if sounds and sounds.collision then sounds.collision:play() end
            entity.health = 0
            entity:startDeath()
            died = true
        end
    end

    return died
end

-- Применить конец хода: урон от огня, повторное утопление
-- Теперь сразу запускает анимацию смерти, ничего не возвращает
function effects.applyEndOfTurnEffects(entities, terrainMap)
    for _, entity in ipairs(entities) do
        if entity.health and entity.health > 0 and not entity.isDying then
            -- Огонь наносит урон в конце хода (если не на воде)
            if status.hasEntityStatus(entity, "fire") then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain ~= "water" then
                    local damage = 1
                    log.infof("effects", "%s burns for %d damage!", entity.name, damage)
                    local wasDestroyed = entity:takeDamage(damage)
                    if sounds and sounds.fire then sounds.fire:play() end
                    if wasDestroyed then
                        entity:startDeath()
                    end
                else
                    status.removeFromEntity(entity, "fire")
                end

            end

            -- ===== ДОБАВИТЬ ОБРАБОТКУ DECAY =====
            if status.hasEntityStatus(entity, "decay") then
                local damage = 1
                log.infof("effects", "%s decays for %d damage!", entity.name, damage)
                local wasDestroyed = entity:takeDamage(damage)
                if sounds and sounds.decay then sounds.decay:play() end
                if wasDestroyed then
                    entity:startDeath()
                end
            end
            -- ====================================

            -- Проверка утопления (если персонаж на воде и не мёртв, не летающий/парящий)
            if entity:isCharacter() and not entity.flying and not entity.hovering then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain == "water" and entity.health > 0 then
                    log.infof("effects", "%s drowns at end of turn!", entity.name)
                    if sounds and sounds.collision then sounds.collision:play() end
                    entity.health = 0
                    entity:startDeath()
                end
            end

            -- Underwater mines в конце хода (добивает выживших)
            if entity.health > 0 then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain == "underwater_mines" then
                    log.infof("effects", "%s destroyed by underwater mines at end of turn!", entity.name)
                    if sounds and sounds.collision then sounds.collision:play() end
                    entity.health = 0
                    entity:startDeath()
                end
            end
        end
    end
end

return effects
