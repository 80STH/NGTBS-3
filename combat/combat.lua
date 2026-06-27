-- combat.lua
-- Combat system with cubic coordinates (pointy-top, odd-r)
local combat = {}
local visual = require("system.visual_effects")
local status = require("system.status")
local Entity = require("entity.entity")
local attack_effects = require("combat.attack_effects")
local log = require("util.log")
local sprites = require("util.sprites")

local hex_utils = require("grid.hex_utils")
local env = require("entity.environment")
-- ============================================================
-- BASE ATTACK CLASS
-- ============================================================
combat.Attack = {}
combat.Attack.__index = combat.Attack

function combat.Attack.new(name, description, range, damage, effects)
    local self = setmetatable({}, combat.Attack)
    self.name = name or "Attack"
    self.description = description or "A basic attack"
    self.range = range or 1
    self.damage = damage or 1
    self.effects = effects or {}
    return self
end

-- Determine straight-line direction (cube step)
function combat.Attack:getLineDirection(fromQ, fromR, toQ, toR, hex)
    local ax, ay, az = hex_utils.axialToCube(fromQ, fromR)
    local bx, by, bz = hex_utils.axialToCube(toQ, toR)
    local dx, dy, dz = bx - ax, by - ay, bz - az

    local function gcd(a, b)
        a = math.abs(a); b = math.abs(b)
        while b ~= 0 do a, b = b, a % b end
        return a
    end

    local g = gcd(gcd(dx, dy), dz)
    if g == 0 then return nil end

    local stepX, stepY, stepZ = dx / g, dy / g, dz / g
    if math.abs(stepX) > 1 or math.abs(stepY) > 1 or math.abs(stepZ) > 1 then return nil end
    if stepX + stepY + stepZ ~= 0 then return nil end
    return stepX, stepY, stepZ
end

-- Find first target on line
function combat.Attack:findFirstTargetOnLine(startQ, startR, stepX, stepY, stepZ, hex, entities)
    local curQ, curR = startQ, startR
    while true do
        curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isValidHex(curQ, curR) then break end
        local target = combat.getEntityAtHex(curQ, curR, entities)
        if target then return target, {q = curQ, r = curR} end
    end
    return nil, nil
end

-- Farthest active cell on line (excluding start)
function combat.getFarthestActiveCellOnLine(startQ, startR, stepX, stepY, stepZ, hex, maxSteps)
    local curQ, curR = startQ, startR
    local lastQ, lastR = nil, nil
    local steps = 0
    while true do
        if maxSteps and steps >= maxSteps then break end
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isActiveHex(nextQ, nextR) then break end
        lastQ, lastR = nextQ, nextR
        curQ, curR = nextQ, nextR
        steps = steps + 1
    end
    if lastQ == nil or (lastQ == startQ and lastR == startR) then return nil end
    return {q = lastQ, r = lastR}
end

-- Find first two targets on line
function combat.Attack:findFirstTwoTargetsOnLine(startQ, startR, stepX, stepY, stepZ, hex, entities)
    local curQ, curR = startQ, startR
    local firstTarget, firstHex, secondTarget, secondHex = nil, nil, nil, nil
    while true do
        curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isValidHex(curQ, curR) then break end
        local target = combat.getEntityAtHex(curQ, curR, entities)
        if target then
            if not firstTarget then
                firstTarget, firstHex = target, {q = curQ, r = curR}
            elseif not secondTarget and target ~= firstTarget then
                secondTarget, secondHex = target, {q = curQ, r = curR}
                break
            end
        end
    end
    return firstTarget, firstHex, secondTarget, secondHex
end

-- Push in direction (with animation)
function combat.Attack:pushTargetInDirection(target, fromQ, fromR, stepX, stepY, stepZ, hex, entities, sounds, onComplete)
    local pushQ, pushR = hex_utils.applyCubeStep(fromQ, fromR, stepX, stepY, stepZ)
    self:pushTargetToHex(target, fromQ, fromR, pushQ, pushR, hex, entities, sounds, onComplete)
end

function combat.Attack:pushTargetToHex(target, fromQ, fromR, toQ, toR, hex, entities, sounds, onComplete)
    if target.isPushable == false then
        if onComplete then onComplete(false) end
        return
    end

    -- Check cell occupancy
    local occupant = combat.getEntityAtHex(toQ, toR, entities)
    if occupant and occupant ~= target then
        -- SharpReefs / lethal collision: instant death
        if occupant.lethalCollision then
            target.health = 0
            target:startDeath()
            log.infof("combat", "%s is pushed into %s! Instant death!", target.name, occupant.name)
            if onComplete then onComplete(false) end
            return
        end
        -- Mountain slope (indestructible) — bounce animation without damage
        if occupant.noCollisionDamage then
            combat.addCollisionBounceAnimation(target, fromQ, fromR, toQ, toR, hex, entities, sounds, occupant, true)
            if onComplete then onComplete(false) end
            return
        end
        -- Directional entity (MountainSlope) — side check
        if occupant.direction then
            local safe = hex_utils.isPushFromSafeSide(occupant, fromQ, fromR)
            if safe then
                -- Safe side: bounce without damage
                combat.addCollisionBounceAnimation(target, fromQ, fromR, toQ, toR, hex, entities, sounds, occupant, true)
            else
                -- Dangerous side: bounce with damage
                combat.addCollisionBounceAnimation(target, fromQ, fromR, toQ, toR, hex, entities, sounds, occupant)
            end
            if onComplete then onComplete(false) end
            return
        end
        -- Deep water — free pass, effect applies after movement
        if occupant.isHazard then
            combat.addPushAnimation(target, fromQ, fromR, toQ, toR, function()
                if onComplete then onComplete(true) end
            end)
            return
        end
        -- Collision → bounce + damage
        combat.addCollisionBounceAnimation(target, fromQ, fromR, toQ, toR, hex, entities, sounds, occupant)
        if onComplete then onComplete(false) end
        return
    end

    -- Flying off the edge
    if not hex:isActiveHex(toQ, toR) then
        if target:isCharacter() then
            target.health = target.health - 1
            log.infof("combat", "%s is slammed against the edge! Takes 1 damage!", target.name)
            sounds.play("collision")
            if target.health <= 0 then
                target.startDeath()
            end
        end
        local effectX, effectY = getDrawCoords(fromQ, fromR)
        visual.addEffect(effectX, effectY, "slam")
        if onComplete then onComplete(false) end
        return
    end

    -- Successful movement (without collision)
    combat.addPushAnimation(target, fromQ, fromR, toQ, toR, function()
        if onComplete then onComplete(true) end
    end)
end

-- Shared: line-effect fallback when no target on line
function combat.Attack:noTargetLineFallback(attacker, stepX, stepY, stepZ, hex)
    local endCell = combat.getFarthestActiveCellOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex)
    if not endCell then return false end
    local fx, fy = getDrawCoords(attacker.q, attacker.r)
    local tx, ty = getDrawCoords(endCell.q, endCell.r)
    visual.addLineEffect(fx, fy, tx, ty, 0.9, 0.7, 0.2, 3, 1.0)
    attacker.hasActedThisTurn = true
    return true
end

-- Shared: get push cell for line-based shot attacks
function combat.Attack:getLineShotPushCell(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
        if hex:isValidHex(pushQ, pushR) then
            return {q = pushQ, r = pushR}
        else
            return {q = pushQ, r = pushR, edge = true}
        end
    end
    local endCell = combat.getFarthestActiveCellOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex)
    if endCell then
        return {q = endCell.q, r = endCell.r, farthest = true}
    end
    return nil
end

-- Shared: get neighbors sorted by direction (top 3)
function combat.Attack:getNeighborsInDirection(centerQ, centerR, dirQ, dirR, hex)
    if centerQ == nil or centerR == nil then return {} end
    local neighbors = hex:getNeighbors(centerQ, centerR)
    local validNeighbors = {}
    for _, nb in ipairs(neighbors) do
        if nb and nb.q ~= nil and nb.r ~= nil then
            table.insert(validNeighbors, nb)
        end
    end
    if #validNeighbors == 0 then return {} end
    local dirVec = { q = dirQ or 0, r = dirR or 0 }
    local function dot(a, b)
        return (a.q or 0) * (b.q or 0) + (a.r or 0) * (b.r or 0)
    end
    table.sort(validNeighbors, function(a, b)
        return dot(a, dirVec) > dot(b, dirVec)
    end)
    local top = {}
    for i = 1, math.min(3, #validNeighbors) do
        table.insert(top, validNeighbors[i])
    end
    return top
end

-- ============================================================
-- GENERAL METHODS FOR ATTACK PREVIEW
-- ============================================================

-- Which cells will be affected when attacking target (targetQ, targetR)
-- Returns array {q, r, damage}
function combat.Attack:getAffectedCells(attacker, targetQ, targetR, hex, entities)
    return {{q = targetQ, r = targetR, damage = self.damage}}
end

-- All valid target cells for this attack
-- Returns table {["q,r"] = true}
function combat.Attack:getValidTargets(attacker, hex, entities)
    local keys = {}
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) then
                local cell = self:getTargetCell(attacker, q, r, hex, entities)
                if cell then
                    keys[q .. "," .. r] = true
                end
            end
        end
    end
    return keys
end

-- ============================================================
-- ATTACK TYPES (with push preview support)
-- ============================================================
-- Replace existing DashAttack class with this one
combat.DashAttack = setmetatable({}, combat.Attack)
combat.DashAttack.__index = combat.DashAttack

function combat.DashAttack.new()
    local self = combat.Attack.new("Dash", "Charge forward, stop before first entity", math.huge, 0, {})
    return setmetatable(self, combat.DashAttack)
end

