-- system/teleporters.lua
-- Teleporter cells: upper terrain "teleporter:<pairId>". Always exist in
-- pairs. When an entity lands on one, it swaps places with the entity
-- standing on the paired cell. Destroying one (terraforming spells like
-- Void) permanently disables the whole pair.

local teleporters = {}

local telePairs = {}   -- pairId -> { disabled = bool, cells = { {q,r}, {q,r} } }

function teleporters.reset()
    telePairs = {}
end

-- Rebuild the pair registry from the current upper terrain layer.
-- Exactly 2 portals per level: only the first complete pair is kept,
-- any extra teleporter markers are stripped.
function teleporters.scan(upperTerrainMap)
    telePairs = {}
    local byId = {}
    local allCells = {}
    for q, row in pairs(upperTerrainMap or {}) do
        for r, val in pairs(row) do
            local id = val:match("^teleporter:(%d+)$")
            if id then
                byId[id] = byId[id] or {}
                table.insert(byId[id], { q = q, r = r })
                table.insert(allCells, { q = q, r = r, id = id })
            end
        end
    end
    local firstPairId = nil
    for id, list in pairs(byId) do
        if #list == 2 then
            firstPairId = id
            break
        end
    end
    if firstPairId then
        telePairs[firstPairId] = { id = firstPairId, cells = byId[firstPairId], disabled = false }
    end
    -- Strip portals that are not part of the active pair
    for _, c in ipairs(allCells) do
        if c.id ~= firstPairId then
            upperTerrainMap[c.q][c.r] = nil
        end
    end
end

-- Returns pairId and the paired cell for a teleporter at (q, r), or nil.
-- Returns nil while the pair is on cooldown (1 turn, refreshed at the
-- start of the player's turn).
function teleporters.getCellInfo(q, r, upperTerrainMap)
    local utm = upperTerrainMap or _G.upperTerrainMap
    local val = utm and utm[q] and utm[q][r]
    local id = val and val:match("^teleporter:(%d+)$")
    if not id then return nil end
    local pair = telePairs[id]
    if not pair or pair.disabled or pair.cooldown then return nil end
    local other = nil
    for _, c in ipairs(pair.cells) do
        if c.q ~= q or c.r ~= r then
            other = c
            break
        end
    end
    if not other then return nil end
    -- Partner must still have its marker; otherwise the pair is dead
    if (utm[other.q] and utm[other.q][other.r]) ~= val then
        pair.disabled = true
        return nil
    end
    return id, other
end

-- Put the pair on cooldown (1 turn)
function teleporters.markUsed(id)
    local pair = telePairs[id]
    if pair then
        pair.cooldown = true
    end
end

-- Refresh cooldowns — called at the start of the player's turn
function teleporters.refresh()
    for _, pair in pairs(telePairs) do
        pair.cooldown = false
    end
end

-- Whether the map has a working teleporter pair
function teleporters.hasActivePair()
    for _, pair in pairs(telePairs) do
        if not pair.disabled then return true end
    end
    return false
end

-- All cells of active teleporter pairs (for hover hints)
function teleporters.getActiveCells()
    local cells = {}
    for _, pair in pairs(telePairs) do
        if not pair.disabled then
            for _, c in ipairs(pair.cells) do
                table.insert(cells, { q = c.q, r = c.r })
            end
        end
    end
    return cells
end

-- Destroy a teleporter (terraforming spells only). The pair is disabled
-- forever and the partner's marker is removed too.
function teleporters.destroy(q, r, upperTerrainMap)
    local utm = upperTerrainMap or _G.upperTerrainMap
    local val = utm and utm[q] and utm[q][r]
    local id = val and val:match("^teleporter:(%d+)$")
    if not id then return end
    local pair = telePairs[id]
    if not pair then return end
    pair.disabled = true
    for _, c in ipairs(pair.cells) do
        if utm[c.q] then
            utm[c.q][c.r] = nil
        end
    end
    return id
end

return teleporters
