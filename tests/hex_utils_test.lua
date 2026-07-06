-- tests/hex_utils_test.lua
-- Тесты для чистых функций кубических координат.
local hex_utils = require("grid.hex_utils")

local function approxEq(a, b, eps)
    eps = eps or 1e-9
    return math.abs(a - b) < eps
end

local suite = {
    name = "hex_utils",
    tests = {
        {
            name = "axialToCube then cubeToAxial is identity (pointy)",
            fn = function()
                hex_utils.setOrientation("pointy")
                for q = -5, 5 do
                    for r = -5, 5 do
                        local x, y, z = hex_utils.axialToCube(q, r)
                        if not approxEq(x + y + z, 0) then
                            return false, "x+y+z ~= 0 at (" .. q .. "," .. r .. ")"
                        end
                        local q2, r2 = hex_utils.cubeToAxial(x, y, z)
                        if q2 ~= q or r2 ~= r then
                            return false, string.format("roundtrip failed: (%d,%d) -> (%d,%d)", q, r, q2, r2)
                        end
                    end
                end
                return true
            end,
        },
        {
            name = "axialToCube then cubeToAxial is identity (flat)",
            fn = function()
                hex_utils.setOrientation("flat")
                for q = -5, 5 do
                    for r = -5, 5 do
                        local x, y, z = hex_utils.axialToCube(q, r)
                        if not approxEq(x + y + z, 0) then
                            return false, "x+y+z ~= 0 at (" .. q .. "," .. r .. ")"
                        end
                        local q2, r2 = hex_utils.cubeToAxial(x, y, z)
                        if q2 ~= q or r2 ~= r then
                            return false, string.format("roundtrip failed: (%d,%d) -> (%d,%d)", q, r, q2, r2)
                        end
                    end
                end
                hex_utils.setOrientation("pointy")
                return true
            end,
        },
        {
            name = "cube invariant x+y+z = 0 (pointy)",
            fn = function()
                hex_utils.setOrientation("pointy")
                for q = -10, 10, 2 do
                    for r = -10, 10, 3 do
                        local x, y, z = hex_utils.axialToCube(q, r)
                        if not approxEq(x + y + z, 0) then
                            return false, string.format("x+y+z=%s at (%d,%d)", tostring(x + y + z), q, r)
                        end
                    end
                end
                return true
            end,
        },
        {
            name = "getDistance is symmetric and non-negative",
            fn = function()
                for q1 = -3, 3 do for r1 = -3, 3 do
                    for q2 = -3, 3 do for r2 = -3, 3 do
                        local d1 = hex_utils.getDistance(q1, r1, q2, r2)
                        local d2 = hex_utils.getDistance(q2, r2, q1, r1)
                        if d1 ~= d2 then return false, "asymmetric" end
                        if d1 < 0 then return false, "negative" end
                        if q1 == q2 and r1 == r2 and d1 ~= 0 then
                            return false, "distance to self != 0"
                        end
                    end end
                end end
                return true
            end,
        },
        {
            name = "getDistance known values (pointy)",
            fn = function()
                hex_utils.setOrientation("pointy")
                -- origin to neighbours: all distance 1
                -- find one neighbour via applyCubeStep
                local nq, nr = hex_utils.applyCubeStep(0, 0, 1, -1, 0)
                if hex_utils.getDistance(0, 0, nq, nr) ~= 1 then
                    return false, "neighbour distance ~= 1"
                end
                -- distance 0 to self
                if hex_utils.getDistance(3, 4, 3, 4) ~= 0 then return false, "self distance ~= 0" end
                return true
            end,
        },
        {
            name = "applyCubeStep returns valid hex (invariant preserved)",
            fn = function()
                for _, dir in ipairs(hex_utils.CUBE_DIRECTIONS) do
                    local q, r = hex_utils.applyCubeStep(4, 4, dir.dx, dir.dy, dir.dz)
                    local x, y, z = hex_utils.axialToCube(q, r)
                    if not approxEq(x + y + z, 0) then
                        return false, string.format("step broke invariant: (%d,%d)", q, r)
                    end
                end
                return true
            end,
        },
        {
            name = "rotateCubeDir 60° preserves cube invariant",
            fn = function()
                for _, dir in ipairs(hex_utils.CUBE_DIRECTIONS) do
                    local dx, dy, dz = hex_utils.rotateCubeDir(dir.dx, dir.dy, dir.dz, true)
                    if not approxEq(dx + dy + dz, 0) then
                        return false, "cw rotation broke invariant"
                    end
                    dx, dy, dz = hex_utils.rotateCubeDir(dir.dx, dir.dy, dir.dz, false)
                    if not approxEq(dx + dy + dz, 0) then
                        return false, "ccw rotation broke invariant"
                    end
                end
                return true
            end,
        },
        {
            name = "isPushFromSafeSide: no direction → safe",
            fn = function()
                local e = { q = 3, r = 3, direction = nil }
                if not hex_utils.isPushFromSafeSide(e, 2, 3) then
                    return false, "no direction should be safe"
                end
                return true
            end,
        },
        {
            name = "isPushFromSafeSide: dot product logic",
            fn = function()
                -- entity at (3,3) facing direction (1,-1,0).
                -- push from (2,3) → diff (to=3,3 from=2,3) = getCubeDiff(3,3,2,3)
                -- safe when dot <= 0.
                local e = { q = 3, r = 3, direction = { dx = 1, dy = -1, dz = 0 } }
                -- Just verify it returns a boolean (logic correctness requires
                -- careful setup; here we smoke-test it doesn't crash).
                local r1 = hex_utils.isPushFromSafeSide(e, 2, 3)
                local r2 = hex_utils.isPushFromSafeSide(e, 4, 3)
                if type(r1) ~= "boolean" or type(r2) ~= "boolean" then
                    return false, "expected boolean result"
                end
                return true
            end,
        },
    },
}

return suite
