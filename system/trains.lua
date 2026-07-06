-- trains.lua
-- Train system: locomotives move forward along railway between tunnels

local Entity = require("entity.entity")
local hex_utils = require("grid.hex_utils")
local log = require("util.log")
local env = require("entity.environment")
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
                if t == "railway" then
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

    local entrances = {}
    local exits = {}
    for _, e in ipairs(entities) do
        if e.name == "TunnelEntrance" and e.health and e.health > 0 then
            table.insert(entrances, e)
        elseif e.name == "TunnelExit" and e.health and e.health > 0 then
            table.insert(exits, e)
        end
    end
    if #entrances == 0 or #exits == 0 then return {} end

    local paths = {}
    local usedExits = {}
    for _, entrance in ipairs(entrances) do
        for j, exitTunnel in ipairs(exits) do
            if not usedExits[j] then
                local rawPath = findRailPath(entrance.q, entrance.r, exitTunnel.q, exitTunnel.r, terrainMap, hex)
                if rawPath and #rawPath >= 3 then
                    table.insert(paths, {tunnelA = entrance, tunnelB = exitTunnel, path = rawPath})
                    usedExits[j] = true
                    break
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
        log.info("trains", "No train paths found - no railway or tunnels on this map")
        return
    end

    local loadedMap = env.loadedMap
    local tileW = (loadedMap and loadedMap.tilewidth) or 14
    local tileH = (loadedMap and loadedMap.tileheight) or 12

    for pi, route in ipairs(paths) do
        local path = route.path

        if #path < 4 then
            log.debugf("trains", "Train group %d: path too short (%d cells), skipping", pi, #path)
            goto continue
        end

        local locoIdx = 3
        local wagonIdx = 2

        local loco = Entity.new("Locomotive", Entity.TYPES.BUILDING, path[locoIdx].q, path[locoIdx].r, 1, false, 0, nil, nil, {})
        loco.isTrainCar = true
        loco.isObjective = true
        loco.sprite = env.generateBuildingSprite("Locomotive", tileW, tileH)

        local wagon = Entity.new("TrainCar", Entity.TYPES.BUILDING, path[wagonIdx].q, path[wagonIdx].r, 1, false, 0, nil, nil, {})
        wagon.isTrainCar = true
        wagon.isObjective = true
        wagon.sprite = env.generateBuildingSprite("TrainCar", tileW, tileH)

        loco.trainGroupId = pi
        wagon.trainGroupId = pi

        table.insert(entities, loco)
        table.insert(entities, wagon)

        local cars = {loco, wagon}
        local group = {
            id = pi,
            cars = cars,
            path = path,
            currentIdx = locoIdx,
            active = true,
            animating = false,
            animTimer = 0,
            animSpeed = 0.3,
            animCallback = nil,
            tunnelA = route.tunnelA,
            tunnelB = route.tunnelB,
        }
        trainGroups[pi] = group

        local targetIdx = group.currentIdx + 1
        if targetIdx <= #path then
            local target = path[targetIdx]
            local dx, dy, dz = hex_utils.getCubeDiff(loco.q, loco.r, target.q, target.r)
            loco.hasPreparedAttack = true
            loco.isTrainAttack = true
            loco.preparedAttack = { name = "TrainShunt", damage = 999, range = 1, minRange = 1 }
            loco.preparedTargetOffset = { dx = dx, dy = dy, dz = dz }
        end

        log.debugf("trains", "Train group %d: %d cars, path %d cells, loco at idx %d", pi, #cars, #path, locoIdx)
        ::continue::
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

function trains.isGroupActive(group)
    if not group or not group.active then return false end
    local entities = _G.entities or {}
    local function isTunnelAlive()
        local tunnelTypes = { "TunnelEntrance", "TunnelExit", "OccupiedTunnel" }
        for _, e in ipairs(entities) do
            for _, tname in ipairs(tunnelTypes) do
                if e.name == tname and e.health and e.health > 0 then
                    if (e.q == group.tunnelA.q and e.r == group.tunnelA.r) or
                       (e.q == group.tunnelB.q and e.r == group.tunnelB.r) then
                        return true
                    end
                end
            end
        end
        return false
    end
    if not isTunnelAlive() then
        group.active = false
        return false
    end
    if group.cars then
        local loco = group.cars[1]
        if loco and (loco.health <= 0 or loco.isDying) then
            group.active = false
            return false
        end
    end
    return true
end

function trains.prepareTrainAttacks(entities, hex)
    for _, group in pairs(trainGroups) do
        if not trains.isGroupActive(group) then
            for _, c in ipairs(group.cars) do
                c.hasPreparedAttack = false
                c.isTrainAttack = nil
            end
            goto next_group
        end

        local loco = group.cars[1]
        if not loco or loco.health <= 0 or loco.isDying then
            group.active = false
            goto next_group
        end

        local targetIdx = group.currentIdx + 1
        if targetIdx > #group.path then
            loco.hasPreparedAttack = false
            loco.isTrainAttack = nil
            goto next_group
        end

        local target = group.path[targetIdx]

        local dx, dy, dz = hex_utils.getCubeDiff(loco.q, loco.r, target.q, target.r)
        loco.hasPreparedAttack = true
        loco.isTrainAttack = true
        loco.preparedAttack = { name = "TrainShunt", damage = 999, range = 1, minRange = 1 }
        loco.preparedTargetOffset = { dx = dx, dy = dy, dz = dz }

        ::next_group::
    end
end

local function convertTunnelToOccupied(tunnelEntity, entities, hex)
    if not tunnelEntity then return end
    if tunnelEntity.name ~= "TunnelEntrance" and tunnelEntity.name ~= "TunnelExit" then return end
    if tunnelEntity.health <= 0 then return end

    local loadedMap = env.loadedMap
    local tileW = (loadedMap and loadedMap.tilewidth) or 14
    local tileH = (loadedMap and loadedMap.tileheight) or 12

    local occ = Entity.new("OccupiedTunnel", Entity.TYPES.BUILDING, tunnelEntity.q, tunnelEntity.r, tunnelEntity.health, false, 0, nil, nil, {})
    occ.isObjective = true
    occ.isOccupiedTunnel = true
    occ.sprite = env.generateBuildingSprite("OccupiedTunnel", tileW, tileH)

    for i, e in ipairs(entities) do
        if e == tunnelEntity then
            entities[i] = occ
            break
        end
    end

    log.infof("trains", "Tunnel at (%d,%d) is now occupied!", occ.q, occ.r)
end

local function startTrainAnimation(group, entities, hex, onComplete)
    local loco = group.cars[1]
    local wagon = group.cars[2]
    local targetIdx = group.currentIdx + 1
    if targetIdx > #group.path then
        if onComplete then onComplete() end
        return
    end

    local targetPos = group.path[targetIdx]
    local wagonTargetIdx = targetIdx - 1
    local wagonTarget = group.path[wagonTargetIdx]

    group.animating = true
    group.animTimer = 0
    group.animCallback = onComplete
    group.pendingCrushQ = targetPos.q
    group.pendingCrushR = targetPos.r
    group.pendingLocoQ = targetPos.q
    group.pendingLocoR = targetPos.r
    group.pendingWagonQ = wagonTarget.q
    group.pendingWagonR = wagonTarget.r

    local hexModule = hex or _G.hex
    if hexModule then
        loco.startX, loco.startY = hexModule:hexToPixel(loco.q, loco.r)
        loco.endX, loco.endY = hexModule:hexToPixel(targetPos.q, targetPos.r)
        wagon.startX, wagon.startY = hexModule:hexToPixel(wagon.q, wagon.r)
        wagon.endX, wagon.endY = hexModule:hexToPixel(wagonTarget.q, wagonTarget.r)
    end

    loco.isMoving = true
    loco.timer = 0
    loco.speed = group.animSpeed
    loco.targetQ = targetPos.q
    loco.targetR = targetPos.r

    wagon.isMoving = true
    wagon.timer = 0
    wagon.speed = group.animSpeed
    wagon.targetQ = wagonTarget.q
    wagon.targetR = wagonTarget.r
end

local function completeShunt(group, entities, hex)
    local loco = group.cars[1]
    local wagon = group.cars[2]

    loco.q = group.pendingLocoQ
    loco.r = group.pendingLocoR
    wagon.q = group.pendingWagonQ
    wagon.r = group.pendingWagonR

    loco.isMoving = false
    wagon.isMoving = false

    local crushQ, crushR = group.pendingCrushQ, group.pendingCrushR

    for i = #entities, 1, -1 do
        local e = entities[i]
        if e ~= loco and e ~= wagon and e.trainGroupId ~= group.id
            and e.q == crushQ and e.r == crushR
            and e.health and e.health > 0 and not e.isDying
            and e.name ~= "TunnelEntrance" and e.name ~= "TunnelExit" and e.name ~= "OccupiedTunnel" then
            local wasDestroyed = e:takeDamage(999)
            if wasDestroyed then e:startDeath() end
            if e.health and e.health <= 0 and not status.hasEntityStatus(e, "stasis") then table.remove(entities, i) end
        end
    end

    for _, e in ipairs(entities) do
        if e.q == crushQ and e.r == crushR and (e.name == "TunnelEntrance" or e.name == "TunnelExit") and e.health and e.health > 0 then
            convertTunnelToOccupied(e, entities, hex)
            break
        end
    end

    group.currentIdx = group.currentIdx + 1
    group.animating = false

    local nextIdx = group.currentIdx + 1
    if nextIdx <= #group.path then
        local nextTarget = group.path[nextIdx]
        local dx, dy, dz = hex_utils.getCubeDiff(loco.q, loco.r, nextTarget.q, nextTarget.r)
        loco.hasPreparedAttack = true
        loco.isTrainAttack = true
        loco.preparedAttack = { name = "TrainShunt", damage = 999, range = 1, minRange = 1 }
        loco.preparedTargetOffset = { dx = dx, dy = dy, dz = dz }
    else
        loco.hasPreparedAttack = false
        loco.isTrainAttack = nil
    end

    if group.animCallback then
        local cb = group.animCallback
        group.animCallback = nil
        cb()
    end
end

function trains.updateMovement(dt)
    local anyAnimating = false
    for _, group in pairs(trainGroups) do
        if group.animating then
            anyAnimating = true
            local loco = group.cars[1]
            local wagon = group.cars[2]

            loco.timer = (loco.timer or 0) + dt
            if loco.timer >= loco.speed then
                wagon.timer = (wagon.timer or 0) + dt
                if wagon.timer >= wagon.speed then
                    completeShunt(group, _G.entities or {}, _G.hex)
                end
            end
        end
    end
    return anyAnimating
end

function trains.isAnyAnimating()
    for _, group in pairs(trainGroups) do
        if group.animating then return true end
    end
    return false
end

function trains.executeTrainShunt(loco, entities, hex, onComplete)
    local group = trains.getCarGroup(loco)
    if not group then
        if onComplete then onComplete() end
        return
    end
    if not trains.isGroupActive(group) then
        if onComplete then onComplete() end
        return
    end

    local targetIdx = group.currentIdx + 1
    if targetIdx > #group.path then
        log.warn("trains", "Train at end of line, cannot shunt")
        if onComplete then onComplete() end
        return
    end

    startTrainAnimation(group, entities, hex, onComplete)
    sounds.play("train")
end

return trains
