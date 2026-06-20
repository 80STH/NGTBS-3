-- src/content/terrain.lua
-- Terrain definitions. Each terrain is a table of flags + a base colour.
-- Adding a new terrain: just add an entry here and a sprite in assets/sprites/terrain.lua.

local terrain = {}

terrain.list = {
    grass = { color = { 0.30, 0.55, 0.25 }, water = false, damage = 0, railway = false, void = false },
    dirt  = { color = { 0.45, 0.35, 0.22 }, water = false, damage = 0, railway = false, void = false },
    sand  = { color = { 0.80, 0.72, 0.45 }, water = false, damage = 0, railway = false, void = false },
    stone = { color = { 0.50, 0.50, 0.55 }, water = false, damage = 0, railway = false, void = false },
    snow  = { color = { 0.85, 0.88, 0.95 }, water = false, damage = 0, railway = false, void = false },
    swamp = { color = { 0.30, 0.38, 0.28 }, water = false, damage = 0, railway = false, void = false },
    water = { color = { 0.20, 0.40, 0.75 }, water = true,  damage = 0, railway = false, void = false },
    underwater_mines = { color = { 0.12, 0.25, 0.45 }, water = true, damage = 0, railway = false, void = false, mine = true },
    lava  = { color = { 0.75, 0.25, 0.10 }, water = false, damage = 1, railway = false, void = false },
    railway = { color = { 0.35, 0.32, 0.30 }, water = false, damage = 0, railway = true, void = false },
    emptiness = { color = { 0.05, 0.05, 0.08 }, water = false, damage = 0, railway = false, void = true },
}

function terrain.get(id)
    return terrain.list[id] or terrain.list.grass
end

-- Can `entity` enter a cell of this terrain (ignoring other occupants)?
function terrain.passable(id, entity)
    local t = terrain.get(id)
    if t.void or t.mine then return false end
    if t.water then
        return entity.flying or entity.hovering or entity.waterWalker
    end
    return true
end

function terrain.isWater(id) return terrain.get(id).water end
function terrain.isVoid(id) return terrain.get(id).void end
function terrain.isRailway(id) return terrain.get(id).railway end

-- Called when an entity enters a cell. Returns damage taken (0 if none).
function terrain.onEnter(id, entity, ctx)
    local t = terrain.get(id)
    if t.damage and t.damage > 0 and not entity.flying then
        return t.damage
    end
    return 0
end

return terrain
