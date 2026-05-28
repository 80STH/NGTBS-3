-- environment.lua
local Entity = require("entity")
local sti = require("libraries.sti")

local environment = {}

-- Соответствие GID тайлов из тайлсета "hex mini" → тип местности
local gidToTerrain = {
    [1] = "grass",
    [2] = "dirt",
    [0] = "sand",
    [4] = "stone",
    [5] = "mud",
    [6] = "lava",
    [7] = "snow",
    [8] = "swamp",
    [13] = "water",
}

-- Соответствие GID из второго тайлсета ("wxtctr615cw31") → сущность
-- (замените ID и параметры под ваш фактический тайлсет)
local gidToEntity = {
    [21] = { type = "character", name = "Warrior",  isPlayable = true,  maxHealth = 5, moveRange = 3, attacks = "warrior" },
    [22] = { type = "character", name = "Mage",     isPlayable = true,  maxHealth = 3, moveRange = 4, attacks = "mage" },
    [23] = { type = "character", name = "Rogue",    isPlayable = true,  maxHealth = 4, moveRange = 5, attacks = "rogue" },
    [24] = { type = "character", name = "Goblin",   isPlayable = false, maxHealth = 3, moveRange = 3, attacks = "enemy" },
    [25] = { type = "obstacle",  name = "Rock",     health = 3 },
    [26] = { type = "obstacle",  name = "Tree",     health = 2 },
    [27] = { type = "building",  name = "Shrine",   health = 4, globalHealthCost = 1 },
}

-- Преобразование тайловых (x,y) в осевые координаты (q,r) для карты с настройками:
-- orientation = "hexagonal", staggeraxis = "y", staggerindex = "odd"
local function tileToAxial(x, y)
    local r = y
    local q = x - math.floor(y / 2)
    return q, r
end

-- Создание сущности по GID и координатам
local function createEntityFromGID(gid, q, r)
    local def = gidToEntity[gid]
    if not def then return nil end

    if def.type == "character" then
        -- Получение списка атак (можно вынести в отдельные функции)
        local attacks = {}
        if def.attacks == "warrior" then
            attacks = environment.getWarriorAttacks()  -- эти функции нужно определить
        elseif def.attacks == "mage" then
            attacks = environment.getMageAttacks()
        elseif def.attacks == "rogue" then
            attacks = environment.getRogueAttacks()
        else
            attacks = {} -- враг без атак (будет использовать базовую атаку из ai)
        end

        local actor = Entity.new(
            def.name,
            Entity.TYPES.CHARACTER,
            q, r,
            def.maxHealth,
            def.isPlayable,
            def.moveRange,
            nil,  -- спрайт будет создан позже
            nil,  -- цвет
            attacks
        )
        -- Создаём простой спрайт (круг) для отладки, в реальности можно подгрузить изображение
        local canvas = love.graphics.newCanvas(32, 32)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(def.isPlayable and {0.2, 0.6, 0.2, 1} or {0.8, 0.2, 0.2, 1})
        love.graphics.circle("fill", 16, 16, 14)
        love.graphics.setCanvas()
        actor.sprite = canvas
        return actor

    elseif def.type == "obstacle" then
        return Entity.new(
            def.name,
            Entity.TYPES.OBSTACLE,
            q, r,
            def.health,
            false, 0, nil, nil, {}
        )
    elseif def.type == "building" then
        local building = Entity.new(
            def.name,
            Entity.TYPES.BUILDING,
            q, r,
            def.health,
            false, 0, nil, nil, {}
        )
        building.globalHealthCost = def.globalHealthCost
        return building
    end
    return nil
end

-- Главная функция загрузки карты: возвращает terrainMap и список entities
function environment.loadMapFromTiled(filePath)
    local map = sti(filePath)
    local terrainMap = {}
    local entities = {}

    -- 1. Обработка слоя Ground
    local groundLayer = nil
    for _, layer in ipairs(map.layers) do
        if layer.name == "terrain" and layer.type == "tilelayer" then
            groundLayer = layer
            break
        end
    end
    if not groundLayer then
        error("'terrain' layer not found!")
    end

    local rawData = groundLayer.data
    local width = map.width
    local height = map.height

    for y = 1, height do
        for x = 1, width do
            local gid
            if type(rawData[y]) == "table" and type(rawData[y][x]) == "table" and rawData[y][x].gid then
                gid = rawData[y][x].gid
            else
                gid = rawData[y][x]
            end
            if gid and gid > 0 then
                local terrainType = gidToTerrain[gid] or "grass"
                local q, r = tileToAxial(x - 1, y - 1)
                if not terrainMap[q] then terrainMap[q] = {} end
                terrainMap[q][r] = terrainType
            end
        end
    end

    -- 2. Обработка слоя objects (tilelayer)
    local objectsLayer = nil
    for _, layer in ipairs(map.layers) do
        if layer.name == "objects" and layer.type == "tilelayer" then
            objectsLayer = layer
            break
        end
    end
    if objectsLayer then
        local objData = objectsLayer.data
        for y = 1, height do
            for x = 1, width do
                local gid
                if type(objData[y]) == "table" and type(objData[y][x]) == "table" and objData[y][x].gid then
                    gid = objData[y][x].gid
                else
                    gid = objData[y][x]
                end
                if gid and gid > 0 then
                    local q, r = tileToAxial(x - 1, y - 1)
                    local entity = createEntityFromGID(gid, q, r)
                    if entity then
                        table.insert(entities, entity)
                    end
                end
            end
        end
    end

    return terrainMap, entities
end

-- Вспомогательные функции для атак (пример – дополните по вашему желанию)
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
        { attack = combat.ShootAttack.new(5), name = "Shoot", description = "Push from distance" },
        { attack = combat.PiercingShootAttack.new(5), name = "Piercing Shot", description = "Hit two enemies" },
    }
end

function environment.getRogueAttacks()
    local combat = require("combat")
    return {
        { attack = combat.DashAttack.new(), name = "Dash", description = "Charge and push" },
        { attack = combat.AoePushAttack.new(), name = "Shockwave", description = "Push all around" },
    }
end

return environment