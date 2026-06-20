-- src/content/statuses.lua
-- Status system. Hex statuses live here; entity statuses live on entity.statuses.
-- A registry of status types with optional callbacks makes adding new ones trivial.
--
-- Callbacks (all optional):
--   onHexEnter(hex, q, r, entity, ctx)        -- entity steps onto a hex with this status
--   onHexTurnEnd(grid, q, r, entities, ctx)   -- end of host turn for hex status
--   onEntityTurnEnd(entity, ctx)              -- end of turn for entity status
--   modifyMoveRange(entity, range) -> range   -- alter movement points
--   blocksMove(entity) -> bool                -- entity may not move (root)

local statuses = {}

-- registry of definitions
statuses.defs = {}

function statuses.define(id, def)
    def.id = id
    statuses.defs[id] = def
end

function statuses.get(id) return statuses.defs[id] end

-- ---- hex status store ----
statuses.hexes = {}   -- "q,r" -> list of { type=, data= }

local function key(q, r) return q .. "," .. r end

function statuses.applyToHex(q, r, stype, data)
    local k = key(q, r)
    statuses.hexes[k] = statuses.hexes[k] or {}
    for _, s in ipairs(statuses.hexes[k]) do
        if s.type == stype then return false end
    end
    table.insert(statuses.hexes[k], { type = stype, data = data or {} })
    return true
end

function statuses.removeFromHex(q, r, stype)
    local k = key(q, r)
    local list = statuses.hexes[k]
    if not list then return end
    for i, s in ipairs(list) do
        if s.type == stype then table.remove(list, i) break end
    end
    if #list == 0 then statuses.hexes[k] = nil end
end

function statuses.getAtHex(q, r) return statuses.hexes[key(q, r)] or {} end

function statuses.hasAtHex(q, r, stype)
    for _, s in ipairs(statuses.getAtHex(q, r)) do
        if s.type == stype then return true end
    end
    return false
end

function statuses.hasNegativeHex(q, r)
    for _, s in ipairs(statuses.getAtHex(q, r)) do
        if s.type == "fire" or s.type == "acid" or s.type == "decay" then return true end
    end
    return false
end

function statuses.clearHexes() statuses.hexes = {} end

-- entity status convenience (delegates to entity)
function statuses.applyToEntity(entity, stype, data) return entity:applyStatus(stype, data) end
function statuses.removeFromEntity(entity, stype) return entity:removeStatus(stype) end
function statuses.hasEntityStatus(entity, stype) return entity:hasStatus(stype) end

-- movement modifiers
function statuses.modifyMoveRange(entity, baseRange)
    local r = baseRange
    for _, s in ipairs(entity.statuses) do
        local def = statuses.defs[s.type]
        if def and def.modifyMoveRange then r = def.modifyMoveRange(entity, r) end
    end
    return math.max(0, r)
end

function statuses.blocksMove(entity)
    for _, s in ipairs(entity.statuses) do
        local def = statuses.defs[s.type]
        if def and def.blocksMove and def.blocksMove(entity) then return true end
    end
    return false
end

-- ---- turn ticking ----
-- tick hex statuses for a given grid + entities. ctx holds callbacks (onChaos, onSpawn, etc.)
function statuses.tickHexes(grid, entities, ctx)
    ctx = ctx or {}
    -- group entities by cell
    local byCell = {}
    for _, e in ipairs(entities) do
        if e:isAlive() then
            local k = key(e.q, e.r)
            byCell[k] = byCell[k] or {}
            table.insert(byCell[k], e)
        end
    end
    for k, list in pairs(statuses.hexes) do
        local q, r = k:match("(-?%d+),(-?%d+)")
        q = tonumber(q); r = tonumber(r)
        local occ = byCell[k] or {}
        for i = #list, 1, -1 do
            local s = list[i]
            local def = statuses.defs[s.type]
            if def and def.onHexTurnEnd then def.onHexTurnEnd(grid, q, r, occ, ctx, s.data) end
            -- age / expire
            if s.data and s.data.duration then
                s.data.duration = s.data.duration - 1
                if s.data.duration <= 0 then table.remove(list, i) end
            end
        end
        if #list == 0 then statuses.hexes[k] = nil end
    end
