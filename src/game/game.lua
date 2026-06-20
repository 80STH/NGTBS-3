-- src/game/game.lua
-- Central game state & orchestrator. Owns grid, entities, terrain, statuses,
-- abilities, trains, objectives, turns, animations, undo history.
--
-- Phases: "menu" | "deploy" | "playing" | "gameover"
-- Turn phases (when "playing"): "player" | "enemy" | "end"

local hex = require("src.core.hex")
local mapmod = require("src.core.map")
local Entity = require("src.core.entity")
local terrain = require("src.content.terrain")
local statuses = require("src.content.statuses")
local attacks = require("src.content.attacks")
local abilities = require("src.content.abilities")
local objectives = require("src.content.objectives")
local units = require("src.content.units")
local trains = require("src.content.trains")
local progression = require("src.content.progression")
local pathfinding = require("src.game.pathfinding")
local ai = require("src.game.ai")

local Game = {}
Game.__index = Game

function Game.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Game)
    self.designW = opts.designW or 720
    self.designH = opts.designH or 1280
    self.phase = "menu"
    self.turn = { phase = "player", count = 1 }
    self.grid = nil
    self.terrain = {}
    self.entities = {}
    self.objective = { type = "kill_all" }
    self.maxTurns = 12
    self.chaos = 0
    self.chaosMax = 6
    self.sounds = opts.sounds or {}

    self.selectedActor = nil
    self.selectedAttackId = nil
    self.attackMode = false
    self.moveTargets = {}     -- "q,r" -> distance
    self.attackTargets = {}   -- "q,r" -> true
    self.overlays = {}        -- general overlays from abilities

    self.pushAnims = {}       -- {entity, fq,fr, tq,tr, t, dur}
    self.effects = {}         -- {name, q, r, data, t, dur}
    self.screenShake = { t = 0, dur = 0.25, mag = 4 }

    self.history = {}
    self.maxUndo = 12

    self.deploy = { unplaced = {}, placed = {}, selectedIdx = nil, zones = {} }
    self.win = false
    self.lose = false
    self.message = nil
    self.messageTimer = 0

    -- enemy turn sequencing
    self.enemyQueue = {}
    self.enemyCurrent = nil
    self.enemySub = "move"   -- "move" | "wait_move" | "attack" | "next"
    self.enemyDelay = 0

    self.mapList = opts.mapList or {}
    self.squads = opts.squads or {}
    self.selectedMap = nil
    self.selectedSquad = nil
    self.progressionRun = false
    self.mapIndex = 1

    -- convenience callback used by abilities/trains to spawn visual effects
    self.onEffect = function(name, q, r, data) self:addEffect(name, q, r, data) end
    return self
end

-- ======================================================================
-- Entity helpers
-- ======================================================================
function Game:entityAt(q, r)
    for _, e in ipairs(self.entities) do
        if e.q == q and e.r == r and e:isAlive() and not e.isHazard then return e end
    end
    return nil
end

function Game:attackCtx()
    local state = self
    return {
        sounds = state.sounds,
        addPushAnim = function(e, fq, fr, tq, tr) state:addPushAnim(e, fq, fr, tq, tr) end,
        addEffect = function(name, q, r, data) state:addEffect(name, q, r, data) end,
        onChaos = function(n) state:addChaos(n) end,
        terrainOnEnter = function(entity, ter) state:terrainOnEnter(entity, ter) end,
        spawnMinion = function(summoner, q, r) state:spawnMinion(summoner, q, r) end,
        spawnEnemy = function(rod, q, r) state:spawnEnemyAt(q, r) end,
        log = function(msg) state:setMessage(msg) end,
    }
end

function Game:addChaos(n)
    self.chaos = math.min(self.chaosMax, self.chaos + n)
end

function Game:terrainOnEnter(entity, ter)
    if ter == "lava" and not entity.flying then
        local died = entity:takeDamage(1, self:attackCtx())
        if died then entity:startDeath() end
    end
end

function Game:addPushAnim(e, fq, fr, tq, tr)
    table.insert(self.pushAnims, { entity = e, fq = fq, fr = fr, tq = tq, tr = tr, t = 0, dur = 0.16 })
    self.screenShake.t = self.screenShake.dur
end

function Game:addEffect(name, q, r, data)
    local dur = 0.35
    if name == "blast" then dur = 0.5
    elseif name == "shoot" then dur = 0.25
    elseif name == "summon" then dur = 0.5
    elseif name == "empower" then dur = 0.5
    elseif name == "heal" then dur = 0.6 end
    table.insert(self.effects, { name = name, q = q, r = r, data = data or {}, t = 0, dur = dur })
