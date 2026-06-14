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
    [34] = { type = "character", name = "Warrior", isPlayable = true,  maxHealth = 2, moveRange = 3, attacks = "warrior" },
    [31] = { type = "character", name = "Mage",    isPlayable = true,  maxHealth = 2, moveRange = 4, attacks = "mage" },
    [30] = { type = "character", name = "Rogue",   isPlayable = true,  maxHealth = 2, moveRange = 5, attacks = "rogue" },
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
    [17] = { type = "obstacle",  name = "DeepWater", isHazard = true },
    [12] = { type = "building",  name = "SmallBuilding", health = 1 },
    [7] = { type = "building",  name = "BigBuilding",   health = 2 },
    [6] = { type = "obstacle",  name = "WeakMountain",  health = 2, maxDamagePerHit = 1 },
    [59] = { type = "building", name = "Ship",          health = 1, moveRange = 1, waterWalker = true },
    [29] = { type = "building", name = "Tower",         health = 1, isObjective = true },
    [60] = { type = "character", name = "Brute",    isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "brute" },
    [62] = { type = "character", name = "Lancer",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "lancer" },
    [80] = { type = "character", name = "BogShaman", isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "bogshaman" },
    [23] = { type = "character", name = "Raider",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "raider" },
    [28] = { type = "character", name = "Dervish",  isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "dervish" },
    [66] = { type = "character", name = "Crusher",  isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "crusher" },
    [83] = { type = "character", name = "SummoningRod", isPlayable = false, maxHealth = 2, moveRange = 0, attacks = "summoningrod" },
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
    
    --  СМЕЩЕНИЯ ПРИ РИСОВАНИИ НА CANVAS
    local drawOffsetX = 1   -- смещение по X при рисовании на canvas
    local drawOffsetY = -4   -- смещение по Y при рисовании на canvas
    
    local canvas = love.graphics.newCanvas(tileWidth, tileHeight)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(texture, quad, drawOffsetX, drawOffsetY)  --  смещение здесь
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

-- Генерация самописных спрайтов для гор и построек
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

    elseif name == "Ship" then
        love.graphics.setColor(0.5, 0.35, 0.2)
        love.graphics.polygon("fill", 1, h-2, w/3, h-6, w*2/3, h-6, w-1, h-2)
        love.graphics.setColor(0.4, 0.25, 0.1)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.55, 0.4, 0.25)
        love.graphics.rectangle("fill", w/3, h-6, w/3, h-8)
        love.graphics.setColor(0.95, 0.95, 1)
        love.graphics.polygon("fill", w*2/3-1, h-8, w*2/3-1, h-6, w-1, h-6)

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
    elseif name == "MountainSlope" then
        love.graphics.setColor(0.55, 0.5, 0.45)
        love.graphics.polygon("fill", 0, h, w*0.6, h*0.2, w, h)
        love.graphics.setColor(0.65, 0.6, 0.55)
        love.graphics.polygon("fill", 0, h, w*0.6, h*0.2, w*0.6, h)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
    elseif name == "DeepWater" then
        love.graphics.setColor(0.1, 0.1, 0.4, 1)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(0.2, 0.2, 0.6, 0.6)
        love.graphics.ellipse("fill", w*0.3, h*0.3, w*0.2, h*0.1)

    end

    love.graphics.setCanvas()
    return canvas
end

