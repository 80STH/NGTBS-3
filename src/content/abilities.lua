-- src/content/abilities.lua
-- Global mana abilities. A registry + a manager (mana, unlocks, active ability).
-- Each ability def:
--   { id, name, key, manaCost, description, needsTarget,
--     onActivate(state), onDeactivate(state),
--     onClickHex(q,r,state) -> bool,   -- called when a target hex is clicked
--     collectOverlays(state, overlays) -- add overlay entries for valid target cells
--     reset() }
--
-- Adding a new ability: register a def here, then unlock it via the progression menu.

local Registry = require("src.core.registry")
local hex = require("src.core.hex")
local terrain = require("src.content.terrain")
local statuses = require("src.content.statuses")
local attacks = require("src.content.attacks")

local abilities = {
    registry = Registry.new(),
    mana = 3,
    maxMana = 3,
    usedThisTurn = false,
    activeAbility = nil,
    unlocked = { heal = true },
    order = { "heal", "extra_move", "wind_torrent", "unearth", "mind_control", "accelerate_decay" },
}

function abilities.register(def) abilities.registry:register(def.id, def) end
function abilities.get(id) return abilities.registry:get(id) end

function abilities.reset()
    abilities.mana = abilities.maxMana
    abilities.usedThisTurn = false
    abilities.activeAbility = nil
    for _, def in ipairs(abilities.registry:all()) do
        if def.reset then def.reset() end
    end
end

function abilities.resetUnlocks()
    abilities.unlocked = {}
    for _, def in ipairs(abilities.registry:all()) do
        abilities.unlocked[def.id] = true
    end
end

function abilities.unlock(id) abilities.unlocked[id] = true end

function abilities.displayOrder()
    local out = {}
    for _, id in ipairs(abilities.order) do
        if abilities.unlocked[id] and abilities.registry:has(id) then table.insert(out, id) end
    end
    return out
end

-- spend mana & mark used this turn
function abilities.spend(def)
    abilities.mana = abilities.mana - def.manaCost
    abilities.usedThisTurn = true
end

function abilities.canActivate(def, state)
    if not abilities.unlocked[def.id] then return false, "not unlocked" end
    if state.turn.phase ~= "player" then return false, "not your turn" end
    if abilities.usedThisTurn then return false, "already used an ability this turn" end
    if abilities.mana < def.manaCost then return false, "not enough mana" end
    return true
end

function abilities.activate(def, state)
    local ok = abilities.canActivate(def, state)
    if ok ~= true then return false end
    if abilities.activeAbility then abilities.activeAbility:onDeactivate(state) end
    abilities.activeAbility = def
    def:onActivate(state)
    return true
end

function abilities.cancel()
    if abilities.activeAbility then
        -- onDeactivate handled by caller with state
        abilities.activeAbility = nil
    end
end

function abilities.handleKey(key, state)
    for _, def in ipairs(abilities.registry:all()) do
        if key == def.key then
            if abilities.unlocked[def.id] then
                abilities.activate(def, state)
            end
            return true
        end
    end
    if key == "escape" and abilities.activeAbility then
        abilities.activeAbility:onDeactivate(state)
        abilities.activeAbility = nil
        return true
    end
    return false
end

function abilities.handleClick(q, r, state)
    local def = abilities.activeAbility
    if not def then return false end
    return def:onClickHex(q, r, state)
end

function abilities.collectOverlays(state, overlays)
    local def = abilities.activeAbility
    if def and def.collectOverlays then def:collectOverlays(state, overlays) end
end

-- ========================================================================
-- Helper: find entity at (q,r) among state.entities
-- ========================================================================
local function entityAt(state, q, r)
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e:isAlive() then return e end
    end
    return nil
end

