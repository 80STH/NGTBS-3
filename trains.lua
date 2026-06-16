-- trains.lua
-- Train system: shuntable train cars moving along railway between tunnels

local Entity = require("entity")
local trains = {}

local trainGroups = {}

function trains.getTrainGroups()
    return trainGroups
end

function trains.isTrainCar(entity)
    return entity and (entity.name == "TrainCar" or entity.name == "Locomotive")
end

local function findRailPath(startQ, startR, endQ, endR, terrainMap, hex)
    if not hex then return nil end
    local path = {{q = startQ, r = startR}}
    local visited = {[startQ .. "," .. startR] = true}
    local current = {q = startQ, r = startR}
    local maxSteps = 100

    for _ = 1, maxSteps do
        if current.q == endQ and current.r == endR then return path end
        local neighbors = hex:getNeighbors(current.q, current.r)
        local nextCell = nil
        for _, n in ipairs(neighbors) do
            local key = n.q .. "," .. n.r
            if not visited[key] and hex:isActiveHex(n.q, n.r) then
                local t = terrainMap[n.q] and terrainMap[n.q][n.r]
                if t == "railway" or (n.q == endQ and n.r == endR) then
                    nextCell = n
                    break
                end
            end
        end
        if not nextCell then return nil end
        visited[nextCell.q .. "," .. nextCell.r] = true
        table.insert(path, {q = nextCell.q, r = nextCell.r})
        current = nextCell
    end
    return nil
end

function trains.findRailwayPaths(entities, terrainMap, hex)
    if not hex then return {} end

    local tunnels = {}
    for _, e in ipairs(entities) do
        if e.name == "Tunnel" and e.health and e.health > 0 then
            table.insert(tunnels, e)
        end
    end
    if #tunnels < 2 then return {} end

    local paths = {}
    local usedTunnels = {}
    for i, t1 in ipairs(tunnels) do
        if not usedTunnels[i] then
            for j, t2 in ipairs(tunnels) do
                if i ~= j and not usedTunnels[j] then
                    local rawPath = findRailPath(t1.q, t1.r, t2.q, t2.r, terrainMap, hex)
                    if rawPath and #rawPath >= 3 then
                        local railPath = {}
                        for k = 2, #rawPath - 1 do
                            table.insert(railPath, rawPath[k])
                        end
                        if #railPath >= 3 then
                            table.insert(paths, {tunnelA = t1, tunnelB = t2, path = railPath})
                            usedTunnels[i] = true
                            usedTunnels[j] = true
                            break
                        end
                    end
                end
            end
        end
    end
    return paths
end

function trains.init(entities, terrainMap, hex)
    trainGroups = {}
    if not hex then return end

    local paths = trains.findRailwayPaths(entities, terrainMap, hex)
    if #paths == 0 then
        print("No train paths found - no railway or tunnels on this map")
        return
    end

    local env = require("environment")
    local loadedMap = env.loadedMap
    local tileW = (loadedMap and loadedMap.tilewidth) or 14
    local tileH = (loadedMap and loadedMap.tileheight) or 12

    for pi, route in ipairs(paths) do
        local path = route.path
        -- Reverse path and swap tunnels so cars move forward visually
        local reversed = {}
        for i = #path, 1, -1 do table.insert(reversed, path[i]) end
        route.path = reversed
        route.tunnelA, route.tunnelB = route.tunnelB, route.tunnelA
        path = reversed

        local carPositions = {}
        local startIdx = 1
        if #path >= 2 then
            table.insert(carPositions, path[startIdx])
            table.insert(carPositions, path[startIdx + 1])
        else
            for _, pos in ipairs(path) do
                table.insert(carPositions, pos)
            end
        end

        -- Place cars in reverse order so locomotive is behind the train car
        local cars = {}
        for ci, pos in ipairs(carPositions) do
            local idx = #carPositions - ci + 1
            local name = (idx == 1) and "Locomotive" or "TrainCar"
            local car = Entity.new(name, Entity.TYPES.BUILDING, pos.q, pos.r, 1, false, 0, nil, nil, {})
            car.isTrainCar = true
            car.isObjective = true

            car.sprite = env.generateBuildingSprite(name, tileW, tileH)
            car.trainGroupId = pi
            car.trainCarIndex = ci
            table.insert(entities, car)
            table.insert(cars, car)
        end

        local group = {
            id = pi,
            cars = cars,
            path = path,
            currentIdx = startIdx,
            direction = 1,
            active = true,
            tunnelA = route.tunnelA,
            tunnelB = route.tunnelB,
        }
        trainGroups[pi] = group

        print(string.format("Train group %d: %d cars on path of %d cells", pi, #cars, #path))
    end
end

function trains.getCarGroup(car)
    for _, group in pairs(trainGroups) do
        for _, c in ipairs(group.cars) do
            if c == car then return group end
        end
    end
    return nil
end

function trains.shuntCar(car, entities)
    local group = trains.getCarGroup(car)
    if not group or not group.active then return false end

    for _, c in ipairs(group.cars) do
        if c.health <= 0 or c.isDying then
            group.active = false
            return false
        end
    end

    local tailIdx = group.currentIdx + (#group.cars - 1)
    local newHeadIdx = group.currentIdx + group.direction
    local newTailIdx = tailIdx + group.direction
    if newHeadIdx < 1 or newTailIdx > #group.path then
        group.direction = -group.direction
        print("Train reversed direction at tunnel")
        return false
    end

    local target = group.path[newHeadIdx]

    -- Locomotive crushes non-tunnel entities in target cell
    local loco
    for _, c in ipairs(group.cars) do
        if c.name == "Locomotive" then loco = c; break end
    end
    for i = #entities, 1, -1 do
        local e = entities[i]
        if e ~= loco and e.trainGroupId ~= group.id and e.q == target.q and e.r == target.r and e.health and e.health > 0 and not e.isDying and e.name ~= "Tunnel" then
            local wasDestroyed = e:takeDamage(999)
            if wasDestroyed then e:startDeath() end
            if e.health and e.health <= 0 then table.remove(entities, i) end
        end
    end

    -- Move entire train by 1 cell along the path (no swapping)
    for ci, c in ipairs(group.cars) do
        local idx = newHeadIdx + (ci - 1)
        c.q = group.path[idx].q
        c.r = group.path[idx].r
    end
    group.currentIdx = newHeadIdx
    return true
end

return trains