-- Returns first target, its cell, and last free cell before target
function combat.DashAttack:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)
    local curQ, curR = attacker.q, attacker.r
    local lastFreeQ, lastFreeR = curQ, curR
    local firstTarget = nil
    local targetHex = nil

    while true do
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isActiveHex(nextQ, nextR) then
            -- Reached edge, last free cell is current
            break
        end

        local occupant = combat.getEntityAtHex(nextQ, nextR, entities)
        if occupant and occupant ~= attacker then
            firstTarget = occupant
            targetHex = {q = nextQ, r = nextR}
            -- lastFree already set as curQ,curR (cell before target)
            break
        end

        -- Cell is free, update last free
        lastFreeQ, lastFreeR = nextQ, nextR
        curQ, curR = nextQ, nextR
    end

    local lastFree = nil
    if not (lastFreeQ == attacker.q and lastFreeR == attacker.r) then
        lastFree = {q = lastFreeQ, r = lastFreeR}
    end

    return firstTarget, targetHex, lastFree
end

function combat.DashAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    local firstTarget, targetHex, lastFree = self:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)

    -- Determine where the attacker will land (cell before target, in cube coords)
    local moveQ, moveR
    local shouldMove = false
    if firstTarget and targetHex then
        local tx, ty, tz = hex_utils.axialToCube(targetHex.q, targetHex.r)
        local bx, by, bz = tx - stepX, ty - stepY, tz - stepZ
        local bq, br = hex_utils.cubeToAxial(bx, by, bz)
        -- Only move if the cell before target is different from attacker's position
        if bq ~= attacker.q or br ~= attacker.r then
            moveQ, moveR = bq, br
            shouldMove = true
        end
    elseif lastFree then
        if lastFree.q ~= attacker.q or lastFree.r ~= attacker.r then
            moveQ, moveR = lastFree.q, lastFree.r
            shouldMove = true
        end
    else
        if targetQ ~= attacker.q or targetR ~= attacker.r then
            moveQ, moveR = targetQ, targetR
            shouldMove = true
        end
    end

    -- Visual effect
    local fxEndQ, fxEndR = attacker.q, attacker.r
    if firstTarget and targetHex then
        fxEndQ, fxEndR = targetHex.q, targetHex.r
    elseif shouldMove then
        fxEndQ, fxEndR = moveQ, moveR
    end
    attack_effects.dash(attacker, firstTarget, fxEndQ, fxEndR, hex)

    -- Deal damage to first target
    if firstTarget then
        self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds, nil)
    end

    -- If target exists and is pushable, push it
    if firstTarget and targetHex and firstTarget.isPushable and firstTarget.health and firstTarget.health > 0 then
        local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
        local occupant = combat.getEntityAtHex(pushQ, pushR, entities)
        local isEdge = not hex:isActiveHex(pushQ, pushR)
        if isEdge or occupant then
            combat.addCollisionBounceAnimation(firstTarget, targetHex.q, targetHex.r, pushQ, pushR, hex, entities, sounds, occupant)
        else
            combat.addPushAnimation(firstTarget, targetHex.q, targetHex.r, pushQ, pushR)
        end
    end

    -- Move attacker (only if there's a cell to move to)
    if shouldMove then
        combat.addPushAnimation(attacker, attacker.q, attacker.r, moveQ, moveR)
    end

    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end

-- 2. FLIP – 1 damage, toss onto 3 chosen cells
combat.FlipAttack = setmetatable({}, combat.Attack)
combat.FlipAttack.__index = combat.FlipAttack
function combat.FlipAttack.new()
    local self = combat.Attack.new("Flip", "Flip target behind (1 dmg), choose destination", 1, 1, {})
    return setmetatable(self, combat.FlipAttack)
end

-- Returns 3 possible flip cells: behind, left, and right
-- (only free and active)
function combat.FlipAttack:getFlipCells(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) ~= 1 then return {} end
    local targetActor = combat.getEntityAtHex(targetQ, targetR, entities)
    if not targetActor or not targetActor:isCharacter() then
        return {}
    end
    local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
    local tX, tY, tZ = hex_utils.axialToCube(targetQ, targetR)
    local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
    -- Three directions: straight back, turn left, turn right
    local dirs = {
        {dirX, dirY, dirZ},
        {-dirY, -dirZ, -dirX},  -- turn left
        {-dirZ, -dirX, -dirY},  -- turn right
    }
    local cells = {}
    for _, d in ipairs(dirs) do
        local flipX, flipY, flipZ = aX + d[1], aY + d[2], aZ + d[3]
        local flipQ, flipR = hex_utils.cubeToAxial(flipX, flipY, flipZ)
        if hex:isActiveHex(flipQ, flipR) and not combat.getEntityAtHex(flipQ, flipR, entities) then
            table.insert(cells, {q = flipQ, r = flipR})
        end
    end
    return cells
end

function combat.FlipAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end
    local targetActor = combat.getEntityAtHex(targetQ, targetR, entities)
    if not targetActor then return false, "No entity at that hex!" end
    if not targetActor:isCharacter() or targetActor.isPushable == false then
        return false, "Target must be a character!"
    end
    -- Determine destination: use _flipDestCell if set, else default (behind)
    local destQ, destR
    if self._flipDestCell then
        destQ, destR = self._flipDestCell.q, self._flipDestCell.r
        self._flipDestCell = nil
    else
        local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
        local tX, tY, tZ = hex_utils.axialToCube(targetQ, targetR)
        local dirX, dirY, dirZ = aX - tX, aY - tY, aZ - tZ
        destQ, destR = hex_utils.cubeToAxial(aX + dirX, aY + dirY, aZ + dirZ)
    end
    if not hex:isActiveHex(destQ, destR) then
        return false, "Destination cell is not active!"
    end
    if combat.getEntityAtHex(destQ, destR, entities) then
        return false, "Destination cell is occupied!"
    end
    -- Deal 1 damage
    self:dealDamageToTarget(targetActor, attacker, 1, entities, sounds, nil)
    -- Movement
    attack_effects.flip(attacker, targetActor, destQ, destR, hex)
    combat.addPushAnimation(targetActor, targetQ, targetR, destQ, destR)
    combat.startPushAnimations(hex)
    log.debugf("combat", "%s flips %s to (%d,%d)!", attacker.name, targetActor.name, destQ, destR)
    sounds.play("flip")
    attacker.hasActedThisTurn = true
    return true
end

-- For backward compatibility with code calling getPushCell
function combat.FlipAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    local cells = self:getFlipCells(attacker, targetQ, targetR, hex, entities)
    return cells[1]  -- first cell = straight behind
end

-- 3. SHOOT
combat.LineShotAttack = setmetatable({}, combat.Attack)
combat.LineShotAttack.__index = combat.LineShotAttack

function combat.LineShotAttack.new(name, desc, range, damage)
    local self = combat.Attack.new(name, desc, range, damage, {})
    return setmetatable(self, combat.LineShotAttack)
end

function combat.LineShotAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then
        return self:noTargetLineFallback(attacker, stepX, stepY, stepZ, hex)
    end
    local pushQ, pushR
    if firstTarget.isPushable ~= false then
        pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
    end
    attack_effects.shoot(attacker, firstTarget, pushQ, pushR, hex)
    self:pushTargetInDirection(firstTarget, targetHex.q, targetHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    if self.damage > 0 then
        self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds, nil)
    end
    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end

function combat.LineShotAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    return self:getLineShotPushCell(attacker, targetQ, targetR, hex, entities)
end

-- Backward compatibility wrappers
combat.ShootAttack = setmetatable({}, combat.LineShotAttack)
combat.ShootAttack.__index = combat.ShootAttack
function combat.ShootAttack.new(range)
    return setmetatable(combat.LineShotAttack.new("Shoot", "Fire a projectile, pushing the first target", range or 999, 1), combat.ShootAttack)
end

combat.PushAttack = setmetatable({}, combat.LineShotAttack)
combat.PushAttack.__index = combat.PushAttack
function combat.PushAttack.new(range)
    return setmetatable(combat.LineShotAttack.new("Push", "Push the first enemy in line (no damage)", range or 999, 0), combat.PushAttack)
end

-- 4. PIERCING SHOT
combat.PiercingShootAttack = setmetatable({}, combat.Attack)
combat.PiercingShootAttack.__index = combat.PiercingShootAttack
function combat.PiercingShootAttack.new(range)
    local self = combat.Attack.new("Piercing Shot", "Shoot through the first target (0 dmg, pushes) to hit the second (1 dmg, pushes)", range or 999, 0, {})
    return setmetatable(self, combat.PiercingShootAttack)
end
function combat.PiercingShootAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local firstTarget, firstHex, secondTarget, secondHex = self:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then
        local ok = self:noTargetLineFallback(attacker, stepX, stepY, stepZ, hex)
        if not ok then return false, "No valid target cell!" end
        return true
    end
    local firstPushQ, firstPushR
    if firstTarget.isPushable ~= false then
        firstPushQ, firstPushR = hex_utils.applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
    end
    local secondPushQ, secondPushR
    if secondTarget and secondTarget.isPushable ~= false and secondHex then
        secondPushQ, secondPushR = hex_utils.applyCubeStep(secondHex.q, secondHex.r, stepX, stepY, stepZ)
    end
    attack_effects.piercingShoot(attacker, firstTarget, secondTarget, firstPushQ, firstPushR, secondPushQ, secondPushR, hex)
    if secondTarget and secondTarget.isPushable ~= false and secondHex then
        local pushQ, pushR = hex_utils.applyCubeStep(secondHex.q, secondHex.r, stepX, stepY, stepZ)
        self:pushTargetToHex(secondTarget, secondHex.q, secondHex.r, pushQ, pushR, hex, entities, sounds)
        local occupant = combat.getEntityAtHex(pushQ, pushR, entities)
        if hex:isActiveHex(pushQ, pushR) and not occupant then
            secondTarget.q = pushQ
            secondTarget.r = pushR
            secondTarget.currentDrawX = nil
            secondTarget.currentDrawY = nil
        end
    end
    if secondTarget then
        self:dealDamageToTarget(secondTarget, attacker, 1, entities, sounds, nil)
    end
    if firstTarget.isPushable ~= false then
        self:pushTargetInDirection(firstTarget, firstHex.q, firstHex.r, stepX, stepY, stepZ, hex, entities, sounds)
    end
    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end
-- Preview: returns push cell list for two targets
function combat.PiercingShootAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return {} end
    local firstTarget, firstHex, secondTarget, secondHex = self:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    local cells = {}
    if firstTarget and firstHex and firstTarget.isPushable ~= false then
        local pushQ, pushR = hex_utils.applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
        table.insert(cells, {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)})
    end
    if secondTarget and secondHex and secondTarget.isPushable ~= false then
        local pushQ, pushR = hex_utils.applyCubeStep(secondHex.q, secondHex.r, stepX, stepY, stepZ)
        table.insert(cells, {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)})
    end
    if #cells == 0 then
        local endCell = combat.getFarthestActiveCellOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex)
        if endCell then
            table.insert(cells, {q = endCell.q, r = endCell.r, farthest = true})
        end
    end
    return cells
