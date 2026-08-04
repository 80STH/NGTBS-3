-- map_editor.lua
-- In-game hex map editor with three layers: terrain, entity, status
-- Placement zone: regular hexagon with radius 5

local editor = {}

local hexgrid = require("grid.hexgrid")
local hex_utils = require("grid.hex_utils")
local water_gen = require("grid.water_gen")
local config = require("core.config")
local log = require("util.log")
local sprites = require("util.sprites")

-- Entity name → GID mapping (same as environment.lua)
local entityNameToGid = {
    Warrior = 34, Puncher = 30, Rogue = 31,
    Summoner = 40, Divider = 45, Summoned = 42, Divided = 44,
    Ghost = 26, Zombie = 25, PoisonousZombie = 21, Lich = 27,
    Brute = 60, Lancer = 62, BogShaman = 80, Raider = 23,
    Dervish = 28, Crusher = 66, SummoningRod = 83,
    SuperMountain = 11, WeakMountain = 6,
    MountainSlope = 9, SuperMountainSlope = 16,
    SharpReefs = 5,
    SmallBuilding = 12, BigBuilding = 7, Tower = 29,
    Caravan = 48, Blockpost = 77,
    MountainHouse = 84, SmallMountainHouse = 85,
}

local function isDirectionalEntity(name)
    local env = require("entity.environment")
    return env.getEntityDirection(name) ~= nil
end

-- Custom sprite generation for buildings/obstacles (same as environment.lua)
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
    elseif name == "Blockpost" then
        love.graphics.setColor(0.45, 0.45, 0.55)
        love.graphics.rectangle("fill", 1, 2, w-2, h-2)
        love.graphics.setColor(0.55, 0.55, 0.65)
        love.graphics.rectangle("fill", 2, 3, w-4, h-5)
        love.graphics.setColor(0.8, 0.75, 0.3)
        love.graphics.circle("fill", w/2, h/2, 2)
    elseif name == "MountainHouse" then
        love.graphics.setColor(0.65, 0.5, 0.35)
        love.graphics.rectangle("fill", 1, 4, w-2, h-4)
        love.graphics.setColor(0.55, 0.35, 0.2)
        love.graphics.polygon("fill", 0, 4, w/2, 0, w, 4)
        love.graphics.setColor(0.85, 0.8, 0.7)
        love.graphics.rectangle("fill", 3, 6, 3, 3)
        love.graphics.rectangle("fill", w-6, 6, 3, 3)
    elseif name == "SmallMountainHouse" then
        love.graphics.setColor(0.6, 0.45, 0.3)
        love.graphics.rectangle("fill", 2, 5, w-4, h-5)
        love.graphics.setColor(0.5, 0.3, 0.2)
        love.graphics.polygon("fill", 1, 5, w/2, 1, w-1, 5)
        love.graphics.setColor(0.85, 0.8, 0.7)
        love.graphics.rectangle("fill", 4, 7, 2, 2)
    elseif name == "MountainRange" then
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.polygon("fill", 0, h, w*0.3, h*0.2, w*0.5, h)
        love.graphics.setColor(0.5, 0.45, 0.4)
        love.graphics.polygon("fill", w*0.5, h, w*0.85, h*0.3, w, h)
        love.graphics.setColor(0.95, 0.95, 1)
        love.graphics.polygon("fill", w*0.3-1, h*0.2, w*0.3+1, h*0.2, w*0.3, h*0.2+2)
        love.graphics.setColor(0.3, 0.25, 0.2)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
    elseif name == "ReefRange" then
        love.graphics.setColor(0.25, 0.4, 0.5)
        love.graphics.rectangle("fill", 0, h-3, w, 3)
        love.graphics.setColor(0.55, 0.65, 0.75)
        love.graphics.polygon("fill", w*0.25, 0, w*0.05, h-1, w*0.2, h-1)
        love.graphics.polygon("fill", w*0.55, 1, w*0.35, h-1, w*0.5, h-1)
        love.graphics.polygon("fill", w*0.85, 2, w*0.65, h-1, w*0.8, h-1)
    elseif name == "SlopeRange" then
        love.graphics.setColor(0.5, 0.45, 0.4)
        love.graphics.polygon("fill", 0, h, w*0.5, h*0.3, w, h)
        love.graphics.setColor(0.6, 0.55, 0.5)
        love.graphics.polygon("fill", 0, h, w*0.5, h*0.3, w*0.5, h)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
    end

    love.graphics.setCanvas()
    return canvas
end

-- Build sprite lookup: entity name → sprite image
local editorSpriteCache = {}

local function buildEditorSpriteCache()
    editorSpriteCache = {}
    local spriteCache = sprites.raw()
    for name, gid in pairs(entityNameToGid) do
        if spriteCache[gid] then
            editorSpriteCache[name] = spriteCache[gid]
        end
    end
    -- Generate custom sprites for buildings/obstacles
    for _, entry in ipairs(editor.entityPalette) do
        if not editorSpriteCache[entry.id] then
            if entry.etype == "building" or entry.etype == "obstacle" then
                local canvas = generateCustomSprite(entry.id, 12, 12)
                if canvas then
                    editorSpriteCache[entry.id] = canvas
                end
            end
        end
    end
end

-- Editor grid: 9x10, center at (4,4), active rows matching game maps
local EDITOR_GRID_WIDTH = 9
local EDITOR_GRID_HEIGHT = 10
local EDITOR_RADIUS = 4
local EDITOR_CENTER_Q = 4
local EDITOR_CENTER_R = 4
local EDITOR_ACTIVE_ROWS = {
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
}

-- Layer definitions
editor.LAYER_TERRAIN = 1
editor.LAYER_ENTITY = 2
editor.LAYER_STATUS = 3
editor.LAYER_UPPER_TERRAIN = 4
editor.layerNames = { "Terrain", "Entity", "Status", "Upper" }

-- Terrain palette: { id, display name }
editor.terrainPalette = {
    { id = "grass",            name = "Grass" },
    { id = "dirt",             name = "Dirt" },
    { id = "sand",             name = "Sand" },
    { id = "stone",            name = "Stone" },
    { id = "snow",             name = "Snow" },
    { id = "swamp",            name = "Swamp" },
    { id = "lava",             name = "Lava" },
    { id = "water",            name = "Water" },
    { id = "emptiness",        name = "Empty" },
}

editor.upperTerrainPalette = {
    { id = "railway",          name = "Railway" },
    { id = "mountain_rubble",  name = "MtnRubble" },
    { id = "building_rubble",  name = "BldRubble" },
}

-- Entity palette: { id, display name, type, color hint }
editor.entityPalette = {
    { id = "Warrior",         name = "Warrior",   etype = "ally",    color = {0.2, 0.8, 0.2} },
    { id = "Puncher",         name = "Puncher",   etype = "ally",    color = {0.2, 0.8, 0.2} },
    { id = "Rogue",           name = "Rogue",     etype = "ally",    color = {0.2, 0.8, 0.2} },
    { id = "Summoner",        name = "Summoner",  etype = "ally",    color = {0.2, 0.8, 0.2} },
    { id = "Divider",         name = "Divider",   etype = "ally",    color = {0.2, 0.8, 0.2} },
    { id = "Ghost",           name = "Ghost",     etype = "enemy",   color = {0.8, 0.2, 0.8} },
    { id = "Zombie",          name = "Zombie",    etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "PoisonousZombie", name = "P.Zombie",  etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "Lich",            name = "Lich",      etype = "enemy",   color = {0.6, 0.2, 0.8} },
    { id = "Brute",           name = "Brute",     etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "Lancer",          name = "Lancer",    etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "BogShaman",       name = "BogShaman", etype = "enemy",   color = {0.5, 0.3, 0.6} },
    { id = "Raider",          name = "Raider",    etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "Dervish",         name = "Dervish",   etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "Crusher",         name = "Crusher",   etype = "enemy",   color = {0.8, 0.2, 0.2} },
    { id = "SummoningRod",    name = "Rod",       etype = "enemy",   color = {0.7, 0.5, 0.2} },
    { id = "SuperMountain",      name = "Mt.Indes.",    etype = "obstacle", color = {0.5, 0.5, 0.5} },
    { id = "SuperMountainSlope", name = "Mt.Slope",     etype = "obstacle", color = {0.55, 0.5, 0.45} },
    { id = "WeakMountain",       name = "Mt.Weak",      etype = "obstacle", color = {0.6, 0.6, 0.4} },
    { id = "SmallBuilding",   name = "Bldg S",    etype = "building", color = {0.4, 0.4, 0.7} },
    { id = "BigBuilding",     name = "Bldg L",    etype = "building", color = {0.3, 0.3, 0.8} },
    { id = "Tower",           name = "Tower",     etype = "building", color = {0.5, 0.5, 0.9} },
    { id = "Caravan",         name = "Caravan",   etype = "building", color = {0.6, 0.5, 0.3} },
    { id = "Blockpost",       name = "Blockpost", etype = "building", color = {0.4, 0.4, 0.6} },
    { id = "MountainHouse",      name = "Mt.House",    etype = "building", color = {0.5, 0.4, 0.3} },
    { id = "SmallMountainHouse", name = "Mt.House Sm", etype = "building", color = {0.55, 0.45, 0.35} },
}

-- Status palette
editor.statusPalette = {
    { id = "fire",  name = "Fire",  color = {1, 0.5, 0} },
    { id = "acid",  name = "Acid",  color = {0.3, 0.9, 0.3} },
}

-- Editor state
editor.active = false
editor.hex = nil
editor.currentLayer = editor.LAYER_TERRAIN
editor.selectedTerrain = "grass"
editor.selectedEntity = "Warrior"
editor.selectedUpperTerrain = "mountain_rubble"
editor.selectedStatus = "fire"
editor.eraser = false
editor.elevBrush = false
editor.isDragging = false
editor.lastPainted = nil
editor.elevationData = {}
editor.ELEV_NORMAL = nil
editor.ELEV_HIGH = "high"
editor.ELEV_LOW = "low"
editor.elevMode = editor.ELEV_NORMAL
editor.selectedEntity = "Warrior"
editor.selectedStatus = "fire"
editor.eraser = false
    editor.elevBrush = false
    editor.directionIndex = 1

-- Map data (simple string-based tables)
    editor.terrainData = {}   -- terrainData["q,r"] = terrainId
    editor.entityData = {}    -- entityData["q,r"] = entityId
    editor.statusData = {}
    editor.upperTerrainData = {}
    editor.elevationData = {}
editor.statusData = {}    -- statusData["q,r"] = { statusId, ... }
editor.upperTerrainData = {}  -- upperTerrainData["q,r"] = upperTerrainId

-- UI state
editor.paletteScroll = 0
editor.isDragging = false
editor.lastPainted = nil
editor.fileName = "custom_map"
editor.message = nil
editor.messageTimer = 0
editor.focusFileName = false
editor.mapListOpen = false
editor.availableMaps = {}

-- Undo/redo stacks
editor.undoStack = {}
editor.redoStack = {}
editor.maxUndo = 50

-- Objective configuration
editor.objectivePrimary = nil
editor.objectiveSecondaries = {}

