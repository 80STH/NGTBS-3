-- src/content/objectives.lua
-- Objective registry. Each def: { id, describe(spec), check(state, spec) -> "ongoing"|"win"|"lose" }
-- Adding a new objective: register a def here and reference its id from a map.

local Registry = require("src.core.registry")
local objectives = { registry = Registry.new() }

function objectives.register(def) objectives.registry:register(def.id, def) end
function objectives.get(id) return objectives.registry:get(id) end

function objectives.describe(spec)
    local def = objectives.registry:get(spec.type)
    if def then return def.describe(spec) end
    return "Unknown objective"
end

function objectives.check(state, spec)
    spec = spec or state.objective or { type = "kill_all" }
    local def = objectives.registry:get(spec.type)
    if not def then return "ongoing" end
    return def.check(state, spec)
end

-- helper: are there any living enemies?
local function enemiesAlive(state)
    for _, e in ipairs(state.entities) do
        if e:isAlive() and e:isEnemy() and e:isCharacter() then return true end
    end
    return false
end

local function alliesAlive(state)
    for _, e in ipairs(state.entities) do
        if e:isAlive() and e:isAlly() then return true end
    end
    return false
end

-- Kill all enemies.
objectives.register({
    id = "kill_all",
    describe = function(spec) return "Defeat all enemies" end,
    check = function(state, spec)
        if not alliesAlive(state) then return "lose" end
        if not enemiesAlive(state) then return "win" end
        return "ongoing"
    end,
})

-- Survive N turns (maxTurns). Win by reaching the turn limit without losing all allies.
objectives.register({
    id = "survive",
    describe = function(spec) return "Survive " .. (spec.turns or state.maxTurns) .. " turns" end,
    check = function(state, spec)
        if not alliesAlive(state) then return "lose" end
        local limit = spec.turns or state.maxTurns
        if state.turn.count >= limit then return "win" end
        return "ongoing"
    end,
})

-- Protect a specific objective entity (e.g. a Tower). Lose if it dies.
objectives.register({
    id = "protect",
    describe = function(spec) return "Protect the " .. (spec.targetName or "objective") end,
    check = function(state, spec)
        local alive = false
        for _, e in ipairs(state.entities) do
            if e.isObjective and e:isAlive() and (not spec.targetId or e.defId == spec.targetId) then
                alive = true; break
            end
        end
        if not alive then return "lose" end
        if spec.alsoKillAll and not enemiesAlive(state) then return "win" end
        if state.turn.count >= (state.maxTurns or 999) then return "win" end
        return "ongoing"
    end,
})

-- Kill a specific boss enemy (e.g. Power Lich).
objectives.register({
    id = "kill_target",
    describe = function(spec) return "Defeat the " .. (spec.targetName or "boss") end,
    check = function(state, spec)
        if not alliesAlive(state) then return "lose" end
        for _, e in ipairs(state.entities) do
            if e:isAlive() and e.defId == spec.targetId then return "ongoing" end
        end
        return "win"
    end,
})

return objectives
