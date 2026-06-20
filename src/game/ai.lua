-- src/game/ai.lua
-- Enemy AI: each enemy plans a move, then attacks from its new position.
-- Behaviour is driven by the unit `behavior` field (melee/ranged/caster/stationary).

local pathfinding = require("src.game.pathfinding")
local attacks = require("src.content.attacks")
local statuses = require("src.content.statuses")
local terrain = require("src.content.terrain")

local ai = {}

local function nearestAlly(state, q, r)
    local best, bestD = nil, math.huge
    for _, e in ipairs(state.entities) do
        if e:isAlive() and e:isAlly() then
            local d = state.grid:getDistance(q, r, e.q, e.r)
            if d < bestD then bestD = d; best = e end
        end
    end
    return best, bestD
end

-- Score an attack from a hypothetical cell: how many allies it would hit.
local function scoreAttack(enemy, attackId, cq, cr, state)
    local def = attacks.get(attackId)
    if not def then return nil end
    local savedQ, savedR = enemy.q, enemy.r
    enemy.q, enemy.r = cq, cr
    local targets = def.getValidTargets(enemy, state.grid, state.entities)
    local best = nil
    for _, t in ipairs(targets) do
        local cells = def.getAffectedCells(enemy, t.q, t.r, state.grid, state.entities)
        local hits = 0
        for _, c in ipairs(cells) do
            for _, e in ipairs(state.entities) do
                if e:isAlive() and e:isAlly() and e.q == c.q and e.r == c.r then hits = hits + 1 end
            end
        end
        -- for summon-type attacks (no allies hit), still valid if cell empty
        local score = hits * 10
        if hits == 0 and def.damage == 0 and (def.targetMode == "cell" or def.targetMode == "self") then
            score = 1
        end
        if score > 0 and (not best or score > best.score) then
            best = { q = t.q, r = t.r, score = score, hits = hits }
        end
    end
    enemy.q, enemy.r = savedQ, savedR
    return best, def
end

-- Choose the best (attack, target) from the enemy's current position. Returns {id,tq,tr} or nil.
function ai.bestAttack(enemy, state)
    local bestPick, bestScore = nil, 0
    for _, aid in ipairs(enemy.attackIds) do
        local pick, def = scoreAttack(enemy, aid, enemy.q, enemy.r, state)
        if pick and pick.score > bestScore then
            bestScore = pick.score
            bestPick = { id = aid, tq = pick.q, tr = pick.r }
        end
    end
    return bestPick
end

-- Plan a move path (list of cells) or nil to stay. Considers attack opportunity after moving.
function ai.planMove(enemy, state)
    if enemy.moveRange == 0 or statuses.blocksMove(enemy) then return nil end
    local ally, _ = nearestAlly(state, enemy.q, enemy.r)
    if not ally then return nil end

    local range = statuses.modifyMoveRange(enemy, enemy.moveRange)
    local stops, dist = pathfinding.reachable(state.grid, state.terrain, state.entities, enemy, range)
    -- candidates: current cell + all reachable stops
    local candidates = { { q = enemy.q, r = enemy.r, path = nil } }
    for k, d in pairs(stops) do
        local q, r = k:match("(-?%d+),(-?%d+)")
        q, r = tonumber(q), tonumber(r)
        local path = pathfinding.pathTo(state.grid, state.terrain, state.entities, enemy, q, r, range)
        if path then table.insert(candidates, { q = q, r = r, path = path }) end
    end

    -- pick candidate maximising attack score; tiebreak by smaller distance to nearest ally
    local best, bestScore, bestDist = nil, -1, math.huge
    for _, c in ipairs(candidates) do
        local score = 0
        for _, aid in ipairs(enemy.attackIds) do
            local pick = scoreAttack(enemy, aid, c.q, c.r, state)
            if pick and pick.score > score then score = pick.score end
        end
        local _, d = nearestAlly(state, c.q, c.r)
        if score > bestScore or (score == bestScore and d < bestDist) then
            bestScore = score; bestDist = d; best = c
        end
    end
    return best and best.path or nil
end

-- Execute the enemy's attack from its current position. Returns true if it acted.
function ai.doAttack(enemy, state)
    local pick = ai.bestAttack(enemy, state)
    if not pick then return false end
    local def = attacks.get(pick.id)
    if not def then return false end
    return def.execute(enemy, pick.tq, pick.tr, state.grid, state.entities, state:attackCtx()) == true
end

return ai
