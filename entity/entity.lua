-- entity.lua
-- Unified entity for actors and obstacles

local Entity = {}
Entity.__index = Entity
local status = require("system.status")
local log = require("util.log")

-- Entity types
Entity.TYPES = {
    CHARACTER = "character",  -- Playable character
    OBSTACLE = "obstacle",    -- Obstacle (destructible)
    BUILDING = "building",    -- Building (affects global health)
    EDGE = "edge",            -- Map border: absolutely invulnerable, immune to all effects
}

function Entity.new(name, type, q, r, maxHealth, isPlayable, moveRange, sprite, color, attacks)
    local self = setmetatable({}, Entity)
    
    self.name = name or "Unknown"
    self.type = type or Entity.TYPES.CHARACTER
    self.q = q or 0
    self.r = r or 0
    self.maxHealth = maxHealth or 2
    self.health = self.maxHealth
    self.isPlayable = isPlayable or false
    self.moveRange = moveRange or 0
    self.sprite = sprite
    self.color = color or {1, 1, 1, 1}
    
    -- Animation
    self.isMoving = false
    self.path = {}
    self.currentPathIndex = 0
    self.timer = 0
    self.speed = 0.2
    self.pulse = math.random() * math.pi * 2
    self.pulseSpeed = 5
    
    -- Attacks (only for characters)
    self.attacks = attacks or {}
    self.currentAttackIndex = 1
    
    -- Flags
    self.hasActedThisTurn = false
    self.hasMovedThisTurn = false   -- for allies
    self.canMoveAfterAttack = false
    

    
    -- Maximum damage per hit (nil = unlimited)
    self.maxDamagePerHit = nil
    
    -- Can walk on water
    self.waterWalker = false
    
    -- Hovering unit (doesn't sink in water, but considers obstacles)
    self.hovering = false
    -- Teleporting unit (appears anywhere, avoids hazards)
    self.teleporting = false
    -- Health cell size (protection from lethal damage, nil = no protection)
    self.healthCellSize = nil
    
    -- Indestructible entity (ignores all damage)
    self.indestructible = false

    -- Edge entity: map border, absolutely invulnerable, no effects apply
    if type == Entity.TYPES.EDGE then
        self.indestructible = true
    end
    
    -- Hazard zone (doesn't block movement, but kills those who enter)
    self.isHazard = false

    -- Lethal collision: any push into this entity = instant death
    self.lethalCollision = false
    
    -- Entity direction (cubic vector {dx, dy, dz})
    self.direction = nil

    --  IMMOVABILITY: obstacles and buildings cannot be pushed
    self.isPushable = (type == Entity.TYPES.CHARACTER)

    -- Summoning rod
    self.isSummoningRod = false
    self.summonCooldown = 0
    self.summonTargetQ = nil
    self.summonTargetR = nil
    self.summonType = nil
    
    -- Train car flag
    self.isTrainCar = false

    -- Death animation
    self.isDying = false
    self.deathTimer = 0
    self.deathDuration = 0.4   -- duration of fade-out animation

    -- Unit upgrade level (0 = base, 1 = upgraded)
    self.upgradeLevel = 0

    -- Warrior chain: after Dash, Flip is possible (and vice versa)
    self.chainAttack = nil  -- "Dash" or "Flip"
    -- Rogue redirect: after Shoot, can fire again
    self.redirectPending = nil
    
    -- AI target preference (for generated enemies)
    self.targetPreference = nil  -- "buildings" | "units" | "indiscriminate" | nil
    
    return self
end

-- Check if entity is a character
function Entity:isCharacter()
    return self.type == Entity.TYPES.CHARACTER
end

-- Check if entity is an obstacle
function Entity:isObstacle()
    return self.type == Entity.TYPES.OBSTACLE
end

-- Check if entity is a building
function Entity:isBuilding()
    return self.type == Entity.TYPES.BUILDING
end

-- Check if entity is a map edge (border) — invulnerable, effect-immune
function Entity:isEdge()
    return self.type == Entity.TYPES.EDGE
end

-- Can the entity be pushed
function Entity:isPushable()
    return self.isPushable
end

-- Get current attack
function Entity:getCurrentAttack()
    if #self.attacks == 0 then
        return nil
    end
    return self.attacks[self.currentAttackIndex].attack
end

-- Switch attack
function Entity:switchAttack()
    if #self.attacks > 0 and not self.hasActedThisTurn and not self.isMoving then
        self.currentAttackIndex = (self.currentAttackIndex % #self.attacks) + 1
        local attack = self:getCurrentAttack()
        log.debugf("entity", "%s switched to: %s", self.name, attack.name)
        return true
    end
    return false
end

-- Apply damage. ignoreShields kept for API compatibility (no shields left);
-- objective/building damage drains soul power, not any entity's health.
function Entity:takeDamage(damage, ignoreShields)
    if self.indestructible or self:isEdge() then
        return false
    end
    if self.maxDamagePerHit then
        damage = math.min(damage, self.maxDamagePerHit)
    end
    -- Health cell protection: cannot lose more than above the threshold
    if self.healthCellSize and self.health > self.healthCellSize then
        damage = math.min(damage, self.health - self.healthCellSize)
    end
    local actualDamage = math.min(damage, self.health)
    self.health = self.health - actualDamage

    -- Solo hero: a lethal hit is a knockdown, not a death — soul power pays
    -- for the respawn and the hero comes back with 1 HP (see heroDeathSave).
    if self.health <= 0 and _G.soloMode and self.isPlayable and _G.hero == self
        and not self.isDying and not self._trueDeath then
        return _G.heroDeathSave(self)
    end

    if self:isBuilding() and actualDamage > 0 and not self.isTrainCar    and self.name ~= "TunnelEntrance" and self.name ~= "TunnelExit" and self.name ~= "OccupiedTunnel" then
        if _G.soloMode and _G.damageHero then
            _G.damageHero(actualDamage)
        else
            _G.chaos = (_G.chaos or 0) + actualDamage
            log.infof("entity", "Building damaged! Chaos +%d (total: %d)", actualDamage, _G.chaos)
        end
    end

    if self.isTrainCar and actualDamage > 0 then
        if _G.soloMode and _G.damageHero then
            _G.damageHero(actualDamage)
        else
            _G.chaos = (_G.chaos or 0) + actualDamage
            log.infof("entity", "Train car damaged! Chaos +%d (total: %d)", actualDamage, _G.chaos)
        end
    end

    log.debugf("entity", "%s takes %d damage! (%d/%d HP)",
          self.name, actualDamage, math.max(0, self.health), self.maxHealth)

    -- Acid: any damage is lethal (solo hero: knockdown via soul respawn)
    if actualDamage > 0 and status.hasEntityStatus(self, "acid") then
        if self:isCharacter() then
            self.health = 0
        else
            self.health = 0
        end
        if _G.soloMode and self.isPlayable and _G.hero == self then
            return _G.heroDeathSave(self)
        end
        log.infof("entity", "%s dissolves in acid!", self.name)
        return true
    end

    -- Summoning rod: any damage cancels summon for 1 turn
    if self.isSummoningRod then
        self.summonCooldown = 1
        if self.hasPreparedAttack then
            self.hasPreparedAttack = false
            self.preparedAttack = nil
            self.summonTargetQ = nil
            self.summonTargetR = nil
            log.debug("entity", "SummoningRod summon cancelled by damage!")
        end
    end
    
    return self.health <= 0
end

-- Start death animation
function Entity:startDeath()
     if self.isDying then return end
     if self:isEdge() then return end  -- map borders can never die
    -- Solo hero: direct kills that skip takeDamage (pillar crush, etc.) still
    -- go through the death-save. heroDeathSave marks _trueDeath for its own
    -- real-death call so it passes through here exactly once.
    if _G.soloMode and self.isPlayable and _G.hero == self and not self._trueDeath then
        _G.heroDeathSave(self)
        return
    end
    self.isDying = true
    self.deathTimer = 0
    self.health = 0
    -- A dying unit no longer threatens anything: drop its prepared attack so
    -- the order heatmap, threat overlays and preview arrows stop referencing
    -- it the moment it dies (and re-preview cleanly after an undo restores it).
    self.hasPreparedAttack = false
    self.preparedAttack = nil
    self.preparedTargetOffset = nil
    self.preparedTarget = nil
    self.summonTargetQ = nil
    self.summonTargetR = nil
    if self.rootedTarget then
        status.removeFromEntity(self.rootedTarget, "rooted")
        self.rootedTarget = nil
    end
    if not self.isPlayable and self:isCharacter() then
        _G.objective_enemiesKilled = (_G.objective_enemiesKilled or 0) + 1
    end
    if sounds and sounds.death then
        sounds.play("death")
    end
end

-- Get string representation
function Entity:getTypeString()
    if self:isCharacter() then
        return self.isPlayable and "ally" or "enemy"
    elseif self:isEdge() then
        return "edge"
    elseif self:isObstacle() then
        return "obstacle"
    else
        return "building"
    end
end

function Entity:isEnemy()
    return self:isCharacter() and not self.isPlayable
end

function Entity:isAlly()
    return self:isCharacter() and self.isPlayable
end

function Entity:isDestructible()
    if self:isEdge() then return false end
    return self:isObstacle() or self:isBuilding()
end

return Entity
