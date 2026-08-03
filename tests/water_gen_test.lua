-- tests/water_gen_test.lua
-- Тесты для генератора водного массива: ровно один связный массив, касающийся края.

local water_gen = require("grid.water_gen")

-- Квадратная карта 0..4 x 0..4 (для теста достаточно 4 соседей).
local function makeGrid()
    local isActive = function(q, r)
        return q >= 0 and q <= 4 and r >= 0 and r <= 4
    end
    local function getNeighbors(q, r)
        return {
            {q = q + 1, r = r}, {q = q - 1, r = r},
            {q = q, r = r + 1}, {q = q, r = r - 1},
        }
    end
    local edgeCells = {}
    for q = 0, 4 do
        for r = 0, 4 do
            for _, nb in ipairs(getNeighbors(q, r)) do
                if not isActive(nb.q, nb.r) then
                    edgeCells[#edgeCells + 1] = {q, r}
                    break
                end
            end
        end
    end
    return { isActive = isActive, getNeighbors = getNeighbors, edgeCells = edgeCells }
end

local function isEdgeCell(grid, q, r)
    for _, nb in ipairs(grid.getNeighbors(q, r)) do
        if not grid.isActive(nb.q, nb.r) then return true end
    end
    return false
end

local function run(grid, target, seed)
    math.randomseed(seed)
    local cells = water_gen.growBlob({
        edgeCells = grid.edgeCells,
        isActive = grid.isActive,
        getNeighbors = grid.getNeighbors,
        target = target,
        random = math.random,
    })
    return cells
end

local function assertTrue(cond, msg)
    if cond then return true end
    return false, msg or "assert failed"
end

local suite = {
    name = "water_gen",
    tests = {
        {
            name = "grows to exactly the target size",
            fn = function()
                local grid = makeGrid()
                local cells = run(grid, 12, 1)
                return assertTrue(#cells == 12, "expected 12 cells, got " .. #cells)
            end,
        },
        {
            name = "blob touches the map edge (starts on an edge cell)",
            fn = function()
                local grid = makeGrid()
                local cells = run(grid, 12, 7)
                local start = cells[1]
                return assertTrue(isEdgeCell(grid, start[1], start[2]),
                    "start cell " .. start[1] .. "," .. start[2] .. " is not on the edge")
            end,
        },
        {
            name = "blob is contiguous and has no duplicates",
            fn = function()
                local grid = makeGrid()
                local cells = run(grid, 15, 3)
                local seen = {}
                for _, c in ipairs(cells) do
                    local key = c[1] .. "," .. c[2]
                    if seen[key] then
                        return false, "duplicate cell " .. key
                    end
                    seen[key] = true
                end
                -- BFS от старта по множеству клеток: должны дойти до всех.
                local stack = {cells[1]}
                local reached = 0
                while #stack > 0 do
                    local cur = table.remove(stack)
                    local ck = cur[1] .. "," .. cur[2]
                    if seen[ck] then
                        seen[ck] = nil
                        reached = reached + 1
                        for _, nb in ipairs(grid.getNeighbors(cur[1], cur[2])) do
                            local nk = nb.q .. "," .. nb.r
                            if seen[nk] then table.insert(stack, {nb.q, nb.r}) end
                        end
                    end
                end
                return assertTrue(reached == #cells, "contiguity broken: reached " .. reached .. " of " .. #cells)
            end,
        },
        {
            name = "target larger than map returns all active cells",
            fn = function()
                local grid = makeGrid()
                local cells = run(grid, 999, 5)
                return assertTrue(#cells == 25, "expected 25 cells, got " .. #cells)
            end,
        },
        {
            name = "target 1 returns single edge cell",
            fn = function()
                local grid = makeGrid()
                local cells = run(grid, 1, 11)
                return assertTrue(#cells == 1 and isEdgeCell(grid, cells[1][1], cells[1][2]),
                    "expected single edge cell")
            end,
        },
    },
}

return suite
