-- maps/map2.lua
-- Protect the Tower (a neutral objective building) from enemies for the turn limit.
-- A Power Lich leads the assault. Allies deploy around the tower.

return {
    name = "Last Stand",
    radius = 4,
    size = 46,
    maxTurns = 12,

    terrain = {
        ["-4,0"] = "water",
        ["4,-1"] = "water",
        ["0,-4"] = "lava",
        ["2,2"]  = "swamp",
        ["-2,2"] = "swamp",
    },

    entities = {
        { def = "PowerLich",   q =  0, r = -4, side = "enemy" },
        { def = "Zombie",      q = -3, r = -1, side = "enemy" },
        { def = "Zombie",      q =  3, r = -2, side = "enemy" },
        { def = "Ghost",       q = -2, r = -3, side = "enemy" },
        { def = "Lancer",      q =  2, r = -3, side = "enemy" },
        { def = "Tower",       q =  0, r =  1, side = "neutral" },
        { def = "SuperMountain", q =  0, r = -2, side = "neutral" },
    },

    statuses = {
        { type = "fire", q =  3, r =  1, data = { duration = 8 } },
    },

    digSites = {
        { q = -3, r = 2, timer = 4, spawn = "Zombie" },
    },

    deployZone = {
        { q = -1, r = 3 }, { q =  0, r = 3 }, { q =  1, r = 2 },
        { q = -2, r = 3 }, { q =  2, r = 2 },
        { q = -1, r = 2 }, { q =  1, r = 3 },
        { q = -3, r = 3 }, { q =  3, r = 1 },
    },

    objective = { type = "protect", targetId = "Tower", targetName = "Tower", alsoKillAll = false },
}