end

function Game:setMessage(msg) self.message = msg; self.messageTimer = 2.5 end

-- ======================================================================
-- Map loading & deploy
-- ======================================================================
function Game:loadMap(mapData, squadUnitIds)
    local data = mapmod.normalize(mapData)
    self.objective = data.objective
    self.maxTurns = data.maxTurns
    self.chaos = 0
    self.entities = {}
    statuses.reset()
    abilities.reset()
    trains.reset()

    local size = data.size or 48
    local cells = mapmod.activeCells(data, hex)
    self.grid = hex.new(size, data.radius, cells, 0, 0)

    -- terrain
    self.terrain = {}
    for _, c in ipairs(cells) do
        self.terrain[c.q .. "," .. c.r] = data.terrain[c.q .. "," .. c.r] or "grass"
    end
    self.grid.terrain = self.terrain

    -- entities from map (allies listed with side="ally" are pre-placed; others placed now)
    self.deploy.unplaced = {}
    self.deploy.placed = {}
    self.deploy.zones = data.deployZone or {}
    for _, ent in ipairs(data.entities) do
        if ent.side == "ally" then
            local e = units.create(ent.def, ent.q, ent.r, "ally")
            progression.applyToEntity(e)
            table.insert(self.entities, e)
        else
            local side = ent.side or "neutral"
            local e = units.create(ent.def, ent.q, ent.r, side)
            table.insert(self.entities, e)
        end
    end

    -- squad allies for deployment
    if squadUnitIds and #squadUnitIds > 0 then
        for _, uid in ipairs(squadUnitIds) do
            local e = units.create(uid, 0, 0, "ally")
            progression.applyToEntity(e)
            e._unplaced = true
            table.insert(self.deploy.unplaced, e)
        end
    end

    -- hex statuses
    for _, s in ipairs(data.statuses) do
        statuses.applyToHex(s.q, s.r, s.type, s.data)
    end

    -- dig sites
    if data.digSites then
        for _, d in ipairs(data.digSites) do
            statuses.setDigSite(d.q, d.r, d.timer or 2, d.spawn)
        end
    end

    -- trains
    trains.build(self.grid, self.entities, data, self:attackCtx())

    -- decide phase
    if #self.deploy.unplaced > 0 then
        self.phase = "deploy"
        self.deploy.selectedIdx = 1
    else
        self.phase = "playing"
        self.turn = { phase = "player", count = 1 }
        self:startPlayerTurn(true)
    end
    self.win = false; self.lose = false
    self.history = {}
    self:checkEnd()
end

-- deploy: place selected ally at (q,r) if in zone (or anywhere on non-water active cell)
function Game:canDeployAt(q, r)
    if not self.grid:isActiveHex(q, r) then return false end
    if self:entityAt(q, r) then return false end
    local ally = self.deploy.unplaced[self.deploy.selectedIdx or 1]
    local anywhere = ally and ally.deployAnywhere
    local ter = self.terrain[q .. "," .. r] or "grass"
    if not anywhere and (ter == "water" or ter == "underwater_mines" or ter == "lava" or ter == "emptiness") then return false end
    if not anywhere and #self.deploy.zones > 0 then
        local inZone = false
        for _, z in ipairs(self.deploy.zones) do if z.q == q and z.r == r then inZone = true break end end
        if not inZone then return false end
    end
    return true
end