end

-- ================== STONE THROW (AoePushAttack) ==================
combat.AoePushAttack = setmetatable({}, combat.Attack)
combat.AoePushAttack.__index = combat.AoePushAttack

function combat.AoePushAttack.new()
    local self = combat.Attack.new("Stone Throw", "Throw a stone at adjacent cell, pushing enemies in a cone", 1, 0, {})
    return setmetatable(self, combat.AoePushAttack)
end

function combat.AoePushAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then
        return false, "Target must be adjacent!"
    end
    if not hex:isActiveHex(targetQ, targetR) then
        return false, "Cannot target outside the active area"
    end

    -- Create stone at target cell (if free)
    local centerEntity = combat.getEntityAtHex(targetQ, targetR, entities)
    if centerEntity then
        self:dealDamageToTarget(centerEntity, attacker, 1, entities, sounds, nil)
    elseif terrainMap and terrainMap[targetQ] and terrainMap[targetQ][targetR] == "water" then
        local cx, cy = hex:hexToPixel(targetQ, targetR)
        visual.addEffect(cx, cy, "drown", 0.3)
    else
        local stone = Entity.new("Stone", Entity.TYPES.OBSTACLE, targetQ, targetR, 1, false, 0, nil, nil, {})
        stone.isPushable = true
        stone.color = {0.5,0.5,0.5,1}
        table.insert(entities, stone)
    end

    -- Direction from attacker to target
    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighborsInDirection = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)

    local pushedTargets = {}
    for _, nb in ipairs(neighborsInDirection) do
        local target = combat.getEntityAtHex(nb.q, nb.r, entities)
        if target and target:isCharacter() and target.health > 0 then
            local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dirX, dirY, dirZ)
            table.insert(pushedTargets, {
                entity = target,
                fromCell = {q = nb.q, r = nb.r},
                pushTo = {q = pushQ, r = pushR}
            })
        end
    end

    attack_effects.stoneThrow(targetQ, targetR, pushedTargets, hex)

    for _, pd in ipairs(pushedTargets) do
        self:pushTargetToHex(pd.entity, pd.fromCell.q, pd.fromCell.r, pd.pushTo.q, pd.pushTo.r, hex, entities, sounds)
    end

    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end

-- Preview for Stone Throw
function combat.AoePushAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return {} end
    if not hex:isActiveHex(targetQ, targetR) then return {} end

    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighbors = self:getNeighborsInDirection(targetQ, targetR, dirQ, dirR, hex)
    local cells = {}
    for _, nb in ipairs(neighbors) do
        local target = combat.getEntityAtHex(nb.q, nb.r, entities)
        if target and target:isCharacter() and target.health > 0 then
            local cX, cY, cZ = hex_utils.axialToCube(targetQ, targetR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dX, dY, dZ)
            table.insert(cells, {
                target = target,
                fromCell = {q = nb.q, r = nb.r},
                pushTo = {q = pushQ, r = pushR, edge = not hex:isActiveHex(pushQ, pushR)}
            })
        end
    end
    return cells
end


-- 6. AoE DIRECTIONAL (Cone Blast) — pushes 3 front neighbors of attacker
combat.AoeDirectionalAttack = setmetatable({}, combat.Attack)
combat.AoeDirectionalAttack.__index = combat.AoeDirectionalAttack
function combat.AoeDirectionalAttack.new()
    local self = combat.Attack.new("Cone Blast", "Pushes 3 front enemies away from the attacker", 1, 0, {})
    return setmetatable(self, combat.AoeDirectionalAttack)
end

function combat.AoeDirectionalAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then
        return false, "Target must be adjacent! (select direction)"
    end
    if not hex:isActiveHex(targetQ, targetR) then
        return false, "Target cell is not active"
    end

    attack_effects.coneBlast(attacker.q, attacker.r, hex)
    sounds.play("cone_blast")

    -- Direction from attacker to clicked cell
    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighborsInDirection = self:getNeighborsInDirection(attacker.q, attacker.r, dirQ, dirR, hex)

    for _, nb in ipairs(neighborsInDirection) do
        if hex:isActiveHex(nb.q, nb.r) then
            local target = combat.getEntityAtHex(nb.q, nb.r, entities)
            if target and target:isCharacter() and target.health > 0 then
                local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
                local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
                local dX, dY, dZ = nX - aX, nY - aY, nZ - aZ
                local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dX, dY, dZ)
                self:pushTargetToHex(target, nb.q, nb.r, pushQ, pushR, hex, entities, sounds)
            end
        end
    end

    combat.startPushAnimations(hex)
    attacker.hasActedThisTurn = true
    return true
end

function combat.AoeDirectionalAttack:getPushCells(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return {} end

    local dirQ, dirR = targetQ - attacker.q, targetR - attacker.r
    local neighbors = self:getNeighborsInDirection(attacker.q, attacker.r, dirQ, dirR, hex)
    local cells = {}
    for _, neighbor in ipairs(neighbors) do
        local target = combat.getEntityAtHex(neighbor.q, neighbor.r, entities)
        if target and target:isCharacter() then
            local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
            local nX, nY, nZ = hex_utils.axialToCube(neighbor.q, neighbor.r)
            local dX, dY, dZ = nX - aX, nY - aY, nZ - aZ
            local pushQ, pushR = hex_utils.applyCubeStep(neighbor.q, neighbor.r, dX, dY, dZ)
            table.insert(cells, {
                target = target,
                fromCell = {q = neighbor.q, r = neighbor.r},
                pushTo = {q = pushQ, r = pushR, edge = not hex:isValidHex(pushQ, pushR)}
            })
        end
    end
    return cells
end

-- 7. LICH MAGIC BOLT (ignores obstacles)
-- 7. LICH MAGIC BOLT (ignores obstacles, no straight line needed)
combat.LichBoltAttack = setmetatable({}, combat.Attack)
combat.LichBoltAttack.__index = combat.LichBoltAttack

function combat.LichBoltAttack.new(range)
    local self = combat.Attack.new("Magic Bolt", "Throw a bolt that hits any target in range, ignoring obstacles and line of sight", range or 5, 1, {})
    self.minRange = 2
    return setmetatable(self, combat.LichBoltAttack)
end

function combat.LichBoltAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then
        return false, "Target too close!"
    end
    if distance > self.range then
        return false, "Target out of range"
    end

    -- Straight line check
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then
        return false, "Target not in a straight line!"
    end

    local target = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                target = e
                break
            end
        end
    end

    if not target then
        return false, "No valid target at that cell"
    end

    local damage = self.damage
    local wasDestroyed = target:takeDamage(damage)
    log.infof("combat", "%s throws a magic bolt at %s for %d damage!", attacker.name, target.name, damage)
    sounds.play("magic_bolt")

    if hex and visual then
        local x, y = getDrawCoords(target.q, target.r)
        visual.addEffect(x, y, "hit", 0.4)
    end

    if wasDestroyed then target:startDeath() end

    attack_effects.magicBolt(attacker, target, hex)

    attacker.hasActedThisTurn = true
    return true
end

function combat.LichBoltAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if dist < self.minRange or dist > self.range then
        return nil
    end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                return {q = targetQ, r = targetR}
            end
        end
    end
    return nil
end

-- 7b. POWER LICH: lethal bolt (99 damage) on target and 3 cells ahead
combat.PowerLichBoltAttack = setmetatable({}, combat.Attack)
combat.PowerLichBoltAttack.__index = combat.PowerLichBoltAttack

function combat.PowerLichBoltAttack.new(range)
    local self = combat.Attack.new("Power Bolt", "Lethal bolt hitting target and 3 cells in front", range or 5, 99, {})
    self.minRange = 2
    return setmetatable(self, combat.PowerLichBoltAttack)
end

function combat.PowerLichBoltAttack:getConeCells(attacker, targetQ, targetR, hex)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return {{q = targetQ, r = targetR}} end
    local cells = {{q = targetQ, r = targetR}}
    -- Cell directly in front of the target
    local q1, r1 = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
    table.insert(cells, {q = q1, r = r1})
    -- Cells on the sides (+-60 degrees)
    local sx1, sy1, sz1 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, true)
    local sx2, sy2, sz2 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, false)
    local q2, r2 = hex_utils.applyCubeStep(targetQ, targetR, sx1, sy1, sz1)
    local q3, r3 = hex_utils.applyCubeStep(targetQ, targetR, sx2, sy2, sz2)
    table.insert(cells, {q = q2, r = r2})
    table.insert(cells, {q = q3, r = r3})
    return cells
end

function combat.PowerLichBoltAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return false, "Target too close!" end
    if distance > self.range then return false, "Target out of range" end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Target not in a straight line!" end

    local cells = self:getConeCells(attacker, targetQ, targetR, hex)
    local anyHit = false
    for _, cell in ipairs(cells) do
        local target = nil
        for _, e in ipairs(entities) do
            if e.q == cell.q and e.r == cell.r and e.health > 0 then
                if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                    target = e
                    break
                end
            end
        end
        if target then
            local wasDestroyed = target:takeDamage(self.damage)
            log.infof("combat", "Power Lich's bolt hits %s for %d damage!", target.name, self.damage)
            sounds.play("power_bolt")
            if hex and visual then
                local x, y = getDrawCoords(target.q, target.r)
                visual.addEffect(x, y, "hit", 0.4)
            end
            if wasDestroyed then
                target:startDeath()
                if target.isPlayable then
                    _G.lichKilledPlayer = true
                end
            end
            anyHit = true
        end
    end

    if anyHit then
        attack_effects.magicBolt(attacker, cells[1], hex) -- visual on primary target
        attacker.hasActedThisTurn = true
    end
    return anyHit
