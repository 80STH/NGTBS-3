-- src/core/entity.lua
-- Single class for actors, obstacles and buildings.
-- Attacks are stored as ids (resolved through the attacks registry at use time).

local Entity = {}
Entity.__index = Entity

Entity.TYPES = { CHARACTER = "character", OBSTACLE = "obstacle", BUILDING = "building" }
Entity.SIDES = { ALLY = "ally", ENEMY = "enemy", NEUTRAL = "neutral" }

-- Movement types
Entity.MOVE = { WALK = "walk", FLY = "fly", HOVER = "hover", WATER_WALK = "water_walk" }

-- opts is a table from the units registry (see src/content/units.lua).
function Entity.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Entity)
    self.defId    = opts.id or opts.name or "unknown"   -- registry id
    self.name     = opts.name or "Unknown"
    self.type     = opts.type or Entity.TYPES.CHARACTER
    self.side     = opts.side or Entity.SIDES.NEUTRAL
    self.q        = opts.q or 0
    self.r        = opts.r or 0
    self.maxHealth = opts.maxHealth or opts.health or 2
    self.health   = self.maxHealth
    self.moveRange = opts.moveRange or 0
    self.armor    = opts.armor or 0
    self.sprite   = opts.sprite       -- optional love Image (else placeholder by defId)
    self.color    = opts.color or { 0.7, 0.7, 0.7, 1 }

    self.attackIds = opts.attacks or {}     -- list of attack ids
    self.currentAttackIndex = 1

    -- movement & body flags
    self.movement     = opts.movement or Entity.MOVE.WALK
    self.waterWalker  = (self.movement == Entity.MOVE.WATER_WALK) or opts.waterWalker or false
    self.flying       = (self.movement == Entity.MOVE.FLY) or opts.flying or false
    self.hovering     = (self.movement == Entity.MOVE.HOVER) or opts.hovering or false
    self.isPushable   = (opts.isPushable ~= nil) and opts.isPushable or (self.type == Entity.TYPES.CHARACTER)
    self.indestructible = opts.indestructible or false
    self.isHazard     = opts.isHazard or false
    self.maxDamagePerHit = opts.maxDamagePerHit     -- nil = no cap
    self.healthCellSize  = opts.healthCellSize      -- nil = no chunk protection
    self.aura         = opts.aura                   -- { type=, radius= } or nil
    self.isObjective  = opts.isObjective or false
    self.direction    = opts.direction              -- {q=,r=} facing for slopes etc.

    -- trains
    self.isTrainCar   = opts.isTrainCar or false
    self.trainGroupId = opts.trainGroupId or nil

    -- summoning rod
    self.isSummoningRod = opts.isSummoningRod or false
    self.summonCooldown = 0

    -- statuses (per-entity, list of {type=, data=})
    self.statuses = {}

    -- turn flags
    self.hasActedThisTurn  = false
    self.hasMovedThisTurn  = false
    self.canMoveAfterAttack = opts.canMoveAfterAttack or false

    -- progression-granted flags (set by progression module after creation)
    self.upgradeFlags = {}
    self.artifactFlags = {}

    -- animation state
    self.isMoving = false
    self.path = {}
    self.pathIndex = 1
    self.moveTimer = 0
    self.moveSpeed = 6   -- cells per second along path
    self.pulse = math.random() * math.pi * 2
    self.pulseSpeed = 4

    self.isDying = false
    self.deathTimer = 0
    self.deathDuration = 0.35

    return self
end

-- type predicates
function Entity:isCharacter() return self.type == Entity.TYPES.CHARACTER end
function Entity:isObstacle()  return self.type == Entity.TYPES.OBSTACLE end
function Entity:isBuilding()  return self.type == Entity.TYPES.BUILDING end
function Entity:isAlly()  return self.side == Entity.SIDES.ALLY end
function Entity:isEnemy() return self.side == Entity.SIDES.ENEMY end
function Entity:isDestructible() return self:isObstacle() or self:isBuilding() end
function Entity:isAlive() return self.health > 0 and not self.isDying end