end

function statuses.tickEntities(entities, ctx)
    ctx = ctx or {}
    for _, e in ipairs(entities) do
        if e:isAlive() then
            for i = #e.statuses, 1, -1 do
                local s = e.statuses[i]
                local def = statuses.defs[s.type]
                if def and def.onEntityTurnEnd then def.onEntityTurnEnd(e, ctx, s.data) end
                if s.data and s.data.duration then
                    s.data.duration = s.data.duration - 1
                    if s.data.duration <= 0 then table.remove(e.statuses, i) end
                end
            end
        end
    end
end

-- ---- dig sites ----
statuses.digSites = {}  -- "q,r" -> { timer=, age=, spawn= }

function statuses.setDigSite(q, r, timer, spawn)
    statuses.digSites[key(q, r)] = { timer = timer or 2, age = 0, spawn = spawn }
end
function statuses.removeDigSite(q, r) statuses.digSites[key(q, r)] = nil end
function statuses.hasDigSite(q, r) return statuses.digSites[key(q, r)] ~= nil end
function statuses.clearAllDigSites() statuses.digSites = {} end
function statuses.getAllDigSites()
    local out = {}
    for k, d in pairs(statuses.digSites) do
        local q, r = k:match("(-?%d+),(-?%d+)")
        table.insert(out, { q = tonumber(q), r = tonumber(r), timer = d.timer, age = d.age, spawn = d.spawn })
    end
    return out
end
-- decrement timers; return list of cells ready to spawn
function statuses.decrementDigTimers()
    local ready = {}
    for k, d in pairs(statuses.digSites) do
        d.timer = d.timer - 1
        if d.timer <= 0 then
            local q, r = k:match("(-?%d+),(-?%d+)")
            table.insert(ready, { q = tonumber(q), r = tonumber(r), spawn = d.spawn })
            statuses.digSites[k] = nil
        end
    end
    return ready
end
function statuses.stepOnDigSite(q, r)
    local d = statuses.digSites[key(q, r)]
    if d then d.timer = d.timer + 1; d.age = 0; return true end
    return false
end
function statuses.ageDigSites()
    for k, d in pairs(statuses.digSites) do
        d.age = d.age + 1
        if d.age >= 4 then statuses.digSites[k] = nil end
    end
end

function statuses.reset()
    statuses.hexes = {}
    statuses.digSites = {}
end

-- ========================================================================
-- Built-in status definitions
-- ========================================================================

-- Fire: damages entities on the cell at end of enemy turn.
statuses.define("fire", {
    color = { 1, 0.45, 0.1 },
    onHexTurnEnd = function(grid, q, r, occ, ctx, data)
        for _, e in ipairs(occ) do
            if e:isAlive() and not e.flying then
                local died = e:takeDamage(1, ctx)
                if died then e:startDeath() end
            end
        end
    end,
})

-- Acid: entities on the cell gain the "acid" entity status (any damage lethal).
statuses.define("acid", {
    color = { 0.6, 1, 0.2 },
    onHexTurnEnd = function(grid, q, r, occ, ctx, data)
        for _, e in ipairs(occ) do
            if e:isAlive() then e:applyStatus("acid") end
        end
    end,
})

-- Decay: a marker that ages; contributes to chaos each turn (via ctx.onChaos).
statuses.define("decay", {
    color = { 0.5, 0.3, 0.5 },
    onHexTurnEnd = function(grid, q, r, occ, ctx, data)
        if ctx.onChaos then ctx.onChaos(1) end
    end,
})

-- Root (entity): cannot move.
statuses.define("root", {
    color = { 0.5, 0.3, 0.15 },
    blocksMove = function(entity) return true end,
})

-- Slow (entity): -1 move range.
statuses.define("slow", {
    color = { 0.3, 0.5, 0.9 },
    modifyMoveRange = function(entity, range) return range - 1 end,
})

-- Empowered (entity): next attack deals +2 damage, then consumed by the attack.
statuses.define("empowered", {
    color = { 1, 0.85, 0.2 },
})

return statuses
