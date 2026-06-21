-- sprites.lua
-- Simple cache of unit sprites loaded from the Tiled map (units_workaround).
-- Extracted from environment.lua to break the combat <-> environment cycle:
-- combat only needs the cache, not the entire environment.
--
-- Populated by: environment.loadUnitSprites() -> sprites.set(gid, image)
-- Read by:    combat.lua (Summon/Divide) -> sprites.get(gid)

local sprites = {}

local cache = {}

-- Set sprite for GID.
function sprites.set(gid, image)
    cache[gid] = image
end

-- Get sprite by GID (or nil).
function sprites.get(gid)
    return cache[gid]
end

-- Direct access to the internal table (for compatibility with env.unitSpriteCache).
-- Prefer using get/set.
function sprites.raw()
    return cache
end

-- Clear cache (e.g., on restart).
function sprites.clear()
    cache = {}
end

return sprites