editor.primaryObjectiveOptions = {
    { id = nil, name = "Auto" },
    { id = "protect_caravans", name = "Caravans" },
    { id = "protect_railway", name = "Railway" },
    { id = "kill_leader", name = "Kill Leader" },
}
editor.secondaryObjectiveOptions = {
    { id = nil, name = "None" },
    { id = "protect_blockpost", name = "Blockpost" },
    { id = "protect_tower", name = "Tower" },
    { id = "kill_poisonous_with_decay", name = "Poison+Decay" },
    { id = "slaughter", name = "Slaughter" },
    { id = "block_dig", name = "Block Dig" },
    { id = "kill_leader", name = "Kill Leader" },
}

-- ============================================================
-- MAP GENERATOR
-- ============================================================

-- What the chosen objectives require the generator to add.
-- Single source of truth: used by generateMap and the objectives UI hint.
local function getObjectiveContent()
    local needs = {
        railway = editor.objectivePrimary == nil or editor.objectivePrimary == "protect_railway",
        caravans = editor.objectivePrimary == "protect_caravans",
        blockpost = false,
        tower = false,
    }
    for _, sid in ipairs(editor.objectiveSecondaries or {}) do
        if sid == "protect_blockpost" then needs.blockpost = true end
        if sid == "protect_tower" then needs.tower = true end
    end
    return needs
end

