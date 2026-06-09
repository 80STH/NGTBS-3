-- status.lua
-- Управление статусами на гексах и на сущностях
local status = {}

-- Таблицы хранения статусов
status.hexStatuses = {}      -- key "q,r" -> список статусов
status.entityStatuses = {}   -- entity -> список статусов

-- Сопоставление GID из Tiled с типами статусов
status.gidToStatus = {
    [41] = "fire",
    [32] = "acid",
    [42] = "decay",   -- если есть GID для разложения в карте
}

-- Применить статус к гексу
function status.applyToHex(q, r, statusType, hex)  -- добавлен параметр hex (опционально)
    if hex and not hex:isActiveHex(q, r) then return end  -- не накладываем статус на неактивные клетки
    local key = q .. "," .. r
    if not status.hexStatuses[key] then
        status.hexStatuses[key] = {}
    end
    for _, st in ipairs(status.hexStatuses[key]) do
        if st == statusType then return end
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
    if q == nil or r == nil then
        print("ERROR: getAtHex called with nil q or r", q, r, debug.traceback())
        return {}
    end
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
    print(string.format(" %s got %s debuff!", entity.name, statusType))
end

-- Удалить статус с сущности
function status.removeFromEntity(entity, statusType)
    if status.entityStatuses[entity] then
        for i, st in ipairs(status.entityStatuses[entity]) do
            if st == statusType then
                table.remove(status.entityStatuses[entity], i)
                print(string.format(" %s lost %s debuff", entity.name, statusType))
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

-- Проверка наличия негативных статусов на гексе (огонь, кислота, разложение)
function status.hasNegativeHexStatus(q, r)
    local hexStatuses = status.getAtHex(q, r)
    for _, st in ipairs(hexStatuses) do
        if st == "fire" or st == "acid" or st == "decay" then
            return true
        end
    end
    return false
end

-- Множитель урона от статусов
function status.getDamageMultiplier(entity)
    if status.hasEntityStatus(entity, "acid") then
        return 2.0
    end
    return 1.0
end

-- Ранение: true для неп-противников со здоровьем меньше максимального
function status.isWounded(entity)
    if not entity or entity.isPlayable then return false end
    if not entity:isCharacter() then return false end
    if entity.health <= 0 then return false end
    return entity.health < entity.maxHealth
end

function status.initHexStatuses(loadedStatuses)
    status.hexStatuses = loadedStatuses or {}
end

-- Копирование статусов сущности
function status.copyEntityStatuses(entity)
    local copy = {}
    local sts = status.entityStatuses[entity]
    if sts then
        for _, v in ipairs(sts) do
            table.insert(copy, v)
        end
    end
    return copy
end

-- Установка статусов сущности (очищает текущие)
function status.setEntityStatuses(entity, statuses)
    status.entityStatuses[entity] = nil
    for _, st in ipairs(statuses) do
        status.applyToEntity(entity, st)
    end
end

-- Хранилище выкопок: ключ "q,r" -> { timer = 0, age = 0, spawnType = nil }
local digSites = {}

-- Установить выкопку на клетку
function status.setDigSite(q, r, timer, spawnType)
    local key = q .. "," .. r
    digSites[key] = { timer = timer or 1, age = 0, spawnType = spawnType }
end

-- Удалить выкопку
function status.removeDigSite(q, r)
    local key = q .. "," .. r
    digSites[key] = nil
end

-- Проверить наличие выкопки
function status.hasDigSite(q, r)
    local key = q .. "," .. r
    return digSites[key] ~= nil
end

-- Получить все выкопки (список {q, r, timer, age})
function status.getAllDigSites()
    local sites = {}
    for key, data in pairs(digSites) do
        local q, r = key:match("(.-),(.*)")
        table.insert(sites, { q = tonumber(q), r = tonumber(r), timer = data.timer, age = data.age, spawnType = data.spawnType })
    end
    return sites
end

-- Увеличить возраст всех выкопок, удалить если age >= 3
function status.ageDigSites()
    for key, data in pairs(digSites) do
        data.age = data.age + 1
        if data.age >= 3 then
            digSites[key] = nil
        end
    end
end

-- Уменьшить таймер у всех выкопок (вызывать в конце хода)
-- Возвращает список выкопок, у которых timer стал 0 (готовы к спавну)
function status.decrementDigTimers()
    local ready = {}
    for key, data in pairs(digSites) do
        data.timer = data.timer - 1
        if data.timer <= 0 then
            local q, r = key:match("(.-),(.*)")
            table.insert(ready, { q = tonumber(q), r = tonumber(r), data = data })
        end
    end
    return ready
end

-- При наступании на выкопку: урон + откладывание (увеличиваем таймер, сбрасываем возраст)
function status.stepOnDigSite(q, r)
    local key = q .. "," .. r
    local site = digSites[key]
    if site then
        site.timer = site.timer + 1   -- откладываем на следующий ход
        site.age = 0                  -- сбрасываем старение
        return true
    end
    return false
end

-- Очистить все выкопки (при рестарте)
function status.clearAllDigSites()
    digSites = {}
end

return status