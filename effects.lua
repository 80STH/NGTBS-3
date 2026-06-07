-- effects.lua
-- Централизованная обработка эффектов окружения (вода, огонь, кислота)
local effects = {}
local status = require("status")

-- Применить ВСЕ эффекты клетки к сущности (статусы + утопление)
-- Возвращает: true, если сущность погибла (анимация запущена)
function effects.applyAllCellEffects(entity, q, r, terrainMap, entities, globalHealth)
    if not entity or not entity.health or entity.health <= 0 then
        return false
    end

    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
    local died = false

    -- 1. Вода тушит огонь
    if terrain == "water" and status.hasEntityStatus(entity, "fire") then
        status.removeFromEntity(entity, "fire")
        print(string.format(" %s stepped into water, fire extinguished!", entity.name))
    end

    -- 2. Огонь с клетки поджигает персонажа
    if status.hasAtHex(q, r, "fire") and not status.hasEntityStatus(entity, "fire") then
        status.applyToEntity(entity, "fire")
        print(string.format(" %s caught fire from cell!", entity.name))
    end

    -- 3. Кислота с клетки накладывает эффект кислоты и исчезает с земли
    if status.hasAtHex(q, r, "acid") and not status.hasEntityStatus(entity, "acid") then
        status.applyToEntity(entity, "acid")
        status.removeFromHex(q, r, "acid")
        print(string.format(" %s covered in acid from cell, ground acid consumed!", entity.name))
    end

    -- 4. Утопление в воде (только для персонажей, не для препятствий)
    if terrain == "water" and entity:isCharacter() then
        print(string.format(" %s drowns in water!", entity.name))
        if sounds and sounds.collision then sounds.collision:play() end
        entity.health = 0
        entity:startDeath()
        died = true
    end

    return died
end

-- Применить конец хода: урон от огня, повторное утопление
-- Теперь сразу запускает анимацию смерти, ничего не возвращает
function effects.applyEndOfTurnEffects(entities, terrainMap, globalHealth)
    for _, entity in ipairs(entities) do
        if entity.health and entity.health > 0 and not entity.isDying then
            -- Огонь наносит урон в конце хода (если не на воде)
            if status.hasEntityStatus(entity, "fire") then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain ~= "water" then
                    local damage = 1
                    print(string.format(" %s burns for %d damage!", entity.name, damage))
                    local wasDestroyed = entity:takeDamage(damage, globalHealth)
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
                print(string.format(" %s decays for %d damage!", entity.name, damage))
                local wasDestroyed = entity:takeDamage(damage, globalHealth)
                if sounds and sounds.decay then sounds.decay:play() end
                if wasDestroyed then
                    entity:startDeath()
                end
            end
            -- ====================================

            -- Проверка утопления (если персонаж на воде и не мёртв)
            if entity:isCharacter() then
                local terrain = terrainMap and terrainMap[entity.q] and terrainMap[entity.q][entity.r] or "grass"
                if terrain == "water" and entity.health > 0 then
                    print(string.format(" %s drowns at end of turn!", entity.name))
                    if sounds and sounds.collision then sounds.collision:play() end
                    entity.health = 0
                    entity:startDeath()
                end
            end
        end
    end
end

return effects