end

function combat.PowerLichBoltAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if dist < self.minRange or dist > self.range then return nil end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            if (e:isCharacter() and e.isPlayable) or e:isBuilding() then
                return {q = targetQ, r = targetR}
            end
        end
    end
    return nil
end

function combat.PowerLichBoltAttack:getAffectedCells(attacker, targetQ, targetR, hex, entities)
    local cells = self:getConeCells(attacker, targetQ, targetR, hex)
    for _, cell in ipairs(cells) do
        cell.damage = self.damage
    end
    return cells
end

-- 8. GHOST: magic projectile with unlimited range, first target on line, damage 2
combat.GhostBoltAttack = setmetatable({}, combat.Attack)
combat.GhostBoltAttack.__index = combat.GhostBoltAttack

function combat.GhostBoltAttack.new()
    local self = combat.Attack.new("Ghost Bolt", "Piercing shot with unlimited range, hits first target", math.huge, 1, {})
    return setmetatable(self, combat.GhostBoltAttack)
end

function combat.GhostBoltAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget then return false, "No target in that direction!" end

    -- Deal damage (no knockback)
    self:dealDamageToTarget(firstTarget, attacker, self.damage, entities, sounds, nil)
    attacker.hasActedThisTurn = true

    attack_effects.ghostBolt(attacker, firstTarget, hex)
    return true
end

-- For preview
function combat.GhostBoltAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        return targetHex
    end
    return nil
end

-- 9. ZOMBIE: point-blank attack, damage 3
combat.ZombieBiteAttack = setmetatable({}, combat.Attack)
combat.ZombieBiteAttack.__index = combat.ZombieBiteAttack

function combat.ZombieBiteAttack.new()
    local self = combat.Attack.new("Bite", "Devastating bite at close range", 1, 1, {})
    return setmetatable(self, combat.ZombieBiteAttack)
end

function combat.ZombieBiteAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end

    local target = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            target = e
            break
        end
    end
    if not target then return false, "No target at that hex" end

    attack_effects.bite(attacker, target, hex)

    self:dealDamageToTarget(target, attacker, self.damage, entities, sounds, nil)
    attacker.hasActedThisTurn = true
    return true
end

function combat.ZombieBiteAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) == 1 then
        local target = nil
        for _, e in ipairs(entities) do
            if e.q == targetQ and e.r == targetR and e.health > 0 then
                target = e
                break
            end
        end
        if target then return {q = targetQ, r = targetR} end
    end
    return nil
end

-- ============================================================
-- SUMMON (minion summon)
-- ============================================================
combat.SummonAttack = setmetatable({}, combat.Attack)
combat.SummonAttack.__index = combat.SummonAttack
function combat.SummonAttack.new(range)
    local self = combat.Attack.new("Summon", "Summon a minion at target cell", range or 5, 0, {})
    self.minRange = 2
    return setmetatable(self, combat.SummonAttack)
end

function combat.SummonAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return false, "Target too close! (minimum 2)" end
    if not hex:isActiveHex(targetQ, targetR) then return false, "Target cell not active" end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local occupant = combat.getEntityAtHex(targetQ, targetR, entities)
    if occupant then return false, "Cell occupied" end

    local sprite = sprites.get(42)
    local minion = Entity.new("Summoned", Entity.TYPES.CHARACTER, targetQ, targetR, 2, true, 2, sprite, sprite and nil or {0.6, 0.3, 0.9}, {
        { attack = combat.PushAttack.new(5), name = "Push", description = "Push first enemy in line" },
    })
    minion.lifetime = -1
    table.insert(entities, minion)

    local fx, fy = getDrawCoords(targetQ, targetR)
    visual.addMagicExplosion(fx, fy, 0.6, 0.2, 1.0)
    sounds.play("summon_attack")

    attacker.hasActedThisTurn = true
    return true
end

function combat.SummonAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return nil end
    if not hex:isActiveHex(targetQ, targetR) then return nil end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local occupant = combat.getEntityAtHex(targetQ, targetR, entities)
    if occupant then return nil end
    return {q = targetQ, r = targetR}
end

-- ============================================================
-- DIVIDER (split)
-- ============================================================
combat.DividerAttack = setmetatable({}, combat.SummonAttack)
combat.DividerAttack.__index = combat.DividerAttack
function combat.DividerAttack.new(range)
    local self = combat.Attack.new("Split", "Split into two Divided units", range or 5, 0, {})
    self.minRange = 2
    return setmetatable(self, combat.DividerAttack)
end

function combat.DividerAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return false, "Target too close! (minimum 2)" end
    if not hex:isActiveHex(targetQ, targetR) then return false, "Target cell not active" end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local occupant = combat.getEntityAtHex(targetQ, targetR, entities)
    if occupant then return false, "Cell occupied" end

    local sprite44 = sprites.get(44)

    -- Create Divided at target cell
    local divided = Entity.new("Divided", Entity.TYPES.CHARACTER, targetQ, targetR, 2, true, 3, sprite44, sprite44 and nil or {0.6, 0.4, 0.1}, {})
    divided.hasActedThisTurn = true
    table.insert(entities, divided)

    -- Transform attacker into Divided
    attacker.name = "Divided"
    attacker.maxHealth = 2
    attacker.health = math.min(attacker.health, 2)
    attacker.moveRange = 3
    attacker.sprite = sprite44
    attacker.color = sprite44 and nil or {0.6, 0.4, 0.1}
    attacker.attacks = {}
    attacker.hasActedThisTurn = true

    local fx1, fy1 = getDrawCoords(attacker.q, attacker.r)
    local fx2, fy2 = getDrawCoords(targetQ, targetR)
    visual.addMagicExplosion(fx1, fy1, 0.9, 0.7, 0.1)
    visual.addMagicExplosion(fx2, fy2, 0.9, 0.7, 0.1)
    sounds.play("split_attack")

    return true
end

-- ============================================================
-- SUMMON ENEMY (summoning rod)
-- ============================================================
combat.SummonEnemyAttack = setmetatable({}, combat.Attack)
combat.SummonEnemyAttack.__index = combat.SummonEnemyAttack

function combat.SummonEnemyAttack.new()
    local self = combat.Attack.new("Summon", "Summon a random enemy unit", 1, 0, {})
    return setmetatable(self, combat.SummonEnemyAttack)
end

function combat.SummonEnemyAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    if not attacker.isSummoningRod then return false end

    local sq, sr = attacker.summonTargetQ, attacker.summonTargetR
    if not sq or not sr then return false end

    -- If cell is occupied — 2 damage to occupant
    local occupant = combat.getEntityAtHex(sq, sr, entities)
    if occupant and occupant.health > 0 then
        local wasDestroyed = occupant:takeDamage(1)
        log.infof("combat", "SummoningRod: %s takes 2 damage from occupied summon cell!", occupant.name)
        sounds.play("summon_enemy")
        local fx, fy = getDrawCoords(sq, sr)
        visual.addEffect(fx, fy, "hit", 0.4)
        if wasDestroyed then occupant:startDeath() end
        attacker.hasActedThisTurn = true
        return true
    end

    -- Create a random enemy on the target cell
    if hex:isActiveHex(sq, sr) then
        local newEnemy = env.createRandomEnemy(sq, sr)
        table.insert(entities, newEnemy)
        local fx, fy = getDrawCoords(sq, sr)
        visual.addMagicExplosion(fx, fy, 0.6, 0.4, 0.2)
        sounds.play("summon_enemy")
        log.infof("combat", "SummoningRod summons %s at (%d,%d)!", newEnemy.name, sq, sr)
    end

    attacker.hasActedThisTurn = true
    return true
end

-- ============================================================
-- VORTEX STRIKE
-- ============================================================
combat.VortexStrikeAttack = setmetatable({}, combat.Attack)
combat.VortexStrikeAttack.__index = combat.VortexStrikeAttack
function combat.VortexStrikeAttack.new()
    local self = combat.Attack.new("Vortex Strike", "Shift an enemy right or left and deal 1 damage", 1, 1, {})
    return setmetatable(self, combat.VortexStrikeAttack)
end

