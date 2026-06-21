-- pathfinding.lua
-- Pathfinding algorithm on a hexagonal grid (BFS)

local pathfinding = {}

--- BFS pathfinding with maximum length limit
-- @param startQ number    Starting coordinate q
-- @param startR number    Starting coordinate r
-- @param targetQ number   Target coordinate q
-- @param targetR number   Target coordinate r
-- @param maxSteps number|nil  Maximum path length (if nil – unlimited)
-- @param isBlocked function(q, r)  Returns true if the cell is impassable
-- @param hex object       Hex grid object (must have methods getNeighbors, isValidHex, optionally isActiveHex)
-- @return table|nil       Array of steps { {q, r}, ... } or nil if path not found
function pathfinding.findPath(startQ, startR, targetQ, targetR, maxSteps, isBlocked, hex)
    if startQ == targetQ and startR == targetR then
        return {}
    end

    local queue = {{q = startQ, r = startR, path = {}}}
    local visited = { [startQ .. "," .. startR] = true }

    while #queue > 0 do
        local current = table.remove(queue, 1)
        local currentPathLen = #current.path

        -- If step limit exceeded, don't expand further
        if maxSteps and currentPathLen >= maxSteps then
            goto continue
        end

        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, nb in ipairs(neighbors) do
            local key = nb.q .. "," .. nb.r
            if not visited[key] then
                -- Check cell validity and activity
                local valid = hex:isValidHex(nb.q, nb.r)
                if valid and hex.isActiveHex then
                    valid = hex:isActiveHex(nb.q, nb.r)
                end
                if valid and not isBlocked(nb.q, nb.r) then
                    visited[key] = true
                    local newPath = {}
                    for _, step in ipairs(current.path) do
                        table.insert(newPath, step)
                    end
                    table.insert(newPath, {q = nb.q, r = nb.r})
                    if nb.q == targetQ and nb.r == targetR then
                        return newPath
                    end
                    table.insert(queue, {q = nb.q, r = nb.r, path = newPath})
                end
            end
        end
        ::continue::
    end
    return nil
end

return pathfinding