-- ui/attack_preview.lua
-- Unified attack preview calculator.
-- Returns a structured prediction of: direct damage, collision damage,
-- push destinations, collision hints and affected cells.
--
-- Rules for damage icons:
--   * 1 damage total              -> wound / building_damage
--   * 2+ damage total             -> heavy_wound / heavy_building_damage
--   * lethal total (any amount)   -> fatal_wound / building_destruction
-- Collision hints are always drawn on the edge between two hexes.

local preview = {}

local hex_utils = require("grid.hex_utils")
local combat    = require("combat.combat")
local status    = require("system.status")

-- ============================================================
-- HELPERS
-- ============================================================

local function cellKey(q, r) return q .. "," .. r end

local function getEntity(q, r, entities)
    -- Use combat.getEntityAtHex so temporary coordinate changes made during
    -- preview (e.g. Piercing Shot pushing the second target first) are visible.
    -- The global getEntityAtHex uses the entityAt spatial index and ignores the
    -- passed entities table, so it would see stale positions.
    if entities then
        return combat.getEntityAtHex(q, r, entities)
    end
    return getEntityAtHex(q, r)
end

local function isActive(q, r, hex)
    return hex:isActiveHex(q, r)
end

local function isValid(q, r, hex)
    return hex:isValidHex(q, r)
end

-- ============================================================
-- DAMAGE CALCULATION (mirrors combat dealDamageToTarget + Entity:takeDamage)
-- ============================================================

-- Returns the *effective* damage that would be dealt to target.
-- Does NOT apply it.  directionIndex and dist are optional.
function preview.calculateEffectiveDamage(target, attacker, baseDamage, directionIndex, dist)
    if not target or target.health <= 0 or target.indestructible then return 0 end
    if not baseDamage or baseDamage <= 0 then return 0 end

    local damage = baseDamage
    local multiplier = 1.0

    if target.armor and directionIndex and target.armor[directionIndex + 1] then
        multiplier = multiplier * target.armor[directionIndex + 1]
    end
    if target.weakPoint ~= nil and directionIndex == target.weakPoint then
        multiplier = multiplier * 2.0
    end
    multiplier = multiplier * status.getDamageMultiplier(target)

    damage = math.floor(damage * multiplier)

    if status.hasEntityStatus(attacker, "empowered") then
        damage = damage + 1
    end
    if baseDamage == 1 and status.hasEntityStatus(attacker, "rage") then
        damage = 99
    end
    if status.hasEntityStatus(attacker, "fatal_damage") then
        damage = 99
    end
    if attacker.pointBlankLethal and dist and dist == 1 then
        damage = 99
    end

    if damage < 1 then damage = 1 end

    if target.isPlayable and (_G.squadArmorBonus or 0) > 0 then
        damage = math.max(0, damage - _G.squadArmorBonus)
    end
    if target.maxDamagePerHit then
        damage = math.min(damage, target.maxDamagePerHit)
    end
    if target.healthCellSize and target.health > target.healthCellSize then
        damage = math.min(damage, target.health - target.healthCellSize)
    end

    return damage
end

-- Will this exact amount of (already-effective) damage kill the target?
-- Collision damage in combat is always 1 HP, but a few modifiers can reduce it.
function preview.calculateEffectiveCollisionDamage(target)
    if not target or target.health <= 0 or target.indestructible then return 0 end
    local damage = 1
    if target.isPlayable and (_G.squadArmorBonus or 0) > 0 then
        damage = math.max(0, damage - _G.squadArmorBonus)
    end
    if target.maxDamagePerHit then
        damage = math.min(damage, target.maxDamagePerHit)
    end
    if target.healthCellSize and target.health > target.healthCellSize then
        damage = math.min(damage, target.health - target.healthCellSize)
    end
    return damage
end

function preview.willKill(target, effectiveDamage)
    if not target or target.health <= 0 or target.indestructible then return false end
    if effectiveDamage <= 0 then return false end
    if status.hasEntityStatus(target, "acid") then return true end
    return effectiveDamage >= target.health
end

-- Choose the icon for the total effective damage on an entity.
function preview.getDamageIcon(entity, totalDamage)
    if not entity or entity.health <= 0 or entity.indestructible then return nil end
    if not totalDamage or totalDamage <= 0 then return nil end

    local kills = preview.willKill(entity, totalDamage)

    if entity:isBuilding() then
        if kills then return "building_destruction" end
        if totalDamage >= 2 then return "heavy_building_damage" end
        return "building_damage"
    end

    if kills then
        if status.hasEntityStatus(entity, "acid") then return "fatal_wound_acid" end
        return "fatal_wound"
    end
    if totalDamage >= 2 then return "heavy_wound" end
    return "wound"
end

-- ============================================================
-- PREVIEW OBJECT
-- ============================================================

