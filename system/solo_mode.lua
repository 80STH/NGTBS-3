-- system/solo_mode.lua
-- Solo mode: control ONE hero (chosen in menu) with 2 attacks + 2 moves per turn.

local solo_mode = {}

local HEROES = nil

local function getHeroes()
    if HEROES then return HEROES end
    local c = require("combat.combat")
    HEROES = {
        {
            id = "blade", name = "Blade", spriteGid = 34, hp = 5, shields = 2, move = 3, tags = {"fire", "push"},
            attacks = function()
                return {
                    { attack = c.DashAttack.new(), name = "Dash", description = "Charge forward, pushes enemy" },
                    { attack = c.FlipAttack.new(), name = "Flip", description = "Flips enemy behind you" },
                    { attack = c.FireStompAttack.new(), name = "Fire Stomp", description = "Ignite the selected cell and two cells in front of it" },
                }
            end,
        },
        {
            id = "gunner", name = "Gunner", spriteGid = 31, hp = 5, shields = 2, move = 4, tags = {"push"},
            attacks = function()
                return {
                    { attack = c.ShootAttack.new(), name = "Shoot", description = "Shoots and pushes first enemy in line" },
                    { attack = c.PiercingShootAttack.new(), name = "Piercing Shot", description = "Pierces first enemy, wounds and pushes the second" },
                    { attack = c.PushAttack.new(5), name = "Push", description = "Pushes first enemy in line, no damage" },
                }
            end,
        },
        {
            id = "brute", name = "Brute", spriteGid = 30, hp = 5, shields = 2, move = 2, tags = {"push"},
            attacks = function()
                return {
                    { attack = c.HeavyPunchAttack.new(), name = "Heavy Punch", description = "Heavy strike, wounds and pushes. Lethal if empowered" },
                    { attack = c.EmpowerPunchAttack.new(), name = "Empower Punch", description = "Pushes target, doubles next attack. Wounds if empowered" },
                    { attack = c.BashAttack.new(), name = "Bash", description = "Heavy blow: wounds target and enemy behind attacker" },
                }
            end,
        },
        {
            id = "storm", name = "Storm", spriteGid = 27, hp = 5, shields = 2, move = 3, tags = {},
            attacks = function()
                return {
                    { attack = c.VortexStrikeAttack.new(), name = "Vortex Strike", description = "Shifts an enemy left or right and wounds" },
                    { attack = c.WideVortexAttack.new(), name = "Wide Vortex", description = "Shifts 3 enemies in front left or right" },
                    { attack = c.ElectricHookAttack.new(), name = "Electric Hook", description = "Arc lightning, wounds everyone on the line" },
                }
            end,
        },
        {
            id = "warlock", name = "Warlock", spriteGid = 40, hp = 5, shields = 2, move = 3, tags = {},
            attacks = function()
                return {
                    { attack = c.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any cell, ignores obstacles, wounds" },
                    { attack = c.SummonAttack.new(), name = "Summon", description = "Summons a minion at target cell" },
                    { attack = c.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, wounds twice" },
                }
            end,
        },
        {
            id = "hooker", name = "Hooker", spriteGid = 31, hp = 5, shields = 2, move = 3, tags = {},
            attacks = function()
                return {
                    { attack = c.CatchAttack.new(), name = "Catch", description = "Hook the first enemy in line, pull it to you and deal 1 damage" },
                    { attack = c.GrappleAttack.new(), name = "Grapple", description = "Pull yourself to the first enemy in line and deal 1 damage. Lethal beyond 3 cells" },
                    { attack = c.WarpPrismAttack.new(), name = "Warp Prism", description = "Swap places with the first enemy in line. Works on grounded units" },
                }
            end,
        },
    }
    return HEROES
end

solo_mode.getHeroes = getHeroes

function solo_mode.getHeroDef(idx)
    return getHeroes()[idx]
end

-- Build the playable hero entity. q/r = -1 until placed.
function solo_mode.createHero(defIdx, q, r)
    local def = getHeroes()[defIdx]
    if not def then return nil end
    local environment = require("entity.environment")
    local Entity = require("entity.entity")
    local sprite = environment.unitSpriteCache and environment.unitSpriteCache[def.spriteGid]
    local e = Entity.new(def.name, Entity.TYPES.CHARACTER, q or -1, r or -1,
        def.hp, true, def.move, sprite, nil, def.attacks())
    e.soloActions = true
    e.attacksLeft = 2
    e.movesLeft = 2
    -- 2 shield points: absorb direct hero damage only, refill between levels
    e.shields = def.shields or 2
    e.maxShields = e.shields
    return e
end

return solo_mode
