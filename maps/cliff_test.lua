return {
  version = 1,
  format = "native",
  width = 9,
  height = 10,
  centerQ = 4,
  centerR = 4,
  orientation = "flat",
  border = "mountain",
  activeRows = {
    [0] = {3, 5},
    [1] = {1, 7},
    [2] = {0, 8},
    [3] = {0, 8},
    [4] = {0, 8},
    [5] = {0, 8},
    [6] = {0, 8},
    [7] = {0, 8},
    [8] = {2, 6},
    [9] = {4, 4},
  },
  terrain = {
    -- Water moat left
    ["0,3"] = "water",
    ["0,4"] = "water",
    ["0,5"] = "water",
    ["1,4"] = "water",
    ["1,5"] = "water",
    -- Water moat right
    ["8,3"] = "water",
    ["8,4"] = "water",
    ["8,5"] = "water",
    ["7,4"] = "water",
    ["7,5"] = "water",
  },
  entities = {
    -- Buildings on lower ground (push targets for cliff testing)
    ["3,1"] = "SmallBuilding",   -- north edge, left of center
    ["5,1"] = "SmallBuilding",   -- north edge, right of center
    ["1,2"] = "BigBuilding",     -- NW corner, left of cliff
    ["1,6"] = "SmallBuilding",   -- SW corner
    ["7,2"] = "BigBuilding",     -- NE corner, right of cliff
    ["7,6"] = "SmallBuilding",   -- SE corner
    ["4,7"] = "SmallBuilding",   -- south edge
    -- Enemies on highground edges (pushable off)
    ["2,2"] = "Zombie",
    ["6,2"] = "Zombie",
    ["4,3"] = "Brute",
    ["3,5"] = "Zombie",
    ["5,5"] = "Zombie",
    ["4,6"] = "Lich",
    -- Enemy in the center (safe from pushes)
    ["4,4"] = "Zombie",
  },
  statuses = {},
  upper_terrain = {},
  elevation = {
    -- Central highground plateau
    ["3,2"] = true,
    ["4,2"] = true,
    ["5,2"] = true,
    ["2,3"] = true,
    ["3,3"] = true,
    ["4,3"] = true,
    ["5,3"] = true,
    ["6,3"] = true,
    ["2,4"] = true,
    ["3,4"] = true,
    ["4,4"] = true,
    ["5,4"] = true,
    ["6,4"] = true,
    ["2,5"] = true,
    ["3,5"] = true,
    ["4,5"] = true,
    ["5,5"] = true,
    ["6,5"] = true,
    ["3,6"] = true,
    ["4,6"] = true,
    ["5,6"] = true,
  },
}
