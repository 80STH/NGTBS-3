-- src/content/attacks.lua
-- Attack registry. Each attack is a definition table:
--   { id, name, description, range, damage, targetMode,
--     getValidTargets(attacker, grid, entities) -> list {q,r},
--     getAffectedCells(attacker, tq, tr, grid, entities) -> list {q,r},
--     execute(attacker, tq, tr, grid, entities, ctx) }
--
-- Adding a new attack: copy a similar def, tweak, then attacks.register(def).
-- `ctx` provides: addPushAnim(e, fq,fr, tq,tr), addEffect(name, q, r, opts),
--                 onChaos(n), sounds, log(msg), afterAttack().

local Registry = require("src.core.registry")
local terrain = require("src.content.terrain")
local statuses = require("src.content.statuses")

local attacks = { registry = Registry.new() }

-- ---- shared helpers ----
local function getEntityAt(entities, q, r)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r and e:isAlive() and not e.isHazard then return e end
    end
    return nil
end
attacks.getEntityAt = getEntityAt

-- direction (one of 6) from (a) to (b), or nil if not axis-aligned
local DIRS = {
    { dq =  1, dr = -1 }, { dq =  1, dr =  0 }, { dq =  0, dr =  1 },
    { dq = -1, dr =  1 }, { dq = -1, dr =  0 }, { dq =  0, dr = -1 },
}
local function dirTowards(fq, fr, tq, tr)
    for _, d in ipairs(DIRS) do
        -- walk from f along d; if we hit t, it's aligned
        local q, r = fq + d.dq, fr + d.dr
        if q == tq and r == tr then return d.dq, d.dr end
        -- extend further
        local cq, cr = q, r
        for _ = 2, 20 do
            cq, cr = cq + d.dq, cr + d.dr
            if cq == tq and cr == tr then return d.dq, d.dr end
        end
    end
    return nil
end
attacks.dirTowards = dirTowards

-- first living entity along a direction within maxRange; returns entity, cell {q,r}
local function lineFirst(fq, fr, dq, dr, grid, entities, maxRange, accept)
    local q, r = fq + dq, fr + dr
    for _ = 1, maxRange do
        if not grid:isActiveHex(q, r) then return nil, nil end
        local e = getEntityAt(entities, q, r)
        if e and (not accept or accept(e)) then return e, { q = q, r = r } end
        q, r = q + dq, r + dr
    end
    return nil, nil
end
attacks.lineFirst = lineFirst

-- Resolve a single-cell push of `target` in direction (dq,dr). Applies collision
-- damage and terrain-on-enter damage. Adds a push animation via ctx.
local function pushEntity(target, dq, dr, grid, entities, ctx)
    ctx = ctx or {}
    local fq, fr = target.q, target.r
    local tq, tr = fq + dq, fr + dr
    local function bounce() if ctx.addPushAnim then ctx.addPushAnim(target, fq, fr, fq, fr) end end

    if not grid:isActiveHex(tq, tr) then
        bounce()
        local died = target:takeDamage(1, ctx)
        if died then target:startDeath() end
        if ctx.sounds and ctx.sounds.collision then ctx.sounds.collision:play() end
        return false
    end
    if not terrain.passable(grid.terrain and grid.terrain[tq..","..tr] or "grass", target) then
        bounce()
        local died = target:takeDamage(1, ctx)
        if died then target:startDeath() end
        return false
    end
    local occ = getEntityAt(entities, tq, tr)
    if occ then
        bounce()
        local d1 = target:takeDamage(1, ctx); if d1 then target:startDeath() end
        local d2 = occ:takeDamage(1, ctx);    if d2 then occ:startDeath() end
        if ctx.sounds and ctx.sounds.collision then ctx.sounds.collision:play() end
        return false
    end
    -- free cell: move
    target:setPos(tq, tr)
    if ctx.addPushAnim then ctx.addPushAnim(target, fq, fr, tq, tr) end
    -- terrain on-enter damage
    local ter = grid.terrain and grid.terrain[tq..","..tr] or "grass"
    local entDmg = terrain.onEnter(ter, target, ctx)
    if entDmg and entDmg > 0 then
        local died = target:takeDamage(entDmg, ctx); if died then target:startDeath() end
    end
    return true
end
attacks.pushEntity = pushEntity

-- consume empowered: returns damage multiplier
local function empoweredDamage(attacker, dmg)
    if attacker:hasStatus("empowered") then
        attacker:removeStatus("empowered")
        return dmg * 2
    end
    return dmg