function preview.new()
    return {
        damages    = {}, -- [key] -> { entity, attackDamage, collisionDamage, totalDamage, pushedTo }
        collisions = {}, -- { fromQ, fromR, toQ, toR, type, target, occupant, reason }
        pushArrows = {}, -- { fromQ, fromR, toQ, toR }
        lines      = {}, -- { fromQ, fromR, toQ, toR }
        overlays   = {}, -- [key] -> { q, r, kind }
    }
end

local function ensureDamageEntry(p, entity)
    local k = cellKey(entity.q, entity.r)
    if not p.damages[k] then
        p.damages[k] = {
            entity          = entity,
            attackDamage    = 0,
            collisionDamage = 0,
            totalDamage     = 0,
            pushedTo        = nil,
        }
    end
    return p.damages[k]
end

function preview.addAttackDamage(p, entity, amount)
    if not entity or entity.health <= 0 or entity.indestructible or amount <= 0 then return end
    local e = ensureDamageEntry(p, entity)
    e.attackDamage = e.attackDamage + amount
    e.totalDamage  = e.attackDamage + e.collisionDamage
end

function preview.addCollisionDamage(p, entity, amount)
    if not entity or entity.health <= 0 or entity.indestructible or amount <= 0 then return end
    local e = ensureDamageEntry(p, entity)
    e.collisionDamage = e.collisionDamage + amount
    e.totalDamage     = e.attackDamage + e.collisionDamage
end

function preview.markPushed(p, entity, toQ, toR)
    if not entity then return end
    local e = ensureDamageEntry(p, entity)
    e.pushedTo = { q = toQ, r = toR }
end

function preview.addCollisionHint(p, fromQ, fromR, toQ, toR, hintType, target, occupant, reason)
    table.insert(p.collisions, {
        fromQ    = fromQ, fromR = fromR,
        toQ      = toQ,   toR   = toR,
        type     = hintType, -- "collision_damage" or "collision_no_damage"
        target   = target,
        occupant = occupant,
        reason   = reason,
    })
end

function preview.addPushArrow(p, fromQ, fromR, toQ, toR)
    table.insert(p.pushArrows, { fromQ = fromQ, fromR = fromR, toQ = toQ, toR = toR })
end

function preview.addLine(p, fromQ, fromR, toQ, toR)
    table.insert(p.lines, { fromQ = fromQ, fromR = fromR, toQ = toQ, toR = toR })
end

function preview.addOverlay(p, q, r, kind)
    local k = cellKey(q, r)
    if not p.overlays[k] then p.overlays[k] = { q = q, r = r, kind = kind or "preview" } end
end

-- ============================================================
-- COLLISION PREDICTION
-- ============================================================

-- Returns a collision descriptor:
--   damage       - 0 or 1 (damage that the *pushed* entity will receive)
--   occupantDmg  - 0 or 1 (damage that the *occupant* will receive)
--   type         - "collision_damage" or "collision_no_damage"
--   reason       - "edge", "collision_both", "collision_immovable"
--   occupant     - the entity being collided with (may be nil for edge)
function preview.predictCollision(entity, fromQ, fromR, toQ, toR, hex, entities)
    local result = {
        damage      = 0,
        occupantDmg = 0,
        type        = nil,
        reason      = nil,
        occupant    = nil,
    }

    -- Off the edge.
    if not isActive(toQ, toR, hex) then
        -- Only characters take edge damage (buildings bounce without damage).
        if entity:isCharacter() then
            result.damage = 1
            result.type   = "collision_damage"
            result.reason = "edge"
        end
        return result
    end

    local occupant = getEntity(toQ, toR, entities)
    if occupant and occupant ~= entity then
        result.occupant = occupant

        -- Mountain slope / indestructible barrier: no damage, just bounce.
        if occupant.noCollisionDamage then
            result.type = "collision_no_damage"
            result.reason = "indestructible"
            return result
        end

        -- Directional barrier: safe side = no damage, dangerous side = damage.
        if occupant.direction then
            local safe = hex_utils.isPushFromSafeSide(occupant, fromQ, fromR)
            if safe then
                result.type = "collision_no_damage"
                result.reason = "directional_safe"
            else
                result.damage = 1
                result.occupantDmg = 1
                result.type = "collision_damage"
                result.reason = "directional_dangerous"
            end
            return result
        end

        -- Deep water / hazard: pass through.
        if occupant.isHazard then
            result.type = nil
            result.reason = "hazard"
            return result
        end

        -- Collision with another character: both take 1 damage.
        if occupant:isCharacter() then
            result.damage = 1
            result.occupantDmg = 1
            result.type = "collision_damage"
            result.reason = "collision_both"
            return result
        end

        -- Immovable object (building / obstacle): the pushed entity takes damage,
        -- and the object itself also takes 1 damage if it is destructible.
        result.damage = 1
        result.type   = "collision_damage"
        result.reason = "collision_immovable"
        if occupant.health and occupant.health > 0 and not occupant.indestructible and not occupant.noCollisionDamage then
            result.occupantDmg = 1
        end
        return result
    end

    return result
