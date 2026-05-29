-- status.lua
-- Управление статусами на гексах и на сущностях
local status = {}

-- Таблицы хранения статусов
status.hexStatuses = {}      -- key "q,r" -> список статусов
status.entityStatuses = {}   -- entity -> список статусов

-- Сопоставление GID из Tiled с типами статусов
status.gidToStatus = {
    [15] = "fire",   -- GID для огня
    [16] = "acid",   -- GID для кислоты
}

-- Применить статус к гексу
function status.applyToHex(q, r, statusType)
    local key = q .. "," .. r
    if not status.hexStatuses[key] then
        status.hexStatuses[key] = {}
    end
    for _, st in ipairs(status.hexStatuses[key]) do
        if st == statusType then return end -- уже есть
    end
    table.insert(status.hexStatuses[key], statusType)
end

-- Удалить статус с гекса
function status.removeFromHex(q, r, statusType)
    local key = q .. "," .. r
    if status.hexStatuses[key] then
        for i, st in ipairs(status.hexStatuses[key]) do
            if st == statusType then
                table.remove(status.hexStatuses[key], i)
                break
            end
        end
        if #status.hexStatuses[key] == 0 then
            status.hexStatuses[key] = nil
        end
    end
end

-- Получить статусы на гексе
function status.getAtHex(q, r)
    local key = q .. "," .. r
    return status.hexStatuses[key] or {}
end

-- Проверить наличие статуса на гексе
function status.hasAtHex(q, r, statusType)
    local hexStatuses = status.getAtHex(q, r)
    for _, st in ipairs(hexStatuses) do
        if st == statusType then return true end
    end
    return false
end

-- Применить статус к сущности
function status.applyToEntity(entity, statusType)
    if not status.entityStatuses[entity] then
        status.entityStatuses[entity] = {}
    end
    for _, st in ipairs(status.entityStatuses[entity]) do
        if st == statusType then return end
    end
    table.insert(status.entityStatuses[entity], statusType)
    print(string.format("🔥 %s got %s debuff!", entity.name, statusType))
end

-- Удалить статус с сущности
function status.removeFromEntity(entity, statusType)
    if status.entityStatuses[entity] then
        for i, st in ipairs(status.entityStatuses[entity]) do
            if st == statusType then
                table.remove(status.entityStatuses[entity], i)
                print(string.format("✨ %s lost %s debuff", entity.name, statusType))
                break
            end
        end
        if #status.entityStatuses[entity] == 0 then
            status.entityStatuses[entity] = nil
        end
    end
end

-- Проверить наличие статуса у сущности
function status.hasEntityStatus(entity, statusType)
    if not status.entityStatuses[entity] then return false end
    for _, st in ipairs(status.entityStatuses[entity]) do
        if st == statusType then return true end
    end
    return false
end

-- Получить все статусы сущности
function status.getEntityStatuses(entity)
    return status.entityStatuses[entity] or {}
end

-- Множитель урона от статусов
function status.getDamageMultiplier(entity)
    if status.hasEntityStatus(entity, "acid") then
        return 2.0
    end
    return 1.0
end

-- Применить урон от огня в начале хода
function status.applyFireDamage(entities, hexGrid, terrainMap, globalHealth)
    local damaged = false
    for i = #entities, 1, -1 do
        local entity = entities[i]
        if entity.health and entity.health > 0 then
            if status.hasEntityStatus(entity, "fire") then
                local q, r = entity.q, entity.r
                local terrain = terrainMap[q] and terrainMap[q][r] or "grass"
                -- Если на воде, огонь тушится (это уже сделано при движении, но на всякий случай проверим)
                if terrain == "water" then
                    status.removeFromEntity(entity, "fire")
                else
                    local damage = 1
                    print(string.format("🔥 %s burns for %d damage!", entity.name, damage))
                    local wasDestroyed = entity:takeDamage(damage, globalHealth)
                    if sounds and sounds.fire then sounds.fire:play() end
                    if wasDestroyed then
                        table.remove(entities, i)
                    end
                    damaged = true
                end
            end
        end
    end
    return damaged
end

-- Обработка эффектов при завершении движения на гексе
function status.onMoveFinished(entity, newQ, newR, terrainMap, globalHealth)
    -- Сначала проверим, не наступил ли на воду – тушим огонь
    local terrain = terrainMap[newQ] and terrainMap[newQ][newR] or "grass"
    if terrain == "water" then
        if status.hasEntityStatus(entity, "fire") then
            status.removeFromEntity(entity, "fire")
            print(string.format("💧 %s steps into water, fire extinguished!", entity.name))
        end
    end

    -- Применить эффекты от гекса (огонь / кислота)
    local hexStatuses = status.getAtHex(newQ, newR)
    for _, st in ipairs(hexStatuses) do
        if st == "fire" then
            if not status.hasEntityStatus(entity, "fire") then
                status.applyToEntity(entity, "fire")
                print(string.format("🔥 %s caught fire!", entity.name))
            end
        elseif st == "acid" then
            if not status.hasEntityStatus(entity, "acid") then
                status.applyToEntity(entity, "acid")
                print(string.format("🧪 %s covered in acid! Damage will be doubled.", entity.name))
            end
        end
    end
end

function status.initHexStatuses(loadedStatuses)
    status.hexStatuses = loadedStatuses or {}
end

return status