-- environment.lua
local Entity = require("entity.entity")
local config = require("core.config")
local log = require("util.log")

-- ============================================================
-- CONTENT REGISTRY: attack sets and enemy types.
-- Previously there were 19 get*Attacks() functions + long if/elseif
-- in three places. Now — two tables.
-- ============================================================

-- Each set is a function returning a list of attacks.
-- Combat acts as the factory (require inside to break the combat<->environment cycle).
local ATTACK_SETS = {
    warrior = function()
        local c = require("combat.combat")
        return {
            { attack = c.DashAttack.new(), name = "Dash", description = "Charge forward, pushes enemy" },
            { attack = c.FlipAttack.new(), name = "Flip", description = "Flips enemy behind you" },
        }
    end,
    puncher = function()
        local c = require("combat.combat")
        return {
            { attack = c.HeavyPunchAttack.new(), name = "Heavy Punch", description = "Heavy strike, wounds and pushes. Lethal if empowered" },
            { attack = c.EmpowerPunchAttack.new(), name = "Empower Punch", description = "Pushes target, doubles next attack. Wounds if empowered" },
        }
    end,
    rogue = function()
        local c = require("combat.combat")
        return {
            { attack = c.ShootAttack.new(), name = "Shoot", description = "Shoots and pushes first enemy in line" },
            { attack = c.PiercingShootAttack.new(), name = "Piercing Shot", description = "Pierces first enemy, wounds and pushes the second" },
        }
    end,
    ghost = function()
        local c = require("combat.combat")
        return {
            { attack = c.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, wounds twice" },
        }
    end,
    zombie = function()
        local c = require("combat.combat")
        return {
            { attack = c.ZombieBiteAttack.new(), name = "Bite", description = "Melee bite, wounds thrice" },
        }
    end,
    lich = function()
        local c = require("combat.combat")
        return {
            { attack = c.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any cell, ignores obstacles, wounds" },
        }
    end,
    powerlich = function()
        local c = require("combat.combat")
        return {
            { attack = c.PowerLichBoltAttack.new(), name = "Power Bolt", description = "Lethal bolt: wounds target and 3 cells ahead" },
        }
    end,
    summoner = function()
        local c = require("combat.combat")
        return {
            { attack = c.SummonAttack.new(), name = "Summon", description = "Summons a minion at target cell" },
        }
    end,
    summoned = function()
        local c = require("combat.combat")
        return {
            { attack = c.PushAttack.new(5), name = "Shoot", description = "Pushes first enemy in line, no damage" },
        }
    end,
    divider = function()
        local c = require("combat.combat")
        return {
            { attack = c.DividerAttack.new(), name = "Split", description = "Splits into two Divided units" },
        }
    end,
    brute = function()
        local c = require("combat.combat")
        return {
            { attack = c.BashAttack.new(), name = "Bash", description = "Heavy blow: wounds target and enemy behind attacker" },
        }
    end,
    dervish = function()
        local c = require("combat.combat")
        return {
            { attack = c.CleaveAttack.new(), name = "Cleave", description = "Wide swing: wounds up to 3 targets in front" },
        }
    end,
    raider = function()
        local c = require("combat.combat")
        return {
            { attack = c.LungeAttack.new(), name = "Lunge", description = "Lunge: wounds target and enemy behind it" },
        }
    end,
    crusher = function()
        local c = require("combat.combat")
        return {
            { attack = c.BashAttack.new(), name = "Bash", description = "Heavy blow: wounds target and enemy behind attacker" },
        }
    end,
    lancer = function()
        local c = require("combat.combat")
        return {
            { attack = c.LungeAttack.new(), name = "Lunge", description = "Lunge: wounds target and enemy behind it" },
        }
    end,
    bogshaman = function()
        local c = require("combat.combat")
        return {
            { attack = c.ZombieBiteAttack.new(), name = "Bite", description = "Melee bite, wounds thrice" },
        }
    end,
    summoningrod = function()
        local c = require("combat.combat")
        return {
            { attack = c.SummonEnemyAttack.new(), name = "Summon", description = "Summons a random enemy" },
        }
    end,
    vortex = function()
        local c = require("combat.combat")
        return {
            { attack = c.VortexStrikeAttack.new(), name = "Vortex Strike", description = "Shifts an enemy left or right and wounds" },
            { attack = c.WideVortexAttack.new(), name = "Wide Vortex", description = "Shifts 3 enemies in front left or right" },
        }
    end,
    hooks = function()
        local c = require("combat.combat")
        return {
            { attack = c.PullHookAttack.new(), name = "Pull Hook", description = "Hooks target and pulls it toward you" },
            { attack = c.ElectricHookAttack.new(), name = "Electric Hook", description = "Arc lightning, wounds everyone on the line" },
        }
    end,
    area = function()
        local c = require("combat.combat")
        return {
            { attack = c.AoePushAttack.new(), name = "Stone Throw", description = "Hurls stone at adjacent cell, pushes enemies in a cone" },
            { attack = c.AoeDirectionalAttack.new(), name = "Cone Blast", description = "Pushes 3 enemies in front away from attacker" },
        }
    end,
    none = function()
        return {}
    end,
    all = function()
        local c = require("combat.combat")
        return {
            { attack = c.DashAttack.new(), name = "Dash", description = "Charge forward, pushes enemy" },
            { attack = c.FlipAttack.new(), name = "Flip", description = "Flips enemy behind you" },
            { attack = c.ShootAttack.new(), name = "Shoot", description = "Shoots and pushes first enemy in line" },
            { attack = c.PushAttack.new(5), name = "Push", description = "Pushes first enemy in line, no damage" },
            { attack = c.PiercingShootAttack.new(), name = "Piercing Shot", description = "Pierces first enemy, wounds and pushes the second" },
            { attack = c.AoePushAttack.new(), name = "Stone Throw", description = "Hurls stone at adjacent cell, pushes enemies in a cone" },
            { attack = c.AoeDirectionalAttack.new(), name = "Cone Blast", description = "Pushes 3 enemies in front away from attacker" },
            { attack = c.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any cell, ignores obstacles, wounds" },
            { attack = c.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, wounds twice" },
            { attack = c.ZombieBiteAttack.new(), name = "Bite", description = "Melee bite, wounds thrice" },
            { attack = c.SummonAttack.new(), name = "Summon", description = "Summons a minion at target cell" },
            { attack = c.DividerAttack.new(), name = "Split", description = "Splits into two Divided units" },
            { attack = c.VortexStrikeAttack.new(), name = "Vortex Strike", description = "Shifts an enemy left or right and wounds" },
            { attack = c.WideVortexAttack.new(), name = "Wide Vortex", description = "Shifts 3 enemies in front left or right" },
            { attack = c.PullHookAttack.new(), name = "Pull Hook", description = "Hooks target and pulls it toward you" },
            { attack = c.ElectricHookAttack.new(), name = "Electric Hook", description = "Arc lightning, wounds everyone on the line" },
            { attack = c.BashAttack.new(), name = "Bash", description = "Heavy blow: wounds target and enemy behind attacker" },
            { attack = c.CleaveAttack.new(), name = "Cleave", description = "Wide swing: wounds up to 3 targets in front" },
            { attack = c.LungeAttack.new(), name = "Lunge", description = "Lunge: wounds target and enemy behind it" },
            { attack = c.HeavyPunchAttack.new(), name = "Heavy Punch", description = "Heavy strike, wounds and pushes. Lethal if empowered" },
            { attack = c.EmpowerPunchAttack.new(), name = "Empower Punch", description = "Pushes target, doubles next attack. Wounds if empowered" },
        }
    end,
}

-- Enemy type registry: name -> specification.
-- Used in createEnemyByType. Supplements ATTACK_SETS
-- with data about health/moveRange/aura/flags.
local ENEMY_TYPES = {
    Ghost           = { attackSet = "ghost",       moveRange = 3, flying = true },
    Zombie          = { attackSet = "zombie",      moveRange = 3 },
    PoisonousZombie = { attackSet = "zombie",      moveRange = 3 },
    Lich            = { attackSet = "lich",        moveRange = 3 },
    Brute           = { attackSet = "brute",       moveRange = 2 },
    Lancer          = { attackSet = "lancer",      moveRange = 3 },
    BogShaman       = { attackSet = "bogshaman",   moveRange = 2, aura = { type = "slow", radius = 1 } },
    Raider          = { attackSet = "raider",      moveRange = 3 },
    Dervish         = { attackSet = "dervish",     moveRange = 3 },
    Crusher         = { attackSet = "crusher",     moveRange = 2 },
    PowerLich       = { attackSet = "powerlich",   moveRange = 3, maxHealth = 6, hovering = true, healthCellSize = 3 },
    SummoningRod    = { attackSet = "summoningrod",moveRange = 0, isSummoningRod = true, isPushable = false },
}

local environment = {}

local gidToEntity = {
    [34] = { type = "character", name = "Warrior", isPlayable = true,  maxHealth = 2, moveRange = 3, attacks = "warrior" },
    [30] = { type = "character", name = "Puncher",  isPlayable = true,  maxHealth = 2, moveRange = 4, attacks = "puncher" },
    [31] = { type = "character", name = "Rogue",   isPlayable = true,  maxHealth = 2, moveRange = 5, attacks = "rogue" },
    [26] = { type = "character", name = "Ghost",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "ghost" },
    [25] = { type = "character", name = "Zombie",  isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "zombie" },
    [21] = { type = "character", name = "PoisonousZombie", isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "zombie" },
    [27] = { type = "character", name = "Lich",    isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "lich" },
    [40] = { type = "character", name = "Summoner", isPlayable = true,  maxHealth = 2, moveRange = 3, attacks = "summoner" },
    [42] = { type = "character", name = "Summoned", isPlayable = true,  maxHealth = 2, moveRange = 2, attacks = "summoned" },
    [44] = { type = "character", name = "Divided",  isPlayable = true,  maxHealth = 2, moveRange = 3, attacks = "none" },
    [45] = { type = "character", name = "Divider",  isPlayable = true,  maxHealth = 2, moveRange = 4, attacks = "divider" },
    [68] = { type = "character", name = "AttackTest", isPlayable = true, maxHealth = 2, moveRange = 6, attacks = "all" },
    [11] = { type = "obstacle",  name = "SuperMountain", indestructible = true },
    [9]  = { type = "obstacle",  name = "MountainSlope", health = 2, maxDamagePerHit = 1, direction = {dx = 1, dy = 0, dz = -1} },
    [15] = { type = "obstacle",  name = "MountainSlope", indestructible = true, noCollisionDamage = true },
    [16] = { type = "obstacle",  name = "SuperMountainSlope", indestructible = true, noCollisionDamage = true },
    [5]  = { type = "obstacle",  name = "SharpReefs", indestructible = true, lethalCollision = true },
    [12] = { type = "building",  name = "SmallBuilding", health = 1 },
    [7] = { type = "building",  name = "BigBuilding",   health = 2 },
    [6] = { type = "obstacle",  name = "WeakMountain",  health = 2, maxDamagePerHit = 1 },

    [29] = { type = "building", name = "Tower",         health = 1, isObjective = true },
    [60] = { type = "character", name = "Brute",    isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "brute" },
    [62] = { type = "character", name = "Lancer",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "lancer" },
    [80] = { type = "character", name = "BogShaman", isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "bogshaman" },
    [23] = { type = "character", name = "Raider",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "raider" },
    [28] = { type = "character", name = "Dervish",  isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "dervish" },
    [66] = { type = "character", name = "Crusher",  isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "crusher" },
    [83] = { type = "character", name = "SummoningRod", isPlayable = false, maxHealth = 2, moveRange = 0, attacks = "summoningrod" },
    [48] = { type = "building",  name = "Caravan",   health = 1, moveRange = 1 },
    [77] = { type = "building",  name = "Blockpost", health = 2 },
    [67] = { type = "building",  name = "TunnelEntrance", health = 2, isObjective = true },
    [68] = { type = "building",  name = "TunnelExit",     health = 2, isObjective = true },
    [74] = { type = "building",  name = "TrainCar",  health = 1, moveRange = 1 },
    [84] = { type = "building",  name = "MountainHouse", health = 2 },
    [85] = { type = "building",  name = "SmallMountainHouse", health = 1 },
}

environment.enemySpriteCache = {}

-- Generation of custom sprites for mountains and buildings
local function generateCustomSprite(name, w, h)
    local canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    if name == "SuperMountain" then
        love.graphics.setColor(0.45, 0.4, 0.35)
        love.graphics.polygon("fill", 0, h, w/2, 0, w, h)
        love.graphics.setColor(0.55, 0.5, 0.45)
        love.graphics.polygon("fill", 0, h, w/2, 0, w/2, h)
        love.graphics.setColor(0.95, 0.95, 1)
        love.graphics.polygon("fill", w/2-2, 0, w/2+2, 0, w/2+1, 3, w/2-2, 3)
        love.graphics.polygon("fill", w/2-1, 1, w/2+1, 1, w/2, 3)
        love.graphics.setColor(0.3, 0.25, 0.2)
        love.graphics.rectangle("fill", 0, h-2, w, 2)

    elseif name == "WeakMountain" then
        love.graphics.setColor(0.5, 0.45, 0.35)
        love.graphics.polygon("fill", 0, h, w/2, 0, w, h)
        love.graphics.setColor(0.6, 0.55, 0.45)
        love.graphics.polygon("fill", 0, h, w/2, 0, w/2, h)
        love.graphics.setColor(0.35, 0.3, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.5, 0.45, 0.35)

    elseif name == "SmallBuilding" then
        love.graphics.setColor(0.7, 0.55, 0.35)
        love.graphics.rectangle("fill", 1, 4, w-2, h-4)
        love.graphics.setColor(0.6, 0.25, 0.15)
        love.graphics.polygon("fill", 0, 4, w/2, 1, w, 4)
        love.graphics.setColor(0.4, 0.25, 0.15)
        love.graphics.rectangle("fill", w/2-2, h-4, 4, 4)
        love.graphics.setColor(0.85, 0.9, 1)
        love.graphics.rectangle("fill", 2, 6, 3, 3)

    elseif name == "BigBuilding" then
        love.graphics.setColor(0.5, 0.55, 0.6)
        love.graphics.rectangle("fill", 0, 2, w, h-2)
        love.graphics.setColor(0.4, 0.45, 0.5)
        love.graphics.rectangle("fill", 0, 0, w, 3)
        love.graphics.setColor(0.8, 0.85, 1)
        for row = 0, 1 do
            for col = 0, 2 do
                love.graphics.rectangle("fill", 2 + col * 4, 5 + row * 5, 2, 3)
            end
        end

    elseif name == "Tower" then
        love.graphics.setColor(0.55, 0.5, 0.45)
        love.graphics.rectangle("fill", w/4, 2, w/2, h-2)
        love.graphics.setColor(0.45, 0.4, 0.35)
        love.graphics.rectangle("fill", w/4-1, 2, w/2+2, 3)
        love.graphics.setColor(0.6, 0.55, 0.5)
        love.graphics.rectangle("fill", w/4-2, 0, w/2+4, 3)
        love.graphics.setColor(0.8, 0.75, 0.65)
        love.graphics.polygon("fill", w/4, h-4, w/2, h-1, w*3/4, h-4)
        love.graphics.setColor(1, 0.7, 0.3)
        love.graphics.circle("fill", w/2, h/2, 2)
    elseif name == "Caravan" then
        love.graphics.setColor(0.5, 0.3, 0.15)
        love.graphics.rectangle("fill", 1, 3, w-2, h-5)
        love.graphics.setColor(0.6, 0.4, 0.2)
        love.graphics.rectangle("fill", 2, 2, w-4, 2)
        love.graphics.setColor(0.8, 0.7, 0.5)
        love.graphics.rectangle("fill", 3, 4, 4, 4)
        love.graphics.setColor(0.3, 0.2, 0.1)
        love.graphics.circle("fill", 3, h-1, 1)
        love.graphics.circle("fill", w-3, h-1, 1)

    elseif name == "OccupiedTunnel" then
        love.graphics.setColor(0.2, 0.1, 0.1)
        love.graphics.rectangle("fill", 0, 0, w, h-2)
        love.graphics.setColor(0.5, 0.2, 0.1)
        love.graphics.rectangle("fill", w/2-3, 0, 6, h-4)
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.6, 0.3, 0.15)
        love.graphics.arc("fill", w/2, h-2, w/3, math.pi, 0)
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.circle("fill", w/2, h/2-1, 2)

    elseif name == "Blockpost" then
        love.graphics.setColor(0.4, 0.3, 0.2)
        love.graphics.rectangle("fill", 0, 3, w, h-3)
        love.graphics.setColor(0.55, 0.45, 0.3)
        love.graphics.rectangle("fill", 0, 3, 2, h-3)
        love.graphics.rectangle("fill", w-2, 3, 2, h-3)
        love.graphics.setColor(0.6, 0.5, 0.35)
        love.graphics.rectangle("fill", 2, 0, w-4, 4)
        love.graphics.setColor(0.5, 0.4, 0.25)
        love.graphics.rectangle("fill", w/2-3, 0, 6, h)

    elseif name == "TunnelEntrance" then
        love.graphics.setColor(0.15, 0.15, 0.15)
        love.graphics.rectangle("fill", 0, 0, w, h-2)
        love.graphics.setColor(0.6, 0.55, 0.5)
        love.graphics.rectangle("fill", w/2-1, 0, 2, h-2)
        love.graphics.setColor(0.25, 0.25, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.arc("fill", w/2, h-2, w/3, math.pi, 0)
        love.graphics.setColor(0.2, 1, 0.2)
        love.graphics.polygon("fill", w/2, 2, w/2-3, 6, w/2+3, 6)

    elseif name == "TunnelExit" then
        love.graphics.setColor(0.15, 0.15, 0.15)
        love.graphics.rectangle("fill", 0, 0, w, h-2)
        love.graphics.setColor(0.6, 0.55, 0.5)
        love.graphics.rectangle("fill", w/2-1, 0, 2, h-2)
        love.graphics.setColor(0.25, 0.25, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.arc("fill", w/2, h-2, w/3, math.pi, 0)
        love.graphics.setColor(1, 0.2, 0.2)
        love.graphics.polygon("fill", w/2, 6, w/2-3, 2, w/2+3, 2)

    elseif name == "DestroyedTunnel" then
        love.graphics.setColor(0.25, 0.22, 0.2)
        love.graphics.rectangle("fill", w/4, h/2-1, w/2, 3)
        love.graphics.setColor(0.35, 0.28, 0.22)
        love.graphics.rectangle("fill", w/3, h/2-4, w/3, 2)
        love.graphics.rectangle("fill", w/4+1, h/2+3, w/2-2, 2)
        love.graphics.setColor(0.2, 0.18, 0.18)
        love.graphics.rectangle("fill", w/3+1, h/2-2, 2, 6)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.rectangle("fill", w/3-2, h/2-2, 2, 3)

    elseif name == "MountainHouse" then
        love.graphics.setColor(0.5, 0.45, 0.35)
        love.graphics.polygon("fill", 0, h, w/2, h*0.25, w, h)
        love.graphics.setColor(0.6, 0.55, 0.45)
        love.graphics.polygon("fill", 0, h, w/2, h*0.25, w/2, h)
        love.graphics.setColor(0.7, 0.5, 0.3)
        love.graphics.rectangle("fill", w/2-4, h*0.25-2, 8, h*0.55)
        love.graphics.setColor(0.6, 0.25, 0.15)
        love.graphics.polygon("fill", w/2-5, h*0.25-2, w/2, h*0.25-7, w/2+5, h*0.25-2)
        love.graphics.setColor(0.85, 0.9, 1)
        love.graphics.rectangle("fill", w/2-1, h*0.45, 2, 4)
        love.graphics.setColor(0.35, 0.3, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)

    elseif name == "SmallMountainHouse" then
        love.graphics.setColor(0.55, 0.5, 0.4)
        love.graphics.polygon("fill", 0, h, w/2, h*0.3, w, h)
        love.graphics.setColor(0.65, 0.6, 0.5)
        love.graphics.polygon("fill", 0, h, w/2, h*0.3, w/2, h)
        love.graphics.setColor(0.75, 0.55, 0.35)
        love.graphics.rectangle("fill", w/2-3, h*0.3-1, 6, h*0.4)
        love.graphics.setColor(0.6, 0.25, 0.15)
        love.graphics.polygon("fill", w/2-4, h*0.3-1, w/2, h*0.3-5, w/2+4, h*0.3-1)
        love.graphics.setColor(0.85, 0.9, 1)
        love.graphics.rectangle("fill", w/2-1, h*0.45, 2, 3)
        love.graphics.setColor(0.35, 0.3, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)

    elseif name == "RuinedMountainHouse" then
        love.graphics.setColor(0.35, 0.3, 0.25)
        love.graphics.polygon("fill", 0, h, w/2, h*0.25, w, h)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.polygon("fill", 0, h, w/2, h*0.25, w/2, h)
        love.graphics.setColor(0.5, 0.35, 0.2)
        love.graphics.rectangle("fill", w/2-3, h*0.25, 2, h*0.35)
        love.graphics.rectangle("fill", w/2+1, h*0.25, 2, h*0.25)
        love.graphics.setColor(0.3, 0.25, 0.2)
        love.graphics.rectangle("fill", w/2-4, h*0.65, 3, 2)
        love.graphics.rectangle("fill", w/2+1, h*0.55, 2, 2)
        love.graphics.setColor(0.35, 0.3, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)

    elseif name == "Locomotive" then
        love.graphics.setColor(0.3, 0.15, 0.1)
        love.graphics.rectangle("fill", 1, 1, w-2, h-4)
        love.graphics.setColor(0.5, 0.2, 0.1)
        love.graphics.rectangle("fill", 1, 1, w-2, h-6)
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.rectangle("fill", w/2-3, 2, 6, 4)
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", 2, 6, w-4, 2)
        love.graphics.setColor(0.3, 0.1, 0.05)
        love.graphics.circle("fill", 2, h-1, 1.5)
        love.graphics.circle("fill", w-2, h-1, 1.5)

    elseif name == "TrainCar" then
        love.graphics.setColor(0.6, 0.2, 0.15)
        love.graphics.rectangle("fill", 1, 2, w-2, h-5)
        love.graphics.setColor(0.4, 0.12, 0.08)
        love.graphics.rectangle("fill", 0, 2, w, 2)
        love.graphics.setColor(0.8, 0.6, 0.4)
        love.graphics.rectangle("fill", 3, 3, 2, 3)
        love.graphics.rectangle("fill", w-5, 3, 2, 3)
        love.graphics.setColor(0.3, 0.1, 0.05)
        love.graphics.circle("fill", 2, h-1, 1.5)
        love.graphics.circle("fill", w-2, h-1, 1.5)

    elseif name == "MountainSlope" then
        love.graphics.setColor(0.55, 0.5, 0.45)
        love.graphics.polygon("fill", 0, h, w*0.6, h*0.2, w, h)
        love.graphics.setColor(0.65, 0.6, 0.55)
        love.graphics.polygon("fill", 0, h, w*0.6, h*0.2, w*0.6, h)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.rectangle("fill", 0, h-2, w, 2)

    elseif name == "SuperMountainSlope" then
        love.graphics.setColor(0.45, 0.42, 0.38)
        love.graphics.polygon("fill", 0, h, w*0.55, 0, w, h)
        love.graphics.setColor(0.55, 0.52, 0.48)
        love.graphics.polygon("fill", 0, h, w*0.55, 0, w*0.55, h)
        love.graphics.setColor(0.95, 0.95, 1)
        love.graphics.polygon("fill", w*0.55-1, 0, w*0.55+1, 0, w*0.55, 2)
        love.graphics.setColor(0.3, 0.25, 0.2)
        love.graphics.rectangle("fill", 0, h-2, w, 2)

    elseif name == "SharpReefs" then
        love.graphics.setColor(0.3, 0.45, 0.55)
        love.graphics.rectangle("fill", 0, h-3, w, 3)
        love.graphics.setColor(0.45, 0.55, 0.65)
        love.graphics.polygon("fill", w*0.5, 1, w*0.1, h-1, w*0.3, h-1)
        love.graphics.polygon("fill", w*0.7, 2, w*0.5, h-1, w*0.9, h-1)
        love.graphics.setColor(0.35, 0.5, 0.6)
        love.graphics.polygon("fill", w*0.2, 3, 0, h-1, w*0.15, h-1)
        love.graphics.polygon("fill", w*0.85, 2, w*0.75, h-1, w, h-1)
        love.graphics.setColor(0.55, 0.65, 0.75)
        love.graphics.polygon("fill", w*0.6, 0, w*0.45, h-2, w*0.75, h-2)
    end

    love.graphics.setCanvas()
    return canvas
end

-- Creating entity with texture from tileset
-- ============================================================
-- Native map loader (for in-game editor maps)
-- ============================================================

-- Build name -> entity def lookup
local nameToEntityDef = {}
for gid, def in pairs(gidToEntity) do
    if not nameToEntityDef[def.name] then
        nameToEntityDef[def.name] = def
    end
end

function environment.loadNativeMap(data)
    log.infof("env", "=== LOADING NATIVE MAP ===")

    local width = data.width or 11
    local height = data.height or 11
    local activeRadius = data.activeRadius or 5
    local centerQ = data.centerQ or 5
    local centerR = data.centerR or 5
    local orientation = data.orientation or "flat"

    local hex_utils = require("grid.hex_utils")
    hex_utils.setOrientation(orientation)

    local terrainMap = {}
    local entities = {}

    local tempHex = require("grid.hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        activeRadius,
        centerQ, centerR,
        orientation
    )

    -- Load terrain
    if data.terrain then
        for key, terrainType in pairs(data.terrain) do
            local q, r = key:match("^(%d+),(%d+)$")
            if q and r then
                q, r = tonumber(q), tonumber(r)
                if tempHex:isActiveHex(q, r) then
                    if not terrainMap[q] then terrainMap[q] = {} end
                    terrainMap[q][r] = terrainType
                end
            end
        end
    end

    -- Load upper terrain (visual debris layer)
    local upperTerrainMap = {}
    if data.upper_terrain then
        for key, value in pairs(data.upper_terrain) do
            local q, r = key:match("^(%d+),(%d+)$")
            if q and r then
                q, r = tonumber(q), tonumber(r)
                if tempHex:isActiveHex(q, r) then
                    if not upperTerrainMap[q] then upperTerrainMap[q] = {} end
                    upperTerrainMap[q][r] = value
                end
            end
        end
    end

    -- Load entities
    if data.entities then
        for key, entityDataVal in pairs(data.entities) do
            local q, r = key:match("^(%d+),(%d+)$")
            if q and r then
                q, r = tonumber(q), tonumber(r)
                if tempHex:isActiveHex(q, r) then
                    local entityName, entityDir = nil, nil
                    if type(entityDataVal) == "table" then
                        entityName = entityDataVal.name or entityDataVal[1]
                        if entityDataVal.dir ~= nil then
                            local dirs = hex_utils.CUBE_DIRECTIONS
                            entityDir = dirs[entityDataVal.dir]
                        elseif entityDataVal.direction then
                            entityDir = entityDataVal.direction
                        end
                    else
                        entityName = entityDataVal
                    end
                    local def = nameToEntityDef[entityName]
                    if def then
                        local entity = nil
                        if def.type == "character" then
                            local attacks = environment.getAttacks(def.attacks)
                            entity = Entity.new(
                                def.name, Entity.TYPES.CHARACTER, q, r,
                                def.maxHealth, def.isPlayable, def.moveRange,
                                nil, nil, attacks
                            )
                            if def.name == "SummoningRod" then
                                entity.isSummoningRod = true
                                entity.isPushable = false
                                entity.moveRange = 0
                            end
                            if def.name == "Ghost" then
                                entity.flying = true
                            end
                            if def.attacks == "bogshaman" then
                                entity.aura = { type = "slow", radius = 1 }
                            end
                        elseif def.type == "obstacle" then
                            local health = def.health or 1
                            entity = Entity.new(def.name, Entity.TYPES.OBSTACLE, q, r, health, false, 0, nil, nil, {})
                            if def.maxDamagePerHit then entity.maxDamagePerHit = def.maxDamagePerHit end
                            if def.indestructible then entity.indestructible = true end
                            if def.noCollisionDamage then entity.noCollisionDamage = true end
                            if def.isHazard then entity.isHazard = true end
                            if def.lethalCollision then entity.lethalCollision = true end
                            if entityDir then
                                entity.direction = { dx = entityDir.dx, dy = entityDir.dy, dz = entityDir.dz }
                            elseif def.direction then
                                entity.direction = { dx = def.direction.dx, dy = def.direction.dy, dz = def.direction.dz }
                            end
                        elseif def.type == "building" then
                            entity = Entity.new(def.name, Entity.TYPES.BUILDING, q, r, def.health, false, (def.moveRange or 0), nil, nil, {})
                            if def.waterWalker then entity.waterWalker = true end
                            if def.isObjective then entity.isObjective = true end
                        end

                        if entity then
                            if def.name == "Caravan" then
                                entity.isPushable = true
                            end
                            -- Generate sprite: custom for buildings/obstacles, colored circle for characters
                            local spriteSize = 16
                            local canvas = nil
                            if def.type == "building" or def.type == "obstacle" then
                                canvas = generateCustomSprite(def.name, 12, 12)
                            end
                            if not canvas then
                                canvas = love.graphics.newCanvas(spriteSize, spriteSize)
                                love.graphics.setCanvas(canvas)
                                love.graphics.clear(0, 0, 0, 0)
                                if def.isPlayable ~= nil then
                                    love.graphics.setColor(def.isPlayable and {0.2, 0.6, 0.2, 1} or {0.8, 0.2, 0.2, 1})
                                else
                                    love.graphics.setColor(0.5, 0.5, 0.5, 1)
                                end
                                love.graphics.circle("fill", spriteSize / 2, spriteSize / 2, spriteSize / 2 - 1)
                                love.graphics.setCanvas()
                            end
                            entity.sprite = canvas

                            table.insert(entities, entity)
                            log.debugf("env", "Created %s at (%d,%d)", entity.name, q, r)
                        end
                    end
                end
            end
        end
    end

    -- Load hex statuses
    local hexStatuses = {}
    if data.statuses then
        for key, val in pairs(data.statuses) do
            local q, r = key:match("^(%d+),(%d+)$")
            if q and r then
                q, r = tonumber(q), tonumber(r)
                if tempHex:isActiveHex(q, r) then
                    if type(val) == "table" then
                        hexStatuses[key] = val
                    elseif type(val) == "string" then
                        hexStatuses[key] = { val }
                    end
                end
            end
        end
    end

    -- Separate playable characters for deployment phase
    local deployableAllies = {}
    local gameEntities = {}
    for _, entity in ipairs(entities) do
        if entity.isPlayable and entity:isCharacter() then
            table.insert(deployableAllies, entity)
        else
            table.insert(gameEntities, entity)
        end
    end

    -- No terrain textures for native maps (procedural rendering)
    environment.loadedMap = nil
    environment.terrainTextures = nil

    log.infof("env", "Native map loaded: %dx%d, radius=%d", width, height, activeRadius)
    log.infof("env", "Entities: %d, Allies: %d", #gameEntities, #deployableAllies)

    return terrainMap, gameEntities, width, height, hexStatuses, {}, deployableAllies, orientation, upperTerrainMap
end

-- ============================================================
-- Attack registry access API
-- ============================================================

-- Returns attack list by set identifier ("warrior", "lich", ...).
-- Replaces 19 old getXxxAttacks() functions.
-- Returns empty list for unknown setId.
function environment.getAttacks(setId)
    local factory = setId and ATTACK_SETS[setId]
    if not factory then return {} end
    return factory()
end

-- Backward-compat: thin wrappers for those calling get*Attacks() by name.
-- (for external calls; no longer used in the project itself)
function environment.getWarriorAttacks()      return environment.getAttacks("warrior") end
function environment.getPuncherAttacks()      return environment.getAttacks("puncher") end
function environment.getRogueAttacks()        return environment.getAttacks("rogue") end
function environment.getGhostAttacks()        return environment.getAttacks("ghost") end
function environment.getZombieAttacks()       return environment.getAttacks("zombie") end
function environment.getLichAttacks()         return environment.getAttacks("lich") end
function environment.getNoneAttacks()         return environment.getAttacks("none") end
function environment.getAllAttacks()          return environment.getAttacks("all") end
function environment.getDividerAttacks()      return environment.getAttacks("divider") end
function environment.getSummonerAttacks()     return environment.getAttacks("summoner") end
function environment.getBruteAttacks()        return environment.getAttacks("brute") end
function environment.getDervishAttacks()      return environment.getAttacks("dervish") end
function environment.getRaiderAttacks()       return environment.getAttacks("raider") end
function environment.getCrusherAttacks()      return environment.getAttacks("crusher") end
function environment.getSummoningRodAttacks() return environment.getAttacks("summoningrod") end
function environment.getPowerLichAttacks()    return environment.getAttacks("powerlich") end
function environment.getLancerAttacks()       return environment.getAttacks("lancer") end
function environment.getBogShamanAttacks()    return environment.getAttacks("bogshaman") end
function environment.getSummonedAttacks()     return environment.getAttacks("summoned") end

-- Sprite cache: source of truth is the sprites module (to break the combat<->environment cycle).
-- environment.unitSpriteCache kept as alias for backward compatibility.
local sprites = require("util.sprites")
local unitSpriteCache = sprites.raw()
environment.unitSpriteCache = unitSpriteCache

function environment.loadUnitSprites()
    local imgPath = "maps/entities.png"
    local imgInfo = love.filesystem.getInfo(imgPath)
    if not imgInfo then
        log.info("env", "No entities.png found, squad units will use fallback colors")
        return
    end
    local img = love.graphics.newImage(imgPath)
    local tw, th = 16, 16
    local cols = 9
    local tileCount = 72
    local firstGid = 21

    log.debug("env", "=== Loading entity sprites from entities.png ===")
    for i = 0, tileCount - 1 do
        local gid = firstGid + i
        local col = i % cols
        local row = math.floor(i / cols)
        local quad = love.graphics.newQuad(col * tw, row * th, tw, th, img:getWidth(), img:getHeight())
        local canvas = love.graphics.newCanvas(tw, th)
        canvas:setFilter("nearest", "nearest")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, quad, 0, 0)
        love.graphics.setCanvas()
        sprites.set(gid, canvas)
        local def = gidToEntity[gid]
        local name = def and def.name or "nil"
        log.debugf("env", "  [OK]   GID %3d -> %-20s", gid, name)
    end
end

function environment.createSquadUnit(unitDef, q, r)
    local attacks = environment.getAttacks(unitDef.attacks)

    local nameToGid = {
        Warrior = 34, Puncher = 30, Rogue = 31,
        Summoner = 40, Divider = 45, Summoned = 42, Divided = 44,
        AttackTest = 68,
    }
    local gid = nameToGid[unitDef.name]
    local sprite = gid and unitSpriteCache[gid] or nil

    local colors = {
        Warrior = {0.8, 0.3, 0.2},
        Puncher = {0.2, 0.8, 0.3},
        Rogue = {0.2, 0.5, 0.8},
        Summoner = {0.8, 0.2, 0.8},
        Divider = {0.9, 0.7, 0.1},
        Summoned = {0.6, 0.3, 0.9},
        Divided = {0.6, 0.4, 0.1},
        AttackTest = {0.2, 0.9, 0.9},
    }

    local entity = Entity.new(
        unitDef.name, Entity.TYPES.CHARACTER, q, r,
        unitDef.maxHealth, true, unitDef.moveRange,
        sprite, sprite and nil or (colors[unitDef.name] or {0.5, 0.5, 0.5}),
        attacks
    )

    -- Apply shop buffs: squad HP/Move bonuses
    local hpBonus = _G.squadHpBonus or 0
    local moveBonus = _G.squadMoveBonus or 0
    if hpBonus > 0 then
        entity.maxHealth = entity.maxHealth + hpBonus
        entity.health = entity.maxHealth
    end
    if moveBonus > 0 then
        entity.moveRange = entity.moveRange + moveBonus
    end

    -- Apply progression upgrades (choice-based)
    local upgradeData = _G.unitUpgrades and _G.unitUpgrades[unitDef.name] or { choices = {} }
    entity.upgradeLevel = #upgradeData.choices

    for _, choiceId in ipairs(upgradeData.choices) do
        if choiceId == "dashToFlipChain" then entity.dashToFlipChain = true end
        if choiceId == "flipToDashChain" then entity.flipToDashChain = true end
        if choiceId == "empowerAtStart" then entity.empowerAtStart = true end
        if choiceId == "choosePushDir" then entity.choosePushDir = true end
        if choiceId == "redirectShot" then entity.redirectShot = true end
        if choiceId == "pointBlankLethal" then entity.pointBlankLethal = true end
    end

    -- Apply artifacts (global bonuses)
    local artifactList = _G.artifacts or {}
    for _, artId in ipairs(artifactList) do
        if artId == "rootImmune" then entity.rootImmune = true end
        if artId == "deployAnywhere" then entity.deployAnywhere = true end
        if artId == "armor" then entity.armor = 1 end
        if artId == "moveSpeed" then entity.moveRange = entity.moveRange + 1 end
        if artId == "canMoveAfterAttack" then entity.canMoveAfterAttack = true end
        if artId == "phaseThroughEnemies" then entity.phaseThroughEnemies = true end
    end

    return entity
end

function environment.createEnemyByType(enemyType, q, r)
    -- Specification from registry; fallback — Zombie.
    local spec = ENEMY_TYPES[enemyType] or ENEMY_TYPES.Zombie
    local name = (ENEMY_TYPES[enemyType] and enemyType) or "Zombie"
    local attacks = environment.getAttacks(spec.attackSet)
    local maxHealth = spec.maxHealth or 2
    local moveRange = spec.moveRange or 2
    local hasAura = spec.aura

    local enemyTypeToGid = {
        Ghost = 26, Zombie = 25, PoisonousZombie = 21, Lich = 27,
        Brute = 60, Lancer = 62, BogShaman = 80,
        Raider = 23, Dervish = 28, Crusher = 66,
        SummoningRod = 83,
    }
    local gid = enemyTypeToGid[enemyType]
    local sprite = gid and environment.unitSpriteCache[gid]
    if not sprite then
        local size = 16
        local canvas = love.graphics.newCanvas(size, size)
        canvas:setFilter("nearest", "nearest")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        if enemyType == "SummoningRod" then
            love.graphics.setColor(0.6, 0.4, 0.2, 1)
            love.graphics.rectangle("fill", size/2-3, 2, 6, size-4)
            love.graphics.setColor(0.8, 0.6, 0.3, 1)
            love.graphics.circle("fill", size/2, 3, 3)
        elseif enemyType == "Ghost" then
            love.graphics.setColor(0.7, 0.3, 1, 1)
            love.graphics.circle("fill", size/2, size/2, size/2 - 1)
        elseif enemyType == "Zombie" or enemyType == "PoisonousZombie" then
            love.graphics.setColor(0.3, 0.7, 0.2, 1)
            love.graphics.circle("fill", size/2, size/2, size/2 - 1)
        elseif enemyType == "Lich" then
            love.graphics.setColor(0.8, 0.2, 0.8, 1)
            love.graphics.circle("fill", size/2, size/2, size/2 - 1)
        elseif enemyType == "PowerLich" then
            -- Body (dark purple)
            love.graphics.setColor(0.15, 0.05, 0.2, 1)
            love.graphics.rectangle("fill", 2, 4, size-4, size-4, 2)
            -- Cape (dark red)
            love.graphics.setColor(0.4, 0.05, 0.1, 0.8)
            love.graphics.rectangle("fill", 1, 5, size-2, size-5, 2)
            -- Glowing eyes
            love.graphics.setColor(0.1, 0.9, 0.3, 1)
            love.graphics.rectangle("fill", 4, 6, 3, 2)
            love.graphics.rectangle("fill", 9, 6, 3, 2)
            -- Crown spikes
            love.graphics.setColor(0.6, 0.1, 0.15, 1)
            love.graphics.polygon("fill", 8, 2, 6, 5, 10, 5)
            love.graphics.polygon("fill", 5, 3, 3, 6, 7, 6)
            love.graphics.polygon("fill", 11, 3, 9, 6, 13, 6)
            -- Staff
            love.graphics.setColor(0.3, 0.3, 0.4, 1)
            love.graphics.rectangle("fill", 13, 5, 2, 10)
            love.graphics.setColor(0.8, 0.1, 0.3, 1)
            love.graphics.circle("fill", 14, 4, 2)
        else
            love.graphics.setColor(1, 0.5, 0, 1)
            love.graphics.circle("fill", size/2, size/2, size/2 - 1)
        end
        love.graphics.setCanvas()
        sprite = canvas
    end

    local entity = Entity.new(name, Entity.TYPES.CHARACTER, q, r, maxHealth, false, moveRange, sprite, nil, attacks)
    -- Flags from registry (only those explicitly set).
    if spec.flying          then entity.flying = true end
    if spec.hovering        then entity.hovering = true end
    if spec.healthCellSize  then entity.healthCellSize = spec.healthCellSize end
    if spec.isSummoningRod  then entity.isSummoningRod = true end
    if spec.isPushable == false then entity.isPushable = false end
    if hasAura then
        entity.aura = hasAura
    end
    return entity
end

-- Create random enemy (from pool)
function environment.createRandomEnemy(q, r)
    local types
    if isProgressionRun then
        types = { "Ghost", "Zombie", "Lich" }
    else
        types = { "Ghost", "Zombie", "Lich", "Brute", "Lancer", "BogShaman", "Raider", "Dervish", "Crusher" }
    end
    local rnd = love.math.random(1, #types)
    return environment.createEnemyByType(types[rnd], q, r)
end

function environment.generateBuildingSprite(name, w, h)
    return generateCustomSprite(name, w or 32, h or 32)
end

function environment.getEntityDirection(name)
    local def = nameToEntityDef[name]
    if def and def.direction then
        return { dx = def.direction.dx, dy = def.direction.dy, dz = def.direction.dz }
    end
    return nil
end

function environment.getAvailableEntityDefs()
    local list = {}
    for name, def in pairs(nameToEntityDef) do
        local entry = { id = name, name = name, type = def.type, health = def.health }
        if def.direction then entry.hasDirection = true end
        table.insert(list, entry)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

return environment