end

-- Register damage + hint for a single push.
function preview.applyPush(p, entity, fromQ, fromR, toQ, toR, hex, entities)
    if not entity then return end
    preview.markPushed(p, entity, toQ, toR)

    -- No preview arrow for purely visual bounces (the destination is still useful).
    preview.addPushArrow(p, fromQ, fromR, toQ, toR)

    local col = preview.predictCollision(entity, fromQ, fromR, toQ, toR, hex, entities)
    if col.type then
        preview.addCollisionHint(p, fromQ, fromR, toQ, toR, col.type, entity, col.occupant, col.reason)
    end
    if col.damage > 0 then
        preview.addCollisionDamage(p, entity, preview.calculateEffectiveCollisionDamage(entity))
    end
    if col.occupantDmg > 0 and col.occupant then
        preview.addCollisionDamage(p, col.occupant, preview.calculateEffectiveCollisionDamage(col.occupant))
    end

    return col
end

-- ============================================================
-- ATTACK-SPECIFIC PREVIEW HANDLERS
-- ============================================================

local handlers = {}

-- Generic getAffectedCells handler (Bash, Cleave, Lunge, Power Bolt, etc.)
local function handleAffectedCells(p, attacker, attack, hoverQ, hoverR, hex, entities)
    if not attack.getAffectedCells then return false end
    local cells = attack:getAffectedCells(attacker, hoverQ, hoverR, hex, entities)
    for _, c in ipairs(cells) do
        local e = getEntity(c.q, c.r, entities)
        if e and e.health > 0 and not e.indestructible then
            local dist = hex:getDistance(attacker.q, attacker.r, c.q, c.r)
            local eff = preview.calculateEffectiveDamage(e, attacker, c.damage or attack.damage or 1, nil, dist)
            preview.addAttackDamage(p, e, eff)
            preview.addOverlay(p, c.q, c.r, "target")
        end
    end
    return true
end

-- Line attacks with optional push: Shoot / Push / Dash / Piercing Shot
local function handleLineShot(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return false end

    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)

    local firstTarget, firstHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget or not firstHex then
        -- No target: just draw line to farthest active cell.
        local endCell = combat.getFarthestActiveCellOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex)
        if endCell then
            preview.addLine(p, attacker.q, attacker.r, endCell.q, endCell.r)
        end
        return false
    end

    preview.addOverlay(p, firstHex.q, firstHex.r, "target")

    -- Direct damage.
    local baseDamage = 0
    if attack.name == "Shoot" or attack.name == "Dash" or attack.name == "Ghost Bolt" then
        baseDamage = attack.damage or 1
    end

    if baseDamage > 0 then
        local dist = hex:getDistance(attacker.q, attacker.r, firstHex.q, firstHex.r)
        local eff = preview.calculateEffectiveDamage(firstTarget, attacker, baseDamage, nil, dist)
        preview.addAttackDamage(p, firstTarget, eff)
    end

    -- Push.
    if firstTarget.isPushable ~= false and firstTarget.health > 0 then
        local pushQ, pushR = hex_utils.applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
        preview.applyPush(p, firstTarget, firstHex.q, firstHex.r, pushQ, pushR, hex, entities)
    end

    return true
end

-- Piercing Shot: second target is pushed FIRST, then the first target follows.
-- This matters when the two targets are adjacent: the first target moves into the
-- cell the second target just left, so no collision occurs between them.
handlers["Piercing Shot"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)

    local firstTarget, firstHex, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if not firstTarget or not firstHex then
        local endCell = combat.getFarthestActiveCellOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex)
        if endCell then
            preview.addLine(p, attacker.q, attacker.r, endCell.q, endCell.r)
        end
        return
    end

    preview.addOverlay(p, firstHex.q, firstHex.r, "target")

    -- First target: 0 direct damage.
    -- Second target: 1 direct damage.
    if secondTarget and secondHex then
        preview.addOverlay(p, secondHex.q, secondHex.r, "target")
        local dist2 = hex:getDistance(attacker.q, attacker.r, secondHex.q, secondHex.r)
        local eff2 = preview.calculateEffectiveDamage(secondTarget, attacker, 1, nil, dist2)
        preview.addAttackDamage(p, secondTarget, eff2)
    end

    -- Push second target first (combat resolves it this way).
    local secondMoved = false
    local secondOldQ, secondOldR
    if secondTarget and secondHex and secondTarget.isPushable ~= false and secondTarget.health > 0 then
        secondOldQ, secondOldR = secondTarget.q, secondTarget.r
        local push2Q, push2R = hex_utils.applyCubeStep(secondHex.q, secondHex.r, stepX, stepY, stepZ)
        local col2 = preview.applyPush(p, secondTarget, secondHex.q, secondHex.r, push2Q, push2R, hex, entities)
        -- If the second target actually moves, shift it so the first target's preview sees a free cell.
        if col2 and not col2.type then
            secondTarget.q, secondTarget.r = push2Q, push2R
            secondMoved = true
        end
    end

    -- Then push the first target into the cell the second target occupied.
    if firstTarget.isPushable ~= false and firstTarget.health > 0 then
        local push1Q, push1R = hex_utils.applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
        preview.applyPush(p, firstTarget, firstHex.q, firstHex.r, push1Q, push1R, hex, entities)
    end

    -- Restore original coordinates so we don't mutate the real entity state.
    if secondMoved then
        secondTarget.q, secondTarget.r = secondOldQ, secondOldR
    end
