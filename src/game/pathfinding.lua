-- src/game/pathfinding.lua
-- BFS reachability & paths over the hex grid, respecting terrain and occupants.

local terrain = require("src.content.terrain")

local pathfinding = {}

-- occupied map: "q,r" -> entity (excluding `mover` and hazards)
local function buildOcc(entities, mover)
    local occ = {}
    for _, e in ipairs(entities) do
        if e ~= mover and e:isAlive() and not e.isHazard then
            occ[e.q .. "," .. e.r] = e
        end
    end
    return occ
end

-- can `mover` stop/enter cell (q,r)? Used for destination legality.
local function canEnter(grid, ter, q, r, mover, occ)
    if not grid:isActiveHex(q, r) then return false end
    local t = ter[q .. "," .. r] or "grass"
    if not terrain.passable(t, mover) then return false end
    local o = occ[q .. "," .. r]
    if o then
        -- cannot stop on another entity, except phasing through enemies (handled in passability)
        return false
    end
    return true
end

-- can `mover` pass through cell (q,r) while moving (not stopping)?
local function canPass(grid, ter, q, r, mover, occ)
    if not grid:isActiveHex(q, r) then return false end
    local t = ter[q .. "," .. r] or "grass"
    if not terrain.passable(t, mover) then return false end
    if mover.flying then return true end  -- flying units pass over occupants
    local o = occ[q .. "," .. r]
    if o then
        if o.side == mover.side then return false end
        if mover.phaseThroughEnemies and o.side ~= mover.side then return true end
        return false
    end
    return true
end

-- BFS: returns a map "q,r" -> distance (in steps) of all reachable cells within range.
function pathfinding.reachable(grid, ter, entities, mover, range)
    local occ = buildOcc(entities, mover)
    local dist = { [mover.q .. "," .. mover.r] = 0 }
    local queue = { { q = mover.q, r = mover.r, d = 0 } }
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        if cur.d < range then
            for _, n in ipairs(grid:neighbors(cur.q, cur.r)) do
                local k = n.q .. "," .. n.r
                if dist[k] == nil and canPass(grid, ter, n.q, n.r, mover, occ) then
                    dist[k] = cur.d + 1
                    table.insert(queue, { q = n.q, r = n.r, d = cur.d + 1 })
                end
            end
        end
    end
    -- destinations: cells where the mover can actually stop
    local stops = {}
    for k, d in pairs(dist) do
        local q, r = k:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        if not (q == mover.q and r == mover.r) and canEnter(grid, ter, q, r, mover, occ) then
            stops[k] = d
        end
    end
    return stops, dist
end

-- Reconstruct a shortest path (list of {q,r}) from mover to (tq,tr) within range.
function pathfinding.pathTo(grid, ter, entities, mover, tq, tr, range)
    local occ = buildOcc(entities, mover)
    local prev = { [mover.q .. "," .. mover.r] = nil }
    local dist = { [mover.q .. "," .. mover.r] = 0 }
    local queue = { { q = mover.q, r = mover.r, d = 0 } }
    local head = 1
    local found = false
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        if cur.q == tq and cur.r == tr then found = true break end
        if cur.d < range then
            for _, n in ipairs(grid:neighbors(cur.q, cur.r)) do
                local k = n.q .. "," .. n.r
                if dist[k] == nil and canPass(grid, ter, n.q, n.r, mover, occ) then
                    dist[k] = cur.d + 1
                    prev[k] = cur.q .. "," .. cur.r
                    table.insert(queue, { q = n.q, r = n.r, d = cur.d + 1 })
                end
            end
        end
    end
    if not found then return nil end
    -- backtrack
    local path = {}
    local k = tq .. "," .. tr
    while k do
        local q, r = k:match("(-?%d+),(-?%d+)")
        table.insert(path, 1, { q = tonumber(q), r = tonumber(r) })
        k = prev[k]
    end
    return path
end

return pathfinding
