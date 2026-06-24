-- tests/attack_preview_test.lua
-- Unit tests for the unified attack preview calculator.

local Entity = require("entity.entity")
local preview = require("ui.attack_preview")

-- Minimal hex grid mock (small 3x3 axial grid)
local mockHex = {
    gridWidth = 3, gridHeight = 3,
    radius = 32,
}

function mockHex:isActiveHex(q, r)
    return q >= 0 and q < self.gridWidth and r >= 0 and r < self.gridHeight
end

function mockHex:isValidHex(q, r)
    return self:isActiveHex(q, r)
end

function mockHex:getDistance(aq, ar, bq, br)
    local ax, ay, az = self:axialToCube(aq, ar)
    local bx, by, bz = self:axialToCube(bq, br)
    return (math.abs(ax - bx) + math.abs(ay - by) + math.abs(az - bz)) // 2
end

function mockHex:axialToCube(q, r)
    return q, -q - r, r
end

function mockHex:cubeToAxial(x, y, z)
    return x, z
end

-- Neighbor order used by the real hex grid is irrelevant for our tests.
function mockHex:getNeighbors(q, r)
    return {
        {q = q + 1, r = r}, {q = q - 1, r = r},
        {q = q, r = r + 1}, {q = q, r = r - 1},
        {q = q + 1, r = r - 1}, {q = q - 1, r = r + 1},
    }
end

-- Provide the global helpers the preview module relies on.
getEntityAtHex = function(q, r, entities)
    for _, e in ipairs(entities or {}) do
        if e.q == q and e.r == r then return e end
    end
    return nil
end

getDrawCoords = function(q, r) return q * 32, r * 32 end

local function makeChar(name, q, r, hp, playable)
    local e = Entity.new(name, Entity.TYPES.CHARACTER, q, r, hp, playable or false, 3, nil, {1,1,1,1}, {})
    return e
end

local function makeBuilding(name, q, r, hp)
    local e = Entity.new(name, Entity.TYPES.BUILDING, q, r, hp, false, 0, nil, {1,1,1,1}, {})
    return e
end

local function shootAttack()
    return {
        name = "Shoot", damage = 1, range = 99,
        getLineDirection = function(self, aq, ar, bq, br, hex)
            local dx, dy, dz = hex:axialToCube(bq, br)
            local ax, ay, az = hex:axialToCube(aq, ar)
            dx, dy, dz = dx - ax, dy - ay, dz - az
            local g = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
            if g == 0 then return nil end
            return dx // g, dy // g, dz // g
        end,
        findFirstTargetOnLine = function(self, sq, sr, sx, sy, sz, hex, entities)
            local cq, cr = sq, sr
            for i = 1, 10 do
                cq, cr = self:step(cq, cr, sx, sy, sz)
                if not hex:isActiveHex(cq, cr) then return nil, nil end
                local e = getEntityAtHex(cq, cr, entities)
                if e then return e, {q = cq, r = cr} end
            end
            return nil, nil
        end,
        step = function(self, q, r, x, y, z)
            local ax, ay, az = mockHex:axialToCube(q, r)
            return mockHex:cubeToAxial(ax + x, ay + y, az + z)
        end,
    }
end

local function biteAttack()
    return { name = "Bite", damage = 1, range = 1 }
end