function combat.VortexStrikeAttack:getLineTarget(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return nil end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local occupant = combat.getEntityAtHex(targetQ, targetR, entities)
    if occupant and occupant:isCharacter() and occupant.health > 0 then
        return {q = targetQ, r = targetR, entity = occupant}
    end
    return nil
end

function combat.VortexStrikeAttack:getShiftDestinations(attacker, targetQ, targetR, hex)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return {} end
    local cells = {}
    -- 60° rotation around attacker: right (CW) and left (CCW)
    local rq, rr = hex_utils.applyCubeStep(attacker.q, attacker.r, -stepY, -stepZ, -stepX)
    if hex:isActiveHex(rq, rr) then
        table.insert(cells, {q = rq, r = rr, dir = "right"})
    end
    local lq, lr = hex_utils.applyCubeStep(attacker.q, attacker.r, -stepZ, -stepX, -stepY)
    if hex:isActiveHex(lq, lr) then
        table.insert(cells, {q = lq, r = lr, dir = "left"})
    end
    return cells
end

function combat.VortexStrikeAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end
    if not hex:isActiveHex(targetQ, targetR) then return false, "Target cell not active" end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local target = combat.getEntityAtHex(targetQ, targetR, entities)
    if not target or not target:isCharacter() or target.health <= 0 then
        return false, "No valid enemy at target cell"
    end
    local destCell = self._vortexDestCell
    if not destCell then return false, "No shift destination selected" end
    self._vortexDestCell = nil
    if not hex:isActiveHex(destCell.q, destCell.r) then return false, "Destination cell not active" end
    if target.isPushable ~= false then
        local occupant = combat.getEntityAtHex(destCell.q, destCell.r, entities)
        if occupant then
            combat.addCollisionBounceAnimation(target, targetQ, targetR, destCell.q, destCell.r, hex, entities, sounds, occupant)
        else
            combat.addPushAnimation(target, targetQ, targetR, destCell.q, destCell.r)
        end
        combat.startPushAnimations(hex)
    end
    self:dealDamageToTarget(target, attacker, self.damage, entities, sounds)
    attacker.hasActedThisTurn = true
    return true
end

function combat.VortexStrikeAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    return {q = targetQ, r = targetR}
end

-- ============================================================
-- WIDE VORTEX (reuses getLineTarget and getShiftDestinations from VortexStrike)
-- ============================================================
combat.WideVortexAttack = setmetatable({}, combat.VortexStrikeAttack)
combat.WideVortexAttack.__index = combat.WideVortexAttack
function combat.WideVortexAttack.new()
    local self = combat.Attack.new("Wide Vortex", "Shift target enemy and a second enemy right or left", 1, 0, {})
    return setmetatable(self, combat.WideVortexAttack)
end

function combat.WideVortexAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end
    if not hex:isActiveHex(targetQ, targetR) then return false, "Target cell not active" end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end
    local shiftDir = self._vortexShiftDir
    if not shiftDir then return false, "No shift direction selected" end
    self._vortexShiftDir = nil
    local ax, ay, az = hex_utils.axialToCube(attacker.q, attacker.r)
    local cx, cy, cz = hex_utils.axialToCube(targetQ, targetR)
    local dx, dy, dz = cx - ax, cy - ay, cz - az
    local dirDX, dirDY, dirDZ
    if shiftDir == "right" then
        dirDX, dirDY, dirDZ = -dy, -dz, -dx
    else
        dirDX, dirDY, dirDZ = -dz, -dx, -dy
    end
    -- Primary target A: push to first destination
    local destQ, destR = hex_utils.cubeToAxial(ax + dirDX, ay + dirDY, az + dirDZ)
    local targetA = combat.getEntityAtHex(targetQ, targetR, entities)
    if targetA and targetA:isCharacter() and targetA.health > 0 and targetA.isPushable ~= false then
        local occupantB = combat.getEntityAtHex(destQ, destR, entities)
        if occupantB then
            if occupantB.isHazard then
                combat.addPushAnimation(targetA, targetQ, targetR, destQ, destR)
            elseif occupantB.isPushable == false then
                combat.addCollisionBounceAnimation(targetA, targetQ, targetR, destQ, destR, hex, entities, sounds, occupantB)
            else
                local b2q, b2r
                if shiftDir == "right" then
                    b2q, b2r = hex_utils.cubeToAxial(ax + dz, ay + dx, az + dy)
                else
                    b2q, b2r = hex_utils.cubeToAxial(ax + dy, ay + dz, az + dx)
                end
                if hex:isActiveHex(b2q, b2r) and not combat.getEntityAtHex(b2q, b2r, entities) then
                    combat.addPushAnimation(targetA, targetQ, targetR, destQ, destR)
                    combat.addPushAnimation(occupantB, destQ, destR, b2q, b2r)
                else
                    combat.addCollisionBounceAnimation(targetA, targetQ, targetR, destQ, destR, hex, entities, sounds, occupantB)
                    local occupantAtB2 = hex:isActiveHex(b2q, b2r) and combat.getEntityAtHex(b2q, b2r, entities) or nil
                    combat.addCollisionBounceAnimation(occupantB, destQ, destR, b2q, b2r, hex, entities, sounds, occupantAtB2)
                end
            end
        else
            combat.addPushAnimation(targetA, targetQ, targetR, destQ, destR)
        end
        combat.startPushAnimations(hex)
    end
    sounds.play("wide_vortex")
    attacker.hasActedThisTurn = true
    return true
end

-- ============================================================
combat.PullHookAttack = setmetatable({}, combat.Attack)
combat.PullHookAttack.__index = combat.PullHookAttack

function combat.PullHookAttack.new()
    local self = combat.Attack.new("Pull Hook", "Hook a target on a straight line, move to a chosen cell and pull it towards you", 999, 0, {})
    return setmetatable(self, combat.PullHookAttack)
end

function combat.PullHookAttack:getLineTarget(attacker, targetQ, targetR, hex, entities)
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    local firstTarget, targetHex = self:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        local dist = hex:getDistance(attacker.q, attacker.r, targetHex.q, targetHex.r)
        if dist < 2 then return nil end
        return {q = targetHex.q, r = targetHex.r, entity = firstTarget}
    end
    return nil
end

function combat.PullHookAttack:getPullHookMoveCells(attacker, stepX, stepY, stepZ, hookTargetQ, hookTargetR, hex, entities)
    local cells = {}
    -- Attacker can always stay in place
    table.insert(cells, {q = attacker.q, r = attacker.r})
    local curQ, curR = attacker.q, attacker.r
    while true do
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isValidHex(nextQ, nextR) then break end
        if nextQ == hookTargetQ and nextR == hookTargetR then break end
        if hex:isActiveHex(nextQ, nextR) then
            local occupied = false
            for _, e in ipairs(entities) do
                if e.health > 0 and e.q == nextQ and e.r == nextR then
                    occupied = true
                    break
                end
            end
            if not occupied then
                table.insert(cells, {q = nextQ, r = nextR})
            end
        end
        curQ, curR = nextQ, nextR
    end
    return cells
end

function combat.PullHookAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local hookTarget = self._pullHookTarget
    if not hookTarget then return false, "No hook target!" end
    self._pullHookTarget = nil

    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, hookTarget.q, hookTarget.r, hex)
    if not stepX then return false, "Not a straight line!" end

    local targetEntity = combat.getEntityAtHex(hookTarget.q, hookTarget.r, entities)
    if not targetEntity or targetEntity.health <= 0 or targetEntity.isPushable == false then return false, "Target is gone!" end

    local moveQ, moveR = targetQ, targetR
    local isStationary = (moveQ == attacker.q and moveR == attacker.r)

    if isStationary then
        -- Attacker stays in place, pull target directly
        local pullQ, pullR = hex_utils.applyCubeStep(moveQ, moveR, stepX, stepY, stepZ)
        if hex:isActiveHex(pullQ, pullR) and not combat.getEntityAtHex(pullQ, pullR, entities) then
            combat.addDirectPushAnimation(targetEntity, hookTarget.q, hookTarget.r, pullQ, pullR)
            combat.startPushAnimations(hex)
        end
    else
        -- Animate attacker moving to selected cell, then pull target
        combat.addDirectPushAnimation(attacker, attacker.q, attacker.r, moveQ, moveR)
        combat.startPushAnimations(hex, function()
            local pullQ, pullR = hex_utils.applyCubeStep(moveQ, moveR, stepX, stepY, stepZ)
            if hex:isActiveHex(pullQ, pullR) and not combat.getEntityAtHex(pullQ, pullR, entities) then
                combat.addDirectPushAnimation(targetEntity, hookTarget.q, hookTarget.r, pullQ, pullR)
                combat.startPushAnimations(hex)
            end
        end)
    end

    sounds.play("pull_hook")
    attacker.hasActedThisTurn = true
    return true
end

-- ============================================================
combat.ElectricHookAttack = setmetatable({}, combat.Attack)
combat.ElectricHookAttack.__index = combat.ElectricHookAttack

function combat.ElectricHookAttack.new()
    local self = combat.Attack.new("Electric Hook", "Arc lightning that damages everyone between you and target", 999, 0, {})
    self.minRange = 2
    return setmetatable(self, combat.ElectricHookAttack)
end

function combat.ElectricHookAttack:getLineTarget(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return nil end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return nil end
    return {q = targetQ, r = targetR, entity = nil}
end

function combat.ElectricHookAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance < self.minRange then return false, "Target too close!" end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not a straight line!" end

    -- Deal 1 damage to everyone on the line (including attacker, excluding entities past target)
    self:dealDamageToTarget(attacker, attacker, 1, entities, sounds, nil)
    local curQ, curR = attacker.q, attacker.r
    while true do
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not hex:isValidHex(nextQ, nextR) then break end
        local e = combat.getEntityAtHex(nextQ, nextR, entities)
        if e and e.health > 0 and e ~= attacker then
            self:dealDamageToTarget(e, attacker, 1, entities, sounds, nil)
        end
        if nextQ == targetQ and nextR == targetR then break end
        curQ, curR = nextQ, nextR
    end

    -- Visual: arc along the line
    local fx, fy = getDrawCoords(attacker.q, attacker.r)
    local tx, ty = getDrawCoords(targetQ, targetR)
    visual.addArcEffect(fx, fy, tx, ty, 0.3, 0.8, 1.0, 0.5)

    sounds.play("electric_hook")
    attacker.hasActedThisTurn = true
    return true
end

-- ============================================================
-- BASH: melee, 2 damage to target + 2 damage behind the attacker
-- ============================================================
combat.BashAttack = setmetatable({}, combat.Attack)
combat.BashAttack.__index = combat.BashAttack

function combat.BashAttack.new()
    local self = combat.Attack.new("Bash", "Melee attack, 1 damage to target and behind attacker", 1, 1, {})
    return setmetatable(self, combat.BashAttack)
end

function combat.BashAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end

    local target = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            target = e
            break
        end
    end
    if not target then return false, "No target at that hex" end

    self:dealDamageToTarget(target, attacker, self.damage, entities, sounds, nil)

    -- Target behind attacker: direction from target to attacker, then one more step past attacker
    local stepX, stepY, stepZ = self:getLineDirection(targetQ, targetR, attacker.q, attacker.r, hex)
    if stepX then
        local behindQ, behindR = hex_utils.applyCubeStep(attacker.q, attacker.r, stepX, stepY, stepZ)
        local behindEntity = nil
        for _, e in ipairs(entities) do
            if e.q == behindQ and e.r == behindR and e.health > 0 then
                behindEntity = e
                break
            end
        end
        if behindEntity then
            self:dealDamageToTarget(behindEntity, attacker, self.damage, entities, sounds, nil)
        end
    end

    attacker.hasActedThisTurn = true
    return true
end

function combat.BashAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) == 1 then
        for _, e in ipairs(entities) do
            if e.q == targetQ and e.r == targetR and e.health > 0 then
                return {q = targetQ, r = targetR}
            end
        end
    end
    return nil
end