function editor.generateMap()
    if not editor.hex then return end
    love.math.setRandomSeed(os.time())
    local seed = love.math.random(1, 99999)
    love.math.setRandomSeed(seed)

    -- Clear all data
    editor.terrainData = {}
    editor.entityData = {}
    editor.statusData = {}
    editor.upperTerrainData = {}
    editor.elevationData = {}

    -- === Terrain: noise-based ===
    local scale = 0.3
    local waterThreshold = -0.35
    local sandThreshold = -0.05
    local stoneThreshold = 0.5

    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            if editor.hex:isActiveHex(q, r) then
                local key = q .. "," .. r
                local n = love.math.noise(q * scale, r * scale, seed * 0.01)
                if n < sandThreshold then
                    if n < waterThreshold and not editor.genSettings.water then
                        editor.terrainData[key] = "water"
                    else
                        editor.terrainData[key] = "sand"
                    end
                elseif n > stoneThreshold then
                    editor.terrainData[key] = "stone"
                else
                    editor.terrainData[key] = "grass"
                end
            end
        end
    end

    -- === Edge barriers (randomised) ===
    -- Top: always MountainRange (the classic top wall)
    local topCells = {{1,1}, {2,1}, {3,0}, {4,0}, {5,0}, {6,1}, {7,1}}
    for _, c in ipairs(topCells) do
        editor.entityData[c[1] .. "," .. c[2]] = nil
    end
    editor.entityData["4,0"] = { name = "MountainRange", cells = topCells }
    for _, c in ipairs(topCells) do
        editor.terrainData[c[1] .. "," .. c[2]] = "stone"
    end

    -- Left side: always full barrier, vary only the type
    local leftCells = {}
    for r = 2, 7 do leftCells[#leftCells + 1] = {0, r} end
    local leftName = love.math.random() < 0.5 and "SlopeRange" or "MountainRange"
    editor.entityData["0,4"] = { name = leftName, cells = leftCells }
    for _, c in ipairs(leftCells) do
        editor.terrainData[c[1] .. "," .. c[2]] = "stone"
    end

    -- Right side: same, independently randomised
    local rightCells = {}
    for r = 2, 7 do rightCells[#rightCells + 1] = {8, r} end
    local rightName = love.math.random() < 0.5 and "SlopeRange" or "MountainRange"
    editor.entityData["8,4"] = { name = rightName, cells = rightCells }
    for _, c in ipairs(rightCells) do
        editor.terrainData[c[1] .. "," .. c[2]] = "stone"
    end

    -- Bottom: ReefRange or SharpReefs (single-cell placement)
    local bottomCells = {{1,7}, {2,8}, {3,8}, {4,9}, {5,8}, {6,8}, {7,7}}
    local bottomName = love.math.random() < 0.4 and "SharpReefs" or "ReefRange"
    if bottomName == "ReefRange" then
        for _, c in ipairs(bottomCells) do
            editor.entityData[c[1] .. "," .. c[2]] = nil
        end
        editor.entityData["4,9"] = { name = "ReefRange", cells = bottomCells }
    else
        -- SharpReefs: place single-cell obstacles
        for _, c in ipairs(bottomCells) do
            editor.entityData[c[1] .. "," .. c[2]] = "SharpReefs"
        end
    end
    for _, c in ipairs(bottomCells) do
        editor.terrainData[c[1] .. "," .. c[2]] = "stone"
    end

    -- === Water: exactly one body, must touch the map edge ===
    -- ponytail: blob grows from a random edge cell inward; incompatible with highgrounds (elevation forced off)
    if editor.genSettings.water then
        local edgeCells = {}
        for q = 0, editor.hex.gridWidth - 1 do
            for r = 0, editor.hex.gridHeight - 1 do
                if editor.hex:isActiveHex(q, r) then
                    for _, nb in ipairs(editor.hex:getNeighbors(q, r)) do
                        if not editor.hex:isActiveHex(nb.q, nb.r) then
                            edgeCells[#edgeCells + 1] = {q, r}
                            break
                        end
                    end
                end
            end
        end
        local waterSizes = {10, 20, 30}
        local cells = water_gen.growBlob({
            edgeCells = edgeCells,
            isActive = function(q, r) return editor.hex:isActiveHex(q, r) end,
            getNeighbors = function(q, r) return editor.hex:getNeighbors(q, r) end,
            target = love.math.random(waterSizes[editor.genSettings.elevSize], waterSizes[editor.genSettings.elevSize] + 6),
            random = love.math.random,
        })
        for _, c in ipairs(cells) do
            local key = c[1] .. "," .. c[2]
            editor.terrainData[key] = "water"
            editor.entityData[key] = nil
            editor.elevationData[key] = nil
        end
    end

    -- === Train tunnels: embedded in the left/right boundary walls, connected by railway ===
    -- Interconnected with objectives: railway infrastructure only when the primary
    -- objective is Auto or "Protect Railway Infrastructure".
    local needs = getObjectiveContent()
    local railTrackCells = {}
    if needs.railway then
    -- Strictly straight line: in this grid a straight left<->right crossing is only possible diagonally
    local railLines = {
        {{0,2},{1,2},{2,3},{3,3},{4,4},{5,4},{6,5},{7,5},{8,6}},
        {{0,3},{1,3},{2,4},{3,4},{4,5},{5,5},{6,6},{7,6},{8,7}},
        {{0,6},{1,5},{2,5},{3,4},{4,4},{5,3},{6,3},{7,2},{8,2}},
    }
    local line = railLines[love.math.random(1, #railLines)]
    local leftCell, rightCell = line[1], line[#line]
    local leftWall = editor.entityData["0,4"]
    local rightWall = editor.entityData["8,4"]
    local function removeCell(wall, cell)
        if not wall then return end
        for i = #wall.cells, 1, -1 do
            if wall.cells[i][1] == cell[1] and wall.cells[i][2] == cell[2] then
                table.remove(wall.cells, i)
                return
            end
        end
    end
    removeCell(leftWall, leftCell)
    removeCell(rightWall, rightCell)
    local leftTunnel, rightTunnel = "TunnelEntrance", "TunnelExit"
    -- direction 1 = down-right (+30 deg), 2 = up-right (-30 deg); travel direction
    local dir = (leftCell[2] < rightCell[2]) and 1 or 2
    if love.math.random() < 0.5 then
        leftTunnel, rightTunnel = rightTunnel, leftTunnel
        dir = (dir == 1 and 5 or 4) -- opposite of 1 is 5, opposite of 2 is 4
    end
    -- tunnel endpoints are never on the walls' home row 4, so no re-home needed
    editor.entityData[leftCell[1] .. "," .. leftCell[2]] = leftTunnel
    editor.entityData[rightCell[1] .. "," .. rightCell[2]] = rightTunnel
    if leftWall then editor.entityData["0,4"] = leftWall end
    if rightWall then editor.entityData["8,4"] = rightWall end
    for _, c in ipairs(line) do
        editor.upperTerrainData[c[1] .. "," .. c[2]] = "railway:" .. dir
        railTrackCells[#railTrackCells + 1] = {c[1], c[2]}
    end
    end -- needs.railway

    -- === Elevation: organic cluster growing down from the top ===
    -- Railway corridor must stay flat: no elevation on the track or its neighbors
    local keepLow = {}
    for _, c in ipairs(railTrackCells) do
        keepLow[c[1] .. "," .. c[2]] = true
        for _, nb in ipairs(editor.hex:getNeighbors(c[1], c[2])) do
            if editor.hex:isActiveHex(nb.q, nb.r) then
                keepLow[nb.q .. "," .. nb.r] = true
            end
        end
    end
    if not editor.genSettings.noElevation and not editor.genSettings.water then
    -- Seed: all active cells at r=0..1 are guaranteed high ground.
    local queue = {}
    for q = 0, editor.hex.gridWidth - 1 do
        for r0 = 0, 1 do
            local key = q .. "," .. r0
            if editor.hex:isActiveHex(q, r0) and not keepLow[key] then
                editor.elevationData[key] = true
                if r0 == 1 then table.insert(queue, {q, 1}) end
            end
        end
    end
    -- Grow downward with random expansion
    local sizes = {10, 20, 30}    -- small, medium, large
    local targetCount = love.math.random(sizes[editor.genSettings.elevSize], sizes[editor.genSettings.elevSize] + 6)
    local elevCount = #queue
    local visited = {}
    for _, c in ipairs(queue) do visited[c[1] .. "," .. c[2]] = true end
    while elevCount < targetCount and #queue > 0 do
        local idx = love.math.random(1, #queue)
        local cur = queue[idx]
        local neighbors = editor.hex:getNeighbors(cur[1], cur[2])
        for i = #neighbors, 2, -1 do
            local j = love.math.random(1, i)
            neighbors[i], neighbors[j] = neighbors[j], neighbors[i]
        end
        local found = false
        for _, nb in ipairs(neighbors) do
            local nk = nb.q .. "," .. nb.r
            if not visited[nk] and editor.hex:isActiveHex(nb.q, nb.r) and not keepLow[nk] and nb.r >= cur[2] then
                local reject = ({0.4, 0.25, 0.1})[editor.genSettings.elevWidth] -- narrow=more gaps
                if nb.r > cur[2] and love.math.random() < reject then
                    -- skip this neighbor, try next
                else
                    editor.elevationData[nk] = true
                    visited[nk] = true
                    table.insert(queue, {nb.q, nb.r})
                    elevCount = elevCount + 1
                    found = true
                    if elevCount >= targetCount then break end
                end
            end
        end
        if not found then table.remove(queue, idx) end
    end
    -- Cleanup: any cell with high-ground below it → also high ground
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 2 do
            local key = q .. "," .. r
            local belowKey = q .. "," .. (r + 1)
            if not editor.elevationData[key] and editor.elevationData[belowKey] and not keepLow[key] then
                editor.elevationData[key] = true
            end
        end
    end
    -- Barrier cells near the top: always high ground (no low-ground corners)
    for k, v in pairs(editor.entityData) do
        if type(v) == "table" and v.cells then
            for _, c in ipairs(v.cells) do
                if c[2] <= 2 and not keepLow[c[1] .. "," .. c[2]] then
                    editor.elevationData[c[1] .. "," .. c[2]] = true
                end
            end
        end
    end
    end -- noElevation

    -- === Buildings: 2-4 placed randomly on inner cells ===
    local buildingCandidates = {}
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            local key = q .. "," .. r
            if editor.hex:isActiveHex(q, r) and not editor.entityData[key]
                and not editor.elevationData[key]
                and editor.terrainData[key] ~= "water"
                and editor.terrainData[key] ~= "stone"
                and not (editor.upperTerrainData[key] or ""):match("^railway") then
                local n3 = love.math.noise(q * 0.6, r * 0.6, seed * 0.02 + 1)
                if n3 > 0.3 then
                    buildingCandidates[#buildingCandidates + 1] = {q = q, r = r, score = n3}
                end
            end
        end
    end
    table.sort(buildingCandidates, function(a, b) return a.score > b.score end)
    local numBuildings = love.math.random(2, 4)
    local buildingTypes = { "SmallBuilding", "SmallBuilding", "BigBuilding", "BigBuilding", "Tower" }
    for i = 1, math.min(numBuildings, #buildingCandidates) do
        local c = buildingCandidates[i]
        local bkey = c.q .. "," .. c.r
        local bt = buildingTypes[love.math.random(1, #buildingTypes)]
        editor.entityData[bkey] = bt
    end

    -- === Mountains: 2-5 WeakMountain on non-edge cells ===
    local mountainCandidates = {}
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            local key = q .. "," .. r
            if editor.hex:isActiveHex(q, r) and not editor.entityData[key]
                and editor.terrainData[key] ~= "water"
                and editor.terrainData[key] ~= "stone"
                and not (editor.upperTerrainData[key] or ""):match("^railway") then
                local n4 = love.math.noise(q * 0.7 + 5, r * 0.7 + 5, seed * 0.02 + 2)
                if n4 > 0.45 then
                    mountainCandidates[#mountainCandidates + 1] = {q = q, r = r, score = n4}
                end
            end
        end
    end
    table.sort(mountainCandidates, function(a, b) return a.score > b.score end)
    local numMountains = love.math.random(2, 5)
    for i = 1, math.min(numMountains, #mountainCandidates) do
        local c = mountainCandidates[i]
        local mkey = c.q .. "," .. c.r
        editor.entityData[mkey] = "WeakMountain"
    end

    -- === Objective content: place what the chosen objectives require ===
    local placements = {}
    if needs.caravans then placements.Caravan = 2; placements.Blockpost = 1 end
    if needs.blockpost then placements.Blockpost = 1 end
    if needs.tower then placements.Tower = 1 end
    for name, count in pairs(placements) do
        local candidates = {}
        for q = 0, editor.hex.gridWidth - 1 do
            for r = 0, editor.hex.gridHeight - 1 do
                local key = q .. "," .. r
                if editor.hex:isActiveHex(q, r) and not editor.entityData[key]
                    and not editor.elevationData[key]
                    and editor.terrainData[key] ~= "water"
                    and editor.terrainData[key] ~= "stone"
                    and not (editor.upperTerrainData[key] or ""):match("^railway") then
                    candidates[#candidates + 1] = {q = q, r = r}
                end
            end
        end
        for i = #candidates, 2, -1 do
            local j = love.math.random(1, i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end
        for i = 1, math.min(count, #candidates) do
            editor.entityData[candidates[i].q .. "," .. candidates[i].r] = name
        end
    end

    editor.fileName = "generated_" .. seed
    editor.message = "Map generated (seed " .. seed .. ")"
    editor.messageTimer = 3
    log.info("editor", "Generated map with seed " .. seed)
end

-- ============================================================
-- INIT / CLEANUP
-- ============================================================

function editor.init()
    love.window.maximize()
    hex_utils.setOrientation("flat")
    editor.hex = hexgrid.new(
        config.HEX_RADIUS,
        EDITOR_GRID_WIDTH, EDITOR_GRID_HEIGHT,
        EDITOR_RADIUS,
        EDITOR_CENTER_Q, EDITOR_CENTER_R,
        "flat",
        EDITOR_ACTIVE_ROWS
    )
    editor.hex:centerOnScreen(love.graphics.getWidth() / editor.getScale(), love.graphics.getHeight() / editor.getScale())
    -- Shift grid left to make room for palette
    editor.hex.offsetX = editor.hex.offsetX - 210
    boundaryGroupCache = nil

    editor.terrainData = {}
    editor.entityData = {}
    editor.statusData = {}
    editor.upperTerrainData = {}
    editor.elevationData = {}
    editor.currentLayer = editor.LAYER_TERRAIN
    editor.selectedTerrain = "grass"
    editor.selectedStatus = "fire"
    editor.selectedUpperTerrain = "mountain_rubble"
    editor.eraser = false
    editor.message = nil
    editor.messageTimer = 0
    editor.fileName = "custom_map"
    editor.objectivePrimary = nil
    editor.objectiveSecondaries = {}
    editor.customEntityName = ""
    editor.active = true
    editor.genSettingsOpen = false
    editor.genSettings = {
        noElevation = false,
        elevSize = 2,     -- 1=small, 2=medium, 3=large
        elevWidth = 2,    -- 1=narrow, 2=medium, 3=wide
        water = false,    -- one water body touching map edge; incompatible with highgrounds
    }
    -- UI scale: base enlargement + manual Ctrl+/- zoom (Ctrl+0 resets)
    editor.uiScale = 1.0
    editor.manualZoom = 1

    -- Dynamic entity palette from environment.lua
    local env = require("entity.environment")
    local defs = env.getAvailableEntityDefs()
    editor.entityPalette = {}
    local etypeColors = {
        character = {0.8, 0.2, 0.2},
        obstacle  = {0.5, 0.5, 0.5},
        building  = {0.4, 0.4, 0.7},
    }
    for _, def in ipairs(defs) do
        local etype = def.type
        if etype == "character" then etype = "enemy" end
        table.insert(editor.entityPalette, {
            id = def.name,
            name = def.name,
            etype = etype,
            color = etypeColors[def.type] or {0.5, 0.5, 0.5},
        })
    end
    editor.selectedEntity = editor.entityPalette[1] and editor.entityPalette[1].id or ""

    -- Dynamic objective options from objectives.lua
    local obj = require("system.objectives")
    editor.primaryObjectiveOptions = { { id = nil, name = "Auto" } }
    for _, pri in ipairs(obj.getAvailablePrimaries()) do
        table.insert(editor.primaryObjectiveOptions, { id = pri.id, name = pri.name })
    end
    table.insert(editor.primaryObjectiveOptions, { id = "kill_leader", name = "Kill Leader" })
    editor.secondaryObjectiveOptions = { { id = nil, name = "None" } }
    for _, sec in ipairs(obj.getAvailableSecondaries()) do
        table.insert(editor.secondaryObjectiveOptions, { id = sec.id, name = sec.name })
    end

    buildEditorSpriteCache()

    -- Fill all active cells with grass by default
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            if editor.hex:isActiveHex(q, r) then
                editor.terrainData[q .. "," .. r] = "grass"
            end
        end
    end

    log.info("editor", "Map editor initialized")
end

function editor.cleanup()
    editor.active = false
    editor.hex = nil
    editor.terrainData = {}
    editor.entityData = {}
    editor.statusData = {}
    editor.upperTerrainData = {}
    editor.elevationData = {}
    editor.customEntityName = ""
    editor.focusNameInput = false
    editor.undoStack = {}
    editor.redoStack = {}
    log.info("editor", "Map editor cleaned up")
end

-- ============================================================
-- UNDO / REDO
-- ============================================================

local function deepCopyMap(t, e, s, u, elv)
    local tc, ec, sc, uc, elvC = {}, {}, {}, {}, {}
    for k, v in pairs(t) do tc[k] = v end
    for k, v in pairs(e) do
        if type(v) == "table" then
            ec[k] = { name = v.name, dir = v.dir }
        else
            ec[k] = v
        end
    end
    for k, v in pairs(s) do
        if type(v) == "table" then
            local copy = {}
            for _, item in ipairs(v) do table.insert(copy, item) end
            sc[k] = copy
        else
            sc[k] = v
        end
    end
    for k, v in pairs(u) do uc[k] = v end
    for k, v in pairs(elv) do elvC[k] = v end
    return tc, ec, sc, uc, elvC
end

function editor.pushUndo()
    local t, e, s, u, elv = deepCopyMap(editor.terrainData, editor.entityData, editor.statusData, editor.upperTerrainData, editor.elevationData)
    table.insert(editor.undoStack, { terrain = t, entities = e, statuses = s, upperTerrain = u, elevation = elv })
    if #editor.undoStack > editor.maxUndo then
        table.remove(editor.undoStack, 1)
    end
    editor.redoStack = {}
end

function editor.undo()
    if #editor.undoStack == 0 then
        editor.message = "Nothing to undo"
        editor.messageTimer = 1.5
        return
    end
    local t, e, s, u, elv = deepCopyMap(editor.terrainData, editor.entityData, editor.statusData, editor.upperTerrainData, editor.elevationData)
    table.insert(editor.redoStack, { terrain = t, entities = e, statuses = s, upperTerrain = u, elevation = elv })
    local snap = table.remove(editor.undoStack)
    editor.terrainData = snap.terrain
    editor.entityData = snap.entities
    editor.statusData = snap.statuses
    editor.upperTerrainData = snap.upperTerrain or {}
    editor.elevationData = snap.elevation or {}
end

function editor.redo()
    if #editor.redoStack == 0 then
        editor.message = "Nothing to redo"
        editor.messageTimer = 1.5
        return
    end
    local t, e, s, u, elv = deepCopyMap(editor.terrainData, editor.entityData, editor.statusData, editor.upperTerrainData, editor.elevationData)
    table.insert(editor.undoStack, { terrain = t, entities = e, statuses = s, upperTerrain = u, elevation = elv })
    local snap = table.remove(editor.redoStack)
    editor.terrainData = snap.terrain
    editor.entityData = snap.entities
    editor.statusData = snap.statuses
    editor.upperTerrainData = snap.upperTerrain or {}
    editor.elevationData = snap.elevation or {}
end

-- ============================================================
-- LOAD NATIVE MAP INTO EDITOR
-- ============================================================

function editor.loadMap(data)
    editor.terrainData = {}
    editor.entityData = {}
    editor.statusData = {}
    editor.upperTerrainData = {}
    editor.elevationData = {}

    -- Use map's grid parameters (same as game does in restartGame)
    local mapWidth = data.width or EDITOR_GRID_WIDTH
    local mapHeight = data.height or EDITOR_GRID_HEIGHT
    local mapActiveRadius = data.activeRadius or EDITOR_RADIUS
    local mapCenterQ = data.centerQ or EDITOR_CENTER_Q
    local mapCenterR = data.centerR or EDITOR_CENTER_R
    local mapOrientation = data.orientation or "flat"

    hex_utils.setOrientation(mapOrientation)
    editor.hex = hexgrid.new(
        config.HEX_RADIUS,
        mapWidth, mapHeight,
        mapActiveRadius,
        mapCenterQ, mapCenterR,
        mapOrientation,
        data.activeRows
    )
    boundaryGroupCache = nil
    editor.hex:centerOnScreen(love.graphics.getWidth() / editor.getScale(), love.graphics.getHeight() / editor.getScale())
    editor.hex.offsetX = editor.hex.offsetX - 200

    if data.terrain then
        for key, val in pairs(data.terrain) do
            editor.terrainData[key] = val
        end
    end
    if data.entities then
        for key, val in pairs(data.entities) do
            editor.entityData[key] = val
        end
    end
    if data.statuses then
        for key, val in pairs(data.statuses) do
            editor.statusData[key] = val
        end
    end
    if data.upper_terrain then
        for key, val in pairs(data.upper_terrain) do
            editor.upperTerrainData[key] = val
        end
    end
    if data.elevation then
        for key, val in pairs(data.elevation) do
            editor.elevationData[key] = val
        end
    end

    editor.objectivePrimary = nil
    editor.objectiveSecondaries = {}
    if data.objectives then
        editor.objectivePrimary = data.objectives.primary or nil
        if data.objectives.secondaries then
            for _, id in ipairs(data.objectives.secondaries) do
                table.insert(editor.objectiveSecondaries, id)
            end
        end
    end

    editor.message = "Map loaded!"
    editor.messageTimer = 2
    log.info("editor", "Map loaded into editor")
end

-- ============================================================
-- SAVE / LOAD
-- ============================================================

function editor.getMapData()
    local data = {
        version = 1,
        format = "native",
        width = editor.hex.gridWidth,
        height = editor.hex.gridHeight,
        activeRadius = editor.hex.activeRadius,
        centerQ = editor.hex.centerQ,
        centerR = editor.hex.centerR,
        orientation = editor.hex.orientation,
        terrain = {},
        entities = {},
        statuses = {},
        upper_terrain = {},
        elevation = {},
    }
    if editor.hex.activeRows then
        data.activeRows = {}
        for r, range in pairs(editor.hex.activeRows) do
            data.activeRows[r] = range
        end
    end
    for key, val in pairs(editor.terrainData) do
        data.terrain[key] = val
    end
    for key, val in pairs(editor.entityData) do
        data.entities[key] = val
    end
    for key, val in pairs(editor.statusData) do
        data.statuses[key] = val
    end
    for key, val in pairs(editor.upperTerrainData) do
        data.upper_terrain[key] = val
    end
    for key, val in pairs(editor.elevationData) do
        data.elevation[key] = val
    end

    data.objectives = {}
    if editor.objectivePrimary then
        data.objectives.primary = editor.objectivePrimary
    end
    if #editor.objectiveSecondaries > 0 then
        data.objectives.secondaries = {}
        for _, id in ipairs(editor.objectiveSecondaries) do
            table.insert(data.objectives.secondaries, id)
        end
    end

    return data
end

function editor.saveMap()
    local data = editor.getMapData()
    local lines = {}
    table.insert(lines, "return {")
    table.insert(lines, string.format("  version = %d,", data.version))
    table.insert(lines, string.format('  format = "native",'))
    table.insert(lines, string.format("  width = %d,", data.width))
    table.insert(lines, string.format("  height = %d,", data.height))
    table.insert(lines, string.format("  activeRadius = %d,", data.activeRadius))
    table.insert(lines, string.format("  centerQ = %d,", data.centerQ))
    table.insert(lines, string.format("  centerR = %d,", data.centerR))
    table.insert(lines, string.format('  orientation = "%s",', data.orientation))

    -- Active rows (custom active area shape)
    if data.activeRows then
        table.insert(lines, "  activeRows = {")
        for r = 0, data.height - 1 do
            local range = data.activeRows[r]
            if range then
                table.insert(lines, string.format("    [%d] = {%d, %d},", r, range[1], range[2]))
            end
        end
        table.insert(lines, "  },")
    end

    -- Terrain
    table.insert(lines, "  terrain = {")
    for key, val in pairs(data.terrain) do
        table.insert(lines, string.format('    ["%s"] = "%s",', key, val))
    end
    table.insert(lines, "  },")

    -- Entities
    table.insert(lines, "  entities = {")
    for key, val in pairs(data.entities) do
        if type(val) == "table" and val.cells then
            local cellsStr = ""
            for i, c in ipairs(val.cells) do
                if i > 1 then cellsStr = cellsStr .. "," end
                cellsStr = cellsStr .. string.format(" {%d, %d}", c[1], c[2])
            end
            table.insert(lines, string.format('    ["%s"] = { name = "%s", cells = {%s} },', key, val.name, cellsStr))
        elseif type(val) == "table" then
            table.insert(lines, string.format('    ["%s"] = { name = "%s", dir = %d },', key, val.name, val.dir))
        else
            table.insert(lines, string.format('    ["%s"] = "%s",', key, val))
        end
    end
    table.insert(lines, "  },")

    -- Statuses
    table.insert(lines, "  statuses = {")
    for key, val in pairs(data.statuses) do
        if type(val) == "table" then
            local items = {}
            for _, s in ipairs(val) do
                table.insert(items, '"' .. s .. '"')
            end
            table.insert(lines, string.format('    ["%s"] = {%s},', key, table.concat(items, ", ")))
        end
    end
    table.insert(lines, "  },")

    -- Upper terrain (visual debris layer)
    table.insert(lines, "  upper_terrain = {")
    for key, val in pairs(data.upper_terrain) do
        table.insert(lines, string.format('    ["%s"] = "%s",', key, val))
    end
    table.insert(lines, "  },")

    -- Elevation (highground/lowground per-cell overrides)
    if data.elevation and next(data.elevation) then
        table.insert(lines, "  elevation = {")
for key, val in pairs(data.elevation) do
             local valStr = val and "true" or "false"
             table.insert(lines, string.format('    ["%s"] = %s,', key, valStr))
         end
        table.insert(lines, "  },")
    end

    -- Objectives
    local hasPrimary = data.objectives and data.objectives.primary
    local hasSecondaries = data.objectives and data.objectives.secondaries and #data.objectives.secondaries > 0
    if hasPrimary or hasSecondaries then
        table.insert(lines, "  objectives = {")
        if hasPrimary then
            table.insert(lines, string.format('    primary = "%s",', data.objectives.primary))
        end
        if hasSecondaries then
            table.insert(lines, "    secondaries = {")
            for _, id in ipairs(data.objectives.secondaries) do
                table.insert(lines, string.format('      "%s",', id))
            end
            table.insert(lines, "    },")
        end
        table.insert(lines, "  },")
    end

    table.insert(lines, "}")

    local content = table.concat(lines, "\n")
    local safeName = editor.fileName:gsub("[^%w_%-]", "_")
    local sourceDir = love.filesystem.getSource()
    sourceDir = sourceDir:gsub("/", "\\")
    if sourceDir:match("^%a:") then
        sourceDir = sourceDir:sub(1,1):upper() .. sourceDir:sub(2)
    end
    local path = sourceDir .. "\\maps\\" .. safeName .. ".lua"
    local f, err = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
        editor.message = "Saved: maps/" .. safeName .. ".lua"
    else
        editor.message = "Save failed: " .. (err or "unknown error")
    end
    editor.messageTimer = 3
    log.infof("editor", "Map saved to %s", path)
end

-- ============================================================
-- PAINT HELPERS
-- ============================================================

-- Boundary group computation from activeRows
local boundaryGroupCache = nil

local function computeBoundaryGroups(hex)
    if not hex.activeRows then return nil end

    local active = {}
    for r = 0, hex.gridHeight - 1 do
        local range = hex.activeRows[r]
        if range then
            for q = range[1], range[2] do
                active[q .. "," .. r] = true
            end
        end
    end

    local boundary = {}
    for r = 0, hex.gridHeight - 1 do
        local range = hex.activeRows[r]
        if range then
            for q = range[1], range[2] do
                local isEdge = false
                for _, nb in ipairs({{q-1,r},{q+1,r},{q,r-1},{q,r+1}}) do
                    if not active[nb[1] .. "," .. nb[2]] then
                        isEdge = true; break
                    end
                end
                if isEdge then
                    boundary[q .. "," .. r] = {q = q, r = r}
                end
            end
        end
    end

    local visited = {}
    local components = {}
    for key, cell in pairs(boundary) do
        if not visited[key] then
            local comp = {}
            local stack = {cell}
            while #stack > 0 do
                local cur = table.remove(stack)
                local ck = cur.q .. "," .. cur.r
                if not visited[ck] and boundary[ck] then
                    visited[ck] = true
                    table.insert(comp, cur)
                    for _, nb in ipairs({{cur.q-1,cur.r},{cur.q+1,cur.r},{cur.q,cur.r-1},{cur.q,cur.r+1}}) do
                        local nk = nb[1] .. "," .. nb[2]
                        if boundary[nk] and not visited[nk] then
                            table.insert(stack, {q = nb[1], r = nb[2]})
                        end
                    end
                end
            end
            if #comp > 0 then
                table.insert(components, comp)
            end
        end
    end

    local midQ = hex.gridWidth / 2
    local midR = hex.gridHeight / 2
    local named = {}

    for _, comp in ipairs(components) do
        local sumQ, sumR = 0, 0
        for _, c in ipairs(comp) do sumQ = sumQ + c.q; sumR = sumR + c.r end
        local avgQ, avgR = sumQ / #comp, sumR / #comp

        local minQ, maxQ, minR, maxR = math.huge, -math.huge, math.huge, -math.huge
        for _, c in ipairs(comp) do
            if c.q < minQ then minQ = c.q end
            if c.q > maxQ then maxQ = c.q end
            if c.r < minR then minR = c.r end
            if c.r > maxR then maxR = c.r end
        end
        local spanQ = maxQ - minQ
        local spanR = maxR - minR

        local groupName
        if spanQ >= spanR then
            groupName = avgR < midR and "top" or "bottom"
        else
            groupName = avgQ < midQ and "left" or "right"
        end
        named[groupName] = comp
    end

    return named
end

local function getBoundaryGroup(hex, q, r)
    if not boundaryGroupCache then
        boundaryGroupCache = computeBoundaryGroups(hex)
    end
    if not boundaryGroupCache then return nil end
    for groupName, cells in pairs(boundaryGroupCache) do
        for _, cell in ipairs(cells) do
            if cell.q == q and cell.r == r then
                return groupName, cells
            end
        end
    end
    return nil
end

local function key(q, r)
    return q .. "," .. r
end

function editor.paintCell(q, r)
    if not editor.hex:isActiveHex(q, r) then return end
    local k = key(q, r)

    if editor.currentLayer == editor.LAYER_TERRAIN then
        if editor.eraser then
            editor.terrainData[k] = "grass"
            editor.elevationData[k] = nil
        elseif editor.elevBrush then
            local cur = editor.elevationData[k]
            if cur then
                editor.elevationData[k] = nil
            else
                editor.elevationData[k] = true
            end
        elseif editor.elevMode then
            editor.elevationData[k] = editor.elevMode
        else
            editor.terrainData[k] = editor.selectedTerrain
        end
    elseif editor.currentLayer == editor.LAYER_ENTITY then
        if editor.eraser then
            -- For boundary entities, erase all cells in the group
            local ev = editor.entityData[k]
            if type(ev) == "table" and ev.cells then
                for _, c in ipairs(ev.cells) do
                    editor.entityData[c[1] .. "," .. c[2]] = nil
                end
            else
                editor.entityData[k] = nil
            end
        else
            local name = (editor.customEntityName ~= "" and editor.customEntityName or editor.selectedEntity)
            -- Boundary entities: fill entire group
            if name == "MountainRange" or name == "ReefRange" or name == "SlopeRange" then
                local groupName, cells = getBoundaryGroup(editor.hex, q, r)
                if groupName and cells then
                    local cellsList = {}
                    for _, cell in ipairs(cells) do
                        table.insert(cellsList, {cell.q, cell.r})
                    end
                    local anchor = cellsList[1]
                    editor.entityData[anchor[1] .. "," .. anchor[2]] = { name = name, cells = cellsList }
                    -- Clear any existing entities on group cells (except anchor)
                    for _, c in ipairs(cellsList) do
                        local ck = c[1] .. "," .. c[2]
                        if ck ~= anchor[1] .. "," .. anchor[2] then
                            editor.entityData[ck] = nil
                        end
                    end
                else
                    editor.message = "No boundary group here"
                    editor.messageTimer = 2
                end
            elseif isDirectionalEntity(name) then
                editor.entityData[k] = { name = name, dir = editor.directionIndex }
            else
                editor.entityData[k] = name
            end
        end
    elseif editor.currentLayer == editor.LAYER_STATUS then
        if editor.eraser then
            editor.statusData[k] = nil
        else
            local existing = editor.statusData[k] or {}
            local found = false
            for _, s in ipairs(existing) do
                if s == editor.selectedStatus then found = true; break end
            end
            if not found then
                table.insert(existing, editor.selectedStatus)
                editor.statusData[k] = existing
            end
        end
    elseif editor.currentLayer == editor.LAYER_UPPER_TERRAIN then
        if editor.eraser then
            editor.upperTerrainData[k] = nil
        elseif editor.selectedUpperTerrain == "railway" then
            editor.upperTerrainData[k] = "railway:" .. editor.directionIndex
        else
            editor.upperTerrainData[k] = editor.selectedUpperTerrain
        end
    end
end

-- ============================================================
-- INPUT
-- ============================================================

-- Manual zoom (Ctrl+/-) applied on top of DPI scale; also scales the draw canvas.
function editor.getManualScale()
    return (editor.uiScale or 1) * (editor.manualZoom or 1)
end

-- Full scale: layout space divisor AND mouse coordinate divisor.
function editor.getScale()
    return (editor.dpiScale or 1) * editor.getManualScale()
end

-- Palette layout constants
local PAL_X = 0
local PAL_W = 0
local PAL_BTN_H = 56
local PAL_TILE_SIZE = 90
local PAL_TILE_GAP = 8
local PAL_COLS = 3

function editor.getPaletteRect()
    local lw = love.graphics.getWidth() / editor.getScale()
    local lh = love.graphics.getHeight() / editor.getScale()
    PAL_W = 420
    PAL_X = lw - PAL_W
    return PAL_X, 0, PAL_W, lh
end

function editor.getLayerTabRects()
    local px, py, pw, _ = editor.getPaletteRect()
    local tabW = math.floor(pw / 4)
    local tabH = 30
    local rects = {}
    for i = 1, 4 do
        rects[i] = { x = px + (i - 1) * tabW, y = py, w = tabW, h = tabH }
    end
    return rects
end

function editor.getTileItems()
    if editor.currentLayer == editor.LAYER_TERRAIN then
        return editor.terrainPalette
    elseif editor.currentLayer == editor.LAYER_ENTITY then
        return editor.entityPalette
    elseif editor.currentLayer == editor.LAYER_UPPER_TERRAIN then
        return editor.upperTerrainPalette
    else
        return editor.statusPalette
    end
end

function editor.getSelectedItem()
    if editor.currentLayer == editor.LAYER_TERRAIN then
        return editor.selectedTerrain
    elseif editor.currentLayer == editor.LAYER_ENTITY then
        return editor.selectedEntity
    elseif editor.currentLayer == editor.LAYER_UPPER_TERRAIN then
        return editor.selectedUpperTerrain
    else
        return editor.selectedStatus
    end
end

function editor.getButtonRects()
    local px, _, pw, _ = editor.getPaletteRect()
    local lh = love.graphics.getHeight() / editor.getScale()
    local btnW = pw - 20
    local btnH = PAL_BTN_H
    local btnX = px + 10
    local btnGap = 8
    local baseY = lh - (btnH + btnGap) * 5 - 20
    return {
        save     = { x = btnX, y = baseY,               w = btnW, h = btnH },
        load     = { x = btnX, y = baseY + btnH + btnGap, w = btnW, h = btnH },
        eraser   = { x = btnX, y = baseY + (btnH + btnGap) * 2, w = btnW, h = btnH },
        elevation = { x = btnX, y = baseY + (btnH + btnGap) * 3, w = btnW, h = btnH },
        back     = { x = btnX, y = baseY + (btnH + btnGap) * 4, w = btnW, h = btnH },
    }
end

function editor.mousepressed(x, y, button)
    if button ~= 1 then return end

    -- Gen settings clicks (top-left, before palette)
    local eg2 = editor._gsElevToggle
    if eg2 and x >= eg2.x and x <= eg2.x + eg2.w and y >= eg2.y and y <= eg2.y + eg2.h then
        editor.genSettings.noElevation = not editor.genSettings.noElevation
        if not editor.genSettings.noElevation then editor.genSettings.water = false end
        return
    end
    local wg2 = editor._gsWaterToggle
    if wg2 and x >= wg2.x and x <= wg2.x + wg2.w and y >= wg2.y and y <= wg2.y + wg2.h then
        editor.genSettings.water = not editor.genSettings.water
        if editor.genSettings.water then editor.genSettings.noElevation = true end
        return
    end
    local genBtn = editor._gsGenerateRect
    if genBtn and x >= genBtn.x and x <= genBtn.x + genBtn.w and y >= genBtn.y and y <= genBtn.y + genBtn.h then
        editor.pushUndo()
        editor.generateMap()
        return
    end

    -- Objective cycling (merged panel)
    local priR = editor._gsPriRect
    if priR and x >= priR.x and x <= priR.x + priR.w and y >= priR.y and y <= priR.y + priR.h then
        local idx = 1
        for i, opt in ipairs(editor.primaryObjectiveOptions) do
            if opt.id == editor.objectivePrimary then idx = i; break end
        end
        editor.objectivePrimary = editor.primaryObjectiveOptions[(idx % #editor.primaryObjectiveOptions) + 1].id
        return
    end
    local function cycleSecondary(slot)
        local sRect = slot == 1 and editor._gsSec1Rect or editor._gsSec2Rect
        if not sRect or x < sRect.x or x > sRect.x + sRect.w or y < sRect.y or y > sRect.y + sRect.h then return false end
        local idx = 1
        for i, opt in ipairs(editor.secondaryObjectiveOptions) do
            if opt.id == editor.objectiveSecondaries[slot] then idx = i; break end
        end
        local newId = editor.secondaryObjectiveOptions[(idx % #editor.secondaryObjectiveOptions) + 1].id
        if newId then
            editor.objectiveSecondaries[slot] = newId
        else
            editor.objectiveSecondaries[slot] = nil
            if slot == 1 and editor.objectiveSecondaries[2] then
                editor.objectiveSecondaries[1] = editor.objectiveSecondaries[2]
                editor.objectiveSecondaries[2] = nil
            end
        end
        return true
    end
    if cycleSecondary(1) then return end
    if cycleSecondary(2) then return end

    for i = 1, 3 do
        local r2 = (editor._gsSizeRects or {})[i]
        if r2 and x >= r2.x and x <= r2.x + r2.w and y >= r2.y and y <= r2.y + r2.h then
            editor.genSettings.elevSize = i
            return
        end
    end
    for i = 1, 3 do
        local r3 = (editor._gsWidthRects or {})[i]
        if r3 and x >= r3.x and x <= r3.x + r3.w and y >= r3.y and y <= r3.y + r3.h then
            editor.genSettings.elevWidth = i
            return
        end
    end

    local px, py, pw, ph = editor.getPaletteRect()

    -- Check palette area
    if x >= px then
        -- Layer tabs
        -- Layer tabs
        local tabs = editor.getLayerTabRects()
        for i, tab in ipairs(tabs) do
            if x >= tab.x and x <= tab.x + tab.w and y >= tab.y and y <= tab.y + tab.h then
                editor.currentLayer = i
                editor.eraser = false
                editor.elevBrush = false
                editor.focusFileName = false
                return
            end
        end

        -- Custom entity name input click
        local nameInputY = 32
        if editor.currentLayer == editor.LAYER_ENTITY then
            local inputW = pw - 20
            local inputH = 24
            if x >= px + 10 and x <= px + 10 + inputW and y >= nameInputY and y <= nameInputY + inputH then
                editor.focusNameInput = true
                editor.focusFileName = false
                return
            end
            nameInputY = nameInputY + inputH + 6
        else
            editor.focusNameInput = false
        end

        -- Tile items
        local items = editor.getTileItems()
        local tileStartY = nameInputY
        for idx, item in ipairs(items) do
            local col = (idx - 1) % PAL_COLS
            local row = math.floor((idx - 1) / PAL_COLS)
            local ix = px + 10 + col * (PAL_TILE_SIZE + PAL_TILE_GAP)
            local iy = tileStartY + row * (PAL_TILE_SIZE + PAL_TILE_GAP)
            if x >= ix and x <= ix + PAL_TILE_SIZE and y >= iy and y <= iy + PAL_TILE_SIZE then
                if editor.currentLayer == editor.LAYER_TERRAIN then
                    editor.selectedTerrain = item.id
                elseif editor.currentLayer == editor.LAYER_ENTITY then
                    editor.selectedEntity = item.id
                elseif editor.currentLayer == editor.LAYER_UPPER_TERRAIN then
                    editor.selectedUpperTerrain = item.id
                else
                    editor.selectedStatus = item.id
                end
                editor.eraser = false
                editor.focusFileName = false
                return
            end
        end

        -- Buttons
        local btns = editor.getButtonRects()
        if x >= btns.save.x and x <= btns.save.x + btns.save.w and y >= btns.save.y and y <= btns.save.y + btns.save.h then
            editor.saveMap()
            return
        end
        if x >= btns.load.x and x <= btns.load.x + btns.load.w and y >= btns.load.y and y <= btns.load.y + btns.load.h then
            editor.openMapList()
            return
        end
        if x >= btns.eraser.x and x <= btns.eraser.x + btns.eraser.w and y >= btns.eraser.y and y <= btns.eraser.y + btns.eraser.h then
            editor.eraser = not editor.eraser
            editor.elevBrush = false
            return
        end
        if x >= btns.elevation.x and x <= btns.elevation.x + btns.elevation.w and y >= btns.elevation.y and y <= btns.elevation.y + btns.elevation.h then
            editor.elevBrush = not editor.elevBrush
            editor.eraser = false
            editor.elevMode = editor.ELEV_NORMAL
            return
        end

        -- File name input click
        local nameY = btns.save.y - 40
        local nameW = pw - 20
        local nameH = 24
        if x >= px + 10 and x <= px + 10 + nameW and y >= nameY and y <= nameY + nameH then
            editor.focusFileName = true
            editor.focusNameInput = false
            return
        end

        if x >= btns.back.x and x <= btns.back.x + btns.back.w and y >= btns.back.y and y <= btns.back.y + btns.back.h then
            editor.cleanup()
            gamePhase = "menu"
            return
        end

        return -- clicked in palette but not on anything specific
    end

    -- Map list dropdown: click on item or outside closes it
    if editor.mapListOpen then
        local lw = love.graphics.getWidth() / editor.getScale()
        local btnRects = editor.getButtonRects()
        local listW = 200
        local listX = lw - 400 - listW - 10
        local listY = btnRects.load.y
        local listItemH = 28
        local totalH = #editor.availableMaps * listItemH
        if x >= listX and x <= listX + listW and y >= listY and y <= listY + totalH then
            local idx = math.floor((y - listY) / listItemH) + 1
            if idx >= 1 and idx <= #editor.availableMaps then
                editor.loadMapFromList(editor.availableMaps[idx])
                return
            end
        end
        editor.mapListOpen = false
        return
    end

    editor.focusNameInput = false
    editor.focusFileName = false

    -- Click on hex grid
    if not editor.hex then return end
    local hq, hr = editor.hex:pixelToHex(x, y)
    if editor.hex:isActiveHex(hq, hr) then
        editor.pushUndo()
        editor.paintCell(hq, hr)
        editor.isDragging = true
        editor.lastPainted = hq .. "," .. hr
    end
end

function editor.mousereleased(x, y, button)
    if button == 1 then
        editor.isDragging = false
        editor.lastPainted = nil
    end
end

function editor.mousemoved(x, y)
    if not editor.isDragging then return end
    if not editor.hex then return end
    if x >= editor.getPaletteRect() then return end

    local hq, hr = editor.hex:pixelToHex(x, y)
    if editor.hex:isActiveHex(hq, hr) then
        local k = hq .. "," .. hr
        if k ~= editor.lastPainted then
            editor.paintCell(hq, hr)
            editor.lastPainted = k
        end
    end
end

function editor.keypressed(key)
    local ctrl = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    if editor.focusNameInput then
        if key == "backspace" then
            editor.customEntityName = editor.customEntityName:sub(1, -2)
        elseif key == "return" or key == "escape" then
            editor.focusNameInput = false
        elseif key == "space" then
            editor.customEntityName = editor.customEntityName .. " "
        elseif #key == 1 then
            editor.customEntityName = editor.customEntityName .. key
        end
        return
    end

    if editor.focusFileName then
        if key == "backspace" then
            editor.fileName = editor.fileName:sub(1, -2)
        elseif key == "return" or key == "escape" then
            editor.focusFileName = false
        elseif key == "space" then
            editor.fileName = editor.fileName .. " "
        elseif #key == 1 then
            editor.fileName = editor.fileName .. key
        end
        return
    end

    if ctrl then
        if key == "z" then
            editor.undo()
        elseif key == "y" then
            editor.redo()
        elseif key == "s" then
            editor.saveMap()
        elseif key == "l" then
            editor.openMapList()
        elseif key == "n" then
            editor.pushUndo()
            editor.terrainData = {}
            editor.entityData = {}
            editor.statusData = {}
            editor.elevationData = {}
            for q = 0, editor.hex.gridWidth - 1 do
                for r = 0, editor.hex.gridHeight - 1 do
                    if editor.hex and editor.hex:isActiveHex(q, r) then
                        editor.terrainData[q .. "," .. r] = "grass"
                    end
                end
            end
            editor.fileName = "custom_map"
            editor.message = "New map created"
            editor.messageTimer = 2
        elseif key == "g" then
            editor.pushUndo()
            editor.generateMap()
        elseif key == "kp_add" or key == "=" then
            editor.manualZoom = math.min(2.5, (editor.manualZoom or 1) + 0.1)
            editor.message = string.format("UI zoom: %.2fx", editor.manualZoom)
            editor.messageTimer = 1.5
        elseif key == "kp_subtract" or key == "-" then
            editor.manualZoom = math.max(0.75, (editor.manualZoom or 1) - 0.1)
            editor.message = string.format("UI zoom: %.2fx", editor.manualZoom)
            editor.messageTimer = 1.5
        elseif key == "0" then
            editor.manualZoom = 1
            editor.message = "UI zoom: 1.00x"
            editor.messageTimer = 1.5
        end
        return
    end

    if key == "1" then editor.currentLayer = editor.LAYER_TERRAIN; editor.focusNameInput = false; editor.focusFileName = false
    elseif key == "2" then editor.currentLayer = editor.LAYER_ENTITY; editor.focusFileName = false
    elseif key == "3" then editor.currentLayer = editor.LAYER_STATUS; editor.focusNameInput = false; editor.focusFileName = false
    elseif key == "4" then editor.currentLayer = editor.LAYER_UPPER_TERRAIN; editor.focusNameInput = false; editor.focusFileName = false
    elseif key == "e" then editor.eraser = not editor.eraser
    elseif key == "g" and editor.currentLayer == editor.LAYER_TERRAIN then
        editor.elevBrush = not editor.elevBrush
        editor.elevMode = editor.ELEV_NORMAL
        editor.eraser = false
        editor.message = editor.elevBrush and "Highground ON" or "Highground OFF"
        editor.messageTimer = 1.5
    elseif key == "r" then
        if editor.currentLayer == editor.LAYER_ENTITY then
            -- If hovering over a placed directional entity, rotate it in-place
            if editor.hex and editor.hex.hoverQ >= 0 and editor.hex.hoverR >= 0 then
                local hk = editor.hex.hoverQ .. "," .. editor.hex.hoverR
                local ev = editor.entityData[hk]
                if type(ev) == "table" and ev.dir then
                    editor.pushUndo()
                    ev.dir = ev.dir % 6 + 1
                    return
                end
            end
            -- Otherwise rotate painting direction
            local name = (editor.customEntityName ~= "" and editor.customEntityName or editor.selectedEntity)
            if isDirectionalEntity(name) then
                editor.directionIndex = editor.directionIndex % 6 + 1
            end
        elseif editor.currentLayer == editor.LAYER_UPPER_TERRAIN and editor.selectedUpperTerrain == "railway" then
            editor.directionIndex = editor.directionIndex % 6 + 1
        end
    elseif key == "escape" then
        if editor.mapListOpen then
            editor.mapListOpen = false
        else
            editor.cleanup()
            gamePhase = "menu"
        end
    end
end

function editor.openMapList()
    editor.mapListOpen = true
    editor.availableMaps = {}
    local items = love.filesystem.getDirectoryItems("maps")
    for _, file in ipairs(items) do
        if file:match("%.lua$") then
            local path = "maps/" .. file
            local ok, loader = pcall(love.filesystem.load, path)
            if ok and loader then
                local ok2, mapData = pcall(loader)
                if ok2 and mapData and mapData.format == "native" then
                    local name = file:gsub("%.lua$", "")
                    table.insert(editor.availableMaps, { name = name, data = mapData })
                end
            end
        end
    end
    table.sort(editor.availableMaps, function(a, b) return a.name < b.name end)
    if #editor.availableMaps == 0 then
        editor.message = "No native maps found in maps/"
        editor.messageTimer = 3
        editor.mapListOpen = false
    end
end

function editor.loadMapFromList(mapEntry)
    editor.loadMap(mapEntry.data)
    editor.fileName = mapEntry.name
    editor.mapListOpen = false
    editor.message = "Loaded: " .. mapEntry.name
    editor.messageTimer = 2
end

-- ============================================================
-- RENDERING
-- ============================================================

local terrainColors = {
    grass            = {0.35, 0.65, 0.2},
    dirt             = {0.65, 0.45, 0.25},
    sand             = {0.9, 0.85, 0.6},
    stone            = {0.55, 0.55, 0.55},
    emptiness        = {0.15, 0.15, 0.15},
    lava             = {0.95, 0.45, 0.1},
    snow             = {0.9, 0.95, 1},
    swamp            = {0.45, 0.65, 0.35},
    water            = {0.2, 0.5, 0.85},
}

local upperTerrainColors = {
    railway          = {0.35, 0.3, 0.25},
    mountain_rubble  = {0.42, 0.38, 0.33},
    building_rubble  = {0.5, 0.33, 0.18},
}

function editor.draw()
    if not editor.hex then return end

    -- Scale the whole editor canvas (UI, fonts, map) by the manual zoom
    love.graphics.push()
    love.graphics.scale(editor.getManualScale(), editor.getManualScale())

    local lw = love.graphics.getWidth() / editor.getScale()
    local lh = love.graphics.getHeight() / editor.getScale()
    local px, py, pw, ph = editor.getPaletteRect()

    -- Draw hex grid
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            if editor.hex:isActiveHex(q, r) then
                local x, y = getDrawCoordsEditor(editor.hex, q, r)
                local k = q .. "," .. r

                -- Terrain fill
                local terrain = editor.terrainData[k] or "grass"
                local col = terrainColors[terrain] or {0.3, 0.3, 0.3}
                local verts = editor.hex:drawHexagon(x, y, editor.hex.radius - 2)
                love.graphics.setColor(col[1], col[2], col[3], 1)
                love.graphics.polygon("fill", verts)
                love.graphics.setColor(0, 0, 0, 0.4)
                love.graphics.setLineWidth(1)
                love.graphics.polygon("line", verts)

                -- Elevation indicator: up-arrow triangle on high ground
                if editor.elevationData[k] then
                    local sz = editor.hex.radius * 0.3
                    love.graphics.setColor(0.2, 0.15, 0.1, 0.35)
                    love.graphics.polygon("fill", x, y - sz, x - sz * 0.55, y + sz * 0.35, x + sz * 0.55, y + sz * 0.35)
                    love.graphics.setColor(0.7, 0.5, 0.2, 0.7)
                    love.graphics.setLineWidth(1.5)
                    love.graphics.polygon("line", x, y - sz, x - sz * 0.55, y + sz * 0.35, x + sz * 0.55, y + sz * 0.35)
                    love.graphics.setLineWidth(1)
                end

                -- Upper terrain indicator
                local upperType = editor.upperTerrainData[k]
                if upperType then
                    local uCol = upperTerrainColors[upperType] or {0.5, 0.5, 0.5}
                    editor.hex:drawUpperTerrain(q, r, upperType, x, y, 0)
                end

                -- Status indicator
                local statuses = editor.statusData[k]
                if statuses and #statuses > 0 then
                    for si, st in ipairs(statuses) do
                        local stCol = {1, 1, 1}
                        for _, sp in ipairs(editor.statusPalette) do
                            if sp.id == st then stCol = sp.color; break end
                        end
                        local ox = (si - 1) * 10 - (#statuses - 1) * 5
                        love.graphics.setColor(stCol[1], stCol[2], stCol[3], 0.85)
                        love.graphics.circle("fill", x + ox, y + editor.hex.radius * 0.4, 4)
                    end
                end

                -- Hover highlight
                if editor.hex.hoverQ == q and editor.hex.hoverR == r then
                    love.graphics.setColor(1, 1, 1, 0.3)
                    local hverts = editor.hex:drawHexagon(x, y, editor.hex.radius - 2)
                    love.graphics.polygon("fill", hverts)
                end
            end
        end
    end

    -- Second pass: draw entities on top of terrain
    local drawnMultiCell = {}
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            if editor.hex:isActiveHex(q, r) then
                local x, y = getDrawCoordsEditor(editor.hex, q, r)
                local k = q .. "," .. r
                local entityVal = editor.entityData[k]
                if entityVal then
                    local entityName, entityDir = nil, nil
                    local isBoundary = false
                    if type(entityVal) == "table" then
                        entityName = entityVal.name
                        entityDir = entityVal.dir
                        isBoundary = entityVal.cells ~= nil
                    else
                        entityName = entityVal
                    end

                    local function drawEntitySprite(cx, cy, ename)
                        local sprite = editorSpriteCache[ename]
                        if sprite then
                            local sw, sh = sprite:getDimensions()
                            local scale = editor.hex.radius * 0.055
                            love.graphics.setColor(1, 1, 1, 0.95)
                            love.graphics.draw(sprite, cx, cy, 0, scale, scale, sw/2, sh/2)
                        else
                            local entCol = {0.8, 0.8, 0.8}
                            for _, ep in ipairs(editor.entityPalette) do
                                if ep.id == ename then entCol = ep.color; break end
                            end
                            love.graphics.setColor(entCol[1], entCol[2], entCol[3], 0.9)
                            love.graphics.circle("fill", cx, cy, editor.hex.radius * 0.35)
                            love.graphics.setColor(1, 1, 1, 1)
                            love.graphics.setLineWidth(2)
                            love.graphics.circle("line", cx, cy, editor.hex.radius * 0.35)
                            local letter = ename:sub(1, 1)
                            local font = love.graphics.getFont()
                            local tw = font:getWidth(letter)
                            love.graphics.setColor(1, 1, 1, 1)
                            love.graphics.print(letter, cx - tw / 2, cy - 7)
                        end
                    end

                    if isBoundary then
                        if not drawnMultiCell[k] then
                            drawnMultiCell[k] = true
                            for _, c in ipairs(entityVal.cells) do
                                local cx, cy = getDrawCoordsEditor(editor.hex, c[1], c[2])
                                drawEntitySprite(cx, cy, entityName)
                            end
                        end
                    else
                        drawEntitySprite(x, y, entityName)
                        if entityDir then
                            local cubeDir = hex_utils.CUBE_DIRECTIONS[entityDir]
                            local tq, tr = hex_utils.applyCubeDiff(q, r, cubeDir.dx, cubeDir.dy, cubeDir.dz)
                            local tx, ty = getDrawCoordsEditor(editor.hex, tq, tr)
                            local angle = math.atan2(ty - y, tx - x)
                            local dist = editor.hex.radius * 0.55
                            local tipX = x + math.cos(angle) * dist
                            local tipY = y + math.sin(angle) * dist
                            local baseX = x + math.cos(angle) * dist * 0.45
                            local baseY = y + math.sin(angle) * dist * 0.45
                            love.graphics.setColor(0.9, 0.25, 0.25, 0.7)
                            love.graphics.setLineWidth(2)
                            love.graphics.line(baseX, baseY, tipX, tipY)
                            local perp = angle + math.pi / 2
                            local headSize = 4
                            local hx1 = tipX - math.cos(angle) * headSize + math.cos(perp) * headSize * 0.5
                            local hy1 = tipY - math.sin(angle) * headSize + math.sin(perp) * headSize * 0.5
                            local hx2 = tipX - math.cos(angle) * headSize - math.cos(perp) * headSize * 0.5
                            local hy2 = tipY - math.sin(angle) * headSize - math.sin(perp) * headSize * 0.5
                            love.graphics.polygon("fill", tipX, tipY, hx1, hy1, hx2, hy2)
                            love.graphics.setLineWidth(1)
                        end
                    end
                end
            end
        end
    end

    -- Draw coordinate labels
    local font = love.graphics.getFont()
    for q = 0, editor.hex.gridWidth - 1 do
        for r = 0, editor.hex.gridHeight - 1 do
            if editor.hex:isActiveHex(q, r) then
                local x, y = getDrawCoordsEditor(editor.hex, q, r)
                love.graphics.setColor(1, 1, 1, 0.4)
                love.graphics.print(q .. "," .. r, x - 12, y + editor.hex.radius * 0.5)
            end
        end
    end

    -- ===== CELL TOOLTIP =====
    if editor.hex and editor.hex.hoverQ >= 0 and editor.hex.hoverR >= 0 then
        local hq, hr = editor.hex.hoverQ, editor.hex.hoverR
        local hk = hq .. "," .. hr
        local terrain = editor.terrainData[hk] or "~"
        local elev = editor.elevationData[hk] and "HIGH" or "LOW"
        local lines = {
            string.format("Cell (%d, %d)", hq, hr),
            "Terrain: " .. terrain,
            "Elevation: " .. elev,
        }
        local ev = editor.entityData[hk]
        if ev then
            local ename = type(ev) == "table" and ev.name or ev
            local extra = ""
            if type(ev) == "table" and ev.cells then extra = " [boundary]" end
            if type(ev) == "table" and ev.dir then extra = " [dir=" .. ev.dir .. "]" end
            lines[#lines + 1] = "Entity: " .. ename .. extra
        end
        local st = editor.statusData[hk]
        if st and #st > 0 then
            lines[#lines + 1] = "Status: " .. table.concat(st, ", ")
        end
        local ut = editor.upperTerrainData[hk]
        if ut then
            local utDir = ut:match(":(%d+)$")
            lines[#lines + 1] = "Upper: " .. (utDir and (ut:gsub(":%d+$", "") .. " [dir=" .. utDir .. "]") or ut)
        end
        editor.tooltipFont = editor.tooltipFont or love.graphics.newFont(24)
        local font = editor.tooltipFont
        local prevFont = love.graphics.getFont()
        love.graphics.setFont(font)
        local pad = 14
        local lineH = font:getHeight() + 6
        local maxW = 0
        for _, l in ipairs(lines) do
            local w = font:getWidth(l)
            if w > maxW then maxW = w end
        end
        local tw, th = maxW + pad * 2, #lines * lineH + pad * 2
        local tx = 14
        local ty = love.graphics.getHeight() / editor.getScale() - th - 14
        love.graphics.setColor(0.08, 0.08, 0.14, 0.92)
        love.graphics.rectangle("fill", tx, ty, tw, th, 6)
        love.graphics.setColor(0.4, 0.4, 0.5, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", tx, ty, tw, th, 6)
        for i, l in ipairs(lines) do
            local ly = ty + pad + (i - 1) * lineH
            if l:find("HIGH") then
                love.graphics.setColor(1, 0.75, 0.3, 1)
            elseif l:find("LOW") then
                love.graphics.setColor(0.5, 0.6, 0.7, 1)
            else
                love.graphics.setColor(0.9, 0.9, 0.9, 1)
            end
            love.graphics.print(l, tx + pad, ly)
        end
        love.graphics.setFont(prevFont)
    end

    -- ===== PALETTE PANEL =====
    love.graphics.setColor(0.12, 0.12, 0.18, 0.95)
    love.graphics.rectangle("fill", px, py, pw, ph)
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(px, py, px, py + ph)

    -- Layer tabs
    local tabs = editor.getLayerTabRects()
    for i, tab in ipairs(tabs) do
        local isActive = (editor.currentLayer == i)
        love.graphics.setColor(isActive and 0.3 or 0.2, isActive and 0.5 or 0.2, isActive and 0.7 or 0.25, 1)
        love.graphics.rectangle("fill", tab.x, tab.y, tab.w, tab.h)
        love.graphics.setColor(1, 1, 1, 1)
        local label = editor.layerNames[i]
        local lw2 = font:getWidth(label)
        love.graphics.print(label, tab.x + tab.w / 2 - lw2 / 2, tab.y + 8)
    end

    -- Custom entity name input (entity layer only)
    local nameInputY = 32
    if editor.currentLayer == editor.LAYER_ENTITY then
        local inputW = pw - 20
        local inputH = 24
        local inputX = px + 10
        love.graphics.setColor(0.15, 0.15, 0.2, 1)
        love.graphics.rectangle("fill", inputX, nameInputY, inputW, inputH, 3)
        if editor.focusNameInput then
            love.graphics.setColor(1, 1, 0.2, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.6, 1)
        end
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", inputX, nameInputY, inputW, inputH, 3)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        local displayText = editor.customEntityName
        if editor.focusNameInput then
            displayText = displayText .. "_"
        elseif displayText == "" then
            displayText = "custom name..."
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.print(displayText, inputX + 4, nameInputY + 5)
        nameInputY = nameInputY + inputH + 6
    end

    -- Tile palette
    local items = editor.getTileItems()
    local selected = editor.getSelectedItem()
    local tileStartY = nameInputY
    for idx, item in ipairs(items) do
        local col = (idx - 1) % PAL_COLS
        local row = math.floor((idx - 1) / PAL_COLS)
        local ix = px + 10 + col * (PAL_TILE_SIZE + PAL_TILE_GAP)
        local iy = tileStartY + row * (PAL_TILE_SIZE + PAL_TILE_GAP)
        local isSelected = (item.id == selected) and not editor.eraser

        -- Background
        local bgCol
        if editor.currentLayer == editor.LAYER_TERRAIN then
            bgCol = terrainColors[item.id] or {0.3, 0.3, 0.3}
        elseif editor.currentLayer == editor.LAYER_UPPER_TERRAIN then
            bgCol = upperTerrainColors[item.id] or {0.5, 0.5, 0.5}
        elseif editor.currentLayer == editor.LAYER_ENTITY then
            bgCol = item.color or {0.5, 0.5, 0.5}
        else
            bgCol = item.color or {0.5, 0.5, 0.5}
        end

        love.graphics.setColor(bgCol[1], bgCol[2], bgCol[3], isSelected and 1 or 0.6)
        love.graphics.rectangle("fill", ix, iy, PAL_TILE_SIZE, PAL_TILE_SIZE, 4)

        -- Draw sprite in palette tile
        if editor.currentLayer == editor.LAYER_ENTITY then
            local sprite = editorSpriteCache[item.id]
            if sprite then
                local sw, sh = sprite:getDimensions()
                local scale = PAL_TILE_SIZE * 0.035
                local sprRot = 0
                if isDirectionalEntity(item.id) then
                    sprRot = (editor.directionIndex - 1) * math.pi / 3
                end
                love.graphics.setColor(1, 1, 1, 0.95)
                love.graphics.draw(sprite, ix + PAL_TILE_SIZE/2, iy + PAL_TILE_SIZE/2 - 4, sprRot, scale, scale, sw/2, sh/2)
            end
        end

        if isSelected then
            love.graphics.setColor(1, 1, 0.2, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", ix, iy, PAL_TILE_SIZE, PAL_TILE_SIZE, 4)
        else
            love.graphics.setColor(0.3, 0.3, 0.3, 1)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", ix, iy, PAL_TILE_SIZE, PAL_TILE_SIZE, 4)
        end

        -- Direction indicator on tile for directional entities
        if editor.currentLayer == editor.LAYER_ENTITY and isDirectionalEntity(item.id) then
            local cx, cy = ix + PAL_TILE_SIZE / 2, iy + PAL_TILE_SIZE / 2
            local dirAngle = (editor.directionIndex - 1) * math.pi / 3
            local arrowLen = PAL_TILE_SIZE * 0.35
            local ax = cx + math.cos(dirAngle) * arrowLen
            local ay = cy + math.sin(dirAngle) * arrowLen
            love.graphics.setColor(0.9, 0.3, 0.3, 0.8)
            love.graphics.setLineWidth(2)
            love.graphics.line(cx, cy, ax, ay)
            local perp = dirAngle + math.pi / 2
            local hSize = 3
            love.graphics.polygon("fill",
                ax, ay,
                ax - math.cos(dirAngle) * hSize + math.cos(perp) * hSize * 0.5,
                ay - math.sin(dirAngle) * hSize + math.sin(perp) * hSize * 0.5,
                ax - math.cos(dirAngle) * hSize - math.cos(perp) * hSize * 0.5,
                ay - math.sin(dirAngle) * hSize - math.sin(perp) * hSize * 0.5
            )
            love.graphics.setLineWidth(1)
        end

        -- Label
        love.graphics.setColor(1, 1, 1, 1)
        local name = item.name
        local nw = font:getWidth(name)
        if nw > PAL_TILE_SIZE - 4 then
            name = name:sub(1, 5) .. ".."
            nw = font:getWidth(name)
        end
        love.graphics.print(name, ix + PAL_TILE_SIZE / 2 - nw / 2, iy + PAL_TILE_SIZE - 14)
    end

    -- Buttons
    local btns = editor.getButtonRects()
    local function drawBtn(rect, label, highlight)
        love.graphics.setColor(highlight and 0.4 or 0.25, highlight and 0.6 or 0.35, highlight and 0.4 or 0.25, 0.9)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4)
        love.graphics.setColor(1, 1, 1, 1)
        local tw = font:getWidth(label)
        love.graphics.print(label, rect.x + rect.w / 2 - tw / 2, rect.y + 8)
    end
    drawBtn(btns.save, "Save [Ctrl+S]", false)
    drawBtn(btns.load, "Load", false)
    drawBtn(btns.eraser, editor.eraser and "[ERASER ON]" or "Eraser [E]", editor.eraser)
    drawBtn(btns.elevation, editor.elevBrush and "[HIGH ON]" or "Highground [G]", editor.elevBrush)
    drawBtn(btns.back, "Back [Esc]", false)

    -- ===== GENERATION + OBJECTIVES (merged panel, top-left) =====
    local gs = editor.genSettings
    local gx, gy = 10, 10
    local gPanelW, gPanelH = 300, 222
    love.graphics.setColor(0.08, 0.08, 0.14, 0.9)
    love.graphics.rectangle("fill", gx, gy, gPanelW, gPanelH, 6)
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", gx, gy, gPanelW, gPanelH, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Generation + Objectives [Ctrl+G]", gx + 10, gy + 8)

    -- Objective rows (click to cycle)
    local function optionName(options, id)
        for _, opt in ipairs(options) do
            if opt.id == id then return opt.name end
        end
        return "Auto"
    end
    love.graphics.setColor(0.8, 0.8, 1, 1)
    love.graphics.print("Pri: [" .. optionName(editor.primaryObjectiveOptions, editor.objectivePrimary) .. "]", gx + 10, gy + 26)
    editor._gsPriRect = {x = gx + 10, y = gy + 24, w = gPanelW - 20, h = 16}
    love.graphics.print("Sec1: [" .. optionName(editor.secondaryObjectiveOptions, editor.objectiveSecondaries[1]) .. "]", gx + 10, gy + 44)
    editor._gsSec1Rect = {x = gx + 10, y = gy + 42, w = gPanelW - 20, h = 16}
    love.graphics.print("Sec2: [" .. optionName(editor.secondaryObjectiveOptions, editor.objectiveSecondaries[2]) .. "]", gx + 10, gy + 62)
    editor._gsSec2Rect = {x = gx + 10, y = gy + 60, w = gPanelW - 20, h = 16}

    -- What the chosen objectives imply for generation
    local genNeeds = getObjectiveContent()
    local hint = {}
    if genNeeds.railway then table.insert(hint, "rail+tunnels+train") end
    if genNeeds.caravans then table.insert(hint, "caravans+blockpost") end
    if genNeeds.blockpost and not genNeeds.caravans then table.insert(hint, "blockpost") end
    if genNeeds.tower then table.insert(hint, "tower") end
    if #hint > 0 then
        love.graphics.setColor(0.7, 0.9, 0.7, 1)
        love.graphics.print("Gen: " .. table.concat(hint, ", "), gx + 10, gy + 80)
    end

    -- Elevation / Water toggles (mutually exclusive)
    local elevOn = not gs.noElevation
    love.graphics.setColor(elevOn and 0.25 or 0.12, elevOn and 0.45 or 0.12, elevOn and 0.25 or 0.12, 0.9)
    love.graphics.rectangle("fill", gx + 10, gy + 94, 140, 22, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(elevOn and "[ON] Elevation" or "[OFF] Elevation", gx + 16, gy + 97)
    editor._gsElevToggle = {x = gx + 10, y = gy + 94, w = 140, h = 22}
    love.graphics.setColor(gs.water and 0.2 or 0.12, gs.water and 0.45 or 0.12, gs.water and 0.55 or 0.12, 0.9)
    love.graphics.rectangle("fill", gx + 158, gy + 94, 132, 22, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(gs.water and "[ON] Water" or "[OFF] Water", gx + 164, gy + 97)
    editor._gsWaterToggle = {x = gx + 158, y = gy + 94, w = 132, h = 22}

    if gs.water or elevOn then
        local sizeLabels = {"Small", "Medium", "Large"}
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Size:", gx + 10, gy + 118)
        for i = 1, 3 do
            local bx2 = gx + 60 + (i - 1) * 66
            local sel2 = i == gs.elevSize
            love.graphics.setColor(sel2 and 0.3 or 0.15, sel2 and 0.5 or 0.15, sel2 and 0.6 or 0.2, 1)
            love.graphics.rectangle("fill", bx2, gy + 116, 60, 22, 3)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(sizeLabels[i], bx2 + 8, gy + 118)
            editor._gsSizeRects = editor._gsSizeRects or {}
            editor._gsSizeRects[i] = {x = bx2, y = gy + 116, w = 60, h = 22}
        end
    end
    if elevOn then
        local widthLabels = {"Narrow", "Medium", "Wide"}
        love.graphics.print("Width:", gx + 10, gy + 146)
        for i = 1, 3 do
            local bx3 = gx + 60 + (i - 1) * 66
            local sel3 = i == gs.elevWidth
            love.graphics.setColor(sel3 and 0.3 or 0.15, sel3 and 0.5 or 0.15, sel3 and 0.6 or 0.2, 1)
            love.graphics.rectangle("fill", bx3, gy + 144, 60, 22, 3)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(widthLabels[i], bx3 + 8, gy + 146)
            editor._gsWidthRects = editor._gsWidthRects or {}
            editor._gsWidthRects[i] = {x = bx3, y = gy + 144, w = 60, h = 22}
        end
        local estSizes = {12, 22, 34}
        local estWidths = {[1] = 0.6, [2] = 0.85, [3] = 1.0}
        local est = math.floor(estSizes[gs.elevSize] * estWidths[gs.elevWidth])
        love.graphics.print(("Est. cells: ~%d"):format(est), gx + 10, gy + 172)
    elseif gs.water then
        local estSizes = {12, 22, 34}
        local est = estSizes[gs.elevSize]
        love.graphics.print(("Est. cells: ~%d"):format(est), gx + 10, gy + 172)
    end

    -- Generate button
    love.graphics.setColor(0.25, 0.45, 0.7, 1)
    love.graphics.rectangle("fill", gx + 10, gy + 190, gPanelW - 20, 24, 4)
    love.graphics.setColor(1, 1, 1, 1)
    local genLabel = "Generate [Ctrl+G]"
    local glw = font:getWidth(genLabel)
    love.graphics.print(genLabel, gx + 10 + (gPanelW - 20) / 2 - glw / 2, gy + 195)
    editor._gsGenerateRect = {x = gx + 10, y = gy + 190, w = gPanelW - 20, h = 24}

    -- File name input area
    local nameY = btns.save.y - 40
    love.graphics.setColor(0.15, 0.15, 0.2, 1)
    love.graphics.rectangle("fill", px + 10, nameY, pw - 20, 24, 3)
    if editor.focusFileName then
        love.graphics.setColor(1, 1, 0.2, 1)
    else
        love.graphics.setColor(0.5, 0.5, 0.6, 1)
    end
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px + 10, nameY, pw - 20, 24, 3)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    local displayName = editor.fileName
    if editor.focusFileName then
        displayName = displayName .. "_"
    end
    love.graphics.print("Name: " .. displayName, px + 14, nameY + 6)

    -- Current tool info
    local toolY = nameY - 30
    love.graphics.setColor(1, 1, 0.6, 1)
    local toolText = "Layer: " .. editor.layerNames[editor.currentLayer]
    if editor.eraser then
        toolText = toolText .. " | ERASER"
    elseif editor.currentLayer == editor.LAYER_ENTITY and editor.customEntityName ~= "" then
        toolText = toolText .. " | \"" .. editor.customEntityName .. "\""
    else
        toolText = toolText .. " | " .. (selected or "-")
    end
    if editor.currentLayer == editor.LAYER_ENTITY and not editor.eraser then
        local checkName = (editor.customEntityName ~= "" and editor.customEntityName or editor.selectedEntity)
        if isDirectionalEntity(checkName) then
            toolText = toolText .. " | Dir: " .. editor.directionIndex .. " [R]"
        end
    end
    if editor.currentLayer == editor.LAYER_UPPER_TERRAIN and editor.selectedUpperTerrain == "railway" and not editor.eraser then
        toolText = toolText .. " | Dir: " .. editor.directionIndex .. " [R]"
    end
if editor.currentLayer == editor.LAYER_TERRAIN and editor.elevBrush then
         toolText = toolText .. " | Highground [g]"
    end
    love.graphics.print(toolText, px + 10, toolY)

    -- Message
    if editor.message and editor.messageTimer > 0 then
        love.graphics.setColor(1, 1, 0.2, math.min(1, editor.messageTimer))
        local mw = font:getWidth(editor.message)
        love.graphics.print(editor.message, lw / 2 - mw / 2, 10)
    end

    -- Map list dropdown
    if editor.mapListOpen then
        local btnRects = editor.getButtonRects()
        local listW = 200
        local listX = lw - 400 - listW - 10
        local listY = btnRects.load.y
        local listItemH = 28

        -- Background
        love.graphics.setColor(0.1, 0.1, 0.15, 0.97)
        local totalH = #editor.availableMaps * listItemH
        love.graphics.rectangle("fill", listX, listY, listW, totalH, 4)
        love.graphics.setColor(0.4, 0.4, 0.5, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", listX, listY, listW, totalH, 4)

        -- Items
        for i, m in ipairs(editor.availableMaps) do
            local iy = listY + (i - 1) * listItemH
            -- Hover highlight
            local mx, my = love.mouse.getPosition()
            local escale = editor.getScale()
            mx = mx / escale
            my = my / escale
            if mx >= listX and mx <= listX + listW and my >= iy and my <= iy + listItemH then
                love.graphics.setColor(0.3, 0.5, 0.7, 0.6)
                love.graphics.rectangle("fill", listX, iy, listW, listItemH)
            end
            -- Name
            local color = (m.name == editor.fileName) and {0.4, 1, 0.4} or {1, 1, 1}
            love.graphics.setColor(color[1], color[2], color[3], 1)
            love.graphics.print(m.name, listX + 8, iy + 6)
        end
        love.graphics.setLineWidth(1)
    end

    love.graphics.pop()
end

function editor.update(dt)
    if editor.messageTimer > 0 then
        editor.messageTimer = editor.messageTimer - dt
    end
    -- Update hover
    if editor.hex then
        local mx, my = love.mouse.getPosition()
        local escale = editor.getScale()
        mx = mx / escale
        my = my / escale
        local hq, hr = editor.hex:pixelToHex(mx, my)
        if editor.hex:isActiveHex(hq, hr) then
            editor.hex.hoverQ, editor.hex.hoverR = hq, hr
        else
            editor.hex.hoverQ, editor.hex.hoverR = -1, -1
        end
    end
end

-- Helper: get draw coords using editor hex grid
function getDrawCoordsEditor(hex, q, r)
    local x, y = hex:hexToPixel(q, r)
    local elv = editor.elevationData[q .. "," .. r]
    if elv then
        y = y - 30
    end
    return x, y
end

return editor
