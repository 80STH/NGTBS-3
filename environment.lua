-- environment.lua
local Entity = require("entity")
local sti = require("libraries.sti")
local config = require("config")

local environment = {}

local gidToTerrain = {
    [13] = "grass",
    [2]  = "dirt",
    [1]  = "sand",
    [4]  = "stone",
    [5]  = "emptiness",
    [6]  = "lava",
    [7]  = "snow",
    [8]  = "swamp",
    [14] = "water",
}

local gidToEntity = {
    [34] = { type = "character", name = "Warrior", isPlayable = true,  maxHealth = 5, moveRange = 3, attacks = "warrior" },
    [31] = { type = "character", name = "Mage",    isPlayable = true,  maxHealth = 3, moveRange = 4, attacks = "mage" },
    [30] = { type = "character", name = "Rogue",   isPlayable = true,  maxHealth = 4, moveRange = 5, attacks = "rogue" },
    [26] = { type = "character", name = "Ghost",   isPlayable = false, maxHealth = 3, moveRange = 1, attacks = "ghost" },
    [25] = { type = "character", name = "Zombie",  isPlayable = false, maxHealth = 3, moveRange = 2, attacks = "zombie" },
    [27] = { type = "character", name = "Lich",    isPlayable = false, maxHealth = 2, moveRange = 1, attacks = "lich" },
    [11] = { type = "obstacle",  name = "SuperMountain", health = 999 },
    [12] = { type = "building",  name = "SmallBuilding", health = 1, globalHealthCost = 1 },
    [7] = { type = "building",  name = "BigBuilding",   health = 2, globalHealthCost = 2 },
}

environment.enemySpriteCache = {}


local terrainSpriteCache = {}  -- Кэш для текстур terrain

-- Загрузка текстуры terrain из GID
local function loadTerrainSprite(map, gid, tileWidth, tileHeight)
    if terrainSpriteCache[gid] then
        return terrainSpriteCache[gid]
    end
    
    local texture = nil
    local quad = nil
    
    
    -- Ищем нужный тайлсет
    for _, tileset in ipairs(map.tilesets) do
        local firstGid = tileset.firstgid
        local lastGid = firstGid + (tileset.tilecount or 1) - 1
        if gid >= firstGid and gid <= lastGid then
            local localId = gid - firstGid
            
            texture = tileset.image or tileset.texture
            if not texture then
                print("Warning: No texture for tileset with firstgid", firstGid)
                return nil
            end
            
            local tw = tileset.tilewidth or tileWidth
            local th = tileset.tileheight or tileHeight
            local cols = tileset.columns or math.floor(tileset.imagewidth / tw)
            local row = math.floor(localId / cols)
            local col = localId % cols
            
            quad = love.graphics.newQuad(col * tw, row * th, tw, th, 
                                         tileset.imagewidth, tileset.imageheight)
            break
        end
    end
    
    if not texture or not quad then
        return nil
    end
    
    -- 👇 СМЕЩЕНИЯ ПРИ РИСОВАНИИ НА CANVAS
    local drawOffsetX = 1   -- смещение по X при рисовании на canvas
    local drawOffsetY = -4   -- смещение по Y при рисовании на canvas
    
    local canvas = love.graphics.newCanvas(tileWidth, tileHeight)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(texture, quad, drawOffsetX, drawOffsetY)  -- 👈 смещение здесь
    love.graphics.setCanvas()
    
    terrainSpriteCache[gid] = canvas
    return canvas
end

-- Кэш для загруженных текстур
local spriteCache = {}

