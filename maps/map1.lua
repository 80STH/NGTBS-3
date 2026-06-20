-- maps/map1.lua
-- A hex-shaped battlefield (radius 4). Lua-table format (no Tiled).
-- Allies deploy in the bottom rows; enemies start at the top.
-- A train runs along a railway into the player's side; a building raises chaos.

return {
    name = "Crossroads",
    radius = 4,
    size = 51,
    maxTurns = 14,

    -- terrain (defaults to "grass" where not listed)
    terrain = {
        ["4,-2"] = "water",
        ["-4,2"] = "lava",
        ["2,-1"] = "railway",
        ["1,0"]  = "railway",
        ["0,1"]  = "railway",
        ["-1,2"] = "railway",
        ["-2,3"] = "railway",
        ["3,1"]  = "stone",
        ["-3,2"] = "stone",
    },

    -- enemies & buildings (allies come from the squad via deploy)
    entities = {
        { def = "Zombie",      q =  0, r = -4, side = "enemy" },
        { def = "Zombie",      q =  2, r = -4, side = "enemy" },
        { def = "Lich",        q = -2, r = -2, side = "enemy" },
        { def = "Brute",       q =  3, r = -3, side = "enemy" },
        { def = "BogShaman",   q = -3, r = -1, side = "enemy" },
        { def = "BigBuilding", q =  3, r =  1, side = "neutral" },
        { def = "Tower",       q = -3, r =  2, side = "neutral" },
    },

    statuses = {
        { type = "fire", q =  0, r = -3, data = { duration = 6 } },
        { type = "acid", q =  1, r = -2, data = { duration = 6 } },
    },

    digSites = {
        { q = -1, r = 0, timer = 3, spawn = "Zombie" },
    },

    trains = {
        { path = { { q = 2, r = -1 }, { q = 1, r = 0 }, { q = 0, r = 1 }, { q = -1, r = 2 }, { q = -2, r = 3 } },
          length = 2, isObjective = false },
    },

    deployZone = {
        { q = -4, r = 4 }, { q = -3, r = 4 }, { q = -2, r = 4 }, { q = -1, r = 4 }, { q = 0, r = 4 },
        { q = -4, r = 3 }, { q = -3, r = 3 }, { q = -2, r = 3 }, { q = -1, r = 3 }, { q = 0, r = 3 }, { q = 1, r = 3 },
    },

    objective = { type = "kill_all" },
}