function combat.BashAttack:getAffectedCells(attacker, targetQ, targetR, hex, entities)
    local cells = {{q = targetQ, r = targetR, damage = self.damage}}
    -- Target behind attacker
    local stepX, stepY, stepZ = self:getLineDirection(targetQ, targetR, attacker.q, attacker.r, hex)
    if stepX then
        local behindQ, behindR = hex_utils.applyCubeStep(attacker.q, attacker.r, stepX, stepY, stepZ)
        table.insert(cells, {q = behindQ, r = behindR, damage = self.damage})
    end
    return cells
end

-- ============================================================
-- CLEAVE: melee, 1 damage to three targets in front
-- ============================================================
combat.CleaveAttack = setmetatable({}, combat.Attack)
combat.CleaveAttack.__index = combat.CleaveAttack

function combat.CleaveAttack.new()
    local self = combat.Attack.new("Cleave", "Melee attack, 1 damage to three targets in front", 1, 1, {})
    return setmetatable(self, combat.CleaveAttack)
end

function combat.CleaveAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end

    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if not stepX then return false, "Not on a straight line" end

    -- Three cells: central target + two side cells (direction rotated +-60)
    local cells = {{q = targetQ, r = targetR}}
    local sx1, sy1, sz1 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, true)
    local sx2, sy2, sz2 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, false)
    local side1Q, side1R = hex_utils.applyCubeStep(attacker.q, attacker.r, sx1, sy1, sz1)
    local side2Q, side2R = hex_utils.applyCubeStep(attacker.q, attacker.r, sx2, sy2, sz2)
    table.insert(cells, {q = side1Q, r = side1R})
    table.insert(cells, {q = side2Q, r = side2R})

    for _, cell in ipairs(cells) do
        local target = nil
        for _, e in ipairs(entities) do
            if e.q == cell.q and e.r == cell.r and e.health > 0 then
                target = e
                break
            end
        end
        if target then
            self:dealDamageToTarget(target, attacker, self.damage, entities, sounds, nil)
        end
    end

    attacker.hasActedThisTurn = true
    return true
end

function combat.CleaveAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) == 1 then
        return {q = targetQ, r = targetR}
    end
    return nil
end

function combat.CleaveAttack:getAffectedCells(attacker, targetQ, targetR, hex, entities)
    local cells = {{q = targetQ, r = targetR, damage = self.damage}}
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if stepX then
        local sx1, sy1, sz1 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, true)
        local sx2, sy2, sz2 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, false)
        local side1Q, side1R = hex_utils.applyCubeStep(attacker.q, attacker.r, sx1, sy1, sz1)
        local side2Q, side2R = hex_utils.applyCubeStep(attacker.q, attacker.r, sx2, sy2, sz2)
        table.insert(cells, {q = side1Q, r = side1R, damage = self.damage})
        table.insert(cells, {q = side2Q, r = side2R, damage = self.damage})
    end
    return cells
end

-- ============================================================
-- LUNGE: melee, 2 damage to target + 2 damage to target behind it
-- ============================================================
combat.LungeAttack = setmetatable({}, combat.Attack)
combat.LungeAttack.__index = combat.LungeAttack

function combat.LungeAttack.new()
    local self = combat.Attack.new("Lunge", "Melee attack, 1 damage to target and the target behind it", 1, 1, {})
    return setmetatable(self, combat.LungeAttack)
end

function combat.LungeAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end

    local target = nil
    for _, e in ipairs(entities) do
        if e.q == targetQ and e.r == targetR and e.health > 0 then
            target = e
            break
        end
    end
    if not target then return false, "No target at that hex" end

    self:dealDamageToTarget(target, attacker, self.damage, entities, sounds, nil)

    -- Target behind target: continue the line from attacker through target
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if stepX then
        local behindQ, behindR = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
        local behindEntity = nil
        for _, e in ipairs(entities) do
            if e.q == behindQ and e.r == behindR and e.health > 0 then
                behindEntity = e
                break
            end
        end
        if behindEntity then
            self:dealDamageToTarget(behindEntity, attacker, self.damage, entities, sounds, nil)
        end
    end

    attacker.hasActedThisTurn = true
    return true
end

function combat.LungeAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    if hex:getDistance(attacker.q, attacker.r, targetQ, targetR) == 1 then
        for _, e in ipairs(entities) do
            if e.q == targetQ and e.r == targetR and e.health > 0 then
                return {q = targetQ, r = targetR}
            end
        end
    end
    return nil
end

function combat.LungeAttack:getAffectedCells(attacker, targetQ, targetR, hex, entities)
    local cells = {{q = targetQ, r = targetR, damage = self.damage}}
    -- Target behind target
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if stepX then
        local behindQ, behindR = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
        table.insert(cells, {q = behindQ, r = behindR, damage = self.damage})
    end
    return cells
end

-- ============================================================
-- HEAVY PUNCH: 2 damage + knockback
-- ============================================================
combat.HeavyPunchAttack = setmetatable({}, combat.Attack)
combat.HeavyPunchAttack.__index = combat.HeavyPunchAttack

function combat.HeavyPunchAttack.new()
    local self = combat.Attack.new("Heavy Punch", "Melee attack, 1 damage, pushes target away. Lethal if empowered", 1, 1, {})
    return setmetatable(self, combat.HeavyPunchAttack)
end

function combat.HeavyPunchAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end
    if not hex:isActiveHex(targetQ, targetR) then return false, "Target cell not active" end

    local target = combat.getEntityAtHex(targetQ, targetR, entities)
    if not target or target.health <= 0 then return false, "No valid target at that hex" end

    if status.hasEntityStatus(attacker, "punch_charged") then
        target.health = 0
        target:startDeath()
        status.removeFromEntity(attacker, "punch_charged")
        log.infof("combat", "%s lands a lethal Heavy Punch on %s!", attacker.name, target.name)
    else
        -- Push first, then damage
        local stepX, stepY, stepZ
        if self._pushDirOverride then
            stepX, stepY, stepZ = self._pushDirOverride.x, self._pushDirOverride.y, self._pushDirOverride.z
            self._pushDirOverride = nil
        else
            stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
        end
        if stepX then
            local pushQ, pushR = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
            self:pushTargetToHex(target, targetQ, targetR, pushQ, pushR, hex, entities, sounds)
            combat.startPushAnimations(hex)
        end
        self:dealDamageToTarget(target, attacker, self.damage, entities, sounds, nil)
    end

    attacker.hasActedThisTurn = true
    return true
end

function combat.HeavyPunchAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance <= self.range then
        local target = combat.getEntityAtHex(targetQ, targetR, entities)
        if target and target.health > 0 then
            return {q = targetQ, r = targetR}
        end
    end
    return nil
end

function combat.HeavyPunchAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then return nil end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if stepX then
        local pushQ, pushR = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
        return {q = pushQ, r = pushR, edge = not hex:isActiveHex(pushQ, pushR)}
    end
    return nil
end

-- ============================================================
-- EMPOWER PUNCH: 1 damage + knockback + double damage next
-- ============================================================
combat.EmpowerPunchAttack = setmetatable({}, combat.Attack)
combat.EmpowerPunchAttack.__index = combat.EmpowerPunchAttack

function combat.EmpowerPunchAttack.new()
    local self = combat.Attack.new("Empower Punch", "Pushes target, doubles next attack damage. Deals 1 damage if empowered", 1, 0, {})
    return setmetatable(self, combat.EmpowerPunchAttack)
end

function combat.EmpowerPunchAttack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance ~= 1 then return false, "Target must be adjacent!" end
    if not hex:isActiveHex(targetQ, targetR) then return false, "Target cell not active" end

    local target = combat.getEntityAtHex(targetQ, targetR, entities)
    if not target or target.health <= 0 then return false, "No valid target at that hex" end

    local punchCharged = status.hasEntityStatus(attacker, "punch_charged")
    if punchCharged then
        target:takeDamage(1)
        status.removeFromEntity(attacker, "punch_charged")
    end

    -- Push first, then damage
    local stepX, stepY, stepZ
    if self._pushDirOverride then
        stepX, stepY, stepZ = self._pushDirOverride.x, self._pushDirOverride.y, self._pushDirOverride.z
        self._pushDirOverride = nil
    else
        stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    end
    if stepX then
        local pushQ, pushR = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
        self:pushTargetToHex(target, targetQ, targetR, pushQ, pushR, hex, entities, sounds)
        combat.startPushAnimations(hex)
    end
    if punchCharged then
        self:dealDamageToTarget(target, attacker, 1, entities, sounds, nil)
    end

    -- Charges the next Heavy Punch (lethal) or Empower Punch (+1 damage)
    status.applyToEntity(attacker, "punch_charged")

    attacker.hasActedThisTurn = true
    return true
end