return {
    name = "attack_preview",
    tests = {
        {
            name = "single damage icon is wound",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local target   = makeChar("T", 1, 0, 3, false)
                local entities = { attacker, target }
                local p = preview.compute(mockHex, attacker, biteAttack(), 1, 0, entities)
                local info = p.damages["1,0"]
                if not info or info.totalDamage ~= 1 then return false, "expected 1 total damage" end
                local icon = preview.getDamageIcon(target, info.totalDamage)
                if icon ~= "wound" then return false, "expected wound, got " .. tostring(icon) end
                return true
            end
        },
        {
            name = "lethal 1-damage shows fatal_wound",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local target   = makeChar("T", 1, 0, 1, false)
                local entities = { attacker, target }
                local p = preview.compute(mockHex, attacker, biteAttack(), 1, 0, entities)
                local icon = preview.getDamageIcon(target, p.damages["1,0"].totalDamage)
                if icon ~= "fatal_wound" then return false, "expected fatal_wound, got " .. tostring(icon) end
                return true
            end
        },
        {
            name = "acid target with 1 damage shows fatal_wound_acid",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local target   = makeChar("T", 1, 0, 5, false)
                -- Apply acid status.  The preview module reads status.hasEntityStatus.
                require("system.status").applyToEntity(target, "acid")
                local entities = { attacker, target }
                local p = preview.compute(mockHex, attacker, biteAttack(), 1, 0, entities)
                local icon = preview.getDamageIcon(target, p.damages["1,0"].totalDamage)
                if icon ~= "fatal_wound_acid" then return false, "expected fatal_wound_acid, got " .. tostring(icon) end
                return true
            end
        },
        {
            name = "building 2 damage shows heavy_building_damage",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local target   = makeBuilding("B", 1, 0, 5)
                local entities = { attacker, target }
                local atk = biteAttack()
                atk.damage = 2
                local p = preview.compute(mockHex, attacker, atk, 1, 0, entities)
                local icon = preview.getDamageIcon(target, p.damages["1,0"].totalDamage)
                if icon ~= "heavy_building_damage" then return false, "expected heavy_building_damage, got " .. tostring(icon) end
                return true
            end
        },
        {
            name = "shoot with push into wall deals collision damage",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local target   = makeChar("T", 1, 0, 3, false)
                local wall     = makeBuilding("Wall", 2, 0, 5)
                local entities = { attacker, target, wall }
                local p = preview.compute(mockHex, attacker, shootAttack(), 2, 0, entities)
                local tinfo = p.damages["1,0"]
                if not tinfo or tinfo.totalDamage ~= 2 then return false, "target expected 2 damage (1 attack + 1 collision), got " .. tostring(tinfo and tinfo.totalDamage) end
                if #p.collisions ~= 1 then return false, "expected 1 collision hint, got " .. tostring(#p.collisions) end
                if p.collisions[1].type ~= "collision_damage" then return false, "expected collision_damage hint" end
                return true
            end
        },
        {
            name = "shoot pushing target into another character marks collision_both",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local t1       = makeChar("T1", 1, 0, 3, false)
                local t2       = makeChar("T2", 2, 0, 3, false)
                local entities = { attacker, t1, t2 }
                local p = preview.compute(mockHex, attacker, shootAttack(), 2, 0, entities)
                if #p.collisions ~= 1 then return false, "expected 1 collision, got " .. tostring(#p.collisions) end
                if p.collisions[1].reason ~= "collision_both" then return false, "expected collision_both, got " .. tostring(p.collisions[1].reason) end
                local t1info = p.damages["1,0"]
                local t2info = p.damages["2,0"]
                if not t1info or t1info.collisionDamage ~= 1 then return false, "t1 expected collision damage" end
                if not t2info or t2info.collisionDamage ~= 1 then return false, "t2 expected collision damage" end
                return true
            end
        },
        {
            name = "shoot pushing target into a building damages the building too",
            fn = function()
                local attacker = makeChar("A", 0, 0, 3, true)
                local target   = makeChar("T", 1, 0, 3, false)
                local building = makeBuilding("House", 2, 0, 5)
                local entities = { attacker, target, building }
                local p = preview.compute(mockHex, attacker, shootAttack(), 2, 0, entities)
                if #p.collisions ~= 1 then return false, "expected 1 collision, got " .. tostring(#p.collisions) end
                if p.collisions[1].reason ~= "collision_immovable" then return false, "expected collision_immovable" end
                local targetInfo = p.damages["1,0"]
                local buildingInfo = p.damages["2,0"]
                if not targetInfo or targetInfo.collisionDamage ~= 1 then return false, "target expected collision damage" end
                if not buildingInfo or buildingInfo.collisionDamage ~= 1 then return false, "building expected collision damage, got " .. tostring(buildingInfo and buildingInfo.collisionDamage) end
                local icon = preview.getDamageIcon(building, buildingInfo.totalDamage)
                if icon ~= "building_damage" then return false, "expected building_damage icon, got " .. tostring(icon) end
                return true
            end
        },
    }
}
