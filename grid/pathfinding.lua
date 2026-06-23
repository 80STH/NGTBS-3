local pathfinding = {}

local function key(q, r) return q .. "," .. r end

function pathfinding.findPath(startQ, startR, targetQ, targetR, maxSteps, isBlocked, hex, isOccupied)
    if startQ == targetQ and startR == targetR then
        return {}
    end

    local OCCUPIED_PENALTY = 100
    local queue = {{q = startQ, r = startR, cost = 0, occupiedCount = 0, parent = nil}}
    local visited = { [key(startQ, startR)] = 0 }

    while #queue > 0 do
        local bestIdx = 1
        local bestCost = queue[1].cost
        for i = 2, #queue do
            if queue[i].cost < bestCost then
                bestCost = queue[i].cost
                bestIdx = i
            end
        end
        local current = queue[bestIdx]
        queue[bestIdx] = queue[#queue]
        queue[#queue] = nil

        local pathLen = 0
        local node = current
        while node.parent do
            pathLen = pathLen + 1
            node = node.parent
        end

        if maxSteps and pathLen >= maxSteps then
            goto continue
        end

        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, nb in ipairs(neighbors) do
            local nbKey = key(nb.q, nb.r)
            if not isBlocked(nb.q, nb.r) then
                local cellOccupied = isOccupied and isOccupied(nb.q, nb.r)
                local newOccupiedCount = current.occupiedCount + (cellOccupied and 1 or 0)
                local newCost = pathLen + 1 + newOccupiedCount * OCCUPIED_PENALTY
                local prevCost = visited[nbKey]
                if not prevCost or newCost < prevCost then
                    local valid = hex:isValidHex(nb.q, nb.r)
                    if valid and hex.isActiveHex then
                        valid = hex:isActiveHex(nb.q, nb.r)
                    end
                    if valid then
                        visited[nbKey] = newCost
                        if nb.q == targetQ and nb.r == targetR then
                            local result = {{q = nb.q, r = nb.r}}
                            local p = current
                            while p.parent do
                                table.insert(result, {q = p.q, r = p.r})
                                p = p.parent
                            end
                            local len = #result
                            for i = 1, math.floor(len / 2) do
                                result[i], result[len - i + 1] = result[len - i + 1], result[i]
                            end
                            return result
                        end
                        queue[#queue + 1] = {q = nb.q, r = nb.r, cost = newCost, occupiedCount = newOccupiedCount, parent = current}
                    end
                end
            end
        end
        ::continue::
    end
    return nil
end

return pathfinding
