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
    ["0,3"] = "water",
    ["0,4"] = "water",
    ["0,5"] = "water",
    ["1,4"] = "water",
    ["1,5"] = "water",
    ["8,3"] = "water",
    ["8,4"] = "water",
    ["8,5"] = "water",
    ["7,4"] = "water",
    ["7,5"] = "water",
  },
  entities = {
    -- Enemies standing on each hazard plate (easy to catch with the button)
    ["2,3"] = "Zombie",      -- on spikes
    ["4,3"] = "Zombie",      -- on oxidizer
    ["6,3"] = "Zombie",      -- on burner
    ["2,6"] = "SmallBuilding",
    ["6,6"] = "SmallBuilding",
  },
  statuses = {},
  upper_terrain = {
    -- Button-activated hazard plates: spikes / burner / oxidizer
    ["2,3"] = "spikes",
    ["3,3"] = "spikes",
    ["4,3"] = "oxidizer",
    ["5,3"] = "burner",
    ["6,3"] = "burner",
  },
  elevation = {},
}