end

-- default valid-target generators
local function validLine(attacker, def, grid, entities)
    local out = {}
    local q, r = attacker.q, attacker.r
    for _, d in ipairs(DIRS) do
        local cq, cr = q + d.dq, r + d.dr
        for _ = 1, def.range do
            if not grid:isActiveHex(cq, cr) then break end
            table.insert(out, { q = cq, r = cr })
            cq, cr = cq + d.dq, cr + d.dr
        end
    end
    return out
end

local function validMelee(attacker, def, grid, entities)
    local out = {}
    for _, n in ipairs(grid:neighbors(attacker.q, attacker.r)) do
        table.insert(out, { q = n.q, r = n.r })
    end
    return out
end

local function validCell(attacker, def, grid, entities)
    local out = {}
    for _, c in ipairs(grid.activeList) do
        if grid:getDistance(attacker.q, attacker.r, c.q, c.r) <= def.range
           and not (c.q == attacker.q and c.r == attacker.r) then
            table.insert(out, { q = c.q, r = c.r })
        end
    end
    return out
end

local function defaultValidTargets(attacker, def, grid, entities)
    if def.targetMode == "line" then return validLine(attacker, def, grid, entities) end
    if def.targetMode == "melee" then return validMelee(attacker, def, grid, entities) end
    if def.targetMode == "cell" then return validCell(attacker, def, grid, entities) end
    if def.targetMode == "self" then return { { q = attacker.q, r = attacker.r } } end
    return {}
end

-- register a definition with defaults filled in
function attacks.register(def)
    if not def.getValidTargets then
        def.getValidTargets = function(a, g, e) return defaultValidTargets(a, def, g, e) end
    end
    if not def.getAffectedCells then
        def.getAffectedCells = function(a, tq, tr, g, e) return { { q = tq, r = tr } } end
    end
    attacks.registry:register(def.id, def)
end

function attacks.get(id) return attacks.registry:get(id) end
function attacks.all() return attacks.registry:all() end
function attacks.ids() return attacks.registry:list() end

-- ========================================================================
-- Built-in attacks
-- ========================================================================

-- Dash: charge along a line to the first target, push it 1 cell, deal 1,
-- and move the attacker into the target's former cell.
attacks.register({
    id = "dash", name = "Dash", description = "Charge and push", range = 5, damage = 1, targetMode = "line",
    getValidTargets = function(a, g, en) return validLine(a, { range = 5, targetMode = "line" }, g, en) end,
    execute = function(a, tq, tr, g, en, ctx)
        local dq, dr = dirTowards(a.q, a.r, tq, tr)
        if not dq then return false end
        local target, cell = lineFirst(a.q, a.r, dq, dr, g, en, 5,
            function(e) return e ~= a and e.side ~= a.side end)
        if not target or not cell then return false end
        local dmg = empoweredDamage(a, 1)
        local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        if ctx.addEffect then ctx.addEffect("hit", cell.q, cell.r) end
        if target:isAlive() then
            pushEntity(target, dq, dr, g, en, ctx)
            -- attacker moves into the vacated cell if free
            if not getEntityAt(en, cell.q, cell.r) and g:isActiveHex(cell.q, cell.r)
               and terrain.passable(g.terrain and g.terrain[cell.q..","..cell.r] or "grass", a) then
                local fq, fr = a.q, a.r
                a:setPos(cell.q, cell.r)
                if ctx.addPushAnim then ctx.addPushAnim(a, fq, fr, cell.q, cell.r) end
            end
        else
            local fq, fr = a.q, a.r
            a:setPos(cell.q, cell.r)
            if ctx.addPushAnim then ctx.addPushAnim(a, fq, fr, cell.q, cell.r) end
        end
        return true
    end,
})

-- Flip: melee; push target to the cell on the opposite side of the attacker, deal 1.
attacks.register({
    id = "flip", name = "Flip", description = "Flip enemy behind", range = 1, damage = 1, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local target = getEntityAt(en, tq, tr)
        if not target or target.side == a.side then return false end
        local dq, dr = tq - a.q, tr - a.r  -- direction from attacker to target
        local dmg = empoweredDamage(a, 1)
        local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        if target:isAlive() then pushEntity(target, dq, dr, g, en, ctx) end
        return true
    end,
})