function Game:placeAlly(q, r)
    local idx = self.deploy.selectedIdx
    if not idx then return false end
    local ally = self.deploy.unplaced[idx]
    if not ally or not self:canDeployAt(q, r) then return false end
    ally:setPos(q, r)
    ally._unplaced = false
    table.insert(self.entities, ally)
    table.remove(self.deploy.unplaced, idx)
    table.insert(self.deploy.placed, ally)
    if #self.deploy.unplaced > 0 then
        self.deploy.selectedIdx = math.min(idx, #self.deploy.unplaced)
    else
        self.deploy.selectedIdx = nil
    end
    if #self.deploy.unplaced == 0 then
        self:finishDeploy()
    end
    return true
end

function Game:selectDeployIdx(i)
    if self.deploy.unplaced[i] then self.deploy.selectedIdx = i end
end

function Game:finishDeploy()
    self.phase = "playing"
    self.turn = { phase = "player", count = 1 }
    self:startPlayerTurn(true)
end

-- ======================================================================
-- Spawning
-- ======================================================================
function Game:spawnEnemyAt(q, r, spawnId)
    if self:entityAt(q, r) then return end
    if not self.grid:isActiveHex(q, r) then return end
    local id = spawnId or units.randomEnemyId()
    local e = units.create(id, q, r, "enemy")
    table.insert(self.entities, e)
    self:addEffect("summon", q, r)
end

function Game:spawnMinion(summoner, q, r)
    if self:entityAt(q, r) then return end
    local e = units.create("Summoned", q, r, "ally")
    e.moveRange = 2
    table.insert(self.entities, e)
end

-- ======================================================================
-- Selection & player actions
-- ======================================================================
function Game:effectiveMoveRange(entity)
    local r = statuses.modifyMoveRange(entity, entity.moveRange)
    -- slow auras from enemies
    if not entity.rootImmune and entity:isAlly() then
        for _, en in ipairs(self.entities) do
            if en:isAlive() and en:isEnemy() and en.aura and en.aura.type == "slow" then
                if self.grid:getDistance(en.q, en.r, entity.q, entity.r) <= (en.aura.radius or 1) then
                    r = math.max(0, r - 1)
                end
            end
        end
    end
    return r
end

function Game:selectActor(e)
    self.selectedActor = e
    self.selectedAttackId = nil
    self.attackMode = false
    self:computeMoveTargets()
    self.attackTargets = {}
end

function Game:clearSelection()
    self.selectedActor = nil
    self.selectedAttackId = nil
    self.attackMode = false
    self.moveTargets = {}
    self.attackTargets = {}
end

function Game:computeMoveTargets()
    self.moveTargets = {}
    if not self.selectedActor then return end
    if self.selectedActor.hasMovedThisTurn or statuses.blocksMove(self.selectedActor) then return end
    local range = self:effectiveMoveRange(self.selectedActor)
    local stops = pathfinding.reachable(self.grid, self.terrain, self.entities, self.selectedActor, range)
    self.moveTargets = stops
end

function Game:selectAttack(aid)
    if not self.selectedActor then return end
    if self.selectedActor.hasActedThisTurn then return end
    self.selectedAttackId = aid
    self.attackMode = true
    self:computeAttackTargets()
end

function Game:computeAttackTargets()
    self.attackTargets = {}
    if not self.selectedActor or not self.selectedAttackId then return end
    local def = attacks.get(self.selectedAttackId)
    if not def then return end
    local targets = def.getValidTargets(self.selectedActor, self.grid, self.entities)
    for _, t in ipairs(targets) do
        self.attackTargets[t.q .. "," .. t.r] = true
    end
end

-- Player tries to move selected actor to (q,r)
function Game:tryMove(q, r)
    if not self.selectedActor then return false end
    if self.selectedActor.hasMovedThisTurn then return false end
    if statuses.blocksMove(self.selectedActor) then return false end
    local k = q .. "," .. r
    if not self.moveTargets[k] then return false end
    local range = self:effectiveMoveRange(self.selectedActor)
    local path = pathfinding.pathTo(self.grid, self.terrain, self.entities, self.selectedActor, q, r, range)
    if not path then return false end
    self:pushHistory()
    self.selectedActor.hasMovedThisTurn = true
    self.selectedActor:startMove(path)
    self.moveTargets = {}
    return true
end

-- Player tries to attack target (q,r) with selected attack
function Game:tryAttack(q, r)
    if not self.selectedActor or not self.selectedAttackId then return false end
    if self.selectedActor.hasActedThisTurn then return false end
    if not self.attackTargets[q .. "," .. r] then return false end
    local def = attacks.get(self.selectedAttackId)
    if not def then return false end
    self:pushHistory()
    local ok = def.execute(self.selectedActor, q, r, self.grid, self.entities, self:attackCtx())
    if not ok then
        table.remove(self.history)  -- action did nothing; drop the snapshot
        return false
    end
    self.selectedActor.hasActedThisTurn = true
    if not self.selectedActor.canMoveAfterAttack then
        self.selectedActor.hasMovedThisTurn = true
    end
    self.attackTargets = {}
    self.attackMode = false
    self.selectedAttackId = nil
    self:checkEnd()
    return true
end

function Game:switchAttack()
    if not self.selectedActor then return end
    if self.selectedActor:switchAttack() then
        if self.attackMode then self:computeAttackTargets() end
    end
end

-- ======================================================================
-- Undo
-- ======================================================================
local function copyStatuses(list)
    local out = {}
    for _, s in ipairs(list) do table.insert(out, { type = s.type, data = { duration = s.data and s.data.duration } }) end
    return out
end

function Game:pushHistory()
    local snap = {
        turnCount = self.turn.count,
        maxTurns = self.maxTurns,
        chaos = self.chaos,
        mana = abilities.mana,
        abilityUsed = abilities.usedThisTurn,
        entities = {},
    }
    for _, e in ipairs(self.entities) do
        table.insert(snap.entities, {
            ref = e,
            q = e.q, r = e.r, health = e.health, maxHealth = e.maxHealth,
            hasActed = e.hasActedThisTurn, hasMoved = e.hasMovedThisTurn,
            canMoveAfterAttack = e.canMoveAfterAttack,
            currentAttackIndex = e.currentAttackIndex,
            isDying = e.isDying, deathTimer = e.deathTimer,
            statuses = copyStatuses(e.statuses),
            attackIds = e.attackIds,  -- summon could change this; snapshot ref list
        })
    end
    snap.hexes = {}
    for k, list in pairs(statuses.hexes) do
        snap.hexes[k] = {}
        for _, s in ipairs(list) do
            table.insert(snap.hexes[k], { type = s.type, data = { duration = s.data and s.data.duration } })
        end
    end
    snap.digSites = {}
    for k, d in pairs(statuses.digSites) do
        snap.digSites[k] = { timer = d.timer, age = d.age, spawn = d.spawn }
    end
    table.insert(self.history, snap)
    if #self.history > self.maxUndo then table.remove(self.history, 1) end
end

function Game:clearHistory() self.history = {} end

function Game:canUndo() return #self.history > 0 and self.turn.phase == "player" and not self:anyBusy() end

function Game:undo()
    if not self:canUndo() then return false end
    local snap = table.remove(self.history)
    self.turn.count = snap.turnCount
    self.maxTurns = snap.maxTurns
    self.chaos = snap.chaos
    abilities.mana = snap.mana
    abilities.usedThisTurn = snap.abilityUsed
    -- remove entities not in snapshot (new summons)
    local inSnap = {}
    for _, s in ipairs(snap.entities) do inSnap[s.ref] = true end
    local kept = {}
    for _, e in ipairs(self.entities) do
        if inSnap[e] then table.insert(kept, e) end
    end
    self.entities = kept
    for _, s in ipairs(snap.entities) do
        local e = s.ref
        e.q, e.r = s.q, s.r
        e.health, e.maxHealth = s.health, s.maxHealth
        e.hasActedThisTurn = s.hasActed
        e.hasMovedThisTurn = s.hasMoved
        e.canMoveAfterAttack = s.canMoveAfterAttack
        e.currentAttackIndex = s.currentAttackIndex
        e.isDying = s.isDying; e.deathTimer = s.deathTimer
        e:cancelMove()
        e.statuses = copyStatuses(s.statuses)
    end
    statuses.hexes = {}
    for k, list in pairs(snap.hexes) do
        statuses.hexes[k] = {}
        for _, s in ipairs(list) do
            table.insert(statuses.hexes[k], { type = s.type, data = { duration = s.data and s.data.duration } })
        end
    end
    statuses.digSites = {}
    for k, d in pairs(snap.digSites) do
        statuses.digSites[k] = { timer = d.timer, age = d.age, spawn = d.spawn }
    end
    self:clearSelection()
    self:checkEnd()
    if self.sounds and self.sounds.undo then self.sounds.undo:play() end
    return true
end

-- ======================================================================
-- Turns
-- ======================================================================
function Game:anyBusy()
    for _, e in ipairs(self.entities) do if e.isMoving then return true end end
    return false
end

function Game:startPlayerTurn(first)
    self.turn.phase = "player"
    abilities.usedThisTurn = false
    for _, e in ipairs(self.entities) do
        if e:isAlly() then
            e.hasActedThisTurn = false
            e.hasMovedThisTurn = false
            e.canMoveAfterAttack = e.artifactFlags and e.artifactFlags.moveAfterAttack or e.canMoveAfterAttack
        end
    end
    if not first then self:checkEnd() end
end

function Game:endTurn()
    if self.turn.phase ~= "player" then return end
    if self:anyBusy() then return end
    self:clearSelection()
    self:clearHistory()
    self:beginEnemyTurn()
end

function Game:beginEnemyTurn()
    self.turn.phase = "enemy"
    self.enemyQueue = {}
    for _, e in ipairs(self.entities) do
        if e:isAlive() and e:isEnemy() and e:isCharacter() then table.insert(self.enemyQueue, e) end
    end
    self.enemySub = "move"
    self.enemyCurrent = nil
    self.enemyDelay = 0.15
    -- trains move at the start of the enemy turn
    trains.update(self.grid, self.entities, self:attackCtx())
    self:checkEnd()
end

function Game:updateEnemyTurn(dt)
    if self:anyBusy() then return end
    if self.enemyDelay > 0 then
        self.enemyDelay = self.enemyDelay - dt
        return
    end
    if self.enemySub == "move" then
        -- pick next enemy
        local e = table.remove(self.enemyQueue, 1)
        self.enemyCurrent = e
        if not e or not e:isAlive() or not e:isEnemy() then
            self.enemyCurrent = nil
            return
        end
        local path = ai.planMove(e, self)
        if path and #path > 0 then
            e.hasMovedThisTurn = true
            e:startMove(path)
            self.enemySub = "wait_move"
        else
            self.enemySub = "attack"
        end
    elseif self.enemySub == "wait_move" then
        if not self.enemyCurrent.isMoving then self.enemySub = "attack" end
    elseif self.enemySub == "attack" then
        local e = self.enemyCurrent
        if e and e:isAlive() then
            ai.doAttack(e, self)
            e.hasActedThisTurn = true
        end
        self.enemySub = "move"
        self.enemyCurrent = nil
        self.enemyDelay = 0.08
    elseif self.enemySub == "done" then
        self:endEnemyTurn()
    end
    -- queue exhausted?
    if self.enemySub == "move" and #self.enemyQueue == 0 and not self.enemyCurrent then
        self.enemySub = "done"
    end
end

function Game:endEnemyTurn()
    -- end-of-round ticking
    local ctx = self:attackCtx()
    statuses.tickHexes(self.grid, self.entities, ctx)
    statuses.tickEntities(self.entities, ctx)
    -- dig sites
    local ready = statuses.decrementDigTimers()
    for _, s in ipairs(ready) do self:spawnEnemyAt(s.q, s.r, s.spawn) end
    statuses.ageDigSites()
    -- remove dead
    self:cleanupDead()
    self.turn.count = self.turn.count + 1
    self:startPlayerTurn(false)
    self:checkEnd()
end

function Game:cleanupDead()
    local kept = {}
    for _, e in ipairs(self.entities) do
        if e.isDying and not e.isMoving then
            -- skip (remove)
        else
            table.insert(kept, e)
        end
    end
    self.entities = kept
end

function Game:checkEnd()
    if self.phase ~= "playing" then return end
    local result = objectives.check(self, self.objective)
    if result == "win" then
        self.win = true; self.phase = "gameover"; self:clearSelection()
        if self.progressionRun then self:onMapCleared() end
    elseif result == "lose" then
        self.lose = true; self.phase = "gameover"; self:clearSelection()
    end
end

-- progression hook (overridden by main for menu flow)
function Game:onMapCleared() end
function Game:onStartMap(path) end
function Game:onRestart() end
function Game:onNextMap() end
function Game:onMenu() end
function Game:onProgressionConfirmed() end

-- ======================================================================
-- Update
-- ======================================================================
function Game:update(dt)
    -- animations always advance
    for _, e in ipairs(self.entities) do
        if e.isMoving then e:updateMove(dt, self.grid, self:attackCtx()) end
        if e.pulse then e.pulse = e.pulse + dt * e.pulseSpeed end
        if e.isDying then
            e.deathTimer = e.deathTimer + dt
        end
    end
    -- push anims
    for i = #self.pushAnims, 1, -1 do
        local a = self.pushAnims[i]
        a.t = a.t + dt
        if a.t >= a.dur then table.remove(self.pushAnims, i) end
    end
    -- effects
    for i = #self.effects, 1, -1 do
        local ef = self.effects[i]
        ef.t = ef.t + dt
        if ef.t >= ef.dur then table.remove(self.effects, i) end
    end
    if self.screenShake.t > 0 then self.screenShake.t = math.max(0, self.screenShake.t - dt) end
    if self.messageTimer > 0 then self.messageTimer = self.messageTimer - dt end

    if self.phase ~= "playing" then return end

    if self.turn.phase == "enemy" then
        self:updateEnemyTurn(dt)
    end

    -- hover for deploy
    if self.phase == "deploy" then
        -- handled in input/main
    end
end

-- draw position for an entity (honours active push/move anims)
function Game:entityDrawPos(e)
    for _, a in ipairs(self.pushAnims) do
        if a.entity == e then
            local t = math.min(1, a.t / a.dur)
            return a.fq + (a.tq - a.fq) * t, a.fr + (a.tr - a.fr) * t
        end
    end
    if e.isMoving then return e:drawPos() end
    return e.q, e.r
end

return Game
