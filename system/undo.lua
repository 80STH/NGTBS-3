-- undo.lua
-- Full battlefield snapshot undo system
-- Stores complete state before each action, restores on undo
-- History persists until end of turn

local undo = {}
local log = require("util.log")

undo.history = {}

-- Take a full battlefield snapshot (call before any action)
function undo.snapshot()
    local status = _G.status
    local snap = {
        entities = {},
        hexStatuses = {},
        selectedActor = _G.selectedActor,
        actionHistoryCount = #undo.history,
    }
    -- Save every entity's state
    for _, e in ipairs(_G.entities) do
        local es = {
            ref = e,
            q = e.q, r = e.r,
            health = e.health, maxHealth = e.maxHealth,
            hasActedThisTurn = e.hasActedThisTurn,
            hasMovedThisTurn = e.hasMovedThisTurn,
            canMoveAfterAttack = e.canMoveAfterAttack,
            isMoving = e.isMoving,
            isDying = e.isDying,
            deathTimer = e.deathTimer,
            direction = e.direction,
            hasPreparedAttack = e.hasPreparedAttack,
            preparedAttack = e.preparedAttack,
            preparePos = e.preparePos,
            preparedTarget = e.preparedTarget,
            chainAttack = e.chainAttack,
            redirectPending = e.redirectPending,
            upgradeLevel = e.upgradeLevel,
            maxDamagePerHit = e.maxDamagePerHit,
            summonCooldown = e.summonCooldown,
            summonTargetQ = e.summonTargetQ,
            summonTargetR = e.summonTargetR,
        }
        -- Copy statuses
        es.statuses = status.copyEntityStatuses(e)
        table.insert(snap.entities, es)
    end
    -- Copy hex statuses
    if status.hexStatuses then
        for key, list in pairs(status.hexStatuses) do
            local copy = {}
            for _, st in ipairs(list) do
                table.insert(copy, st)
            end
            snap.hexStatuses[key] = copy
        end
    end
    table.insert(undo.history, snap)
    log.infof("undo", "Snapshot saved #%d. Entities: %d", #undo.history, #snap.entities)
    return snap
end

-- Restore entire battlefield to a saved snapshot
function undo.restore(snap)
    if not snap then return false end
    local status = _G.status
    local entities = _G.entities

    -- Restore entity data
    local existingRefs = {}
    for _, es in ipairs(snap.entities) do
        if es.ref then
            es.ref.q = es.q
            es.ref.r = es.r
            es.ref.health = es.health
            es.ref.maxHealth = es.maxHealth
            es.ref.hasActedThisTurn = es.hasActedThisTurn
            es.ref.hasMovedThisTurn = es.hasMovedThisTurn
            es.ref.canMoveAfterAttack = es.canMoveAfterAttack
            es.ref.isMoving = es.isMoving
            es.ref.isDying = es.isDying
            es.ref.deathTimer = es.deathTimer
            es.ref.direction = es.direction
            es.ref.hasPreparedAttack = es.hasPreparedAttack
            es.ref.preparedAttack = es.preparedAttack
            es.ref.preparePos = es.preparePos
            es.ref.preparedTarget = es.preparedTarget
            es.ref.chainAttack = es.chainAttack
            es.ref.redirectPending = es.redirectPending
            es.ref.upgradeLevel = es.upgradeLevel
            es.ref.maxDamagePerHit = es.maxDamagePerHit
            es.ref.summonCooldown = es.summonCooldown
            es.ref.summonTargetQ = es.summonTargetQ
            es.ref.summonTargetR = es.summonTargetR
            -- Restore statuses
            status.setEntityStatuses(es.ref, es.statuses)
            existingRefs[es.ref] = true
        end
    end

    -- Remove entities that weren't in the snapshot (created after snapshot)
    for i = #entities, 1, -1 do
        if not existingRefs[entities[i]] and entities[i]:isCharacter() then
            table.remove(entities, i)
        end
    end

    -- Re-add entities that were removed (dead and revived)
    for _, es in ipairs(snap.entities) do
        if es.ref and es.health > 0 then
            local found = false
            for _, e in ipairs(entities) do
                if e == es.ref then found = true; break end
            end
            if not found then
                table.insert(entities, es.ref)
                log.infof("undo", "Restored %s to battlefield", es.ref.name or "entity")
            end
        end
    end

    -- Restore hex statuses
    if status.hexStatuses then
        for key, _ in pairs(status.hexStatuses) do
            status.hexStatuses[key] = nil
        end
        for key, list in pairs(snap.hexStatuses) do
            local copy = {}
            for _, st in ipairs(list) do
                table.insert(copy, st)
            end
            status.hexStatuses[key] = copy
        end
    end

    -- Restore selected actor
    _G.selectedActor = snap.selectedActor
    if _G.selectedActor then
        _G.hex.selectedQ = _G.selectedActor.q
        _G.hex.selectedR = _G.selectedActor.r
        _G.updateAttackButtons(_G.selectedActor)
    end
    _G.attackMode = false
    _G.selectedAttack = nil

    log.debugf("undo", "Snapshot restored. History size: %d", #undo.history)
    return true
end

-- Undo the last action (restore to previous snapshot)
function undo.undoLast()
    if #undo.history <= 1 then
        log.infof("undo", "undoLast: only %d snapshot(s), nothing to undo", #undo.history)
        return false
    end
    -- Remove current snapshot (state after last action)
    table.remove(undo.history)
    -- Restore to the now-last snapshot (state before last action)
    local snap = undo.history[#undo.history]
    log.infof("undo", "undoLast: restoring snapshot %d/%d", #undo.history, #undo.history)
    return undo.restore(snap)
end

-- Undo all actions (restore to start of turn)
function undo.undoAll()
    if #undo.history <= 1 then
        return undo.undoLast()
    end
    -- Keep only the first snapshot (start of turn)
    local firstSnap = undo.history[1]
    while #undo.history > 0 do
        table.remove(undo.history)
    end
    table.insert(undo.history, firstSnap)
    return undo.restore(firstSnap)
end

-- Clear history (called at end of turn)
function undo.clear()
    undo.history = {}
    log.debug("undo", "History cleared")
end

return undo
