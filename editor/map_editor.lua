-- map_editor.lua
-- In-game hex map editor with three layers: terrain, entity, status
-- Placement zone: regular hexagon with radius 5

local editor = {}

local hexgrid = require("grid.hexgrid")
local hex_utils = require("grid.hex_utils")
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

-- Editor grid: 11x11, center at (5,5), active radius 5
local EDITOR_GRID_SIZE = 11
local EDITOR_RADIUS = 4
local EDITOR_CENTER = 5

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
    { id = "underwater_mines", name = "Mines" },
    { id = "railway",          name = "Railway" },
    { id = "emptiness",        name = "Empty" },
}

editor.upperTerrainPalette = {
    { id = "mountain_rubble", name = "MtnRubble" },
    { id = "building_rubble", name = "BldRubble" },
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
editor.selectedStatus = "fire"
editor.eraser = false
editor.directionIndex = 1

-- Map data (simple string-based tables)
editor.terrainData = {}   -- terrainData["q,r"] = terrainId
editor.entityData = {}    -- entityData["q,r"] = entityId
editor.statusData = {}    -- statusData["q,r"] = { statusId, ... }
editor.upperTerrainData = {}  -- upperTerrainData["q,r"] = upperTerrainId

-- UI state
editor.paletteScroll = 0
editor.isDragging = false
editor.lastPainted = nil
editor.fileName = "custom_map"
editor.message = nil
editor.messageTimer = 0

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
-- INIT / CLEANUP
-- ============================================================

function editor.init()
    hex_utils.setOrientation("flat")
    editor.hex = hexgrid.new(
        config.HEX_RADIUS,
        EDITOR_GRID_SIZE, EDITOR_GRID_SIZE,
        EDITOR_RADIUS,
        EDITOR_CENTER, EDITOR_CENTER,
        "flat"
    )
    editor.hex:centerOnScreen(love.graphics.getWidth() / (editor.dpiScale or 1), love.graphics.getHeight() / (editor.dpiScale or 1))
    -- Shift grid left to make room for palette
    editor.hex.offsetX = editor.hex.offsetX - 200

    editor.terrainData = {}
    editor.entityData = {}
    editor.statusData = {}
    editor.upperTerrainData = {}
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
    for q = 0, EDITOR_GRID_SIZE - 1 do
        for r = 0, EDITOR_GRID_SIZE - 1 do
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
    editor.customEntityName = ""
    editor.focusNameInput = false
    editor.undoStack = {}
    editor.redoStack = {}
    log.info("editor", "Map editor cleaned up")
end

-- ============================================================
-- UNDO / REDO
-- ============================================================

local function deepCopyMap(t, e, s, u)
    local tc, ec, sc, uc = {}, {}, {}, {}
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
    return tc, ec, sc, uc
end

function editor.pushUndo()
    local t, e, s, u = deepCopyMap(editor.terrainData, editor.entityData, editor.statusData, editor.upperTerrainData)
    table.insert(editor.undoStack, { terrain = t, entities = e, statuses = s, upperTerrain = u })
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
    -- Save current state to redo
    local t, e, s, u = deepCopyMap(editor.terrainData, editor.entityData, editor.statusData, editor.upperTerrainData)
    table.insert(editor.redoStack, { terrain = t, entities = e, statuses = s, upperTerrain = u })
    -- Restore
    local snap = table.remove(editor.undoStack)
    editor.terrainData = snap.terrain
    editor.entityData = snap.entities
    editor.statusData = snap.statuses
    editor.upperTerrainData = snap.upperTerrain or {}
end

function editor.redo()
    if #editor.redoStack == 0 then
        editor.message = "Nothing to redo"
        editor.messageTimer = 1.5
        return
    end
    -- Save current state to undo
    local t, e, s, u = deepCopyMap(editor.terrainData, editor.entityData, editor.statusData, editor.upperTerrainData)
    table.insert(editor.undoStack, { terrain = t, entities = e, statuses = s, upperTerrain = u })
    -- Restore
    local snap = table.remove(editor.redoStack)
    editor.terrainData = snap.terrain
    editor.entityData = snap.entities
    editor.statusData = snap.statuses
    editor.upperTerrainData = snap.upperTerrain or {}
end

-- ============================================================
-- LOAD NATIVE MAP INTO EDITOR
-- ============================================================

function editor.loadMap(data)
    editor.terrainData = {}
    editor.entityData = {}
    editor.statusData = {}
    editor.upperTerrainData = {}

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
        width = EDITOR_GRID_SIZE,
        height = EDITOR_GRID_SIZE,
        activeRadius = EDITOR_RADIUS,
        centerQ = EDITOR_CENTER,
        centerR = EDITOR_CENTER,
        orientation = "flat",
        terrain = {},
        entities = {},
        statuses = {},
        upper_terrain = {},
    }
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
    table.insert(lines, string.format('  orientation = "flat",'))

    -- Terrain
    table.insert(lines, "  terrain = {")
    for key, val in pairs(data.terrain) do
        table.insert(lines, string.format('    ["%s"] = "%s",', key, val))
    end
    table.insert(lines, "  },")

    -- Entities
    table.insert(lines, "  entities = {")
    for key, val in pairs(data.entities) do
        if type(val) == "table" then
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