end

-- Ghost Bolt: no push.
handlers["Ghost Bolt"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end
    local firstTarget, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
    if firstTarget and targetHex then
        preview.addLine(p, attacker.q, attacker.r, targetHex.q, targetHex.r)
        local dist = hex:getDistance(attacker.q, attacker.r, targetHex.q, targetHex.r)
        local eff = preview.calculateEffectiveDamage(firstTarget, attacker, attack.damage or 1, nil, dist)
        preview.addAttackDamage(p, firstTarget, eff)
        preview.addOverlay(p, targetHex.q, targetHex.r, "target")
    else
        preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)
    end
end

-- Shoot / Push / Dash / Piercing Shot
handlers["Shoot"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    handleLineShot(p, attacker, attack, hoverQ, hoverR, hex, entities)
end
handlers["Push"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    handleLineShot(p, attacker, attack, hoverQ, hoverR, hex, entities)
end
handlers["Dash"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    handleLineShot(p, attacker, attack, hoverQ, hoverR, hex, entities)
end

-- Melee single-target attacks without push: Bite / Magic Bolt
handlers["Bite"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end
    local target = getEntity(hoverQ, hoverR, entities)
    if target and target.health > 0 and not target.indestructible then
        local eff = preview.calculateEffectiveDamage(target, attacker, attack.damage or 1, nil, dist)
        preview.addAttackDamage(p, target, eff)
        preview.addOverlay(p, hoverQ, hoverR, "target")
    end
end

handlers["Magic Bolt"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 0) or dist > attack.range then return end
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end
    local target = getEntity(hoverQ, hoverR, entities)
    -- Magic Bolt only damages playable characters and buildings.
    if target and target.health > 0 and not target.indestructible
       and (target:isBuilding() or (target:isCharacter() and target.isPlayable)) then
        local eff = preview.calculateEffectiveDamage(target, attacker, attack.damage or 1, nil, dist)
        preview.addAttackDamage(p, target, eff)
        preview.addOverlay(p, hoverQ, hoverR, "target")
        preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)
    end
end

-- Power Bolt: lethal bolt hitting target and 3 cells in front.
handlers["Power Bolt"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 0) or dist > attack.range then return end
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    local cells = attack:getConeCells(attacker, hoverQ, hoverR, hex)
    for _, c in ipairs(cells) do
        local e = getEntity(c.q, c.r, entities)
        if e and e.health > 0 and not e.indestructible
           and (e:isBuilding() or (e:isCharacter() and e.isPlayable)) then
            local d = hex:getDistance(attacker.q, attacker.r, c.q, c.r)
            local eff = preview.calculateEffectiveDamage(e, attacker, attack.damage or 99, nil, d)
            preview.addAttackDamage(p, e, eff)
            preview.addOverlay(p, c.q, c.r, "target")
        end
    end
    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)
end

-- Heavy Punch / Empower Punch: melee + push, optional lethal charge.
local function handlePunch(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end
    local target = getEntity(hoverQ, hoverR, entities)
    if not target or target.health <= 0 or target.indestructible then return end

    preview.addOverlay(p, hoverQ, hoverR, "target")

    local charged = status.hasEntityStatus(attacker, "punch_charged")
    local baseDamage = 0
    if attack.name == "Heavy Punch" then
        baseDamage = (charged and 99) or (attack.damage or 1)
    elseif attack.name == "Empower Punch" then
        baseDamage = charged and 1 or 0
    end

    if baseDamage > 0 then
        local eff = preview.calculateEffectiveDamage(target, attacker, baseDamage, nil, dist)
        preview.addAttackDamage(p, target, eff)
    end

    if target.isPushable ~= false and target.health > 0 then
        local stepX, stepY, stepZ
        if attack._pushDirOverride then
            stepX, stepY, stepZ = attack._pushDirOverride.x, attack._pushDirOverride.y, attack._pushDirOverride.z
        else
            stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        end
        if stepX then
            local pushQ, pushR = hex_utils.applyCubeStep(hoverQ, hoverR, stepX, stepY, stepZ)
            preview.applyPush(p, target, hoverQ, hoverR, pushQ, pushR, hex, entities)
        end
    end
end
handlers["Heavy Punch"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    handlePunch(p, attacker, attack, hoverQ, hoverR, hex, entities)
end
handlers["Empower Punch"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    handlePunch(p, attacker, attack, hoverQ, hoverR, hex, entities)
end

-- Flip: 1 damage and move target behind attacker.
handlers["Flip"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end
    local target = getEntity(hoverQ, hoverR, entities)
    if not target or not target:isCharacter() or target.health <= 0 then return end

    local eff = preview.calculateEffectiveDamage(target, attacker, attack.damage or 1, nil, dist)
    preview.addAttackDamage(p, target, eff)
    preview.addOverlay(p, hoverQ, hoverR, "target")

    local cells = attack:getFlipCells(attacker, hoverQ, hoverR, hex, entities)
    -- Default flip destination is straight behind attacker.
    if cells and #cells > 0 then
        local dest = cells[1]
        preview.markPushed(p, target, dest.q, dest.r)
        preview.addPushArrow(p, hoverQ, hoverR, dest.q, dest.r)
        preview.addOverlay(p, dest.q, dest.r, "push_dest")
    end
end

-- Vortex Strike: shift target left/right.
handlers["Vortex Strike"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end
    local target = getEntity(hoverQ, hoverR, entities)
    if not target or not target:isCharacter() or target.health <= 0 then return end

    local eff = preview.calculateEffectiveDamage(target, attacker, attack.damage or 1, nil, dist)
    preview.addAttackDamage(p, target, eff)
    preview.addOverlay(p, hoverQ, hoverR, "target")

    if target.isPushable ~= false then
        local dests = attack:getShiftDestinations(attacker, hoverQ, hoverR, hex)
        -- If a destination is pre-selected, use it; otherwise show both.
        local chosen = _G.vortexTargetCell
        for _, dc in ipairs(dests) do
            if not chosen or (dc.q == chosen.q and dc.r == chosen.r) then
                preview.applyPush(p, target, hoverQ, hoverR, dc.q, dc.r, hex, entities)
                preview.addOverlay(p, dc.q, dc.r, "push_dest")
            end
        end
    end
end

-- Wide Vortex: shift target and secondary target around attacker.
handlers["Wide Vortex"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end
    local target = getEntity(hoverQ, hoverR, entities)
    if not target or not target:isCharacter() or target.health <= 0 then return end

    preview.addOverlay(p, hoverQ, hoverR, "target")

    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    local ax, ay, az = hex_utils.axialToCube(attacker.q, attacker.r)
    local dests = attack:getShiftDestinations(attacker, hoverQ, hoverR, hex)
    local chosen = _G.vortexTargetCell

    for _, dc in ipairs(dests) do
        if not chosen or (dc.q == chosen.q and dc.r == chosen.r) then
            preview.applyPush(p, target, hoverQ, hoverR, dc.q, dc.r, hex, entities)
            preview.addOverlay(p, dc.q, dc.r, "push_dest")

            -- Secondary target B pushed one step further around attacker.
            local b2q, b2r
            if dc.dir == "right" then
                b2q, b2r = hex_utils.cubeToAxial(ax + stepZ, ay + stepX, az + stepY)
            else
                b2q, b2r = hex_utils.cubeToAxial(ax + stepY, ay + stepZ, az + stepX)
            end
            local occupantB = getEntity(dc.q, dc.r, entities)
            if occupantB and occupantB ~= target and occupantB:isCharacter() and occupantB.health > 0 then
                preview.applyPush(p, occupantB, dc.q, dc.r, b2q, b2r, hex, entities)
            end
        end
    end
end

-- Stone Throw: center damage + cone push.
handlers["Stone Throw"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 1) or dist > attack.range then return end
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)
    preview.addOverlay(p, hoverQ, hoverR, "target")

    local center = getEntity(hoverQ, hoverR, entities)
    if center and center.health > 0 and not center.indestructible then
        local eff = preview.calculateEffectiveDamage(center, attacker, attack.damage or 1, nil, dist)
        preview.addAttackDamage(p, center, eff)
    end

    local dirQ, dirR = hoverQ - attacker.q, hoverR - attacker.r
    local neighbors = attack:getNeighborsInDirection(hoverQ, hoverR, dirQ, dirR, hex)
    for _, nb in ipairs(neighbors) do
        local target = getEntity(nb.q, nb.r, entities)
        if target and target:isCharacter() and target.health > 0 then
            local cX, cY, cZ = hex_utils.axialToCube(hoverQ, hoverR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dX, dY, dZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dX, dY, dZ)
            preview.applyPush(p, target, nb.q, nb.r, pushQ, pushR, hex, entities)
            preview.addOverlay(p, nb.q, nb.r, "target")
        end
    end
end

-- Cone Blast: push 3 front neighbors of attacker.
handlers["Cone Blast"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 1) or dist > attack.range then return end
    local dirQ, dirR = hoverQ - attacker.q, hoverR - attacker.r
    local neighbors = attack:getNeighborsInDirection(attacker.q, attacker.r, dirQ, dirR, hex)

    for _, nb in ipairs(neighbors) do
        local target = getEntity(nb.q, nb.r, entities)
        if target and target:isCharacter() and target.health > 0 then
            local aX, aY, aZ = hex_utils.axialToCube(attacker.q, attacker.r)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dX, dY, dZ = nX - aX, nY - aY, nZ - aZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dX, dY, dZ)
            preview.applyPush(p, target, nb.q, nb.r, pushQ, pushR, hex, entities)
            preview.addOverlay(p, nb.q, nb.r, "target")
        end
    end
end

-- Electric Hook: 1 damage to everyone on the line.
handlers["Electric Hook"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 2) then return end
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)

    local curQ, curR = attacker.q, attacker.r
    while true do
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not isValid(nextQ, nextR, hex) then break end
        local e = getEntity(nextQ, nextR, entities)
        if e and e.health > 0 and not e.indestructible then
            local d = hex:getDistance(attacker.q, attacker.r, nextQ, nextR)
            local eff = preview.calculateEffectiveDamage(e, attacker, attack.damage or 1, nil, d)
            preview.addAttackDamage(p, e, eff)
            preview.addOverlay(p, nextQ, nextR, "target")
        end
        if nextQ == hoverQ and nextR == hoverR then break end
        curQ, curR = nextQ, nextR
    end
end

-- Pull Hook: no damage, pull target one step closer.
handlers["Pull Hook"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local hookTarget = _G.pullHookTargetCell and getEntity(_G.pullHookTargetCell.q, _G.pullHookTargetCell.r, entities)
    if not hookTarget then return end

    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hookTarget.q, hookTarget.r, hex)
    if not stepX then return end

    local moveCells = attack:getPullHookMoveCells(attacker, stepX, stepY, stepZ, hookTarget.q, hookTarget.r, hex, entities)
    for _, c in ipairs(moveCells) do
        preview.addOverlay(p, c.q, c.r, "push_dest")
        if c.q == hoverQ and c.r == hoverR then
            local pullQ, pullR = hex_utils.applyCubeStep(c.q, c.r, stepX, stepY, stepZ)
            if isActive(pullQ, pullR, hex) then
                preview.markPushed(p, hookTarget, pullQ, pullR)
                preview.addPushArrow(p, hookTarget.q, hookTarget.r, pullQ, pullR)
                preview.addOverlay(p, pullQ, pullR, "push_dest")
            end
        end
    end
end

-- Rampage: dash, push enemies aside, lethal to primary target.
handlers["Rampage"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)

    local firstTarget, firstHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)

    -- Walk the path and push adjacent enemies sideways (including attacker's starting cell)
    local curQ, curR = attacker.q, attacker.r
    while true do
        local sideX1, sideY1, sideZ1 = -stepY, -stepZ, -stepX
        local sideX2, sideY2, sideZ2 = -stepZ, -stepX, -stepY
        for _, side in ipairs({{sideX1, sideY1, sideZ1}, {sideX2, sideY2, sideZ2}}) do
            local sideQ, sideR = hex_utils.applyCubeStep(curQ, curR, side[1], side[2], side[3])
            local e = getEntity(sideQ, sideR, entities)
            if e and e:isCharacter() and e.health > 0 and e.isPushable ~= false and not e.isPlayable then
                local pushQ, pushR = hex_utils.applyCubeStep(sideQ, sideR, side[1], side[2], side[3])
                preview.applyPush(p, e, sideQ, sideR, pushQ, pushR, hex, entities)
                preview.addOverlay(p, sideQ, sideR, "target")
            end
        end

        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not isActive(nextQ, nextR, hex) then break end
        if firstTarget and firstHex and nextQ == firstHex.q and nextR == firstHex.r then break end
        curQ, curR = nextQ, nextR
    end

    -- Primary target: lethal damage + push
    if firstTarget and firstHex then
        preview.addOverlay(p, firstHex.q, firstHex.r, "target")
        local dist = hex:getDistance(attacker.q, attacker.r, firstHex.q, firstHex.r)
        local eff = preview.calculateEffectiveDamage(firstTarget, attacker, attack.damage or 99, nil, dist)
        preview.addAttackDamage(p, firstTarget, eff)

        if firstTarget.isPushable ~= false and firstTarget.health > 0 then
            local pushQ, pushR = hex_utils.applyCubeStep(firstHex.q, firstHex.r, stepX, stepY, stepZ)
            preview.applyPush(p, firstTarget, firstHex.q, firstHex.r, pushQ, pushR, hex, entities)
        end
    end
end

-- Mend: show Colossus as target, no damage preview needed.
handlers["Mend"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local colossus = nil
    for _, e in ipairs(entities) do
        if e.name == "Colossus" and e.isPlayable then
            colossus = e
            break
        end
    end
    if not colossus then return end
    if hoverQ ~= colossus.q or hoverR ~= colossus.r then return end
    local dist = hex:getDistance(attacker.q, attacker.r, colossus.q, colossus.r)
    if dist ~= 1 then return end
    preview.addOverlay(p, colossus.q, colossus.r, "push_dest")
end

-- Phase Shift: show ally and landing options.
handlers["Phase Shift"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local ally = getEntity(hoverQ, hoverR, entities)
    if not ally or not ally.isPlayable or ally == attacker or ally.health <= 0 then return end

    preview.addOverlay(p, hoverQ, hoverR, "target")

    -- Show attacker's original position as push_dest (where ally goes)
    preview.addOverlay(p, attacker.q, attacker.r, "push_dest")
    preview.addPushArrow(p, hoverQ, hoverR, attacker.q, attacker.r)

    -- Show landing options around ally (radius 1)
    for dq = -1, 1 do
        for dr = -1, 1 do
            if dq ~= 0 or dr ~= 0 then
                local q = hoverQ + dq
                local r = hoverR + dr
                local landingDist = hex:getDistance(hoverQ, hoverR, q, r)
                if landingDist == 1 and isActive(q, r, hex) then
                    local occupant = getEntity(q, r, entities)
                    if not occupant or occupant == attacker then
                        preview.addOverlay(p, q, r, "push_dest")
                    end
                end
            end
        end
    end
end

-- Frenzy: lethal to target + behind, puts Colossus in stasis.
handlers["Frenzy"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end

    local target = getEntity(hoverQ, hoverR, entities)
    if not target or target.health <= 0 then return end

    preview.addOverlay(p, hoverQ, hoverR, "target")
    local eff = preview.calculateEffectiveDamage(target, attacker, attack.damage or 99, nil, dist)
    preview.addAttackDamage(p, target, eff)

    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if stepX then
        local behindQ, behindR = hex_utils.applyCubeStep(hoverQ, hoverR, stepX, stepY, stepZ)
        local behindTarget = getEntity(behindQ, behindR, entities)
        if behindTarget and behindTarget.health > 0 then
            preview.addOverlay(p, behindQ, behindR, "target")
            local effBehind = preview.calculateEffectiveDamage(behindTarget, attacker, attack.damage or 99)
            preview.addAttackDamage(p, behindTarget, effBehind)
        end
    end

    -- Show Colossus affected
    for _, e in ipairs(entities) do
        if e.name == "Colossus" and e.isPlayable and e.health > 0 then
            preview.addOverlay(p, e.q, e.r, "target")
            preview.addAttackDamage(p, e, 99)
            break
        end
    end
end

-- Hunt: push target, lethal collision with Colossus.
handlers["Hunt"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist ~= 1 then return end

    local target = getEntity(hoverQ, hoverR, entities)
    if not target or target.health <= 0 or target.isPushable == false then return end

    preview.addOverlay(p, hoverQ, hoverR, "target")

    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    local pushQ, pushR = hex_utils.applyCubeStep(hoverQ, hoverR, stepX, stepY, stepZ)
    local occupant = getEntity(pushQ, pushR, entities)

    -- Check if push destination is Colossus
    local colossus = nil
    for _, e in ipairs(entities) do
        if e.name == "Colossus" and e.isPlayable then
            colossus = e
            break
        end
    end

    if colossus and occupant == colossus then
        -- Lethal collision: Colossus unharmed, enemy dies
        preview.addPushArrow(p, hoverQ, hoverR, pushQ, pushR)
        preview.markPushed(p, target, pushQ, pushR)
        preview.addCollisionHint(p, hoverQ, hoverR, pushQ, pushR, "collision_damage", target, colossus, "collision_both")
        preview.addAttackDamage(p, target, 99)
    else
        -- Normal push
        preview.applyPush(p, target, hoverQ, hoverR, pushQ, pushR, hex, entities)
    end
end

-- Mighty Throw: grab adjacent target, throw in direction, both die, struck pushed aside.
handlers["Mighty Throw"] = function(p, attacker, attack, hoverQ, hoverR, hex, entities)
    local throwTarget = _G.mightyThrowTarget
    if not throwTarget then
        local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if dist ~= 1 then return end
        local target = getEntity(hoverQ, hoverR, entities)
        if not target or not target:isCharacter() or target.health <= 0 or target.isPushable == false then return end
        preview.addOverlay(p, hoverQ, hoverR, "target")
        return
    end

    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end

    preview.addOverlay(p, throwTarget.q, throwTarget.r, "target")
    preview.addAttackDamage(p, throwTarget, 99)

    preview.addLine(p, attacker.q, attacker.r, hoverQ, hoverR)

    local curQ, curR = attacker.q, attacker.r
    local struckTarget, struckQ, struckR
    while true do
        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
        if not isValid(nextQ, nextR, hex) then break end
        local e = getEntity(nextQ, nextR, entities)
        if e and e ~= throwTarget and e.health > 0 then
            struckTarget = e
            struckQ, struckR = nextQ, nextR
            break
        end
        curQ, curR = nextQ, nextR
    end

    if struckTarget and struckQ then
        preview.addOverlay(p, struckQ, struckR, "target")
        preview.addAttackDamage(p, struckTarget, 99)

        local backQ, backR = struckQ, struckR
        local throwLandQ, throwLandR
        for i = 1, 20 do
            local nq, nr = hex_utils.applyCubeStep(backQ, backR, -stepX, -stepY, -stepZ)
            if not isActive(nq, nr, hex) then break end
            if not getEntity(nq, nr, entities) then
                throwLandQ, throwLandR = nq, nr
                break
            end
            backQ, backR = nq, nr
        end
        if throwLandQ then
            preview.markPushed(p, throwTarget, throwLandQ, throwLandR)
            preview.addPushArrow(p, throwTarget.q, throwTarget.r, throwLandQ, throwLandR)
        end

        local rightX, rightY, rightZ = -stepY, -stepZ, -stepX
        local leftX, leftY, leftZ = -stepZ, -stepX, -stepY

        local rq, rr = hex_utils.applyCubeStep(struckQ, struckR, rightX, rightY, rightZ)
        local lq, lr = hex_utils.applyCubeStep(struckQ, struckR, leftX, leftY, leftZ)

        local sideQ, sideR
        if isActive(rq, rr, hex) and not getEntity(rq, rr, entities) then
            sideQ, sideR = rq, rr
        elseif isActive(lq, lr, hex) and not getEntity(lq, lr, entities) then
            sideQ, sideR = lq, lr
        end

        if sideQ then
            preview.applyPush(p, struckTarget, struckQ, struckR, sideQ, sideR, hex, entities)
            preview.addOverlay(p, sideQ, sideR, "push_dest")
        end
    end
end

-- Generic fallback for attacks that only provide getAffectedCells.
function handlers.__fallback(p, attacker, attack, hoverQ, hoverR, hex, entities)
    handleAffectedCells(p, attacker, attack, hoverQ, hoverR, hex, entities)
end

-- ============================================================
-- MAIN ENTRY POINT
-- ============================================================

function preview.compute(hex, attacker, attack, hoverQ, hoverR, entities)
    local p = preview.new()
    if not attack or not attacker or attacker.hasActedThisTurn then return p end
    if not hex:isActiveHex(hoverQ, hoverR) then return p end
    if hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR) > attack.range then return p end

    local handler = handlers[attack.name]
    if handler then
        handler(p, attacker, attack, hoverQ, hoverR, hex, entities)
    elseif attack.getAffectedCells then
        handlers.__fallback(p, attacker, attack, hoverQ, hoverR, hex, entities)
    end

    return p
end

-- Build icon list from a computed preview.
function preview.buildIcons(p, hex)
    local icons = {}
    for _, info in pairs(p.damages) do
        local icon = preview.getDamageIcon(info.entity, info.totalDamage)
        if icon then
            local x, y = getDrawCoords(info.entity.q, info.entity.r)
            icons[#icons + 1] = {
                q = info.entity.q, r = info.entity.r,
                icon = icon, x = x, y = y,
            }
        end
    end
    for _, col in ipairs(p.collisions) do
        if col.type then
            local x1, y1 = getDrawCoords(col.fromQ, col.fromR)
            local x2, y2 = getDrawCoords(col.toQ, col.toR)
            icons[#icons + 1] = {
                x = (x1 + x2) / 2, y = (y1 + y2) / 2,
                icon = col.type,
            }
        end
    end
    return icons
end

-- Build push arrow list from a computed preview.
function preview.buildPushArrows(p, hex)
    local arrows = {}
    for _, arrow in ipairs(p.pushArrows) do
        local fromX, fromY = getDrawCoords(arrow.fromQ, arrow.fromR)
        local toX, toY = getDrawCoords(arrow.toQ, arrow.toR)
        arrows[#arrows + 1] = {
            fromX = fromX, fromY = fromY,
            toX = toX, toY = toY,
            fromQ = arrow.fromQ, fromR = arrow.fromR,
            toQ = arrow.toQ, toR = arrow.toR,
        }
    end
    return arrows
end

return preview
