-- status.lua
-- Managing statuses on hexes and on entities
local status = {}
local log = require("util.log")

-- Status storage tables
status.hexStatuses = {}      -- key "q,r" -> list of statuses
status.entityStatuses = {}   -- entity -> list of statuses

-- Mapping GIDs from Tiled to status types
status.gidToStatus = {
    [41] = "fire",
    [32] = "acid",
    [42] = "decay",   -- if there is a GID for decay in the map
}

-- Apply status to a hex
function status.applyToHex(q, r, statusType, hex)  -- added hex parameter (optional)
    if hex and not hex:isActiveHex(q, r) then return end  -- do not apply status to inactive cells
    local key = q .. "," .. r
    if not status.hexStatuses[key] then
        status.hexStatuses[key] = {}
    end
    for _, st in ipairs(status.hexStatuses[key]) do
        if st == statusType then return end
    end
    table.insert(status.hexStatuses[key], statusType)
end

-- Remove status from a hex
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

-- Get statuses on a hex
function status.getAtHex(q, r)
    if q == nil or r == nil then
        log.error("status", "getAtHex called with nil q or r", q, r, debug.traceback())
        return {}
    end
    local key = q .. "," .. r
    return status.hexStatuses[key] or {}
end

-- Check if a status is present on a hex
function status.hasAtHex(q, r, statusType)
    local hexStatuses = status.getAtHex(q, r)
    for _, st in ipairs(hexStatuses) do
        if st == statusType then return true end
    end
    return false
end

-- Apply status to an entity
function status.applyToEntity(entity, statusType)
    if not status.entityStatuses[entity] then
        status.entityStatuses[entity] = {}
    end
    for _, st in ipairs(status.entityStatuses[entity]) do
        if st == statusType then return end
    end
    table.insert(status.entityStatuses[entity], statusType)
    log.infof("status", "%s got %s debuff!", entity.name, statusType)
end

-- Remove status from an entity
function status.removeFromEntity(entity, statusType)
    if status.entityStatuses[entity] then
        for i, st in ipairs(status.entityStatuses[entity]) do
            if st == statusType then
                table.remove(status.entityStatuses[entity], i)
                log.infof("status", "%s lost %s debuff", entity.name, statusType)
                break
            end
        end
        if #status.entityStatuses[entity] == 0 then
            status.entityStatuses[entity] = nil
        end
    end
end

-- Check if an entity has a status
function status.hasEntityStatus(entity, statusType)
    if not status.entityStatuses[entity] then return false end
    for _, st in ipairs(status.entityStatuses[entity]) do
        if st == statusType then return true end
    end
    return false
end

-- Get all statuses of an entity
function status.getEntityStatuses(entity)
    return status.entityStatuses[entity] or {}
end

-- Check for negative statuses on a hex (fire, acid, decay)
function status.hasNegativeHexStatus(q, r)
    local hexStatuses = status.getAtHex(q, r)
    for _, st in ipairs(hexStatuses) do
        if st == "fire" or st == "acid" or st == "decay" then
            return true
        end
    end
    return false
end

-- Damage multiplier from statuses
function status.getDamageMultiplier(entity)
    if status.hasEntityStatus(entity, "acid") then
        return 2.0
    end
    return 1.0
end

-- Wounded: true for non-player characters with health below maximum
function status.isWounded(entity)
    if not entity or entity.isPlayable then return false end
    if not entity:isCharacter() then return false end
    if entity.health <= 0 then return false end
    return entity.health < entity.maxHealth
end

function status.initHexStatuses(loadedStatuses)
    status.hexStatuses = loadedStatuses or {}
end

-- Copy entity statuses
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

-- Set entity statuses (clears current ones)
function status.setEntityStatuses(entity, statuses)
    status.entityStatuses[entity] = nil
    for _, st in ipairs(statuses) do
        status.applyToEntity(entity, st)
    end
end

-- Dig site storage: key "q,r" -> { timer = 0, age = 0, spawnType = nil }
local digSites = {}

-- Set a dig site on a cell
function status.setDigSite(q, r, timer, spawnType)
    local key = q .. "," .. r
    digSites[key] = { timer = timer or 1, age = 0, spawnType = spawnType }
end

-- Remove a dig site
function status.removeDigSite(q, r)
    local key = q .. "," .. r
    digSites[key] = nil
end

-- Check if a dig site exists
function status.hasDigSite(q, r)
    local key = q .. "," .. r
    return digSites[key] ~= nil
end

-- Get all dig sites (list {q, r, timer, age})
function status.getAllDigSites()
    local sites = {}
    for key, data in pairs(digSites) do
        local q, r = key:match("(.-),(.*)")
        table.insert(sites, { q = tonumber(q), r = tonumber(r), timer = data.timer, age = data.age, spawnType = data.spawnType })
    end
    return sites
end

-- Increase age of all dig sites, remove if age >= 3
function status.ageDigSites()
    for key, data in pairs(digSites) do
        data.age = data.age + 1
        if data.age >= 3 then
            digSites[key] = nil
        end
    end
end

-- Decrement timer on all dig sites (call at end of turn)
-- Returns a list of dig sites whose timer reached 0 (ready to spawn)
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

-- When stepping on a dig site: damage + delay (increase timer, reset age)
function status.stepOnDigSite(q, r)
    local key = q .. "," .. r
    local site = digSites[key]
    if site then
        site.timer = site.timer + 1   -- delay to next turn
        site.age = 0                  -- reset aging
        return true
    end
    return false
end

-- Clear all dig sites (on restart)
function status.clearAllDigSites()
    digSites = {}
end

-- Save dig sites for undo snapshot
function status.saveDigSites()
    local saved = {}
    for key, data in pairs(digSites) do
        saved[key] = { timer = data.timer, age = data.age, spawnType = data.spawnType }
    end
    return saved
end

-- Restore dig sites from undo snapshot
function status.restoreDigSites(saved)
    digSites = {}
    if saved then
        for key, data in pairs(saved) do
            digSites[key] = { timer = data.timer, age = data.age, spawnType = data.spawnType }
        end
    end
end

return status