-- ========================================================================
-- Heal: fully restore an ally's HP and clear its debuffs.
-- ========================================================================
abilities.register({
    id = "heal", name = "Heal", key = "h", manaCost = 1, needsTarget = true,
    description = "Full HP + clear debuffs for one ally",
    reset = function() end,
    onActivate = function(state) end,
    onDeactivate = function(state) end,
    onClickHex = function(q, r, state)
        local t = entityAt(state, q, r)
        if not t or not t:isCharacter() or t.side ~= "ally" then return false end
        t.health = t.maxHealth
        t:clearStatuses()
        abilities.spend(abilities.get("heal"))
        abilities.activeAbility = nil
        if state.onEffect then state.onEffect("heal", q, r) end
        if state.sounds and state.sounds.heal then state.sounds.heal:play() end
        state:clearHistory()
        return true
    end,
    collectOverlays = function(state, overlays)
        for _, e in ipairs(state.entities) do
            if e:isAlive() and e:isCharacter() and e.side == "ally" then
                overlays[e.q .. "," .. e.r] = { abilityTarget = "heal" }
            end
        end
    end,
})

-- ========================================================================
-- Extra Move: let an ally who already acted move again this turn.
-- ========================================================================
abilities.register({
    id = "extra_move", name = "Extra Move", key = "x", manaCost = 1, needsTarget = true,
    description = "An ally who acted may move again",
    reset = function() end,
    onActivate = function(state) end,
    onDeactivate = function(state) end,
    onClickHex = function(q, r, state)
        local t = entityAt(state, q, r)
        if not t or t.side ~= "ally" then return false end
        if not t.hasActedThisTurn then return false end
        t.canMoveAfterAttack = true
        t.hasActedThisTurn = false
        abilities.spend(abilities.get("extra_move"))
        abilities.activeAbility = nil
        if state.onEffect then state.onEffect("empower", q, r) end
        state:clearHistory()
        return true
    end,
    collectOverlays = function(state, overlays)
        for _, e in ipairs(state.entities) do
            if e:isAlive() and e.side == "ally" and e.hasActedThisTurn then
                overlays[e.q .. "," .. e.r] = { abilityTarget = "extra_move" }
            end
        end
    end,
})

-- ========================================================================
-- Wind Torrent: push every pushable entity one cell in a chosen direction.
-- ========================================================================
local windStep = {
    [ "1,-1"] = { dq = 1, dr = -1 }, ["1,0"]  = { dq = 1, dr = 0 },  ["0,1"]  = { dq = 0, dr = 1 },
    ["-1,1"] = { dq = -1, dr = 1 }, ["-1,0"] = { dq = -1, dr = 0 }, ["0,-1"] = { dq = 0, dr = -1 },
}
abilities.register({
    id = "wind_torrent", name = "Wind Torrent", key = "w", manaCost = 2, needsTarget = true,
    description = "Push all units one cell in a direction",
    reset = function() end,
    onActivate = function(state) end,
    onDeactivate = function(state) end,
    onClickHex = function(q, r, state)
        local dq, dr = hex.dirTowards(state.grid.centerQ, state.grid.centerR, q, r)
        if not dq then return false end
        local ctx = state:attackCtx()
        -- push farthest-first so chain collisions resolve cleanly
        local list = {}
        for _, e in ipairs(state.entities) do
            if e:isAlive() and e.isPushable then table.insert(list, e) end
        end
        table.sort(list, function(a, b)
            return state.grid:getDistance(state.grid.centerQ, state.grid.centerR, a.q, a.r)
                 > state.grid:getDistance(state.grid.centerQ, state.grid.centerR, b.q, b.r)
        end)
        for _, e in ipairs(list) do
            if e:isAlive() then attacks.pushEntity(e, dq, dr, state.grid, state.entities, ctx) end
        end
        abilities.spend(abilities.get("wind_torrent"))
        abilities.activeAbility = nil
        if state.onEffect then state.onEffect("blast", state.grid.centerQ, state.grid.centerR) end
        if state.sounds and state.sounds.wind then state.sounds.wind:play() end
        state:clearHistory()
        state:checkEnd()
        return true
    end,
    collectOverlays = function(state, overlays)
        -- valid targets are any active hex; the direction is read from it
        for _, c in ipairs(state.grid.activeList) do
            overlays[c.q .. "," .. c.r] = { abilityTarget = "wind" }
        end
    end,
})