-- attacks
function Entity:getCurrentAttackId()
    if #self.attackIds == 0 then return nil end
    return self.attackIds[self.currentAttackIndex]
end

function Entity:switchAttack()
    if #self.attackIds == 0 or self.hasActedThisTurn or self.isMoving then return false end
    self.currentAttackIndex = (self.currentAttackIndex % #self.attackIds) + 1
    return true
end

-- statuses helpers (hex statuses are handled by the statuses module)
function Entity:applyStatus(stype, data)
    for _, s in ipairs(self.statuses) do
        if s.type == stype then return false end
    end
    table.insert(self.statuses, { type = stype, data = data or {} })
    return true
end

function Entity:removeStatus(stype)
    for i, s in ipairs(self.statuses) do
        if s.type == stype then table.remove(self.statuses, i) return true end
    end
    return false
end

function Entity:hasStatus(stype)
    for _, s in ipairs(self.statuses) do if s.type == stype then return true end end
    return false
end

function Entity:getStatus(stype)
    for _, s in ipairs(self.statuses) do if s.type == stype then return s end end
    return nil
end

function Entity:clearStatuses() self.statuses = {} end

-- Apply damage. Returns true if the entity died from this hit.
function Entity:takeDamage(amount, ctx)
    ctx = ctx or {}
    if self.indestructible then return false end
    if self.maxDamagePerHit then amount = math.min(amount, self.maxDamagePerHit) end
    if self.healthCellSize and self.health > self.healthCellSize then
        amount = math.min(amount, self.health - self.healthCellSize)
    end
    if self.armor then amount = math.max(0, amount - self.armor) end
    if amount <= 0 then return false end

    local actual = math.min(amount, self.health)
    self.health = self.health - actual

    -- buildings contribute to chaos
    if ctx and ctx.onChaos and self:isBuilding() and actual > 0 and not self.isTrainCar then
        ctx.onChaos(actual)
    end

    -- acid: any damage is lethal
    if actual > 0 and self:hasStatus("acid") then
        self.health = 0
    end

    return self.health <= 0
end

function Entity:startDeath()
    if self.isDying then return end
    self.isDying = true
    self.deathTimer = 0
    self.health = 0
end

function Entity:setPos(q, r)
    self.q = q; self.r = r
end

-- Begin a stepwise move along `path` (list of {q,r} cells, excluding the current cell).
function Entity:startMove(path)
    if not path or #path == 0 then return end
    self.moveFromQ = self.q
    self.moveFromR = self.r
    self.path = path
    self.pathIndex = 1
    self.moveTimer = 0
    self.isMoving = true
end

function Entity:cancelMove()
    self.isMoving = false
    self.path = {}
    self.pathIndex = 1
    self.moveTimer = 0
end

-- Advance movement. `ctx` provides onChaos / sounds. Returns true while still moving.
function Entity:updateMove(dt, grid, ctx)
    if not self.isMoving then return false end
    self.moveTimer = self.moveTimer + dt * self.moveSpeed
    while self.moveTimer >= 1 and self.isMoving do
        local node = self.path[self.pathIndex]
        self.moveFromQ = self.q
        self.moveFromR = self.r
        self:setPos(node.q, node.r)
        -- terrain on-enter damage
        local ter = grid.terrain and grid.terrain[self.q .. "," .. self.r] or "grass"
        if ctx and ctx.terrainOnEnter then ctx.terrainOnEnter(self, ter) end
        self.moveTimer = self.moveTimer - 1
        self.pathIndex = self.pathIndex + 1
        if self.pathIndex > #self.path then
            self.isMoving = false
            self.moveTimer = 0
            break
        end
    end
    return self.isMoving
end

-- Interpolated draw position (for renderer).
function Entity:drawPos()
    if not self.isMoving or self.pathIndex > #self.path then
        return self.q, self.r
    end
    local node = self.path[self.pathIndex]
    local t = math.min(1, self.moveTimer)
    return self.moveFromQ + (node.q - self.moveFromQ) * t,
           self.moveFromR + (node.r - self.moveFromR) * t
end

return Entity
