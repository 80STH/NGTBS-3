-- water_gen.lua
-- Pure water-body generation: exactly one contiguous blob starting on the map edge.
-- All grid access is injected so this runs without love (see tests/water_gen_test.lua).

local water_gen = {}

-- params:
--   edgeCells    = {{q,r}, ...} — cells on the map border
--   isActive     = function(q, r) -> bool
--   getNeighbors = function(q, r) -> {{q=..., r=...}, ...}
--   target       = desired blob size
--   random       = function() -> float in [0,1)
-- returns: {{q,r}, ...} — water cells; contiguous, first cell is an edge cell.
function water_gen.growBlob(params)
    local start = params.edgeCells[math.floor(params.random() * #params.edgeCells) + 1]
    local cells = {start}
    local visited = {[start[1] .. "," .. start[2]] = true}
    local queue = {start}
    while #queue > 0 and #cells < params.target do
        local idx = math.floor(params.random() * #queue) + 1
        local cur = queue[idx]
        local found = false
        for _, nb in ipairs(params.getNeighbors(cur[1], cur[2])) do
            local nk = nb.q .. "," .. nb.r
            if not visited[nk] and params.isActive(nb.q, nb.r) then
                visited[nk] = true
                table.insert(cells, {nb.q, nb.r})
                table.insert(queue, {nb.q, nb.r})
                found = true
                if #cells >= params.target then break end
            end
        end
        if not found then table.remove(queue, idx) end
    end
    return cells
end

return water_gen
