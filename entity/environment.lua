-- environment.lua
local Entity = require("entity.entity")
local sti = require("libraries.sti")
local config = require("core.config")
local log = require("util.log")

-- ============================================================
-- РЕЕСТР КОНТЕНТА: наборы атак и типы врагов.
-- Раньше было 19 функций get*Attacks() + длинные if/elseif
-- в трёх местах. Теперь — две таблицы.
-- ============================================================

-- Каждый набор — это функция, возвращающая список атак.
-- Фабрикой выступает combat (require внутри, чтобы разорвать цикл combat<->environment).
local ATTACK_SETS = {
    warrior = function()
        local c = require("combat.combat")
        return {
            { attack = c.DashAttack.new(), name = "Dash", description = "Charge and push" },
            { attack = c.FlipAttack.new(), name = "Flip", description = "Flip enemy behind" },
        }
    end,
    puncher = function()
        local c = require("combat.combat")
        return {
            { attack = c.HeavyPunchAttack.new(), name = "Heavy Punch", description = "Melee attack, 1 damage, pushes target away. Lethal if empowered" },
            { attack = c.EmpowerPunchAttack.new(), name = "Empower Punch", description = "Pushes target, doubles next attack damage. Deals 1 damage if empowered" },
        }
    end,
    rogue = function()
        local c = require("combat.combat")
        return {
            { attack = c.ShootAttack.new(), name = "Shoot", description = "Shoot and push first enemy" },
            { attack = c.PiercingShootAttack.new(), name = "Piercing Shot", description = "Shoot through first enemy, hit and push the second" },
        }
    end,
    ghost = function()
        local c = require("combat.combat")
        return {
            { attack = c.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, 2 damage" },
        }
    end,
    zombie = function()
        local c = require("combat.combat")
        return {
            { attack = c.ZombieBiteAttack.new(), name = "Bite", description = "Melee attack, 3 damage" },
        }
    end,
    lich = function()
        local c = require("combat.combat")
        return {
            { attack = c.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any target cell, ignores obstacles" },
        }
    end,
    powerlich = function()
        local c = require("combat.combat")
        return {
            { attack = c.PowerLichBoltAttack.new(), name = "Power Bolt", description = "Lethal bolt hitting target and 3 cells in front" },
        }
    end,
    summoner = function()
        local c = require("combat.combat")
        return {
            { attack = c.SummonAttack.new(), name = "Summon", description = "Summon a minion at target cell (min 2)" },
        }
    end,
    summoned = function()
        local c = require("combat.combat")
        return {
            { attack = c.PushAttack.new(5), name = "Shoot", description = "Push first enemy in line (no damage)" },
        }
    end,
    divider = function()
        local c = require("combat.combat")
        return {
            { attack = c.DividerAttack.new(), name = "Split", description = "Split into two Divided units" },
        }
    end,
    brute = function()
        local c = require("combat.combat")
        return {
            { attack = c.BashAttack.new(), name = "Bash", description = "Melee 2 dmg to target and behind attacker" },
        }
    end,
    dervish = function()
        local c = require("combat.combat")
        return {
            { attack = c.CleaveAttack.new(), name = "Cleave", description = "Melee 1 dmg to 3 targets in front" },
        }
    end,
    raider = function()
        local c = require("combat.combat")
        return {
            { attack = c.LungeAttack.new(), name = "Lunge", description = "Melee 2 dmg to target and target behind it" },
        }
    end,
    crusher = function()
        local c = require("combat.combat")
        return {
            { attack = c.BashAttack.new(), name = "Bash", description = "Melee 2 dmg to target and behind attacker" },
        }
    end,
    lancer = function()
        local c = require("combat.combat")
        return {
            { attack = c.LungeAttack.new(), name = "Lunge", description = "Melee 2 dmg to target and target behind it" },
        }
    end,
    bogshaman = function()
        local c = require("combat.combat")
        return {
            { attack = c.ZombieBiteAttack.new(), name = "Bite", description = "Melee attack, 3 damage" },
        }
    end,
    summoningrod = function()
        local c = require("combat.combat")
        return {
            { attack = c.SummonEnemyAttack.new(), name = "Summon", description = "Summon a random enemy" },
        }
    end,
    none = function()
        return {}
    end,
    all = function()
        local c = require("combat.combat")
        return {
            { attack = c.DashAttack.new(), name = "Dash", description = "Charge and push" },
            { attack = c.FlipAttack.new(), name = "Flip", description = "Flip enemy behind" },
            { attack = c.ShootAttack.new(), name = "Shoot", description = "Shoot and push first enemy" },
            { attack = c.PushAttack.new(5), name = "Push", description = "Push first enemy in line (no damage)" },
            { attack = c.PiercingShootAttack.new(), name = "Piercing Shot", description = "Shoot through first enemy, hit and push the second" },
            { attack = c.AoePushAttack.new(), name = "Stone Throw", description = "Throw a stone that pushes enemies around" },
            { attack = c.AoeDirectionalAttack.new(), name = "Shockwave", description = "Pushes all 6 surrounding enemies away from the center" },
            { attack = c.LichBoltAttack.new(5), name = "Magic Bolt", description = "Hits any target cell, ignores obstacles" },
            { attack = c.GhostBoltAttack.new(), name = "Ghost Bolt", description = "Piercing shot, unlimited range, 2 damage" },
            { attack = c.ZombieBiteAttack.new(), name = "Bite", description = "Melee attack, 3 damage" },
            { attack = c.SummonAttack.new(), name = "Summon", description = "Summon a minion at target cell" },
            { attack = c.DividerAttack.new(), name = "Split", description = "Split into two Divided units" },
            { attack = c.VortexStrikeAttack.new(), name = "Vortex Strike", description = "Shift an enemy right or left and deal 1 damage" },
            { attack = c.WideVortexAttack.new(), name = "Wide Vortex", description = "Shift 3 enemies in front right or left" },
            { attack = c.PullHookAttack.new(), name = "Pull Hook", description = "Hook a target and pull it towards you" },
            { attack = c.ElectricHookAttack.new(), name = "Electric Hook", description = "Arc lightning that damages everyone on the line" },
            { attack = c.BashAttack.new(), name = "Bash", description = "Melee 2 dmg to target and behind attacker" },
            { attack = c.CleaveAttack.new(), name = "Cleave", description = "Melee 1 dmg to 3 targets in front" },
            { attack = c.LungeAttack.new(), name = "Lunge", description = "Melee 2 dmg to target and target behind it" },
            { attack = c.HeavyPunchAttack.new(), name = "Heavy Punch", description = "Melee 2 dmg and push target away" },
            { attack = c.EmpowerPunchAttack.new(), name = "Empower Punch", description = "Melee 1 dmg, push target, double next attack damage" },
        }
    end,
}

-- Реестр типов врагов: имя -> спецификация.
-- Используется в createEnemyByType. Дополняет ATTACK_SETS
-- данными о health/moveRange/aura/флагах.
local ENEMY_TYPES = {
    Ghost           = { attackSet = "ghost",       moveRange = 3, flying = true },
    Zombie          = { attackSet = "zombie",      moveRange = 3 },
    PoisonousZombie = { attackSet = "zombie",      moveRange = 3 },
    Lich            = { attackSet = "lich",        moveRange = 3 },
    Brute           = { attackSet = "brute",       moveRange = 2 },
    Lancer          = { attackSet = "lancer",      moveRange = 3 },
    BogShaman       = { attackSet = "bogshaman",   moveRange = 2, aura = { type = "slow", radius = 1 } },
    Raider          = { attackSet = "raider",      moveRange = 3 },
    Dervish         = { attackSet = "dervish",     moveRange = 3 },
    Crusher         = { attackSet = "crusher",     moveRange = 2 },
    PowerLich       = { attackSet = "powerlich",   moveRange = 3, maxHealth = 6, hovering = true, healthCellSize = 3 },
    SummoningRod    = { attackSet = "summoningrod",moveRange = 0, isSummoningRod = true, isPushable = false },
}

local environment = {}

local gidToTerrain = {
    [3]  = "grass",
    [2]  = "dirt",
    [1]  = "sand",
    [4]  = "stone",
    [5]  = "emptiness",
    [6]  = "lava",
    [7]  = "snow",
    [8]  = "swamp",
    [14] = "water",
    [17] = "underwater_mines",
    [13] = "railway",
}

local gidToEntity = {
    [34] = { type = "character", name = "Warrior", isPlayable = true,  maxHealth = 2, moveRange = 3, attacks = "warrior" },
    [30] = { type = "character", name = "Puncher",  isPlayable = true,  maxHealth = 2, moveRange = 4, attacks = "puncher" },
    [31] = { type = "character", name = "Rogue",   isPlayable = true,  maxHealth = 2, moveRange = 5, attacks = "rogue" },
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
    -- [17] removed: DeepWater is now terrain "underwater_mines"
    [12] = { type = "building",  name = "SmallBuilding", health = 1 },
    [7] = { type = "building",  name = "BigBuilding",   health = 2 },
    [6] = { type = "obstacle",  name = "WeakMountain",  health = 2, maxDamagePerHit = 1 },

    [29] = { type = "building", name = "Tower",         health = 1, isObjective = true },
    [60] = { type = "character", name = "Brute",    isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "brute" },
    [62] = { type = "character", name = "Lancer",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "lancer" },
    [80] = { type = "character", name = "BogShaman", isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "bogshaman" },
    [23] = { type = "character", name = "Raider",   isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "raider" },
    [28] = { type = "character", name = "Dervish",  isPlayable = false, maxHealth = 2, moveRange = 3, attacks = "dervish" },
    [66] = { type = "character", name = "Crusher",  isPlayable = false, maxHealth = 2, moveRange = 2, attacks = "crusher" },
    [83] = { type = "character", name = "SummoningRod", isPlayable = false, maxHealth = 2, moveRange = 0, attacks = "summoningrod" },
    [48] = { type = "building",  name = "Caravan",   health = 1, moveRange = 1 },
    [77] = { type = "building",  name = "Blockpost", health = 2 },
    [67] = { type = "building",  name = "Tunnel",    health = 2, isObjective = true },
    [74] = { type = "building",  name = "TrainCar",  health = 1, moveRange = 1 },
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
                log.warnf("env", "Warning: No texture for tileset with firstgid %s", firstGid)
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
                log.warnf("env", "Warning: No texture for tileset with firstgid %s", firstGid)
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
        log.warnf("env", "Warning: Could not extract tile for GID %s", gid)
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

    elseif name == "OccupiedTunnel" then
        love.graphics.setColor(0.2, 0.1, 0.1)
        love.graphics.rectangle("fill", 0, 0, w, h-2)
        love.graphics.setColor(0.5, 0.2, 0.1)
        love.graphics.rectangle("fill", w/2-3, 0, 6, h-4)
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.6, 0.3, 0.15)
        love.graphics.arc("fill", w/2, h-2, w/3, math.pi, 0)
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.circle("fill", w/2, h/2-1, 2)

    elseif name == "Blockpost" then
        love.graphics.setColor(0.4, 0.3, 0.2)
        love.graphics.rectangle("fill", 0, 3, w, h-3)
        love.graphics.setColor(0.55, 0.45, 0.3)
        love.graphics.rectangle("fill", 0, 3, 2, h-3)
        love.graphics.rectangle("fill", w-2, 3, 2, h-3)
        love.graphics.setColor(0.6, 0.5, 0.35)
        love.graphics.rectangle("fill", 2, 0, w-4, 4)
        love.graphics.setColor(0.5, 0.4, 0.25)
        love.graphics.rectangle("fill", w/2-3, 0, 6, h)

    elseif name == "Tunnel" then
        love.graphics.setColor(0.15, 0.15, 0.15)
        love.graphics.rectangle("fill", 0, 0, w, h-2)
        love.graphics.setColor(0.6, 0.55, 0.5)
        love.graphics.rectangle("fill", w/2-1, 0, 2, h-2)
        love.graphics.setColor(0.25, 0.25, 0.25)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.arc("fill", w/2, h-2, w/3, math.pi, 0)

    elseif name == "DestroyedTunnel" then
        love.graphics.setColor(0.25, 0.22, 0.2)
        love.graphics.rectangle("fill", w/4, h/2-1, w/2, 3)
        love.graphics.setColor(0.35, 0.28, 0.22)
        love.graphics.rectangle("fill", w/3, h/2-4, w/3, 2)
        love.graphics.rectangle("fill", w/4+1, h/2+3, w/2-2, 2)
        love.graphics.setColor(0.2, 0.18, 0.18)
        love.graphics.rectangle("fill", w/3+1, h/2-2, 2, 6)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.rectangle("fill", w/3-2, h/2-2, 2, 3)

    elseif name == "Locomotive" then
        love.graphics.setColor(0.3, 0.15, 0.1)
        love.graphics.rectangle("fill", 1, 1, w-2, h-4)
        love.graphics.setColor(0.5, 0.2, 0.1)
        love.graphics.rectangle("fill", 1, 1, w-2, h-6)
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.rectangle("fill", w/2-3, 2, 6, 4)
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", 2, 6, w-4, 2)
        love.graphics.setColor(0.3, 0.1, 0.05)
        love.graphics.circle("fill", 2, h-1, 1.5)
        love.graphics.circle("fill", w-2, h-1, 1.5)

    elseif name == "TrainCar" then
        love.graphics.setColor(0.6, 0.2, 0.15)
        love.graphics.rectangle("fill", 1, 2, w-2, h-5)
        love.graphics.setColor(0.4, 0.12, 0.08)
        love.graphics.rectangle("fill", 0, 2, w, 2)
        love.graphics.setColor(0.8, 0.6, 0.4)
        love.graphics.rectangle("fill", 3, 3, 2, 3)
        love.graphics.rectangle("fill", w-5, 3, 2, 3)
        love.graphics.setColor(0.3, 0.1, 0.05)
        love.graphics.circle("fill", 2, h-1, 1.5)
        love.graphics.circle("fill", w-2, h-1, 1.5)

    elseif name == "MountainSlope" then
        love.graphics.setColor(0.55, 0.5, 0.45)
        love.graphics.polygon("fill", 0, h, w*0.6, h*0.2, w, h)
        love.graphics.setColor(0.65, 0.6, 0.55)
        love.graphics.polygon("fill", 0, h, w*0.6, h*0.2, w*0.6, h)
        love.graphics.setColor(0.4, 0.35, 0.3)
        love.graphics.rectangle("fill", 0, h-2, w, 2)
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

        if def.name == "SuperMountain" or def.name == "WeakMountain" or def.name == "SmallBuilding" or def.name == "BigBuilding" or def.name == "Tower" or def.name == "MountainSlope" or def.name == "Caravan" or def.name == "Blockpost" or def.name == "Tunnel" or def.name == "TrainCar" or def.name == "Locomotive" or def.name == "OccupiedTunnel" or def.name == "DestroyedTunnel" then
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
        local attacks = environment.getAttacks(def.attacks)

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
    log.infof("env", "=== LOADING MAP: %s ===", filePath)

    local file = love.filesystem.getInfo(filePath)
    if not file then error("File not found: " .. filePath) end

    local map = sti(filePath)
    local width, height = map.width, map.height

    local orientation = (map.staggeraxis == "x") and "flat" or "pointy"
    local hex_utils = require("grid.hex_utils")
    hex_utils.setOrientation(orientation)

    -- Создаём карту terrain и текстур только для активных клеток шестиугольника
    local terrainMap = {}
    local terrainTextures = {}
    local entities = {}
    local walkable = {}

    local tempHex = require("grid.hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R,
        orientation
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
    local terrainTypesFound = {}
    local unknownTerrainGids = {}

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
            if gid and gid > 0 then
                local tt = gidToTerrain[gid]
                if tt then
                    terrainTypesFound[tt] = true
                else
                    unknownTerrainGids[gid] = true
                end
            end
        end
    end

    local typesList = {}
    for t, _ in pairs(terrainTypesFound) do
        table.insert(typesList, t)
    end
    table.sort(typesList)
    log.debugf("env", "Terrain types found: %s", table.concat(typesList, ", "))

    local unknownList = {}
    for gid, _ in pairs(unknownTerrainGids) do
        table.insert(unknownList, tostring(gid))
    end
    table.sort(unknownList, function(a, b) return tonumber(a) < tonumber(b) end)
    if #unknownList > 0 then
        log.warnf("env", "Unknown terrain GIDs: %s", table.concat(unknownList, ", "))
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
                            log.debugf("env", "Created %s at grid(%d,%d)", entity.name, gridX, gridY)
                        elseif not gidToEntity[gid] then
                            log.warnf("env", "Warning: Unknown entity GID %d at grid(%d,%d)", gid, gridX, gridY)
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
                            log.debugf("env", "Status %s at (%d,%d)", statusType, gridX, gridY)
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

    log.info("env", "--- LOADING COMPLETE ---")
    log.infof("env", "Active terrain cells: %d", (function() local count = 0 for _,row in pairs(terrainMap) do for _ in pairs(row) do count = count + 1 end end return count end)())
    log.infof("env", "Entities loaded: %d", #gameEntities)
    log.infof("env", "Allies for deploy: %d", #deployableAllies)

    return terrainMap, gameEntities, width, height, hexStatuses, walkable, deployableAllies, orientation
end

-- ============================================================
-- API доступа к реестру атак
-- ============================================================

-- Возвращает список атак по идентификатору набора ("warrior", "lich", ...).
-- Заменяет 19 старых функций getXxxAttacks().
-- Возвращает пустой список для неизвестного setId.
function environment.getAttacks(setId)
    local factory = setId and ATTACK_SETS[setId]
    if not factory then return {} end
    return factory()
end

-- Backward-compat: тонкие обёртки для тех, кто зовёт get*Attacks() по имени.
-- (на случай внешних вызовов; в самом проекте уже не используется)
function environment.getWarriorAttacks()      return environment.getAttacks("warrior") end
function environment.getPuncherAttacks()      return environment.getAttacks("puncher") end
function environment.getRogueAttacks()        return environment.getAttacks("rogue") end
function environment.getGhostAttacks()        return environment.getAttacks("ghost") end
function environment.getZombieAttacks()       return environment.getAttacks("zombie") end
function environment.getLichAttacks()         return environment.getAttacks("lich") end
function environment.getNoneAttacks()         return environment.getAttacks("none") end
function environment.getAllAttacks()          return environment.getAttacks("all") end
function environment.getDividerAttacks()      return environment.getAttacks("divider") end
function environment.getSummonerAttacks()     return environment.getAttacks("summoner") end
function environment.getBruteAttacks()        return environment.getAttacks("brute") end
function environment.getDervishAttacks()      return environment.getAttacks("dervish") end
function environment.getRaiderAttacks()       return environment.getAttacks("raider") end
function environment.getCrusherAttacks()      return environment.getAttacks("crusher") end
function environment.getSummoningRodAttacks() return environment.getAttacks("summoningrod") end
function environment.getPowerLichAttacks()    return environment.getAttacks("powerlich") end
function environment.getLancerAttacks()       return environment.getAttacks("lancer") end
function environment.getBogShamanAttacks()    return environment.getAttacks("bogshaman") end
function environment.getSummonedAttacks()     return environment.getAttacks("summoned") end

-- Кэш спрайтов: источник истины — модуль sprites (для разрыва цикла combat↔environment).
-- environment.unitSpriteCache оставлен как алиас для обратной совместимости.
local sprites = require("util.sprites")
local unitSpriteCache = sprites.raw()
environment.unitSpriteCache = unitSpriteCache

function environment.loadUnitSprites()
    local workaroundPath = "maps/units_workaround.lua"
    local info = love.filesystem.getInfo(workaroundPath)
    if not info then
        log.info("env", "No units_workaround.lua found, squad units will use fallback colors")
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
        log.debug("env", "=== All entity GIDs from workaround ===")
        for gid = firstGid, lastGid do
            local sprite = loadTileSprite(map, gid, tileWidth, tileHeight)
            local def = gidToEntity[gid]
            local name = def and def.name or "nil"
            local info = def and string.format("type=%s hp=%s", def.type, def.maxHealth or def.health or "?") or ""
            if sprite then
                sprites.set(gid, sprite)
                log.debugf("env", "  [OK]   GID %3d -> %-20s %s", gid, name, info)
            else
                log.warnf("env", "  [FAIL] GID %3d -> %-20s (no sprite)", gid, name, info)
            end
        end
    end

    log.debug("env", "=== Tile positions on workaround map ===")
    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" then
            local data = layer.data
            log.debugf("env", "  Layer '%s' (%d x %d):", layer.name, layer.width, layer.height)
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
                        log.debugf("env", "    (%d,%d) -> GID %d (%s)", x-1, y-1, gid, name)
                    end
                end
            end
        end
    end
end

function environment.createSquadUnit(unitDef, q, r)
    local attacks = environment.getAttacks(unitDef.attacks)

    local nameToGid = {
        Warrior = 34, Puncher = 30, Rogue = 31,
        Summoner = 40, Divider = 45, Summoned = 42, Divided = 44,
        AttackTest = 68,
    }
    local gid = nameToGid[unitDef.name]
    local sprite = gid and unitSpriteCache[gid] or nil

    local colors = {
        Warrior = {0.8, 0.3, 0.2},
        Puncher = {0.2, 0.8, 0.3},
        Rogue = {0.2, 0.5, 0.8},
        Summoner = {0.8, 0.2, 0.8},
        Divider = {0.9, 0.7, 0.1},
        Summoned = {0.6, 0.3, 0.9},
        Divided = {0.6, 0.4, 0.1},
        AttackTest = {0.2, 0.9, 0.9},
    }

    local entity = Entity.new(
        unitDef.name, Entity.TYPES.CHARACTER, q, r,
        unitDef.maxHealth, true, unitDef.moveRange,
        sprite, sprite and nil or (colors[unitDef.name] or {0.5, 0.5, 0.5}),
        attacks
    )

    -- Apply progression upgrades (choice-based)
    local upgradeData = _G.unitUpgrades and _G.unitUpgrades[unitDef.name] or { choices = {} }
    entity.upgradeLevel = #upgradeData.choices

    for _, choiceId in ipairs(upgradeData.choices) do
        if choiceId == "dashToFlipChain" then entity.dashToFlipChain = true end
        if choiceId == "flipToDashChain" then entity.flipToDashChain = true end
        if choiceId == "empowerAtStart" then entity.empowerAtStart = true end
        if choiceId == "choosePushDir" then entity.choosePushDir = true end
        if choiceId == "redirectShot" then entity.redirectShot = true end
        if choiceId == "pointBlankLethal" then entity.pointBlankLethal = true end
    end

    -- Apply artifacts (global bonuses)
    local artifactList = _G.artifacts or {}
    for _, artId in ipairs(artifactList) do
        if artId == "rootImmune" then entity.rootImmune = true end
        if artId == "deployAnywhere" then entity.deployAnywhere = true end
        if artId == "armor" then entity.armor = 1 end
        if artId == "moveSpeed" then entity.moveRange = entity.moveRange + 1 end
        if artId == "canMoveAfterAttack" then entity.canMoveAfterAttack = true end
        if artId == "phaseThroughEnemies" then entity.phaseThroughEnemies = true end
    end

    return entity
end

function environment.createEnemyByType(enemyType, q, r)
    -- Спецификация из реестра; fallback — Zombie.
    local spec = ENEMY_TYPES[enemyType] or ENEMY_TYPES.Zombie
    local name = (ENEMY_TYPES[enemyType] and enemyType) or "Zombie"
    local attacks = environment.getAttacks(spec.attackSet)
    local maxHealth = spec.maxHealth or 2
    local moveRange = spec.moveRange or 2
    local hasAura = spec.aura

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
        elseif enemyType == "PowerLich" then
            -- Body (dark purple)
            love.graphics.setColor(0.15, 0.05, 0.2, 1)
            love.graphics.rectangle("fill", 2, 4, size-4, size-4, 2)
            -- Cape (dark red)
            love.graphics.setColor(0.4, 0.05, 0.1, 0.8)
            love.graphics.rectangle("fill", 1, 5, size-2, size-5, 2)
            -- Glowing eyes
            love.graphics.setColor(0.1, 0.9, 0.3, 1)
            love.graphics.rectangle("fill", 4, 6, 3, 2)
            love.graphics.rectangle("fill", 9, 6, 3, 2)
            -- Crown spikes
            love.graphics.setColor(0.6, 0.1, 0.15, 1)
            love.graphics.polygon("fill", 8, 2, 6, 5, 10, 5)
            love.graphics.polygon("fill", 5, 3, 3, 6, 7, 6)
            love.graphics.polygon("fill", 11, 3, 9, 6, 13, 6)
            -- Staff
            love.graphics.setColor(0.3, 0.3, 0.4, 1)
            love.graphics.rectangle("fill", 13, 5, 2, 10)
            love.graphics.setColor(0.8, 0.1, 0.3, 1)
            love.graphics.circle("fill", 14, 4, 2)
        else
            love.graphics.setColor(1, 0.5, 0, 1)
            love.graphics.circle("fill", size/2, size/2, size/2 - 1)
        end
        love.graphics.setCanvas()
        sprite = canvas
    end

    local entity = Entity.new(name, Entity.TYPES.CHARACTER, q, r, maxHealth, false, moveRange, sprite, nil, attacks)
    -- Флаги из реестра (только те, что заданы явно).
    if spec.flying          then entity.flying = true end
    if spec.hovering        then entity.hovering = true end
    if spec.healthCellSize  then entity.healthCellSize = spec.healthCellSize end
    if spec.isSummoningRod  then entity.isSummoningRod = true end
    if spec.isPushable == false then entity.isPushable = false end
    if hasAura then
        entity.aura = hasAura
    end
    return entity
end

-- Создать случайного врага (из пула)
function environment.createRandomEnemy(q, r)
    local types
    if isProgressionRun then
        types = { "Ghost", "Zombie", "Lich" }
    else
        types = { "Ghost", "Zombie", "Lich", "Brute", "Lancer", "BogShaman", "Raider", "Dervish", "Crusher" }
    end
    local rnd = love.math.random(1, #types)
    return environment.createEnemyByType(types[rnd], q, r)
end

function environment.generateBuildingSprite(name, w, h)
    return generateCustomSprite(name, w or 32, h or 32)
end

return environment
