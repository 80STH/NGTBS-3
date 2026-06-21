-- sprites.lua
-- Простой кэш спрайтов юнитов, загружаемых из Tiled-карты (units_workaround).
-- Вынесен из environment.lua, чтобы разорвать цикл combat ↔ environment:
-- combat-у нужен только кэш, а не весь environment.
--
-- Заполняется: environment.loadUnitSprites() -> sprites.set(gid, image)
-- Читается:    combat.lua (Summon/Divide) -> sprites.get(gid)

local sprites = {}

local cache = {}

-- Установить спрайт для GID.
function sprites.set(gid, image)
    cache[gid] = image
end

-- Получить спрайт по GID (или nil).
function sprites.get(gid)
    return cache[gid]
end

-- Прямой доступ к внутренней таблице (для совместимости с env.unitSpriteCache).
-- Предпочтительно использовать get/set.
function sprites.raw()
    return cache
end

-- Очистить кэш (например, при рестарте).
function sprites.clear()
    cache = {}
end

return sprites