-- Загрузка текстуры из тайлсета (без использования map:getTile)
local function loadTileSprite(map, gid, tileWidth, tileHeight)
    if spriteCache[gid] then
        return spriteCache[gid]
    end
    
    local texture = nil
    local quad = nil
    
    -- Ищем нужный тайлсет
    for _, tileset in ipairs(map.tilesets) do
        local firstGid = tileset.firstgid
        local lastGid = firstGid + (tileset.tilecount or 1) - 1
        if gid >= firstGid and gid <= lastGid then
            local localId = gid - firstGid
            
            -- Получаем текстуру (изображение тайлсета)
            texture = tileset.image  -- В STI это уже объект love Image
            if not texture then
                texture = tileset.texture
            end
            
            if not texture then
                print("Warning: No texture for tileset with firstgid", firstGid)
                return nil
            end
            
            -- Вычисляем координаты тайла в тайлсете
            local tw = tileset.tilewidth or tileWidth
            local th = tileset.tileheight or tileHeight
            local cols = tileset.columns or math.floor(tileset.imagewidth / tw)
            local row = math.floor(localId / cols)
            local col = localId % cols
            
            quad = love.graphics.newQuad(col * tw, row * th, tw, th, 
                                         tileset.imagewidth, tileset.imageheight)
            break
        end
    end
    
    if not texture or not quad then
        print("Warning: Could not extract tile for GID", gid)
        return nil
    end
    
    -- Создаём canvas с тайлом
    local canvas = love.graphics.newCanvas(tileWidth, tileHeight)
    canvas:setFilter("nearest", "nearest")  -- ← Отключает сглаживание
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(texture, quad, 0, 0)
    love.graphics.setCanvas()
    
    spriteCache[gid] = canvas
    return canvas
end

-- Создание сущности с текстурой из тайлсета
local function createEntityFromGID(map, gid, gridX, gridY)
    local def = gidToEntity[gid]
    if not def then return nil end

    local tileWidth = map.tilewidth or 32
    local tileHeight = map.tileheight or 32
    local entitySprite = loadTileSprite(map, gid, tileWidth, tileHeight)
    
    -- Fallback, если не удалось загрузить спрайт
    if not entitySprite then
        local canvas = love.graphics.newCanvas(tileWidth, tileHeight)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        -- Цвет для отладки
        if def.isPlayable ~= nil then
            love.graphics.setColor(def.isPlayable and {0.2, 0.6, 0.2, 1} or {0.8, 0.2, 0.2, 1})
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.circle("fill", tileWidth/2, tileHeight/2, tileWidth/2 - 2)
        love.graphics.setCanvas()
        entitySprite = canvas
    end

    if def.type == "character" then
        local attacks = {}
        if def.attacks == "warrior" then
            attacks = environment.getWarriorAttacks()
        elseif def.attacks == "mage" then
            attacks = environment.getMageAttacks()
        elseif def.attacks == "rogue" then
            attacks = environment.getRogueAttacks()
        elseif def.attacks == "lich" then
            attacks = environment.getLichAttacks()
        elseif def.attacks == "ghost" then
            attacks = environment.getGhostAttacks()
        elseif def.attacks == "zombie" then
            attacks = environment.getZombieAttacks()
        else
            attacks = {}
        end

        local actor = Entity.new(
            def.name, Entity.TYPES.CHARACTER, gridX, gridY,
            def.maxHealth, def.isPlayable, def.moveRange,
            nil, nil, attacks
        )
        actor.sprite = entitySprite
        if not def.isPlayable then
            environment.enemySpriteCache[def.name] = entitySprite
        end
        return actor

    elseif def.type == "obstacle" then
        local obstacle = Entity.new(def.name, Entity.TYPES.OBSTACLE, gridX, gridY, def.health, false, 0, nil, nil, {})
        obstacle.sprite = entitySprite
        return obstacle
    elseif def.type == "building" then
        local building = Entity.new(def.name, Entity.TYPES.BUILDING, gridX, gridY, def.health, false, 0, nil, nil, {})
        building.globalHealthCost = def.globalHealthCost
        building.sprite = entitySprite
        return building
    end
    return nil
end