function combat.EmpowerPunchAttack:getTargetCell(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance <= self.range then
        local target = combat.getEntityAtHex(targetQ, targetR, entities)
        if target and target.health > 0 then
            return {q = targetQ, r = targetR}
        end
    end
    return nil
end

function combat.EmpowerPunchAttack:getPushCell(attacker, targetQ, targetR, hex, entities)
    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    if distance > self.range then return nil end
    local stepX, stepY, stepZ = self:getLineDirection(attacker.q, attacker.r, targetQ, targetR, hex)
    if stepX then
        local pushQ, pushR = hex_utils.applyCubeStep(targetQ, targetR, stepX, stepY, stepZ)
        return {q = pushQ, r = pushR, edge = not hex:isActiveHex(pushQ, pushR)}
    end
    return nil
end

-- ============================================================
-- AURA: quagmire (passive, reduces speed by 2, min 1)
-- ============================================================

-- Checks if entity is within enemy aura radius
function combat.isInSlowingAura(entity, entities, hex)
    if entity.rootImmune then return false end
    for _, e in ipairs(entities) do
        if e ~= entity and e.health > 0 and e.aura and e.aura.type == "slow" then
            local dist = hex:getDistance(entity.q, entity.r, e.q, e.r)
            if dist <= e.aura.radius then
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- ANIMATION QUEUE
-- ============================================================
pushAnimations = { queue = {}, active = false }

function combat.addPushAnimation(obj, fromQ, fromR, toQ, toR, onComplete)

    -- Add wind effect from start cell to destination cell
    local startX, startY = getDrawCoords(fromQ, fromR)
    local endX, endY = getDrawCoords(toQ, toR)
    visual.addPushEffect(startX, startY, endX, endY, 0.25)

    table.insert(pushAnimations.queue, {
        obj = obj, fromQ = fromQ, fromR = fromR, toQ = toQ, toR = toR,
        startX = 0, startY = 0, endX = 0, endY = 0, timer = 0, duration = 0.2,
        isMoving = false,
        onComplete = function(pushedObj)
            -- Check if target cell is free (skip hazard zones)
            local occupant = combat.getEntityAtHex(toQ, toR, entities)
            if occupant and occupant ~= pushedObj and occupant.health > 0 and not occupant.isHazard then
                -- Lethal collision: instant death
                if occupant.lethalCollision then
                    pushedObj.health = 0
                    pushedObj:startDeath()
                    log.infof("combat", "%s collides with %s! Instant death!", pushedObj.name, occupant.name)
                    sounds.play("collision")
                    return
                end
                -- Collision: damage to pushed unit, immovable targets take no damage
                if pushedObj.health and pushedObj.health > 0 then
                    pushedObj.health = pushedObj.health - 1
                    log.infof("combat", "%s collides with %s! %s takes 1 damage!", pushedObj.name, occupant.name, pushedObj.name)
                    sounds.play("collision")
                end
                if occupant.health and occupant.isPushable ~= false then
                    occupant.health = occupant.health - 1
                    if occupant.health <= 0 then
                        occupant:startDeath()
                    end
                end
                if pushedObj.health <= 0 then
                    pushedObj:startDeath()
                end
                -- Don't move object, stays in place
                if pushedObj.health <= 0 then
                    -- If died, don't apply cell effects
                else
                    -- Apply cell effects (fire, water) at original position
                    if terrainMap then
                        effects.applyAllCellEffects(pushedObj, fromQ, fromR, terrainMap, entities)
                    end
                end
            else
                -- Cell is free – perform movement
                pushedObj.q = toQ
                pushedObj.r = toR
                -- If zombie was pushed — remove rooted from its target
                if pushedObj.rootedTarget then
                    status.removeFromEntity(pushedObj.rootedTarget, "rooted")
                    pushedObj.rootedTarget = nil
                end
                -- Apply cell effects after movement
                if pushedObj and terrainMap then
                    local died = effects.applyAllCellEffects(pushedObj, toQ, toR, terrainMap, entities)
                    if died then
                        pushedObj:startDeath()
                    end
                end
            end
            if onComplete then onComplete(pushedObj) end
        end
    })
end

-- Movement animation without collision checks (for abilities where collisions are pre-processed, e.g. Wind Torrent)
function combat.addDirectPushAnimation(obj, fromQ, fromR, toQ, toR)
    local startX, startY = getDrawCoords(fromQ, fromR)
    local endX, endY = getDrawCoords(toQ, toR)
    visual.addPushEffect(startX, startY, endX, endY, 0.25)
    table.insert(pushAnimations.queue, {
        obj = obj, fromQ = fromQ, fromR = fromR, toQ = toQ, toR = toR,
        startX = 0, startY = 0, endX = 0, endY = 0, timer = 0, duration = 0.2,
        isMoving = false,
        onComplete = function(pushedObj)
            pushedObj.q = toQ
            pushedObj.r = toR
            if pushedObj.rootedTarget then
                status.removeFromEntity(pushedObj.rootedTarget, "rooted")
                pushedObj.rootedTarget = nil
            end
            if terrainMap then
                local died = effects.applyAllCellEffects(pushedObj, toQ, toR, terrainMap, entities)
                if died then pushedObj:startDeath() end
            end
        end
    })
end

function combat.startPushAnimations(hex, callback)
    if #pushAnimations.queue == 0 then if callback then callback() end; return end
    pushAnimations.active = true
    pushAnimations.globalCallback = function()
        if callback then callback() end
        -- Here apply effects to all objects that participated in animations
        for _, anim in ipairs(pushAnimations.queue) do
            if anim.obj then
                -- but queue is already cleared? Better to store list of moved objects
            end
        end
    end
    combat.initNextPushAnimation(hex)
end

function combat.initNextPushAnimation(hex)
    if #pushAnimations.queue == 0 then
        pushAnimations.active = false
        if pushAnimations.globalCallback then
            pushAnimations.globalCallback()
            pushAnimations.globalCallback = nil
        end
        return
    end
    for _, anim in ipairs(pushAnimations.queue) do
        if not anim.isMoving then
            if not anim.isShake then
                anim.startX, anim.startY = getDrawCoords(anim.fromQ, anim.fromR)
                anim.endX, anim.endY = getDrawCoords(anim.toQ, anim.toR)
            end
            anim.timer = 0
            anim.isMoving = true
        end
    end
end

function combat.updatePushAnimations(dt, hex)
    if not pushAnimations.active or #pushAnimations.queue == 0 then return end
    local allDone = true
    local queue = pushAnimations.queue
    local i = 1
    while i <= #queue do
        local anim = queue[i]
        if anim and anim.isMoving then
            anim.timer = anim.timer + dt
            local t = math.min(1, anim.timer / anim.duration)

            local ease
            if anim.bounceBack then
                local forwardT = math.min(1, t * 1.25)
                ease = forwardT
                if t > 0.8 then
                    local backT = (t - 0.8) / 0.2
                    ease = 1 - backT
                end
            else
                ease = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
            end

            if anim.isShake then
                local x, y = getDrawCoords(anim.obj.q, anim.obj.r)
                anim.obj.currentDrawX = x + anim.offsetX * (1 - ease)
                anim.obj.currentDrawY = y + anim.offsetY * (1 - ease)
            else
                local x = anim.startX + (anim.endX - anim.startX) * ease
                local y = anim.startY + (anim.endY - anim.startY) * ease
                anim.obj.currentDrawX = x
                anim.obj.currentDrawY = y
            end

            if anim.bounceBack and anim.onPeak and t >= 0.8 and not anim._peakFired then
                anim._peakFired = true
                anim.onPeak(anim.obj)
            end

            if t >= 1 then
                if anim.isShake then
                    anim.obj.currentDrawX = nil
                    anim.obj.currentDrawY = nil
                elseif anim.bounceBack then
                    anim.obj.q = anim.fromQ
                    anim.obj.r = anim.fromR
                    anim.obj.currentDrawX = nil
                    anim.obj.currentDrawY = nil
                else
                    anim.obj.q = anim.toQ
                    anim.obj.r = anim.toR
                    anim.obj.currentDrawX = nil
                    anim.obj.currentDrawY = nil
                end
                if anim.onComplete then anim.onComplete(anim.obj) end
                queue[i] = queue[#queue]
                queue[#queue] = nil
            else
                allDone = false
                i = i + 1
            end
        end
    end
    if #pushAnimations.queue == 0 and allDone then
        pushAnimations.active = false
        if pushAnimations.globalCallback then
            pushAnimations.globalCallback()
            pushAnimations.globalCallback = nil
        end
    end
end

function combat.flushPushAnimations()
    for i = 1, 2 do
        for _, anim in ipairs(pushAnimations.queue) do
            if anim.obj and anim.toQ and anim.toR then
                if not anim.bounceBack then
                    anim.obj.q = anim.toQ
                    anim.obj.r = anim.toR
                end
                anim.obj.currentDrawX = nil
                anim.obj.currentDrawY = nil
            end
        end
        local callbacks = {}
        for _, anim in ipairs(pushAnimations.queue) do
            if anim.onComplete then
                table.insert(callbacks, { fn = anim.onComplete, obj = anim.obj })
            end
        end
        pushAnimations.queue = {}
        pushAnimations.active = false
        pushAnimations.globalCallback = nil
        for _, cb in ipairs(callbacks) do
            cb.fn(cb.obj)
        end
        if #pushAnimations.queue == 0 then break end
    end
    pushAnimations.queue = {}
    pushAnimations.active = false
    pushAnimations.globalCallback = nil
end

-- ============================================================
-- HELPER FUNCTIONS (common)
-- ============================================================
function combat.getEntityAtHex(q, r, entities)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then return e end
    end
    return nil
end

-- combat.lua (replace existing method)
function combat.Attack:dealDamageToTarget(target, attacker, damage, entities, sounds, directionIndex)
    -- Base multiplier = 1.0
    local multiplier = 1.0

    if target.armor and directionIndex and target.armor[directionIndex+1] then
        multiplier = multiplier * target.armor[directionIndex+1]
    end

    -- Weak point
    if target.weakPoint ~= nil and directionIndex == target.weakPoint then
        multiplier = multiplier * 2.0
        log.infof("combat", "Critical hit! %s hits %s's weak point!", attacker.name, target.name)
    end

    local statusMultiplier = status.getDamageMultiplier(target)
    multiplier = multiplier * statusMultiplier

    local finalDamage = math.floor(damage * multiplier)

    -- Empowered: +1 damage to direct damage attacks only
    if damage > 0 and status.hasEntityStatus(attacker, "empowered") then
        finalDamage = finalDamage + 1
    end

    -- Fatal damage: increases damage to 99 (one-time, removed after attack)
    if damage > 0 and status.hasEntityStatus(attacker, "fatal_damage") then
        finalDamage = 99
        status.removeFromEntity(attacker, "fatal_damage")
    end

    -- Point-blank lethal: Shoot at distance 1 instantly kills
    if damage > 0 and attacker.pointBlankLethal and hex then
        local dist = hex:getDistance(attacker.q, attacker.r, target.q, target.r)
        if dist == 1 then
            finalDamage = 99
        end
    end

    if finalDamage < 1 and damage > 0 then finalDamage = 1 end

    local wasDestroyed = target:takeDamage(finalDamage)
    sounds.play("attack")

    if hex and visual then
        local x, y = getDrawCoords(target.q, target.r)
        visual.addEffect(x, y, "hit", 0.4)
    end

    if wasDestroyed then target:startDeath() end
    return wasDestroyed
end

function combat.addBounceAnimation(obj, fromQ, fromR, toQ, toR, duration, onPeak)
    table.insert(pushAnimations.queue, {
        obj = obj,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        bounceBack = true,
        startX = 0, startY = 0,
        endX = 0, endY = 0,
        timer = 0,
        duration = duration or 0.2,
        isMoving = false,
        onPeak = onPeak,
        onComplete = function() end
    })
end

function combat.addShakeAnimation(obj, q, r)
    local offsetX = (math.random() - 0.5) * 10
    local offsetY = (math.random() - 0.5) * 10
    table.insert(pushAnimations.queue, {
        obj = obj,
        isShake = true,
        offsetX = offsetX,
        offsetY = offsetY,
        timer = 0,
        duration = 0.1,
        startX = 0, startY = 0,
        onComplete = function() end
    })
end

function combat.addCollisionBounceAnimation(obj, fromQ, fromR, toQ, toR, hex, entities, sounds, withEntity, skipDamage)
    -- Collision effect at target cell (visual, no damage)
    local x, y = getDrawCoords(toQ, toR)
    visual.addEffect(x, y, "collision", 0.3)
    sounds.play("collision")

    -- Delayed damage application after animation
    local function applyDamage()
        if skipDamage then return end
        -- Directional entity: safe side — no damage
        if withEntity and withEntity.direction then
            local safe = hex_utils.isPushFromSafeSide(withEntity, fromQ, fromR)
            if safe then return end
        end
        local damage = 1
        if obj.health and obj.health > 0 then
            if not (withEntity and withEntity.noCollisionDamage) then
                local wasDestroyed = obj:takeDamage(damage)
                if wasDestroyed then
                    obj:startDeath()
                end
            end
        end
        if withEntity and withEntity.health and withEntity.health > 0 then
            if not withEntity.noCollisionDamage then
                local wasDestroyed = withEntity:takeDamage(damage)
                if wasDestroyed then
                    withEntity:startDeath()
                end
            end
        end
    end

    -- Bounce animation (movement 80% of the way and back)
    local startX, startY = getDrawCoords(fromQ, fromR)
    local endX, endY = getDrawCoords(toQ, toR)
    table.insert(pushAnimations.queue, {
        obj = obj,
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        bounceBack = true,
        startX = startX, startY = startY,
        endX = endX, endY = endY,
        timer = 0,
        duration = 0.2,
        isMoving = false,
        onComplete = function(pushedObj)
            -- Damage is applied only after animation completes
            applyDamage()
            if pushedObj.health <= 0 then
                pushedObj:startDeath()
            end
        end
    })
end

-- ============================================================
-- PLAYER ACTIONS (move / attack / undo)
-- ============================================================

function performMove(actor, targetQ, targetR)
    if not actor.isPlayable then return false end
    if not hex:isActiveHex(targetQ, targetR) then
        log.warn("combat", "Target cell is outside the playable hexagon")
        return false
    end
    if actor.isMoving then return false end
    if status.hasEntityStatus(actor, "rooted") and not actor.rootImmune then
        log.infof("combat", "%s is rooted by a Zombie and cannot move!", actor.name)
        return false
    end
    if status.hasEntityStatus(actor, "stasis") then
        log.infof("combat", "%s is in stasis and cannot move!", actor.name)
        return false
    end
    if actor.hasActedThisTurn and not actor.canMoveAfterAttack then return false end
    if actor.hasMovedThisTurn and not actor.canMoveAfterAttack then
        log.debugf("combat", "%s has already moved this turn!", actor.name)
        return false
    end
    if actor.q == targetQ and actor.r == targetR then return false end
    local distance = hex:getDistance(actor.q, actor.r, targetQ, targetR)
    local baseRange = actor.moveRange + (status.hasEntityStatus(actor, "empowered") and 1 or 0)
    if combat.isInSlowingAura then
        if combat.isInSlowingAura(actor, entities, hex) then
            baseRange = math.max(1, baseRange - 2)
        end
    end
    local effectiveRange = baseRange
    if distance > effectiveRange then
        log.debug("combat", "Too far")
        return false
    end
    if isCellOccupiedForStop(targetQ, targetR, actor) then
        log.debug("combat", "Cell occupied")
        return false
    end
    local path = pathfinding.findPath(actor.q, actor.r, targetQ, targetR, effectiveRange,
        function(q, r) return not isCellPassable(q, r, actor) end, hex,
        function(q, r) local e = getEntityAtHex(q, r); return e and e ~= actor and not e.isHazard end)
    if not path or #path == 0 then
        log.debug("combat", "No valid path")
        return false
    end
    actor.hasMovedThisTurn = true
    actor.path = path
    actor.currentPathIndex = 1
    startNextMove(actor)
    return true
end

function startNextMove(actor)
    if actor.currentPathIndex <= #actor.path then
        local step = actor.path[actor.currentPathIndex]
        actor.isMoving = true
        actor.timer = 0
        actor.targetQ = step.q
        actor.targetR = step.r
        actor.startX, actor.startY = getDrawCoords(actor.q, actor.r)
        actor.endX, actor.endY = getDrawCoords(actor.targetQ, actor.targetR)
    else
        actor.isMoving = false
        actor.path = {}
        actor.currentPathIndex = 0
        undo.snapshot()
        if selectedActor == actor then
            hex.selectedQ = actor.q
            hex.selectedR = actor.r
        end
    end
end

function updateActorMovement(actor, dt)
    if not actor.isPlayable then return end
    if actor.isDying then
        if actor.isMoving then
            actor.isMoving = false
            actor.path = {}
            actor.currentPathIndex = 0
            if selectedActor == actor then
                hex.selectedQ = actor.q
                hex.selectedR = actor.r
            end
            undo.snapshot()
        end
        return
    end
    if actor.isMoving then
        actor.timer = actor.timer + dt
        local t = actor.timer / actor.speed
        if t >= 1 then
            actor.q = actor.targetQ
            actor.r = actor.targetR
            -- Apply cell effects at each step of the path
            sounds.play("move")
            if terrainMap then
                local died = effects.applyAllCellEffects(actor, actor.q, actor.r, terrainMap, entities)
                if died then
                    local x, y = hex:hexToPixel(actor.q, actor.r)
                    visual.addEffect(x, y, "drown")
                    undo.snapshot()
                    checkGameEnd()
                    actor.isMoving = false
                    actor.path = {}
                    actor.currentPathIndex = 0
                    if selectedActor == actor then
                        hex.selectedQ = actor.q
                        hex.selectedR = actor.r
                    end
                    return
                end
            end
            actor.isMoving = false
            actor.currentPathIndex = actor.currentPathIndex + 1
            if actor.currentPathIndex <= #actor.path then
                startNextMove(actor)
            else
                actor.path = {}
                actor.currentPathIndex = 0
                undo.snapshot()
                if actor.canMoveAfterAttack then
                    actor.canMoveAfterAttack = false
                    actor.hasActedThisTurn = true
                end
                if selectedActor == actor then
                    hex.selectedQ = actor.q
                    hex.selectedR = actor.r
                end
            end
        end
    end
end

function performAttackWithSelectedAttack(attacker, targetQ, targetR, attack)
    log.debug("combat", "performAttackWithSelectedAttack called")
    log.debug("combat", "attacker:", attacker and attacker.name, "hasActed:", attacker and attacker.hasActedThisTurn)
    log.debug("combat", "targetQ,targetR:", targetQ, targetR)
    log.debug("combat", "attack:", attack and attack.name)

    if not attacker.isPlayable then
        log.debug("combat", "Not a playable character")
        return false, "Not a playable character"
    end
    if status.hasEntityStatus(attacker, "stasis") then
        log.infof("combat", "%s is in stasis and cannot attack!", attacker.name)
        return false, "Unit is in stasis"
    end
    if attacker.hasActedThisTurn then
        log.debug("combat", "Already acted this turn")
        return false, "Already acted this turn"
    end
    if not attack then
        log.debug("combat", "No attack selected")
        return false, "No attack selected"
    end

    local distance = hex:getDistance(attacker.q, attacker.r, targetQ, targetR)
    log.debug("combat", "Distance to target:", distance, "Attack range:", attack.range)
    if distance > attack.range then
        return false, "Target out of range"
    end

    log.debug("combat", "Executing attack...")
    local success, message = attack:execute(attacker, targetQ, targetR, hex, entities, sounds)
    log.debug("combat", "Attack result:", success, message)

    if success then
        if pushAnimations.active then
            combat.flushPushAnimations()
        end
        undo.snapshot()
        local endTurn = true

        -- Warrior chain: directional (Dash→Flip or Flip→Dash)
        if attacker.dashToFlipChain and attack.name == "Dash" then
            if attacker.chainAttack == "Dash" then
                attacker.chainAttack = nil
            elseif not attacker.chainAttack then
                attacker.chainAttack = "Flip"
                endTurn = false
                updateAttackButtons(attacker)
            end
        elseif attacker.flipToDashChain and attack.name == "Flip" then
            if attacker.chainAttack == "Flip" then
                attacker.chainAttack = nil
            elseif not attacker.chainAttack then
                attacker.chainAttack = "Dash"
                endTurn = false
                updateAttackButtons(attacker)
            end
        end

        -- Redirect shot: Rogue lvl3, Shoot/Piercing Shot can be used twice
        if endTurn and attacker.redirectShot and not attacker.redirectPending and
           (attack.name == "Shoot" or attack.name == "Piercing Shot") then
            attacker.redirectPending = true
            endTurn = false
            log.debugf("combat", "%s can redirect shot", attacker.name)
        elseif attacker.redirectPending and (attack.name == "Shoot" or attack.name == "Piercing Shot") then
            attacker.redirectPending = nil
        end

        if endTurn then
            attacker.hasActedThisTurn = true
            log.debugf("combat", "%s attacked and ended turn.", attacker.name)
            attackMode = false
            selectedAttack = nil
            checkGameEnd()
        else
            attackMode = false
            selectedAttack = nil
        end
    else
        log.warnf("combat", "Attack failed: %s", (message or "unknown"))
    end
    return success, message
end

return combat
