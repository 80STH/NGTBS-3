-- tests/cell_rules_test.lua
-- Тесты для параметризованной проходимости.
-- Использует моки для hex/terrainMap/entities — без зависимости от love.

local cell_rules = require("grid.cell_rules")

-- Мок гексагональной сетки: активны клетки в квадрате 0..4.
local function makeHexMock()
    return {
        isActiveHex = function(self, q, r)
            return q >= 0 and q <= 4 and r >= 0 and r <= 4
        end,
        -- прочие методы не вызываются в cell_rules
    }
end

-- Мок сущности-персонажа.
local function makeChar(q, r, isPlayable)
    return {
        q = q, r = r, isPlayable = isPlayable,
        isCharacter = function() return true end,
    }
end

-- Мок сущности-препятствия.
local function makeObstacle(q, r)
    return {
        q = q, r = r, isPlayable = false,
        isCharacter = function() return false end,
    }
end

local function assertEq(got, expected, msg)
    if got ~= expected then
        return false, string.format("%s: expected %s, got %s", msg or "?", tostring(expected), tostring(got))
    end
    return true
end

local suite = {
    name = "cell_rules",
    tests = {
        {
            name = "isPassable: grass empty cell → passable",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "grass" } }
                local mover = makeChar(1, 2, true)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                return assertEq(ok, true, "grass should be passable")
            end,
        },
        {
            name = "isPassable: out of bounds → not passable",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(2, 2, true)
                local ok = cell_rules.isPassable(99, 99, mover, {
                    entities = {}, terrainMap = {}, hex = hex,
                })
                return assertEq(ok, false, "out of bounds")
            end,
        },
        {
            name = "isPassable: water blocks ground unit",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "water" } }
                local mover = makeChar(1, 2, true)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                return assertEq(ok, false, "water blocks ground unit")
            end,
        },
        {
            name = "isPassable: water passable for hovering",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "water" } }
                local mover = makeChar(1, 2, true)
                mover.hovering = true
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                return assertEq(ok, true, "hovering ignores water")
            end,
        },
        {
            name = "isPassable: emptiness blocks ground unit",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "emptiness" } }
                local mover = makeChar(1, 2, true)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                return assertEq(ok, false, "emptiness blocks ground unit")
            end,
        },
        {
            name = "isPassable: emptiness passable ONLY for hovering",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "emptiness" } }
                local hover = makeChar(1, 2, true)
                hover.hovering = true
                local okHover = cell_rules.isPassable(2, 2, hover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                local walker = makeChar(1, 2, true)
                walker.waterWalker = true
                local okWalker = cell_rules.isPassable(2, 2, walker, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                if okHover ~= true then return false, "hovering should cross emptiness" end
                return assertEq(okWalker, false, "waterWalker must NOT cross emptiness")
            end,
        },
        {
            name = "isOccupied: emptiness occupied for ground, free for hovering",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "emptiness" } }
                local mover = makeChar(1, 2, true)
                local occ = cell_rules.isOccupied(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                local hover = makeChar(1, 2, true)
                hover.hovering = true
                local free = cell_rules.isOccupied(2, 2, hover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                if occ ~= true then return false, "ground unit counts emptiness as occupied" end
                return assertEq(free, false, "hovering ignores emptiness")
            end,
        },
        {
            name = "isPassable: same-side character passable",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                local ally = makeChar(2, 2, true)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = { ally }, terrainMap = {}, hex = hex,
                    passableSide = "ally",
                })
                return assertEq(ok, true, "ally can pass through ally")
            end,
        },
        {
            name = "isPassable: enemy blocks ally (default side)",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                local enemy = makeChar(2, 2, false)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = { enemy }, terrainMap = {}, hex = hex,
                })
                return assertEq(ok, false, "enemy blocks ally")
            end,
        },
        {
            name = "isPassable: phaseThroughEnemies lets ally pass enemy",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                mover.phaseThroughEnemies = true
                local enemy = makeChar(2, 2, false)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = { enemy }, terrainMap = {}, hex = hex,
                    passableSide = "ally",
                    allowPhaseThroughEnemies = true,
                })
                return assertEq(ok, true, "phaseThroughEnemies should let ally pass enemy")
            end,
        },
        {
            name = "isPassable: phaseThroughEnemies does NOT let pass ally",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                mover.phaseThroughEnemies = true
                local ally = makeChar(2, 2, true)
                -- ally is same side → no blocking in the first place; test by
                -- flipping: put ally on enemy side via passableSide="enemy"
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = { ally }, terrainMap = {}, hex = hex,
                    passableSide = "enemy",
                    allowPhaseThroughEnemies = true,
                })
                return assertEq(ok, false, "phaseThroughEnemies only phases through enemies")
            end,
        },
        {
            name = "isOccupiedForStop: empty cell → not occupied",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                local ok = cell_rules.isOccupiedForStop(2, 2, mover, {
                    entities = {}, hex = hex,
                })
                return assertEq(ok, false, "empty cell not occupied")
            end,
        },
        {
            name = "isOccupiedForStop: cell with other entity → occupied",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                local other = makeChar(2, 2, true)
                local ok = cell_rules.isOccupiedForStop(2, 2, mover, {
                    entities = { other }, hex = hex,
                })
                return assertEq(ok, true, "cell with other entity is occupied")
            end,
        },
        {
            name = "isOccupiedForStop: hazard does NOT count as occupied",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                local hazard = makeObstacle(2, 2)
                hazard.isHazard = true
                local ok = cell_rules.isOccupiedForStop(2, 2, mover, {
                    entities = { hazard }, hex = hex,
                })
                return assertEq(ok, false, "hazard should not count as occupied")
            end,
        },
        {
            name = "isOccupiedForStop: self excluded",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(2, 2, true)
                local ok = cell_rules.isOccupiedForStop(2, 2, mover, {
                    entities = { mover }, hex = hex,
                })
                return assertEq(ok, false, "mover should not block itself")
            end,
        },
        {
            name = "isOccupied: water blocks ground unit",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "water" } }
                local mover = makeChar(1, 2, true)
                local ok = cell_rules.isOccupied(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                return assertEq(ok, true, "water occupies for ground")
            end,
        },
        {
            name = "isOccupied: waterWalker not blocked by water",
            fn = function()
                local hex = makeHexMock()
                local terrainMap = { [2] = { [2] = "water" } }
                local mover = makeChar(1, 2, true)
                mover.waterWalker = true
                local ok = cell_rules.isOccupied(2, 2, mover, {
                    entities = {}, terrainMap = terrainMap, hex = hex,
                })
                return assertEq(ok, false, "waterWalker not occupied by water")
            end,
        },
        {
            name = "isPassable: passableSide=enemy lets enemy pass enemy",
            fn = function()
                local hex = makeHexMock()
                local enemy1 = makeChar(1, 2, false)
                local enemy2 = makeChar(2, 2, false)
                local ok = cell_rules.isPassable(2, 2, enemy1, {
                    entities = { enemy2 }, terrainMap = {}, hex = hex,
                    passableSide = "enemy",
                })
                return assertEq(ok, true, "enemy passes enemy")
            end,
        },
        {
            name = "isPassable: passableSide=enemy blocked by ally",
            fn = function()
                local hex = makeHexMock()
                local enemy = makeChar(1, 2, false)
                local ally = makeChar(2, 2, true)
                local ok = cell_rules.isPassable(2, 2, enemy, {
                    entities = { ally }, terrainMap = {}, hex = hex,
                    passableSide = "enemy",
                })
                return assertEq(ok, false, "enemy blocked by ally")
            end,
        },
        {
            name = "isPassable: obstacle blocks mover",
            fn = function()
                local hex = makeHexMock()
                local mover = makeChar(1, 2, true)
                local obs = makeObstacle(2, 2)
                local ok = cell_rules.isPassable(2, 2, mover, {
                    entities = { obs }, terrainMap = {}, hex = hex,
                    passableSide = "ally",
                })
                return assertEq(ok, false, "obstacle blocks mover")
            end,
        },
        {
            name = "isRailway: plain railway upper terrain",
            fn = function()
                local upper = { [2] = { [2] = "railway" } }
                return assertEq(cell_rules.isRailway(2, 2, upper), true, "railway recognized")
            end,
        },
        {
            name = "isRailway: railway with direction suffix",
            fn = function()
                local upper = { [2] = { [2] = "railway:4" } }
                return assertEq(cell_rules.isRailway(2, 2, upper), true, "railway:4 recognized")
            end,
        },
        {
            name = "isRailway: non-railway upper terrain is not railway",
            fn = function()
                local upper = { [2] = { [2] = "mountain_rubble" } }
                return assertEq(cell_rules.isRailway(2, 2, upper), false, "rubble is not railway")
            end,
        },
        {
            name = "isRailway: empty cell is not railway",
            fn = function()
                return assertEq(cell_rules.isRailway(2, 2, {}), false, "empty is not railway")
            end,
        },
    },
}

return suite
