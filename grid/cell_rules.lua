-- cell_rules.lua
-- Single place for cell passability checks.
-- Previously there were 5 scattered variants (isPositionOccupied, isCellPassable,
-- isCellOccupiedForStop in main.lua; isCellPassableForEnemy, ui.isCellReachable
-- in ui.lua) with subtle differences. Now — one parameterized API.
--
-- Main functions:
--   cell_rules.isPassable(q, r, mover, opts)        — whether the cell can be PASSED THROUGH
--   cell_rules.isOccupiedForStop(q, r, mover, opts) — whether cell is occupied for STOPPING
--
-- opts (optional):
--   entities       — list of entities (default _G.entities)
--   terrainMap     — tile map (default _G.terrainMap)
--   hex            — hex grid object (default _G.hex)
--   passableSide   — "ally" | "enemy" | "none" — whose side is considered passable
--                    ("ally" for allies, "enemy" for enemies; default —
--                    side of mover)
--   allowPhaseThroughEnemies — whether to consider mover.phaseThroughEnemies (default true)
--   ignoreWater    — don't check water (for stopping)

local cell_rules = {}

local function defaultOpts(opts, mover)
    opts = opts or {}
    local function pick(key, globName)
        if opts[key] ~= nil then return opts[key] end
        return _G[globName]
    end
    return {
        entities   = pick("entities", "entities") or {},
        terrainMap = pick("terrainMap", "terrainMap"),
        hex        = pick("hex", "hex"),
        passableSide = opts.passableSide or (mover and mover.isPlayable and "ally" or "enemy"),
        allowPhaseThroughEnemies = (opts.allowPhaseThroughEnemies ~= false),
        ignoreWater = opts.ignoreWater or false,
    }
end

-- Same side as mover?
local function sameSide(e, mover, side)
    if not (e:isCharacter() and mover) then return false end
    if side == "ally" then
        return e.isPlayable == true and mover.isPlayable == true
    elseif side == "enemy" then
        return e.isPlayable == false and mover.isPlayable == false
    end
    return false
end

-- Whether the cell can be passed through (for movement/pathfinding).
function cell_rules.isPassable(q, r, mover, opts)
    local o = defaultOpts(opts, mover)
    local hex = o.hex
    if not hex or not hex:isActiveHex(q, r) then return false end

    if not o.ignoreWater then
        local terrain = o.terrainMap and o.terrainMap[q] and o.terrainMap[q][r] or "grass"
        if terrain == "water" then
            if mover and (mover.waterWalker or mover.flying or mover.hovering) then
                -- ok
            else
                return false
            end
        end
    end

    -- Flying ignores everything on the ground
    if mover and mover.flying then
        return true
    end

    for _, e in ipairs(o.entities) do
        if e ~= mover and e.q == q and e.r == r and not e.isHazard then
            if not sameSide(e, mover, o.passableSide) then
                -- phaseThroughEnemies: can pass through enemies (but not allies)
                if o.allowPhaseThroughEnemies and mover and mover.phaseThroughEnemies
                   and e:isCharacter() and not e.isPlayable then
                    -- skip
                else
                    return false
                end
            end
        end
    end
    return true
end

-- Whether cell is occupied for stopping (ignoring phaseThroughEnemies and water).
function cell_rules.isOccupiedForStop(q, r, mover, opts)
    local o = defaultOpts(opts, mover)
    local hex = o.hex
    if not hex or not hex:isActiveHex(q, r) then return true end
    for _, e in ipairs(o.entities) do
        if e ~= mover and e.q == q and e.r == r and not e.isHazard then
            return true
        end
    end
    return false
end

-- Universal "is cell occupied" (with water and phaseThroughEnemies).
-- Corresponds to old isPositionOccupied.
function cell_rules.isOccupied(q, r, mover, opts)
    local o = defaultOpts(opts, mover)
    local hex = o.hex
    if not hex or not hex:isActiveHex(q, r) then return true end

    if o.terrainMap and o.terrainMap[q] and o.terrainMap[q][r] then
        local terrain = o.terrainMap[q][r]
        if terrain == "water" then
            if mover and (mover.waterWalker or mover.flying or mover.hovering) then
                -- ok
            else
                return true
            end
        end
    end

    for _, e in ipairs(o.entities) do
        if e ~= mover and e.q == q and e.r == r and not e.isHazard then
            if not sameSide(e, mover, o.passableSide) then
                if o.allowPhaseThroughEnemies and mover and mover.phaseThroughEnemies
                   and e:isCharacter() and not e.isPlayable then
                    -- skip
                else
                    return true
                end
            end
        end
    end
    return false
end

return cell_rules
