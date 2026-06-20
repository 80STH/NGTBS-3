-- src/content/units.lua
-- Unit & enemy registry. Each def is a table consumed by Entity.new.
-- Adding a new unit: add a def here and a sprite in assets/sprites/units.lua (or enemies.lua).

local Entity = require("src.core.entity")
local Registry = require("src.core.registry")

local units = { registry = Registry.new(), enemyPool = {} }

function units.register(def) units.registry:register(def.id, def) end
function units.get(id) return units.registry:get(id) end
function units.all() return units.registry:all() end
function units.ids() return units.registry:list() end

-- factory: create an entity from a def id at (q,r); optional side override
function units.create(id, q, r, sideOverride)
    local def = units.registry:get(id)
    if not def then error("Unknown unit: " .. tostring(id)) end
    local opts = {}
    for k, v in pairs(def) do opts[k] = v end
    opts.q = q; opts.r = r
    if sideOverride then opts.side = sideOverride end
    return Entity.new(opts)
end

function units.isEnemy(id)
    local d = units.registry:get(id)
    return d and d.side == Entity.SIDES.ENEMY
end

-- random enemy from the pool (excluding special rods/bosses)
function units.randomEnemyId()
    return units.enemyPool[love.math.random(#units.enemyPool)]
end

-- ========================================================================
-- Allies
-- ========================================================================

units.register({
    id = "Warrior", name = "Warrior", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ALLY,
    maxHealth = 2, moveRange = 3, attacks = { "dash", "flip" },
    color = { 0.85, 0.35, 0.25 }, behavior = "melee",
})
units.register({
    id = "Puncher", name = "Puncher", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ALLY,
    maxHealth = 2, moveRange = 3, attacks = { "heavy_punch", "empower_punch" },
    color = { 0.25, 0.80, 0.35 }, behavior = "melee",
})
units.register({
    id = "Rogue", name = "Rogue", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ALLY,
    maxHealth = 2, moveRange = 4, attacks = { "shoot", "piercing_shot" },
    color = { 0.25, 0.50, 0.85 }, behavior = "ranged",
})
units.register({
    id = "Summoner", name = "Summoner", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ALLY,
    maxHealth = 2, moveRange = 3, attacks = { "summon" },
    color = { 0.80, 0.25, 0.80 }, behavior = "caster",
})
units.register({
    id = "Summoned", name = "Summoned", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ALLY,
    maxHealth = 2, moveRange = 2, attacks = { "push" },
    color = { 0.60, 0.35, 0.90 }, behavior = "melee",
})

-- ========================================================================
-- Enemies
-- ========================================================================

units.register({
    id = "Zombie", name = "Zombie", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "bite" },
    color = { 0.35, 0.65, 0.25 }, behavior = "melee",
})
units.register({
    id = "PoisonousZombie", name = "Poisonous Zombie", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "bite" },
    color = { 0.45, 0.75, 0.30 }, behavior = "melee", aura = { type = "poison", radius = 1 },
})
units.register({
    id = "Ghost", name = "Ghost", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "ghost_bolt" },
    color = { 0.70, 0.45, 0.95 }, movement = Entity.MOVE.FLY, behavior = "ranged",
})
units.register({
    id = "Lich", name = "Lich", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "magic_bolt" },
    color = { 0.80, 0.30, 0.80 }, behavior = "caster",
})
units.register({
    id = "Brute", name = "Brute", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 2, attacks = { "bash" },
    color = { 0.80, 0.45, 0.20 }, behavior = "melee",
})
units.register({
    id = "Lancer", name = "Lancer", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "lunge" },
    color = { 0.55, 0.40, 0.20 }, behavior = "melee",
})
units.register({
    id = "BogShaman", name = "Bog Shaman", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 2, attacks = { "bite" },
    color = { 0.30, 0.50, 0.40 }, behavior = "melee", aura = { type = "slow", radius = 1 },
})
units.register({
    id = "Raider", name = "Raider", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "lunge" },
    color = { 0.70, 0.30, 0.30 }, behavior = "melee",
})
units.register({
    id = "Dervish", name = "Dervish", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 3, attacks = { "cleave" },
    color = { 0.85, 0.70, 0.25 }, behavior = "melee",
})
units.register({
    id = "Crusher", name = "Crusher", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 2, attacks = { "bash" },
    color = { 0.50, 0.30, 0.25 }, behavior = "melee",
})
units.register({
    id = "SummoningRod", name = "Summoning Rod", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 2, moveRange = 0, attacks = { "summon_enemy" },
    color = { 0.65, 0.50, 0.25 }, behavior = "stationary", isPushable = false, isSummoningRod = true,
})
units.register({
    id = "PowerLich", name = "Power Lich", type = Entity.TYPES.CHARACTER, side = Entity.SIDES.ENEMY,
    maxHealth = 6, moveRange = 3, attacks = { "power_bolt" },
    color = { 0.30, 0.10, 0.35 }, movement = Entity.MOVE.HOVER, healthCellSize = 3,
    behavior = "caster", isObjective = true,
})

-- enemy spawn pool (exclude SummoningRod and PowerLich)
for _, id in ipairs({ "Zombie", "PoisonousZombie", "Ghost", "Lich", "Brute", "Lancer", "BogShaman", "Raider", "Dervish", "Crusher" }) do
    table.insert(units.enemyPool, id)
end

-- ========================================================================
-- Obstacles & buildings (also created through units.create for convenience)
-- ========================================================================

units.register({
    id = "SuperMountain", name = "Mountain", type = Entity.TYPES.OBSTACLE, side = Entity.SIDES.NEUTRAL,
    maxHealth = 999, moveRange = 0, indestructible = true, isPushable = false,
    color = { 0.50, 0.45, 0.40 },
})
units.register({
    id = "WeakMountain", name = "Crag", type = Entity.TYPES.OBSTACLE, side = Entity.SIDES.NEUTRAL,
    maxHealth = 2, moveRange = 0, maxDamagePerHit = 1, isPushable = false,
    color = { 0.55, 0.50, 0.45 },
})
units.register({
    id = "SmallBuilding", name = "Hut", type = Entity.TYPES.BUILDING, side = Entity.SIDES.NEUTRAL,
    maxHealth = 1, moveRange = 0, isPushable = false,
    color = { 0.70, 0.55, 0.35 },
})
units.register({
    id = "BigBuilding", name = "House", type = Entity.TYPES.BUILDING, side = Entity.SIDES.NEUTRAL,
    maxHealth = 2, moveRange = 0, isPushable = false,
    color = { 0.50, 0.55, 0.60 },
})
units.register({
    id = "Tower", name = "Tower", type = Entity.TYPES.BUILDING, side = Entity.SIDES.NEUTRAL,
    maxHealth = 1, moveRange = 0, isPushable = false, isObjective = true,
    color = { 0.55, 0.50, 0.45 },
})
units.register({
    id = "Locomotive", name = "Locomotive", type = Entity.TYPES.BUILDING, side = Entity.SIDES.ENEMY,
    maxHealth = 3, moveRange = 0, isPushable = false, isTrainCar = true,
    color = { 0.35, 0.18, 0.12 },
})
units.register({
    id = "TrainCar", name = "Train Car", type = Entity.TYPES.BUILDING, side = Entity.SIDES.ENEMY,
    maxHealth = 1, moveRange = 0, isPushable = false, isTrainCar = true,
    color = { 0.60, 0.22, 0.18 },
})

return units