-- Создание сущности с текстурой из тайлсета
local function createEntityFromGID(map, gid, gridX, gridY)
    local def = gidToEntity[gid]
    if not def then return nil end

    local tileWidth = map.tilewidth or 32
    local tileHeight = map.tileheight or 32
    local entitySprite

        if def.name == "SuperMountain" or def.name == "WeakMountain" or def.name == "SmallBuilding" or def.name == "BigBuilding" or def.name == "Ship" or def.name == "Tower" or def.name == "MountainSlope" or def.name == "DeepWater" then
        entitySprite = generateCustomSprite(def.name, tileWidth, tileHeight)
    else
        entitySprite = loadTileSprite(map, gid, tileWidth, tileHeight)
    end
    
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
        elseif def.attacks == "summoner" then
            attacks = environment.getSummonerAttacks()
        elseif def.attacks == "summoned" then
            attacks = environment.getSummonedAttacks()
        elseif def.attacks == "divider" then
            attacks = environment.getDividerAttacks()
        elseif def.attacks == "none" then
            attacks = environment.getNoneAttacks()
        elseif def.attacks == "all" then
            attacks = environment.getAllAttacks()
        elseif def.attacks == "brute" then
            attacks = environment.getBruteAttacks()
        elseif def.attacks == "lancer" then
            attacks = environment.getLancerAttacks()
        elseif def.attacks == "bogshaman" then
            attacks = environment.getBogShamanAttacks()
        elseif def.attacks == "raider" then
            attacks = environment.getRaiderAttacks()
        elseif def.attacks == "dervish" then
            attacks = environment.getDervishAttacks()
        elseif def.attacks == "crusher" then
            attacks = environment.getCrusherAttacks()
        elseif def.attacks == "summoningrod" then
            attacks = environment.getSummoningRodAttacks()
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
        if def.name == "SummoningRod" then
            actor.isSummoningRod = true
            actor.isPushable = false
            actor.moveRange = 0
        end
        if def.name == "Ghost" then
            actor.flying = true
        end
        -- Ауры для врагов
        if def.attacks == "bogshaman" then
            actor.aura = { type = "slow", radius = 1 }
        end
        return actor

    elseif def.type == "obstacle" then
        local health = def.health or 999
        local obstacle = Entity.new(def.name, Entity.TYPES.OBSTACLE, gridX, gridY, health, false, 0, nil, nil, {})
        obstacle.sprite = entitySprite
        if def.maxDamagePerHit then obstacle.maxDamagePerHit = def.maxDamagePerHit end
        if def.indestructible then obstacle.indestructible = true end
        if def.noCollisionDamage then obstacle.noCollisionDamage = true end
        if def.isHazard then obstacle.isHazard = true end
        if def.direction then obstacle.direction = def.direction end
        return obstacle
    elseif def.type == "building" then
        local building = Entity.new(def.name, Entity.TYPES.BUILDING, gridX, gridY, def.health, false, (def.moveRange or 0), nil, nil, {})
        if def.waterWalker then building.waterWalker = true end
        if def.isObjective then building.isObjective = true end
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

    local tempHex = require("hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R
    )

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

    -- Сохраняем карту и текстуры для отрисовки
    environment.loadedMap = map
    environment.terrainTextures = terrainTextures

    print("\n--- LOADING COMPLETE ---")
    print(string.format("Active terrain cells: %d", (function() local count = 0 for _,row in pairs(terrainMap) do for _ in pairs(row) do count = count + 1 end end return count end)()))
    print(string.format("Entities loaded: %d", #gameEntities))
    print(string.format("Allies for deploy: %d", #deployableAllies))

    return terrainMap, gameEntities, width, height, hexStatuses, walkable, deployableAllies
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
        { attack = combat.AoeDirectionalAttack.new(), name = "Shockwave", description = "Pushes all 6 surrounding enemies away from the center" },
    }
end

function environment.getRogueAttacks()
    local combat = require("combat")
    return {
        { attack = combat.ShootAttack.new(), name = "Shoot", description = "Shoot and push first enemy" },
        { attack = combat.PiercingShootAttack.new(), name = "Piercing Shot", description = "Shoot through first enemy, hit and push the second" },
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

function environment.getNoneAttacks()
    return {}
end

function environment.getAllAttacks()
    local combat = require("combat")
    return {
        { attack = combat.DashAttack.new(), name = "Dash", description = "Charge and push" },
        { attack = combat.FlipAttack.new(), name = "Flip", description = "Flip enemy behind" },
        { attack = combat.ShootAttack.new(), name = "Shoot", description = "Shoot and push first enemy" },
        { attack = combat.PushAttack.new(5), name = "Push", description = "Push first enemy in line (no damage)" },
        { attack = combat.PiercingShootAttack.new(), name = "Piercing Shot", description = "Shoot through first enemy, hit and push the second" },
        { attack = combat.AoePushAttack.new(), name = "Stone Throw", description = "Throw a stone that pushes enemies around" },
        { attack = combat.AoeDirectionalAttack.new(), name = "Shockwave", description = "Pushes all 6 surrounding enemies away from the center" },
        { attack = combat.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any target cell, ignores obstacles" },
        { attack = combat.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, 2 damage" },
        { attack = combat.ZombieBiteAttack.new(), name = "Bite", description = "Melee attack, 3 damage" },
        { attack = combat.SummonAttack.new(), name = "Summon", description = "Summon a minion at target cell" },
        { attack = combat.DividerAttack.new(), name = "Split", description = "Split into two Divided units" },
        { attack = combat.VortexStrikeAttack.new(), name = "Vortex Strike", description = "Shift an enemy right or left and deal 1 damage" },
        { attack = combat.WideVortexAttack.new(), name = "Wide Vortex", description = "Shift 3 enemies in front right or left" },
        { attack = combat.PullHookAttack.new(), name = "Pull Hook", description = "Hook a target and pull it towards you" },
        { attack = combat.ElectricHookAttack.new(), name = "Electric Hook", description = "Arc lightning that damages everyone on the line" },
        { attack = combat.BashAttack.new(), name = "Bash", description = "Melee 2 dmg to target and behind attacker" },
        { attack = combat.CleaveAttack.new(), name = "Cleave", description = "Melee 1 dmg to 3 targets in front" },
        { attack = combat.LungeAttack.new(), name = "Lunge", description = "Melee 2 dmg to target and target behind it" },
        { attack = combat.HeavyPunchAttack.new(), name = "Heavy Punch", description = "Melee 2 dmg and push target away" },
        { attack = combat.EmpowerPunchAttack.new(), name = "Empower Punch", description = "Melee 1 dmg, push target, double next attack damage" },
    }
end

function environment.getDividerAttacks()
    local combat = require("combat")
    return {
        { attack = combat.DividerAttack.new(), name = "Split", description = "Split into two Divided units" },
    }
end

function environment.getSummonerAttacks()
    local combat = require("combat")
    return {
        { attack = combat.SummonAttack.new(), name = "Summon", description = "Summon a minion at target cell (min 2)" },
    }
end

function environment.getBruteAttacks()
    local combat = require("combat")
    return {
        { attack = combat.BashAttack.new(), name = "Bash", description = "Melee 2 dmg to target and behind attacker" },
    }
end

function environment.getDervishAttacks()
    local combat = require("combat")
    return {
        { attack = combat.CleaveAttack.new(), name = "Cleave", description = "Melee 1 dmg to 3 targets in front" },
    }
end

function environment.getRaiderAttacks()
    local combat = require("combat")
    return {
        { attack = combat.LungeAttack.new(), name = "Lunge", description = "Melee 2 dmg to target and target behind it" },
    }
end

function environment.getCrusherAttacks()
    local combat = require("combat")
    return {
        { attack = combat.BashAttack.new(), name = "Bash", description = "Melee 2 dmg to target and behind attacker" },
    }
end

function environment.getSummoningRodAttacks()
    local combat = require("combat")
    return {
        { attack = combat.SummonEnemyAttack.new(), name = "Summon", description = "Summon a random enemy" },
    }
end

function environment.getLancerAttacks()
    local combat = require("combat")
    return {
        { attack = combat.LungeAttack.new(), name = "Lunge", description = "Melee 2 dmg to target and target behind it" },
    }
end

function environment.getBogShamanAttacks()
    local combat = require("combat")
    return {
        { attack = combat.ZombieBiteAttack.new(), name = "Bite", description = "Melee attack, 3 damage" },
    }
end

function environment.getSummonedAttacks()
    local combat = require("combat")
    return {
        { attack = combat.PushAttack.new(5), name = "Shoot", description = "Push first enemy in line (no damage)" },
    }
end

local unitSpriteCache = {}
environment.unitSpriteCache = unitSpriteCache

function environment.loadUnitSprites()
    local workaroundPath = "maps/units_workaround.lua"
    local info = love.filesystem.getInfo(workaroundPath)
    if not info then
        print("No units_workaround.lua found, squad units will use fallback colors")
        return
    end
    local map = sti(workaroundPath)
    local tileWidth = map.tilewidth or 16
    local tileHeight = map.tileheight or 16

    local entitiesTileset = nil
    for _, ts in ipairs(map.tilesets) do
        if ts.name == "entities" then
            entitiesTileset = ts
            break
        end
    end

    if entitiesTileset then
        local firstGid = entitiesTileset.firstgid
        local lastGid = firstGid + (entitiesTileset.tilecount or 1) - 1
        print("=== All entity GIDs from workaround ===")
        for gid = firstGid, lastGid do
            local sprite = loadTileSprite(map, gid, tileWidth, tileHeight)
            local def = gidToEntity[gid]
            local name = def and def.name or "nil"
            local info = def and string.format("type=%s hp=%s", def.type, def.maxHealth or def.health or "?") or ""
            if sprite then
                unitSpriteCache[gid] = sprite
                print(string.format("  [OK]   GID %3d -> %-20s %s", gid, name, info))
            else
                print(string.format("  [FAIL] GID %3d -> %-20s (no sprite)", gid, name, info))
            end
        end
    end

    print("=== Tile positions on workaround map ===")
    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" then
            local data = layer.data
            print(string.format("  Layer '%s' (%d x %d):", layer.name, layer.width, layer.height))
            for y = 1, layer.height do
                for x = 1, layer.width do
                    local gid = nil
                    if type(data) == "table" then
                        if data[y] then
                            if type(data[y]) == "table" then
                                if data[y][x] then
                                    if type(data[y][x]) == "table" and data[y][x].gid then
                                        gid = data[y][x].gid
                                    elseif type(data[y][x]) == "number" then
                                        gid = data[y][x]
                                    end
                                end
                            elseif type(data[y]) == "number" then
                                local idx = (y - 1) * layer.width + x
                                gid = data[idx]
                            end
                        end
                    end
                    if gid and gid > 0 then
                        local def = gidToEntity[gid]
                        local name = def and def.name or (gid < 21 and "terrain" or "entity")
                        print(string.format("    (%d,%d) -> GID %d (%s)", x-1, y-1, gid, name))
                    end
                end
            end
        end
    end
end

function environment.createSquadUnit(unitDef, q, r)
    local Entity = require("entity")
    local attacks = {}
    if unitDef.attacks == "warrior" then
        attacks = environment.getWarriorAttacks()
    elseif unitDef.attacks == "mage" then
        attacks = environment.getMageAttacks()
    elseif unitDef.attacks == "rogue" then
        attacks = environment.getRogueAttacks()
    elseif unitDef.attacks == "summoner" then
        attacks = environment.getSummonerAttacks()
    elseif unitDef.attacks == "divider" then
        attacks = environment.getDividerAttacks()
    elseif unitDef.attacks == "all" then
        attacks = environment.getAllAttacks()
    end

    local nameToGid = {
        Warrior = 34, Mage = 31, Rogue = 30,
        Summoner = 40, Divider = 45, Summoned = 42, Divided = 44,
        AttackTest = 68,
    }
    local gid = nameToGid[unitDef.name]
    local sprite = gid and unitSpriteCache[gid] or nil

    local colors = {
        Warrior = {0.8, 0.3, 0.2},
        Mage = {0.2, 0.5, 0.8},
        Rogue = {0.2, 0.8, 0.3},
        Summoner = {0.8, 0.2, 0.8},
        Divider = {0.9, 0.7, 0.1},
        Summoned = {0.6, 0.3, 0.9},
        Divided = {0.6, 0.4, 0.1},
        AttackTest = {0.2, 0.9, 0.9},
    }

    return Entity.new(
        unitDef.name, Entity.TYPES.CHARACTER, q, r,
        unitDef.maxHealth, true, unitDef.moveRange,
        sprite, sprite and nil or (colors[unitDef.name] or {0.5, 0.5, 0.5}),
        attacks
    )
end

function environment.createEnemyByType(enemyType, q, r)
    local Entity = require("entity")
    local attacks = {}
    local name = ""
    local maxHealth = 2
    local moveRange = 2
    local hasAura = nil

    if enemyType == "Ghost" then
        attacks = environment.getGhostAttacks()
        name = "Ghost"
        moveRange = 3
    elseif enemyType == "Zombie" then
        attacks = environment.getZombieAttacks()
        name = "Zombie"
        moveRange = 3
    elseif enemyType == "PoisonousZombie" then
        attacks = environment.getZombieAttacks()
        name = "PoisonousZombie"
        moveRange = 3
    elseif enemyType == "Lich" then
        attacks = environment.getLichAttacks()
        name = "Lich"
        moveRange = 3
    elseif enemyType == "Brute" then
        attacks = environment.getBruteAttacks()
        name = "Brute"
        moveRange = 2
    elseif enemyType == "Lancer" then
        attacks = environment.getLancerAttacks()
        name = "Lancer"
        moveRange = 3
    elseif enemyType == "BogShaman" then
        attacks = environment.getBogShamanAttacks()
        name = "BogShaman"
        moveRange = 2
        hasAura = { type = "slow", radius = 1 }
    elseif enemyType == "Raider" then
        attacks = environment.getRaiderAttacks()
        name = "Raider"
        moveRange = 3
    elseif enemyType == "Dervish" then
        attacks = environment.getDervishAttacks()
        name = "Dervish"
        moveRange = 3
    elseif enemyType == "Crusher" then
        attacks = environment.getCrusherAttacks()
        name = "Crusher"
        moveRange = 2
    elseif enemyType == "SummoningRod" then
        attacks = environment.getSummoningRodAttacks()
        name = "SummoningRod"
        moveRange = 0
    else
        attacks = environment.getZombieAttacks()
        name = "Zombie"
        moveRange = 3
    end

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
        else
            love.graphics.setColor(1, 0.5, 0, 1)
            love.graphics.circle("fill", size/2, size/2, size/2 - 1)
        end
        love.graphics.setCanvas()
        sprite = canvas
    end

    local entity = Entity.new(name, Entity.TYPES.CHARACTER, q, r, maxHealth, false, moveRange, sprite, nil, attacks)
    if enemyType == "Ghost" then
        entity.flying = true
    end
    if hasAura then
        entity.aura = hasAura
    end
    if enemyType == "SummoningRod" then
        entity.isSummoningRod = true
        entity.isPushable = false
        entity.moveRange = 0
    end
    return entity
end

-- Создать случайного врага (из пула)
function environment.createRandomEnemy(q, r)
    local types = _G.playtestEnemyTypes or { "Ghost", "Zombie", "Lich", "Brute", "Lancer", "BogShaman", "Raider", "Dervish", "Crusher" }
    local rnd = love.math.random(1, #types)
    return environment.createEnemyByType(types[rnd], q, r)
end

function environment.generateBuildingSprite(name, w, h)
    return generateCustomSprite(name, w or 32, h or 32)
end

return environment