-- src/assets/sprites.lua
-- Master sprite dispatcher. Resolves the right drawable for an entity.

local allies = require("src.assets.sprites.allies")
local enemies = require("src.assets.sprites.enemies")
local buildings = require("src.assets.sprites.buildings")
local terrain = require("src.assets.sprites.terrain")
local effects = require("src.assets.sprites.effects")

local sprites = {}
sprites.allies = allies
sprites.enemies = enemies
sprites.buildings = buildings
sprites.terrain = terrain
sprites.effects = effects

function sprites.forEntity(e)
    if e:isCharacter() then
        if e:isAlly() then return allies.get(e.defId) end
        return enemies.get(e.defId)
    end
    return buildings.get(e.defId)
end

return sprites