local function key(q, r)
    return q .. "," .. r
end

function editor.paintCell(q, r)
    if not editor.hex:isActiveHex(q, r) then return end
    local k = key(q, r)

    if editor.currentLayer == editor.LAYER_TERRAIN then
        if editor.eraser then
            editor.terrainData[k] = "grass"
        else
            editor.terrainData[k] = editor.selectedTerrain
        end
    elseif editor.currentLayer == editor.LAYER_ENTITY then
        if editor.eraser then
            editor.entityData[k] = nil
        else
            local name = (editor.customEntityName ~= "" and editor.customEntityName or editor.selectedEntity)
            if isDirectionalEntity(name) then
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
        else
            editor.upperTerrainData[k] = editor.selectedUpperTerrain
        end
    end
end

-- ============================================================
-- INPUT
-- ============================================================

-- Palette layout constants
local PAL_X = 0
local PAL_W = 0
local PAL_BTN_H = 40
local PAL_TILE_SIZE = 68
local PAL_TILE_GAP = 6
local PAL_COLS = 4

function editor.getPaletteRect()
    local lw = love.graphics.getWidth() / (editor.dpiScale or 1)
    local lh = love.graphics.getHeight() / (editor.dpiScale or 1)
    PAL_W = 400
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
    local lh = love.graphics.getHeight() / (editor.dpiScale or 1)
    local btnW = pw - 20
    local btnH = PAL_BTN_H
    local btnX = px + 10
    local btnGap = 8
    local baseY = lh - (btnH + btnGap) * 4 - 20
    return {
        save   = { x = btnX, y = baseY,               w = btnW, h = btnH },
        load   = { x = btnX, y = baseY + btnH + btnGap, w = btnW, h = btnH },
        eraser = { x = btnX, y = baseY + (btnH + btnGap) * 2, w = btnW, h = btnH },
        back   = { x = btnX, y = baseY + (btnH + btnGap) * 3, w = btnW, h = btnH },
    }
end