-- ========================================================================
-- Unearth: all dig sites immediately spawn their enemy and are cleared.
-- ========================================================================
abilities.register({
    id = "unearth", name = "Unearth", key = "u", manaCost = 1, needsTarget = false,
    description = "Trigger all dig sites now",
    reset = function() end,
    onActivate = function(state)
        local sites = statuses.getAllDigSites()
        if #sites == 0 then abilities.activeAbility = nil; return end
        for _, s in ipairs(sites) do
            if not entityAt(state, s.q, s.r) and state.grid:isActiveHex(s.q, s.r) then
                local ter = state.terrain[s.q..","..s.r] or "grass"
                if not terrain.isWater(ter) and ter ~= "underwater_mines" then
                    state:spawnEnemyAt(s.q, s.r, s.spawn)
                end
            end
            statuses.removeDigSite(s.q, s.r)
        end
        abilities.spend(abilities.get("unearth"))
        abilities.activeAbility = nil
        state:clearHistory()
        state:checkEnd()
    end,
    onDeactivate = function(state) end,
    onClickHex = function(q, r, state) return false end,
    collectOverlays = function(state, overlays)
        for _, s in ipairs(statuses.getAllDigSites()) do
            overlays[s.q .. "," .. s.r] = { abilityTarget = "unearth" }
        end
    end,
})

-- ========================================================================
-- Mind Control: move an enemy one cell to an adjacent empty cell.
-- ========================================================================
abilities.register({
    id = "mind_control", name = "Mind Control", key = "m", manaCost = 2, needsTarget = true,
    description = "Move an enemy one cell",
    phase = nil, target = nil,
    reset = function() local def = abilities.get("mind_control"); def.phase = nil; def.target = nil end,
    onActivate = function(state)
        local def = abilities.get("mind_control")
        def.phase = "select_enemy"; def.target = nil
    end,
    onDeactivate = function(state)
        local def = abilities.get("mind_control")
        def.phase = nil; def.target = nil
    end,
    onClickHex = function(q, r, state)
        local def = abilities.get("mind_control")
        if def.phase == "select_enemy" then
            local t = entityAt(state, q, r)
            if not t or t.side ~= "enemy" then return false end
            def.target = t; def.phase = "select_dest"
            return true
        end
        if def.phase == "select_dest" then
            if not def.target then return false end
            if state.grid:getDistance(def.target.q, def.target.r, q, r) ~= 1 then return false end
            if not state.grid:isActiveHex(q, r) or entityAt(state, q, r) then return false end
            def.target:setPos(q, r)
            if state.onEffect then state.onEffect("empower", q, r) end
            abilities.spend(abilities.get("mind_control"))
            abilities.activeAbility = nil
            def.phase = nil; def.target = nil
            state:clearHistory()
            return true
        end
        return false
    end,
    collectOverlays = function(state, overlays)
        local def = abilities.get("mind_control")
        if def.phase == "select_enemy" then
            for _, e in ipairs(state.entities) do
                if e:isAlive() and e.side == "enemy" then
                    overlays[e.q .. "," .. e.r] = { abilityTarget = "mind_enemy" }
                end
            end
        elseif def.phase == "select_dest" and def.target then
            for _, n in ipairs(state.grid:neighbors(def.target.q, def.target.r)) do
                if not entityAt(state, n.q, n.r) then
                    overlays[n.q .. "," .. n.r] = { abilityTarget = "mind_dest" }
                end
            end
        end
    end,
})

-- ========================================================================
-- Accelerate Decay: reduce max turns by 1 (min: current turn + 1).
-- ========================================================================
abilities.register({
    id = "accelerate_decay", name = "Accelerate Decay", key = "d", manaCost = 1, needsTarget = false,
    description = "Reduce max turns by 1",
    reset = function() end,
    onActivate = function(state)
        if state.maxTurns then
            state.maxTurns = math.max(state.turnCount + 1, state.maxTurns - 1)
        end
        abilities.spend(abilities.get("accelerate_decay"))
        abilities.activeAbility = nil
        if state.onEffect then state.onEffect("decay", 0, 0) end
        state:clearHistory()
    end,
    onDeactivate = function(state) end,
    onClickHex = function(q, r, state) return false end,
    collectOverlays = function(state, overlays) end,
})

return abilities
