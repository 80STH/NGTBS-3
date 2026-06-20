-- src/core/map.lua
-- Loads maps in the new Lua-table format (no Tiled).
--
-- Map file returns a table like:
--   {
--     name = "Crossroads",
--     radius = 4,            -- hex-shaped grid radius (if cells omitted)
--     size = 48,             -- hex pixel size (optional, default from config)
--     maxTurns = 12,
--     cells = { {q=,r=}, ... }              -- explicit active cells (optional)
--     terrain = { ["2,3"] = "grass", ... }  -- key "q,r" -> terrain id (default "grass")
--     entities = { { def="Warrior", q=, r=, side="ally" }, ... }
--     statuses = { { type="fire", q=, r= }, ... }
--     objective = "kill_all"  -- or a table spec; see objectives.lua
--   }
--
-- Missing terrain defaults to "grass". Cells outside `cells`/`radius` are inactive.

local map = {}

function map.load(path)
    local chunk = love.filesystem.load(path)
    if not chunk then error("Map not found: " .. path) end
    local data = chunk()
    if not data then error("Map returned nil: " .. path) end
    return data
end

-- Normalize a raw map table into a standardised structure.
function map.normalize(data)
    local out = {}
    out.name = data.name or "Untitled"
    out.size = data.size
    out.maxTurns = data.maxTurns or 12
    out.radius = data.radius or 4
    out.cells = data.cells          -- nil -> hex shape
    out.terrain = data.terrain or {}
    out.entities = data.entities or {}
    out.statuses = data.statuses or {}
    out.objective = data.objective or { type = "kill_all" }
    out.deployZone = data.deployZone   -- list of {q,r} where allies may be placed
    out.digSites = data.digSites        -- list of { q=, r=, timer=, spawn= }
    out.trains = data.trains            -- list of { path={ {q,r},... }, length=, isObjective= }
    return out
end

-- Build the active-cell list for a map.
function map.activeCells(data, hexmod)
    if data.cells then return data.cells end
    local list = {}
    for q = -data.radius, data.radius do
        for r = -data.radius, data.radius do
            if hexmod.distance(0, 0, q, r) <= data.radius then
                table.insert(list, { q = q, r = r })
            end
        end
    end
    return list
end

return map
