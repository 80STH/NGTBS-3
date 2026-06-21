-- pathfinding.lua
-- Pathfinding algorithm on a hexagonal grid (BFS with occupancy penalty)

local pathfinding = {}

--- BFS pathfinding with maximum length limit and occupancy avoidance
-- @param startQ number    Starting coordinate q
-- @param startR number    Starting coordinate r
-- @param targetQ number   Target coordinate q
-- @param targetR number   Target coordinate r
-- @param maxSteps number|nil  Maximum path length (if nil – unlimited)
-- @param isBlocked function(q, r)  Returns true if the cell is impassable
-- @param hex object       Hex grid object (must have methods getNeighbors, isValidHex, optionally isActiveHex)
-- @param isOccupied function(q, r)|nil  Returns true if the cell is occupied by a passable unit (paths through occupied cells are deprioritized)
-- @return table|nil       Array of steps { {q, r}, ... } or nil if path not found
function pathfinding.findPath(startQ, startR, targetQ, targetR, maxSteps, isBlocked, hex, isOccupied)
    if startQ == targetQ and startR == targetR then
        return {}
    end

    -- Priority queue: lower cost = higher priority. Occupied cells add penalty.
    local OCCUPIED_PENALTY = 100
    local queue = {{q = startQ, r = startR, path = {}, cost = 0, occupiedCount = 0}}
    local visited = { [startQ .. "," .. startR] = 0 }

    while #queue > 0 do
        -- Find lowest-cost item (simple linear scan for small queues)
        local bestIdx = 1
        local bestCost = queue[1].cost
        for i = 2, #queue do
            if queue[i].cost < bestCost then
                bestCost = queue[i].cost
                bestIdx = i
            end
        end
        local current = table.remove(queue, bestIdx)
        local currentPathLen = #current.path

        -- If step limit exceeded, skip expansion (occupied cells don't count against limit)
        if maxSteps and currentPathLen >= maxSteps then
            goto continue
        end

        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, nb in ipairs(neighbors) do
            local key = nb.q .. "," .. nb.r
            local isBlockedCell = isBlocked(nb.q, nb.r)
            if not isBlockedCell then
                local cellOccupied = isOccupied and isOccupied(nb.q, nb.r)
                local newOccupiedCount = current.occupiedCount + (cellOccupied and 1 or 0)
                local newCost = currentPathLen + 1 + newOccupiedCount * OCCUPIED_PENALTY
                local prevCost = visited[key]
                if not prevCost or newCost < prevCost then
                    -- Check cell validity and activity
                    local valid = hex:isValidHex(nb.q, nb.r)
                    if valid and hex.isActiveHex then
                        valid = hex:isActiveHex(nb.q, nb.r)
                    end
                    if valid then
                        visited[key] = newCost
                        local newPath = {}
                        for _, step in ipairs(current.path) do
                            table.insert(newPath, step)
                        end
                        table.insert(newPath, {q = nb.q, r = nb.r})
                        if nb.q == targetQ and nb.r == targetR then
                            return newPath
                        end
                        table.insert(queue, {q = nb.q, r = nb.r, path = newPath, cost = newCost, occupiedCount = newOccupiedCount})
                    end
                end
            end
        end
        ::continue::
    end
    return nil
end

return pathfinding