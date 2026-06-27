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
    local ga = _G.global_abilities
    local abilityStates = {}
    if ga then
        for name, ab in pairs(ga.registry) do
            abilityStates[name] = ab.hasBeenUsed
        end
    end

    local snap = {
        entities = {},
        hexStatuses = {},
        upperTerrain = {},
        selectedActor = _G.selectedActor,
        chaos = _G.chaos or 0,
        abilityMana = ga and ga.mana or 0,
        abilityUsedThisTurn = ga and ga.abilityUsedThisTurn or false,
        activeAbilityName = ga and ga.activeAbility and ga.activeAbility.name or nil,
        abilityStates = abilityStates,
        actionHistoryCount = #undo.history,
    }
    -- Save every entity's state
    for _, e in ipairs(_G.entities) do
        local es = {
            ref = e,
            q = e.q, r = e.r,
            health = e.health, maxHealth = e.maxHealth,
            attacksFirst = e.attacksFirst,
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
    -- Copy upper terrain map
    local utm = _G.upperTerrainMap or {}
    for q, row in pairs(utm) do
        local rowCopy = {}
        for r, val in pairs(row) do
            rowCopy[r] = val
        end
        snap.upperTerrain[q] = rowCopy
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

    -- Cancel any pending push animations so they don't overwrite restored positions
    if pushAnimations then
        pushAnimations.queue = {}
        pushAnimations.active = false
        pushAnimations.globalCallback = nil
    end

    -- Restore entity data
    local existingRefs = {}
    for _, es in ipairs(snap.entities) do
        if es.ref then
            es.ref.q = es.q
            es.ref.r = es.r
            es.ref.currentDrawX = nil
            es.ref.currentDrawY = nil
            es.ref.health = es.health
            es.ref.maxHealth = es.maxHealth
            es.ref.attacksFirst = es.attacksFirst
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
        if not existingRefs[entities[i]] then
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

    -- Restore upper terrain map
    if not _G.upperTerrainMap then _G.upperTerrainMap = {} end
    local utm = _G.upperTerrainMap
    for q, _ in pairs(utm) do
        utm[q] = nil
    end
    for q, row in pairs(snap.upperTerrain or {}) do
        local rowCopy = {}
        for r, val in pairs(row) do
            rowCopy[r] = val
        end
        utm[q] = rowCopy
    end

    -- Keep current selected actor, just update its highlight position
    if _G.selectedActor then
        _G.hex.selectedQ = _G.selectedActor.q
        _G.hex.selectedR = _G.selectedActor.r
        _G.updateAttackButtons(_G.selectedActor)
    end
    _G.attackMode = false
    _G.selectedAttack = nil
    _G.chaos = snap.chaos or 0

    -- Restore ability state
    local ga = _G.global_abilities
    if ga and snap.abilityStates then
        ga.mana = snap.abilityMana or 0
        ga.abilityUsedThisTurn = snap.abilityUsedThisTurn or false
        for name, ab in pairs(ga.registry) do
            ab.hasBeenUsed = snap.abilityStates[name] or false
        end
        if snap.activeAbilityName and ga.registry[snap.activeAbilityName] then
            ga.activeAbility = ga.registry[snap.activeAbilityName]
        else
            ga.activeAbility = nil
        end
    end

    log.debugf("undo", "Snapshot restored. History size: %d", #undo.history)
    if _G.rebuildEntityIndex then _G.rebuildEntityIndex() end
    return true
end

-- Undo the last action (restore to previous snapshot)
function undo.undoLast()
    if #undo.history <= 1 then
        log.infof("undo", "undoLast: only %d snapshot(s), nothing to undo", #undo.history)
        return false
    end
    -- Save reference to the snapshot before the last action (state before last action)
    -- BEFORE modifying undo.history, to avoid any timing/length issues
    local targetSnap = undo.history[#undo.history - 1]
    -- Remove current snapshot (state after last action)
    table.remove(undo.history)
    -- Restore to the state before the last action
    log.infof("undo", "undoLast: restoring snapshot %d/%d", #undo.history, #undo.history)
    return undo.restore(targetSnap)
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