function editor.mousepressed(x, y, button)
    if button ~= 1 then return end
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
                return
            end
        end

        -- Objectives cycling
        local btns = editor.getButtonRects()
        local nameY = btns.save.y - 40
        local toolY = nameY - 30
        local objY = toolY - 55
        local font = love.graphics.getFont()

        local function hitY(row)
            return objY + 15 + row * 15
        end

        -- Primary
        local priName = "Auto"
        local priIdx = 1
        for i, opt in ipairs(editor.primaryObjectiveOptions) do
            if opt.id == editor.objectivePrimary then priIdx = i; priName = opt.name; break end
        end
        local priText = "Pri: [" .. priName .. "]"
        if y >= hitY(0) and y <= hitY(0) + 14 and x >= px + 10 and x <= px + 10 + font:getWidth(priText) then
            local nextIdx = (priIdx % #editor.primaryObjectiveOptions) + 1
            editor.objectivePrimary = editor.primaryObjectiveOptions[nextIdx].id
            return
        end

        -- Sec1
        local sec1Id = editor.objectiveSecondaries[1]
        local sec1Idx = 1
        for i, opt in ipairs(editor.secondaryObjectiveOptions) do
            if opt.id == sec1Id then sec1Idx = i; break end
        end
        local sec1Name = editor.secondaryObjectiveOptions[sec1Idx].name
        local sec1Text = "Sec1: [" .. sec1Name .. "]"
        if y >= hitY(1) and y <= hitY(1) + 14 and x >= px + 10 and x <= px + 10 + font:getWidth(sec1Text) then
            local nextIdx = (sec1Idx % #editor.secondaryObjectiveOptions) + 1
            local newId = editor.secondaryObjectiveOptions[nextIdx].id
            if newId then
                editor.objectiveSecondaries[1] = newId
            else
                editor.objectiveSecondaries[1] = nil
                if editor.objectiveSecondaries[2] then
                    editor.objectiveSecondaries[1] = editor.objectiveSecondaries[2]
                    editor.objectiveSecondaries[2] = nil
                end
            end
            return
        end

        -- Sec2
        local sec2Id = editor.objectiveSecondaries[2]
        local sec2Idx = 1
        for i, opt in ipairs(editor.secondaryObjectiveOptions) do
            if opt.id == sec2Id then sec2Idx = i; break end
        end
        local sec2Name = editor.secondaryObjectiveOptions[sec2Idx].name
        local sec2Text = "Sec2: [" .. sec2Name .. "]"
        if y >= hitY(2) and y <= hitY(2) + 14 and x >= px + 10 and x <= px + 10 + font:getWidth(sec2Text) then
            local nextIdx = (sec2Idx % #editor.secondaryObjectiveOptions) + 1
            local newId = editor.secondaryObjectiveOptions[nextIdx].id
            if newId then
                editor.objectiveSecondaries[2] = newId
            else
                editor.objectiveSecondaries[2] = nil
            end
            return
        end

        -- Buttons
        if x >= btns.save.x and x <= btns.save.x + btns.save.w and y >= btns.save.y and y <= btns.save.y + btns.save.h then
            editor.saveMap()
            return
        end
        if x >= btns.load.x and x <= btns.load.x + btns.load.w and y >= btns.load.y and y <= btns.load.y + btns.load.h then
            editor.loadMapFromFile()
            return
        end
        if x >= btns.eraser.x and x <= btns.eraser.x + btns.eraser.w and y >= btns.eraser.y and y <= btns.eraser.y + btns.eraser.h then
            editor.eraser = not editor.eraser
            return
        end
        if x >= btns.back.x and x <= btns.back.x + btns.back.w and y >= btns.back.y and y <= btns.back.y + btns.back.h then
            editor.cleanup()
            gamePhase = "menu"
            return
        end

        return -- clicked in palette but not on anything specific
    end

    editor.focusNameInput = false

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

    if ctrl then
        if key == "z" then
            editor.undo()
        elseif key == "y" then
            editor.redo()
        elseif key == "s" then
            editor.saveMap()
        elseif key == "l" then
            editor.loadMapFromFile()
        elseif key == "n" then
            editor.pushUndo()
            editor.terrainData = {}
            editor.entityData = {}
            editor.statusData = {}
            for q = 0, EDITOR_GRID_SIZE - 1 do
                for r = 0, EDITOR_GRID_SIZE - 1 do
                    if editor.hex and editor.hex:isActiveHex(q, r) then
                        editor.terrainData[q .. "," .. r] = "grass"
                    end
                end
            end
            editor.fileName = "custom_map"
            editor.message = "New map created"
            editor.messageTimer = 2
        end
        return
    end

    if key == "1" then editor.currentLayer = editor.LAYER_TERRAIN; editor.focusNameInput = false
    elseif key == "2" then editor.currentLayer = editor.LAYER_ENTITY
    elseif key == "3" then editor.currentLayer = editor.LAYER_STATUS; editor.focusNameInput = false
    elseif key == "4" then editor.currentLayer = editor.LAYER_UPPER_TERRAIN; editor.focusNameInput = false
    elseif key == "e" then editor.eraser = not editor.eraser
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
        end
    elseif key == "escape" then
        editor.cleanup()
        gamePhase = "menu"
    end
end

function editor.loadMapFromFile()
    -- Scan maps/ for native format maps
    local items = love.filesystem.getDirectoryItems("maps")
    local nativeMaps = {}
    for _, file in ipairs(items) do
        if file:match("%.lua$") then
            local path = "maps/" .. file
            local ok, data = pcall(love.filesystem.load(path))
            if ok and data then
                local ok2, result = pcall(data)
                if ok2 and result and result.format == "native" then
                    table.insert(nativeMaps, { name = file:gsub("%.lua$", ""), path = path, data = result })
                end
            end
        end
    end

    if #nativeMaps == 0 then
        editor.message = "No native maps found in maps/"
        editor.messageTimer = 3
        return
    end

    -- Cycle to next map after current fileName
    local currentIdx = 0
    for i, m in ipairs(nativeMaps) do
        if m.name == editor.fileName then currentIdx = i; break end
    end
    local nextIdx = (currentIdx % #nativeMaps) + 1
    local chosen = nativeMaps[nextIdx]

    editor.fileName = chosen.name
    editor.loadMap(chosen.data)
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
    underwater_mines = {0.08, 0.25, 0.45},
    railway          = {0.35, 0.3, 0.25},
}

local upperTerrainColors = {
    mountain_rubble  = {0.42, 0.38, 0.33},
    building_rubble  = {0.5, 0.33, 0.18},
}

function editor.draw()
    if not editor.hex then return end

    local lw = love.graphics.getWidth() / (editor.dpiScale or 1)
    local lh = love.graphics.getHeight() / (editor.dpiScale or 1)
    local px, py, pw, ph = editor.getPaletteRect()

    -- Draw hex grid
    for q = 0, EDITOR_GRID_SIZE - 1 do
        for r = 0, EDITOR_GRID_SIZE - 1 do
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

                -- Upper terrain indicator
                local upperType = editor.upperTerrainData[k]
                if upperType then
                    local uCol = upperTerrainColors[upperType] or {0.5, 0.5, 0.5}
                    editor.hex:drawUpperTerrain(q, r, upperType, x, y, 0)
                end

                -- Entity indicator
                local entityVal = editor.entityData[k]
                if entityVal then
                    local entityName, entityDir = nil, nil
                    if type(entityVal) == "table" then
                        entityName = entityVal.name
                        entityDir = entityVal.dir
                    else
                        entityName = entityVal
                    end
                    local sprite = editorSpriteCache[entityName]
                    local rot = 0
                    if entityDir then
                        rot = (entityDir - 1) * math.pi / 3
                    end
                    if sprite then
                        local sw, sh = sprite:getDimensions()
                        local scale = editor.hex.radius * 0.055
                        love.graphics.setColor(1, 1, 1, 0.95)
                        love.graphics.draw(sprite, x, y, rot, scale, scale, sw/2, sh/2)
                    else
                        local entCol = {0.8, 0.8, 0.8}
                        for _, ep in ipairs(editor.entityPalette) do
                            if ep.id == entityName then entCol = ep.color; break end
                        end
                        love.graphics.setColor(entCol[1], entCol[2], entCol[3], 0.9)
                        love.graphics.circle("fill", x, y, editor.hex.radius * 0.35)
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.setLineWidth(2)
                        love.graphics.circle("line", x, y, editor.hex.radius * 0.35)
                        local letter = entityName:sub(1, 1)
                        local font = love.graphics.getFont()
                        local tw = font:getWidth(letter)
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.print(letter, x - tw / 2, y - 7)
                    end
                    -- Direction arrow for directional entities
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
                        -- Arrow head
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

    -- Draw coordinate labels
    local font = love.graphics.getFont()
    for q = 0, EDITOR_GRID_SIZE - 1 do
        for r = 0, EDITOR_GRID_SIZE - 1 do
            if editor.hex:isActiveHex(q, r) then
                local x, y = getDrawCoordsEditor(editor.hex, q, r)
                love.graphics.setColor(1, 1, 1, 0.4)
                love.graphics.print(q .. "," .. r, x - 12, y + editor.hex.radius * 0.5)
            end
        end
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

    -- Objectives section
    local btns = editor.getButtonRects()
    local nameY = btns.save.y - 40
    local toolY = nameY - 30
    local objY = toolY - 55

    local function optionName(options, id)
        for _, opt in ipairs(options) do
            if opt.id == id then return opt.name end
        end
        return "Auto"
    end

    love.graphics.setColor(0.5, 0.5, 0.7, 1)
    love.graphics.print("Objectives:", px + 10, objY)

    local priName = optionName(editor.primaryObjectiveOptions, editor.objectivePrimary)
    love.graphics.setColor(0.8, 0.8, 1, 1)
    love.graphics.print("Pri: [" .. priName .. "]", px + 10, objY + 15)

    local sec1Name = optionName(editor.secondaryObjectiveOptions, editor.objectiveSecondaries[1])
    local sec2Name = optionName(editor.secondaryObjectiveOptions, editor.objectiveSecondaries[2])
    love.graphics.print("Sec1: [" .. sec1Name .. "]", px + 10, objY + 30)
    love.graphics.print("Sec2: [" .. sec2Name .. "]", px + 10, objY + 45)

    -- Buttons
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
    drawBtn(btns.back, "Back [Esc]", false)

    -- File name input area
    local nameY = btns.save.y - 40
    love.graphics.setColor(0.15, 0.15, 0.2, 1)
    love.graphics.rectangle("fill", px + 10, nameY, pw - 20, 24, 3)
    love.graphics.setColor(0.5, 0.5, 0.6, 1)
    love.graphics.rectangle("line", px + 10, nameY, pw - 20, 24, 3)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.print("Name: " .. editor.fileName, px + 14, nameY + 6)

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
    love.graphics.print(toolText, px + 10, toolY)

    -- Message
    if editor.message and editor.messageTimer > 0 then
        love.graphics.setColor(1, 1, 0.2, math.min(1, editor.messageTimer))
        local mw = font:getWidth(editor.message)
        love.graphics.print(editor.message, lw / 2 - mw / 2, 10)
    end
end

function editor.update(dt)
    if editor.messageTimer > 0 then
        editor.messageTimer = editor.messageTimer - dt
    end
    -- Update hover
    if editor.hex then
        local mx, my = love.mouse.getPosition()
        local dpiScale = editor.dpiScale or 1
        mx = mx / dpiScale
        my = my / dpiScale
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
    return hex:hexToPixel(q, r)
end

return editor
