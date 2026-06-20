-- src/content/trains.lua
-- Trains: a locomotive + cars that advance one cell per enemy turn along a path.
-- Map data: data.trains = { { path = { {q=,r=}, ... }, length = 2, isObjective = false } }
-- The first cell of the path is the locomotive's starting cell; cars follow.
-- Trains plow through entities on entered cells (2 damage).

local Entity = require("src.core.entity")
local units = require("src.content.units")

local trains = { groups = {} }

local function entityAt(entities, q, r)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r and e:isAlive() and not e.isTrainCar then return e end
    end
    return nil
end

function trains.reset() trains.groups = {} end

-- Build train entities from map data and register groups.
function trains.build(grid, entities, data, ctx)
    trains.groups = {}
    if not data or not data.trains then return end
    for gi, t in ipairs(data.trains) do
        local path = t.path or {}
        local length = math.max(1, t.length or 1)
        local cars = {}
        for i = 1, length do
            local cell = path[i]
            if not cell then break end
            local e
            if i == 1 then
                e = units.create("Locomotive", cell.q, cell.r)
                e.isObjective = t.isObjective or false
            else
                e = units.create("TrainCar", cell.q, cell.r)
            end
            e.isTrainCar = true
            e.trainGroupId = gi
            e.isPushable = false
            table.insert(cars, e)
            table.insert(entities, e)
        end
        table.insert(trains.groups, {
            path = path, headIndex = 1, cars = cars, active = #cars > 0,
            isObjective = t.isObjective or false,
        })
    end
end

-- Advance all trains one step (called once per enemy turn).
function trains.update(grid, entities, ctx)
    ctx = ctx or {}
    for _, g in ipairs(trains.groups) do
        if g.active and g.cars and #g.cars > 0 then
            local loco = g.cars[1]
            if not loco:isAlive() then g.active = false else
                local nextIndex = g.headIndex + 1
                local nextCell = g.path[nextIndex]
                if nextCell and grid:isActiveHex(nextCell.q, nextCell.r) then
                    -- plow through whatever is on the next cell
                    local occ = entityAt(entities, nextCell.q, nextCell.r)
                    if occ then
                        local died = occ:takeDamage(2, ctx); if died then occ:startDeath() end
                    end
                    -- shift each car to the previous car's cell
                    for i = #g.cars, 2, -1 do
                        g.cars[i]:setPos(g.cars[i - 1].q, g.cars[i - 1].r)
                    end
                    loco:setPos(nextCell.q, nextCell.r)
                    g.headIndex = nextIndex
                    if ctx.onEffect then ctx.onEffect("hit", nextCell.q, nextCell.r) end
                    if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
                end
            end
        end
    end
end

function trains.anyActive()
    for _, g in ipairs(trains.groups) do if g.active then return true end end
    return false
end

return trains