-- environment.lua (фрагмент loadMapFromTiled)
function environment.loadMapFromTiled(filePath)
    print("\n=== LOADING MAP: " .. filePath .. " ===")

    local file = love.filesystem.getInfo(filePath)
    if not file then error("File not found: " .. filePath) end

    local map = sti(filePath)
    local width, height = map.width, map.height

    -- Создаём карту terrain и текстур только для активных клеток шестиугольника
    local terrainMap = {}
    local terrainTextures = {}
    local entities = {}
    local walkable = {}

    -- Временно создаём hex-объект для проверки isActiveHex (позже он будет пересоздан в main)
    -- Но нам нужны координаты, поэтому используем временный hex с теми же размерами
    local tempHex = require("hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R
    )
    -- Центр шестиугольника предполагается в (5,5) при width=11, height=11
    -- Функция isActiveHex использует жёстко заданный центр 5,5, что корректно только для карты 11x11.
    -- Если карта другого размера, нужно вычислять центр динамически. Оставим как есть, т.к. в проекте 11x11.

    -- Находим слой terrain
    local groundLayer = nil
    for _, layer in ipairs(map.layers) do
        if layer.name == "terrain" and layer.type == "tilelayer" then
            groundLayer = layer
            break
        end
    end
    if not groundLayer then error("'terrain' layer not found!") end

    local rawData = groundLayer.data
    for y = 1, height do
        for x = 1, width do
            local gid = nil
            if type(rawData) == "table" then
                if rawData[y] then
                    if type(rawData[y]) == "table" then
                        if rawData[y][x] then
                            if type(rawData[y][x]) == "table" and rawData[y][x].gid then
                                gid = rawData[y][x].gid
                            elseif type(rawData[y][x]) == "number" then
                                gid = rawData[y][x]
                            end
                        end
                    elseif type(rawData[y]) == "number" then
                        local idx = (y-1) * width + x
                        gid = rawData[idx]
                    end
                end
            end
            
            if gid and gid > 0 then
                local gridX = x - 1
                local gridY = y - 1
                -- ИЗМЕНЕНО: проверяем, активна ли клетка в шестиугольнике
                if tempHex:isActiveHex(gridX, gridY) then
                    local terrainType = gidToTerrain[gid] or "grass"
                    if not terrainMap[gridX] then terrainMap[gridX] = {} end
                    if not terrainTextures[gridX] then terrainTextures[gridX] = {} end
                    
                    terrainMap[gridX][gridY] = terrainType
                    
                    local tileWidth = map.tilewidth or 32
                    local tileHeight = map.tileheight or 32
                    local texture = loadTerrainSprite(map, gid, tileWidth, tileHeight)
                    terrainTextures[gridX][gridY] = texture
                end
            end
        end
    end

    -- Загружаем entities только на активных клетках
    local objectsLayer = nil
    for _, layer in ipairs(map.layers) do
        if layer.name == "entities" and layer.type == "tilelayer" then
            objectsLayer = layer
            break
        end
    end
    
    if objectsLayer then
        local objData = objectsLayer.data
        for y = 1, height do
            for x = 1, width do
                local gid = nil
                if type(objData) == "table" then
                    if objData[y] then
                        if type(objData[y]) == "table" then
                            if objData[y][x] then
                                if type(objData[y][x]) == "table" and objData[y][x].gid then
                                    gid = objData[y][x].gid
                                elseif type(objData[y][x]) == "number" then
                                    gid = objData[y][x]
                                end
                            end
                        elseif type(objData[y]) == "number" then
                            local idx = (y-1) * width + x
                            gid = objData[idx]
                        end
                    end
                end
                
                if gid and gid > 0 then
                    local gridX = x - 1
                    local gridY = y - 1
                    -- ИЗМЕНЕНО: создаём сущность только на активной клетке
                    if tempHex:isActiveHex(gridX, gridY) then
                        local entity = createEntityFromGID(map, gid, gridX, gridY)
                        if entity then
                            table.insert(entities, entity)
                            print(string.format("  Created %s at grid(%d,%d)", entity.name, gridX, gridY))
                        elseif not gidToEntity[gid] then
                            print(string.format("  Warning: Unknown entity GID %d at grid(%d,%d)", gid, gridX, gridY))
                        end
                    end
                end
            end
        end
    end

    -- Загрузка статусов со слоя "status" (аналогично фильтруем по isActiveHex)
    local statusLayer = nil
    for _, layer in ipairs(map.layers) do
        if layer.name == "status" and layer.type == "tilelayer" then
            statusLayer = layer
            break
        end
    end

    local hexStatuses = {}
    if statusLayer then
        local statusData = statusLayer.data
        for y = 1, height do
            for x = 1, width do
                local gid = nil
                if type(statusData) == "table" then
                    if statusData[y] then
                        if type(statusData[y]) == "table" then
                            if statusData[y][x] then
                                if type(statusData[y][x]) == "table" and statusData[y][x].gid then
                                    gid = statusData[y][x].gid
                                elseif type(statusData[y][x]) == "number" then
                                    gid = statusData[y][x]
                                end
                            end
                        elseif type(statusData[y]) == "number" then
                            local idx = (y-1) * width + x
                            gid = statusData[idx]
                        end
                    end
                end
                if gid and gid > 0 then
                    local gridX = x - 1
                    local gridY = y - 1
                    if tempHex:isActiveHex(gridX, gridY) then
                        local statusType = status.gidToStatus[gid]
                        if statusType then
                            local key = gridX .. "," .. gridY
                            if not hexStatuses[key] then hexStatuses[key] = {} end
                            table.insert(hexStatuses[key], statusType)
                            print(string.format("  Status %s at (%d,%d)", statusType, gridX, gridY))
                        end
                    end
                end
            end
        end
    end

    -- Сохраняем карту и текстуры для отрисовки
    environment.loadedMap = map
    environment.terrainTextures = terrainTextures

    print("\n--- LOADING COMPLETE ---")
    print(string.format("Active terrain cells: %d", (function() local count = 0 for _,row in pairs(terrainMap) do for _ in pairs(row) do count = count + 1 end end return count end)()))
    print(string.format("Entities loaded: %d", #entities))

    return terrainMap, entities, width, height, hexStatuses, walkable
end

-- Функции атак (без изменений)
function environment.getWarriorAttacks()
    local combat = require("combat")
    return {
        { attack = combat.DashAttack.new(), name = "Dash", description = "Charge and push" },
        { attack = combat.FlipAttack.new(), name = "Flip", description = "Flip enemy behind" },
    }
end

function environment.getMageAttacks()
    local combat = require("combat")
    return {
        { attack = combat.AoePushAttack.new(), name = "Stone Throw", description = "Throw a stone that pushes enemies around" },
        { attack = combat.AoeDirectionalAttack.new(), name = "Shockwave", description = "Deals 1 damage and pushes 3 enemies in a cone" },
    }
end

function environment.getRogueAttacks()
    local combat = require("combat")
    return {
        { attack = combat.ShootAttack.new(), name = "Shoot", description = "Shoot and push first enemy" },
        { attack = combat.PiercingShootAttack.new(5), name = "Piercing Shot", description = "Shoot through first enemy, hit and push the second" },
    }
end

function environment.getGhostAttacks()
    local combat = require("combat")
    return {
        { attack = combat.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, 2 damage" },
    }
end

function environment.getZombieAttacks()
    local combat = require("combat")
    return {
        { attack = combat.ZombieBiteAttack.new(), name = "Bite", description = "Melee attack, 3 damage" },
    }
end

-- Добавить функцию getLichAttacks()
function environment.getLichAttacks()
    local combat = require("combat")
    return {
        { attack = combat.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any target cell, ignores obstacles" },
    }
end

function environment.createEnemyByType(enemyType, q, r)
    local Entity = require("entity")
    local attacks = {}
    local name = ""
    local maxHealth = 3
    local moveRange = 2

    if enemyType == "Ghost" then
        attacks = environment.getGhostAttacks()
        name = "Ghost"
        maxHealth = 3
        moveRange = 1
    elseif enemyType == "Zombie" then
        attacks = environment.getZombieAttacks()
        name = "Zombie"
        maxHealth = 3
        moveRange = 2
    elseif enemyType == "Lich" then
        attacks = environment.getLichAttacks()
        name = "Lich"
        maxHealth = 2
        moveRange = 1
    else
        attacks = environment.getZombieAttacks()
        name = "Zombie"
        maxHealth = 3
        moveRange = 2
    end

    local sprite = environment.enemySpriteCache[enemyType]
    if not sprite then
        -- Fallback: создаём цветной круг (на случай, если спрайт не загрузился)
        local size = 64
        local canvas = love.graphics.newCanvas(size, size)
        canvas:setFilter("nearest", "nearest")
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        if enemyType == "Ghost" then
            love.graphics.setColor(0.7, 0.3, 1, 1)
        elseif enemyType == "Zombie" then
            love.graphics.setColor(0.3, 0.7, 0.2, 1)
        elseif enemyType == "Lich" then
            love.graphics.setColor(0.8, 0.2, 0.8, 1)
        else
            love.graphics.setColor(1, 0.5, 0, 1)
        end
        love.graphics.circle("fill", size/2, size/2, size/2 - 4)
        love.graphics.setCanvas()
        sprite = canvas
    end

    local entity = Entity.new(name, Entity.TYPES.CHARACTER, q, r, maxHealth, false, moveRange, sprite, nil, attacks)
    return entity
end

-- Создать случайного врага (из пула)
function environment.createRandomEnemy(q, r)
    local types = { "Ghost", "Zombie", "Lich" }
    local rnd = love.math.random(1, #types)
    return environment.createEnemyByType(types[rnd], q, r)
end

return environment