-- Shoot: line shot; hits first enemy, pushes it, 1 damage.
attacks.register({
    id = "shoot", name = "Shoot", description = "Shoot and push first enemy", range = 6, damage = 1, targetMode = "line",
    execute = function(a, tq, tr, g, en, ctx)
        local dq, dr = dirTowards(a.q, a.r, tq, tr)
        if not dq then return false end
        local target, cell = lineFirst(a.q, a.r, dq, dr, g, en, 6,
            function(e) return e.side ~= a.side end)
        if not target then return false end
        local dmg = empoweredDamage(a, 1)
        local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        if ctx.addEffect then ctx.addEffect("shoot", a.q, a.r, { toQ = cell.q, toR = cell.r }) end
        if target:isAlive() then pushEntity(target, dq, dr, g, en, ctx) end
        return true
    end,
})

-- Push: line; push first entity, no damage.
attacks.register({
    id = "push", name = "Push", description = "Push first in line (no damage)", range = 5, damage = 0, targetMode = "line",
    execute = function(a, tq, tr, g, en, ctx)
        local dq, dr = dirTowards(a.q, a.r, tq, tr)
        if not dq then return false end
        local target, cell = lineFirst(a.q, a.r, dq, dr, g, en, 5)
        if not target then return false end
        empoweredDamage(a, 0)
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        pushEntity(target, dq, dr, g, en, ctx)
        return true
    end,
})

-- Piercing Shot: pass through first enemy, hit & push the second.
attacks.register({
    id = "piercing_shot", name = "Piercing Shot", description = "Shoot through first, hit second", range = 6, damage = 1, targetMode = "line",
    execute = function(a, tq, tr, g, en, ctx)
        local dq, dr = dirTowards(a.q, a.r, tq, tr)
        if not dq then return false end
        local first, cell1 = lineFirst(a.q, a.r, dq, dr, g, en, 6,
            function(e) return e.side ~= a.side end)
        if not first then return false end
        local dmg = empoweredDamage(a, 1)
        local d1 = first:takeDamage(dmg, ctx); if d1 then first:startDeath() end
        if ctx.addEffect then ctx.addEffect("shoot", a.q, a.r, { toQ = cell1.q, toR = cell1.r }) end
        -- second target beyond first
        if first:isAlive() then
            local q2, r2 = cell1.q + dq, cell1.r + dr
            if g:isActiveHex(q2, r2) then
                local second = getEntityAt(en, q2, r2)
                if second and second.side ~= a.side then
                    local d2 = second:takeDamage(dmg, ctx); if d2 then second:startDeath() end
                    if second:isAlive() then pushEntity(second, dq, dr, g, en, ctx) end
                end
            end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Bite: melee, 3 damage.
attacks.register({
    id = "bite", name = "Bite", description = "Melee, 3 damage", range = 1, damage = 3, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local target = getEntityAt(en, tq, tr)
        if not target then return false end
        local dmg = empoweredDamage(a, 3)
        local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        return true
    end,
})

-- Bash: melee 2 to target and to entity behind the attacker.
attacks.register({
    id = "bash", name = "Bash", description = "2 dmg to target and behind attacker", range = 1, damage = 2, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local target = getEntityAt(en, tq, tr)
        local dmg = empoweredDamage(a, 2)
        if target then
            local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
            if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        end
        -- behind attacker: opposite direction
        local dq, dr = a.q - tq, a.r - tr
        local bq, br = a.q + dq, a.r + dr
        local behind = getEntityAt(en, bq, br)
        if behind then
            local d2 = behind:takeDamage(dmg, ctx); if d2 then behind:startDeath() end
            if ctx.addEffect then ctx.addEffect("hit", bq, br) end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Cleave: melee 1 dmg to 3 cells in the front arc (target + two adjacent arcs).
attacks.register({
    id = "cleave", name = "Cleave", description = "1 dmg to 3 cells in front", range = 1, damage = 1, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local dmg = empoweredDamage(a, 1)
        -- the three front cells: target and its two neighbours adjacent to attacker
        local dq, dr = tq - a.q, tr - a.r
        local cells = { { q = tq, r = tr } }
        -- neighbours of target that are also neighbours of attacker (the arc)
        local attn = {}
        for _, n in ipairs(g:neighbors(a.q, a.r)) do attn[n.q..","..n.r] = true end
        for _, n in ipairs(g:neighbors(tq, tr)) do
            if attn[n.q..","..n.r] and not (n.q == tq and n.r == tr) then
                table.insert(cells, { q = n.q, r = n.r })
            end
        end
        for _, c in ipairs(cells) do
            local e = getEntityAt(en, c.q, c.r)
            if e and e.side ~= a.side then
                local died = e:takeDamage(dmg, ctx); if died then e:startDeath() end
                if ctx.addEffect then ctx.addEffect("hit", c.q, c.r) end
            end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Lunge: melee 2 to target and the cell behind the target.
attacks.register({
    id = "lunge", name = "Lunge", description = "2 dmg to target and behind it", range = 1, damage = 2, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local dmg = empoweredDamage(a, 2)
        local target = getEntityAt(en, tq, tr)
        if target then
            local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
            if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        end
        local dq, dr = tq - a.q, tr - a.r
        local bq, br = tq + dq, tr + dr
        local behind = getEntityAt(en, bq, br)
        if behind then
            local d2 = behind:takeDamage(dmg, ctx); if d2 then behind:startDeath() end
            if ctx.addEffect then ctx.addEffect("hit", bq, br) end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Heavy Punch: melee 1 dmg + push; lethal if empowered (damage doubled).
attacks.register({
    id = "heavy_punch", name = "Heavy Punch", description = "1 dmg + push (lethal if empowered)", range = 1, damage = 1, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local target = getEntityAt(en, tq, tr)
        if not target or target.side == a.side then return false end
        local dmg = empoweredDamage(a, 1)
        local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
        if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        if target:isAlive() then
            local dq, dr = tq - a.q, tr - a.r
            pushEntity(target, dq, dr, g, en, ctx)
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Empower Punch: push target; apply empowered to self; 1 dmg if already empowered.
attacks.register({
    id = "empower_punch", name = "Empower Punch", description = "Push + empower self; 1 dmg if empowered", range = 1, damage = 1, targetMode = "melee",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) ~= 1 then return false end
        local target = getEntityAt(en, tq, tr)
        if not target then return false end
        local wasEmp = a:hasStatus("empowered")
        if wasEmp then
            local died = target:takeDamage(1, ctx); if died then target:startDeath() end
            a:removeStatus("empowered")
            if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        else
            a:applyStatus("empowered")
            if ctx.addEffect then ctx.addEffect("empower", a.q, a.r) end
        end
        if target:isAlive() then
            local dq, dr = tq - a.q, tr - a.r
            pushEntity(target, dq, dr, g, en, ctx)
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Magic Bolt: ranged; hits any cell within range, ignores obstacles, 1 dmg.
attacks.register({
    id = "magic_bolt", name = "Magic Bolt", description = "Ranged, ignores obstacles, 1 dmg", range = 5, damage = 1, targetMode = "cell",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) > 5 then return false end
        local target = getEntityAt(en, tq, tr)
        if not target then
            if ctx.addEffect then ctx.addEffect("bolt", a.q, a.r, { toQ = tq, toR = tr }) end
            return true
        end
        local dmg = empoweredDamage(a, 1)
        local died = target:takeDamage(dmg, ctx); if died then target:startDeath() end
        if ctx.addEffect then ctx.addEffect("bolt", a.q, a.r, { toQ = tq, toR = tr }) end
        if ctx.addEffect then ctx.addEffect("hit", tq, tr) end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Ghost Bolt: piercing, unlimited range, 2 dmg.
attacks.register({
    id = "ghost_bolt", name = "Ghost Bolt", description = "Piercing, unlimited range, 2 dmg", range = 99, damage = 2, targetMode = "line",
    execute = function(a, tq, tr, g, en, ctx)
        local dq, dr = dirTowards(a.q, a.r, tq, tr)
        if not dq then return false end
        local dmg = empoweredDamage(a, 2)
        local q, r = a.q + dq, a.r + dr
        if ctx.addEffect then ctx.addEffect("shoot", a.q, a.r, { toQ = tq, toR = tr, piercing = true }) end
        while g:isActiveHex(q, r) do
            local e = getEntityAt(en, q, r)
            if e and e.side ~= a.side then
                local died = e:takeDamage(dmg, ctx); if died then e:startDeath() end
                if ctx.addEffect then ctx.addEffect("hit", q, r) end
            end
            q, r = q + dq, r + dr
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Summon: spawn an allied minion at target cell (empty, within range).
attacks.register({
    id = "summon", name = "Summon", description = "Summon allied minion at cell", range = 3, damage = 0, targetMode = "cell",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) > 3 then return false end
        if getEntityAt(en, tq, tr) then return false end
        if not g:isActiveHex(tq, tr) then return false end
        if ctx.spawnMinion then ctx.spawnMinion(a, tq, tr) end
        if ctx.addEffect then ctx.addEffect("summon", tq, tr) end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Stone Throw (aoe push): throw to a cell, push all surrounding enemies away.
attacks.register({
    id = "stone_throw", name = "Stone Throw", description = "Push enemies around target cell", range = 4, damage = 0, targetMode = "cell",
    getAffectedCells = function(a, tq, tr, g, en)
        local out = { { q = tq, r = tr } }
        for _, n in ipairs(g:neighbors(tq, tr)) do table.insert(out, { q = n.q, r = n.r }) end
        return out
    end,
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) > 4 then return false end
        if ctx.addEffect then ctx.addEffect("blast", tq, tr) end
        for _, n in ipairs(g:neighbors(tq, tr)) do
            local e = getEntityAt(en, n.q, n.r)
            if e and e.isPushable then
                local dq, dr = n.q - tq, n.r - tr
                pushEntity(e, dq, dr, g, en, ctx)
            end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Shockwave (aoe directional): push all 6 neighbours of attacker away.
attacks.register({
    id = "shockwave", name = "Shockwave", description = "Push all adjacent enemies away", range = 1, damage = 0, targetMode = "self",
    getAffectedCells = function(a, tq, tr, g, en)
        local out = {}
        for _, n in ipairs(g:neighbors(a.q, a.r)) do table.insert(out, { q = n.q, r = n.r }) end
        return out
    end,
    execute = function(a, tq, tr, g, en, ctx)
        if ctx.addEffect then ctx.addEffect("blast", a.q, a.r) end
        for _, n in ipairs(g:neighbors(a.q, a.r)) do
            local e = getEntityAt(en, n.q, n.r)
            if e and e.isPushable then
                local dq, dr = n.q - a.q, n.r - a.r
                pushEntity(e, dq, dr, g, en, ctx)
            end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Summon Enemy: SummoningRod spawns a random enemy at an adjacent empty cell.
attacks.register({
    id = "summon_enemy", name = "Summon", description = "Summon a random enemy nearby", range = 2, damage = 0, targetMode = "cell",
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) > 2 then return false end
        if getEntityAt(en, tq, tr) then return false end
        if not g:isActiveHex(tq, tr) then return false end
        if ctx.spawnEnemy then ctx.spawnEnemy(a, tq, tr) end
        if ctx.addEffect then ctx.addEffect("summon", tq, tr) end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

-- Power Bolt: ranged cone; hits target cell + 3 cells beyond it.
attacks.register({
    id = "power_bolt", name = "Power Bolt", description = "Cone bolt, 2 dmg", range = 5, damage = 2, targetMode = "cell",
    getAffectedCells = function(a, tq, tr, g, en)
        local out = { { q = tq, r = tr } }
        local dq, dr = dirTowards(a.q, a.r, tq, tr)
        if not dq then return out end
        local fq, fr = tq + dq, tr + dr
        if g:isActiveHex(fq, fr) then
            table.insert(out, { q = fq, r = fr })
            for _, n in ipairs(g:neighbors(fq, fr)) do
                if g:getDistance(a.q, a.r, n.q, n.r) > g:getDistance(a.q, a.r, fq, fr)
                   and g:isActiveHex(n.q, n.r) then
                    table.insert(out, { q = n.q, r = n.r })
                end
            end
        end
        return out
    end,
    execute = function(a, tq, tr, g, en, ctx)
        if g:getDistance(a.q, a.r, tq, tr) > 5 then return false end
        local cells = attacks.get("power_bolt").getAffectedCells(a, tq, tr, g, en)
        local dmg = empoweredDamage(a, 2)
        if ctx.addEffect then ctx.addEffect("bolt", a.q, a.r, { toQ = tq, toR = tr }) end
        for _, c in ipairs(cells) do
            local e = getEntityAt(en, c.q, c.r)
            if e and e.side ~= a.side then
                local died = e:takeDamage(dmg, ctx); if died then e:startDeath() end
                if ctx.addEffect then ctx.addEffect("hit", c.q, c.r) end
            end
        end
        if ctx.sounds and ctx.sounds.attack then ctx.sounds.attack:play() end
        return true
    end,
})

return attacks
