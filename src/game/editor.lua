-- src/game/editor.lua
-- Map editor state & operations. Lists of terrain/entity/status are pulled
-- automatically from the content registries, so new defs show up here for free.
--
-- Each active cell may hold: a terrain id (default "grass"), at most one entity,
-- and any number of hex statuses. Editor renders at a display hex size computed
-- to fit the available area; the stored map `size` is the in-game play size.

local hex = require("src.core.hex")
local Entity = require("src.core.entity")
local terrain = require("src.content.terrain")
local units = require("src.content.units")
local statuses = require("src.content.statuses")

local SQRT3 = math.sqrt(3)

local Editor = {}
Editor.__index = Editor

-- sorted keys of a plain dict table
local function sortedKeys(t)
    local ks = {}
    for k in pairs(t) do table.insert(ks, k) end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    return ks
end

-- ---- auto-pulled option lists (rebuilt each call so new defs appear) ----
function Editor.terrainIds()
    return sortedKeys(terrain.list)
end
function Editor.entityIds()
    return units.ids()   -- registry order
end
-- hex-placeable statuses: defs that react to end-of-turn on a hex
function Editor.statusIds()
    local out = {}
    for _, id in ipairs(sortedKeys(statuses.defs)) do
        local d = statuses.defs[id]
        if d and d.onHexTurnEnd then table.insert(out, id) end
    end
    return out
end
function Editor.sides()
    return { Entity.SIDES.ALLY, Entity.SIDES.ENEMY, Entity.SIDES.NEUTRAL }
end

-- ========================================================================
function Editor.new()
    local self = setmetatable({}, Editor)
    self.radius = 4
    self.playSize = 46
    self.maxTurns = 12
    self.objective = { type = "kill_all" }
    self.mapName = "new_map"
    self.terrain = {}            -- "q,r" -> id
    self.entities = {}           -- list { def=id, q=, r=, side= }
    self.statuses = {}           -- list { type=, q=, r=, data={duration=} }
    self.cells = nil             -- nil -> hex shape of `radius`; list -> custom
    self.customShape = false
    self.tool = "terrain"
    self.selTerrain = "grass"
    self.selEntity = "Warrior"
    self.selSide = Entity.SIDES.ALLY
    self.selStatus = "fire"
    self.scroll = 0
    self.editingName = false
    self.loadOpen = false
    self.message = nil
    self.messageTimer = 0
    self.hoverQ = nil
    self.hoverR = nil
    self._entCache = {}
    self:rebuildGrid()
    return self
end

-- ========================================================================
-- Grid construction & coordinate helpers
-- ========================================================================
function Editor:rebuildGrid()
    local R = self.radius
    if not self.cells then
        local list = {}
        for q = -R, R do
            for r = -R, R do
                if hex.distance(0, 0, q, r) <= R then table.insert(list, { q = q, r = r }) end
            end
        end
        self.cells = list
    end
    -- display size: fit inside the editor's grid area (700x720)
    local availW, availH = 700, 720
    local sw = availW / (3 * R + 2)
    local sh = availH / (SQRT3 * (2 * R + 1))
    self.dispSize = math.max(14, math.floor(math.min(sw, sh, 48)))
    self.grid = hex.new(self.dispSize, R, self.cells, 0, 0)
    -- center inside area (x:10..710, y:96..816)
    local areaX, areaY, areaW, areaH = 10, 96, 700, 720
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(self.grid.activeList) do
        local x, y = hex.toPixel(c.q, c.r, self.dispSize, 0, 0)
        minX = math.min(minX, x); maxX = math.max(maxX, x)
        minY = math.min(minY, y); maxY = math.max(maxY, y)
    end
    local gw = (maxX - minX) + self.dispSize * 2
    local gh = (maxY - minY) + self.dispSize * SQRT3
    self.grid.originX = areaX + (areaW - gw) / 2 - minX + self.dispSize
    self.grid.originY = areaY + (areaH - gh) / 2 - minY + self.dispSize * SQRT3 / 2
end

function Editor:setRadius(r)
    if self.customShape then return end
    r = math.max(1, math.min(8, r))
    if r == self.radius then return end
    self.radius = r
    self.cells = nil
    self:rebuildGrid()
    self:filterToActive()
end

function Editor:filterToActive()
    local act = {}
    for _, c in ipairs(self.grid.activeList) do act[c.q .. "," .. c.r] = true end
    local kept = {}
    for _, e in ipairs(self.entities) do
        if act[e.q .. "," .. e.r] then table.insert(kept, e) end
    end
    self.entities = kept
    local keptS = {}
    for _, s in ipairs(self.statuses) do
        if act[s.q .. "," .. s.r] then table.insert(keptS, s) end
    end
    self.statuses = keptS
    for k in pairs(self.terrain) do
        if not act[k] then self.terrain[k] = nil end
    end
end

function Editor:updateHover(dx, dy)
    if not self.grid then return end
    local q, r = self.grid:pixelToHex(dx, dy)
    if self.grid:isActiveHex(q, r) then
        self.hoverQ, self.hoverR = q, r
    else
        self.hoverQ, self.hoverR = nil, nil
    end
end

-- ========================================================================
-- Cell data access
-- ========================================================================
function Editor:terrainAt(q, r) return self.terrain[q .. "," .. r] or "grass" end

function Editor:entityAt(q, r)
    for _, e in ipairs(self.entities) do
        if e.q == q and e.r == r then return e end
    end
    return nil
end

function Editor:statusesAt(q, r)
    local out = {}
    for _, s in ipairs(self.statuses) do
        if s.q == q and s.r == r then table.insert(out, s) end
    end
    return out
end

-- cached temp entity for drawing
function Editor:tempEntity(defId, side)
    local k = defId .. "," .. side
    if not self._entCache[k] then
        local ok = pcall(units.create, defId, 0, 0, side)
        if ok then self._entCache[k] = units.create(defId, 0, 0, side) end
    end
    return self._entCache[k]
end

-- ========================================================================
-- Placement
-- ========================================================================
function Editor:place(q, r)
    if not self.grid:isActiveHex(q, r) then return end
    if self.tool == "terrain" then
        self.terrain[q .. "," .. r] = self.selTerrain
    elseif self.tool == "entity" then
        -- replace any existing entity on this cell
        for i, e in ipairs(self.entities) do
            if e.q == q and e.r == r then table.remove(self.entities, i) break end
        end
        table.insert(self.entities, { def = self.selEntity, q = q, r = r, side = self.selSide })
    elseif self.tool == "status" then
        -- replace same-type status on this cell, else add
        for i, s in ipairs(self.statuses) do
            if s.q == q and s.r == r and s.type == self.selStatus then table.remove(self.statuses, i) break end
        end
        table.insert(self.statuses, { type = self.selStatus, q = q, r = r, data = { duration = 6 } })
    elseif self.tool == "erase" then
        self:eraseCell(q, r)
    end
end

function Editor:eraseCell(q, r)
    for i = #self.entities, 1, -1 do
        if self.entities[i].q == q and self.entities[i].r == r then table.remove(self.entities, i) end
    end
    for i = #self.statuses, 1, -1 do
        if self.statuses[i].q == q and self.statuses[i].r == r then table.remove(self.statuses, i) end
    end
    self.terrain[q .. "," .. r] = "grass"
end

function Editor:clear()
    self.terrain = {}
    self.entities = {}
    self.statuses = {}
    self:setMessage("Cleared")
end

function Editor:setMessage(msg) self.message = msg; self.messageTimer = 2 end

-- ========================================================================
-- Load / Save
-- ========================================================================
function Editor:loadMap(path)
    local chunk = love.filesystem.load(path)
    if not chunk then self:setMessage("Load failed: " .. path) return false end
    local data = chunk()
    if not data then self:setMessage("Map returned nil") return false end
    self.radius = data.radius or 4
    self.playSize = data.size or 46
    self.maxTurns = data.maxTurns or 12
    self.objective = data.objective or { type = "kill_all" }
    self.mapName = path:match("([^/\\]+)%.lua$") or "new_map"
    self.terrain = {}
    if data.terrain then for k, v in pairs(data.terrain) do self.terrain[k] = v end end
    self.entities = {}
    if data.entities then
        for _, e in ipairs(data.entities) do
            table.insert(self.entities, { def = e.def, q = e.q, r = e.r, side = e.side or "enemy" })
        end
    end
    self.statuses = {}
    if data.statuses then
        for _, s in ipairs(data.statuses) do
            table.insert(self.statuses, { type = s.type, q = s.q, r = s.r, data = { duration = (s.data and s.data.duration) or 6 } })
        end
    end
    if data.cells then
        self.cells = data.cells
        self.customShape = true
    else
        self.cells = nil
        self.customShape = false
    end
    self:rebuildGrid()
    self:filterToActive()
    self.loadOpen = false
    self:setMessage("Loaded " .. self.mapName)
    return true
end

-- simple Lua table serializer
local function ser(t, indent)
    indent = indent or 0
    local pad = string.rep("    ", indent)
    if type(t) == "table" then
        local n, isArray = 0, true
        for k in pairs(t) do
            n = n + 1
            if type(k) ~= "number" then isArray = false end
        end
        if n == 0 then return "{}" end
        local parts = {}
        if isArray then
            for _, v in ipairs(t) do table.insert(parts, pad .. "    " .. ser(v, indent + 1)) end
        else
            local keys = {}
            for k in pairs(t) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local kk = (type(k) == "string") and k or "[" .. tostring(k) .. "]"
                table.insert(parts, pad .. "    " .. kk .. " = " .. ser(t[k], indent + 1))
            end
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
    elseif type(t) == "string" then
        return string.format("%q", t)
    elseif type(t) == "boolean" or type(t) == "number" then
        return tostring(t)
    elseif t == nil then
        return "nil"
    end
    return tostring(t)
end

function Editor:save()
    local name = (self.mapName or "new_map"):gsub("[^%w_]", "_")
    if name == "" then name = "new_map" end
    local data = {
        name = name,
        radius = self.radius,
        size = self.playSize,
        maxTurns = self.maxTurns,
        terrain = self.terrain,
        entities = self.entities,
        statuses = self.statuses,
        objective = self.objective,
    }
    if self.customShape and self.cells then data.cells = self.cells end
    local content = "return " .. ser(data, 0) .. "\n"
    local path = "maps/" .. name .. ".lua"
    local ok, err = love.filesystem.write(path, content)
    if ok then
        self.mapName = name
        self:setMessage("Saved -> " .. path)
    else
        self:setMessage("Save error: " .. tostring(err))
    end
    return ok
end

function Editor:listMapFiles()
    local items = love.filesystem.getDirectoryItems("maps")
    local list = {}
    for _, f in ipairs(items) do
        if f:match("%.lua$") then table.insert(list, "maps/" .. f) end
    end
    table.sort(list)
    return list
end

-- ========================================================================
-- Input helpers (text entry for map name)
-- ========================================================================
function Editor:keypressed(key)
    if self.editingName then
        if key == "backspace" then
            self.mapName = self.mapName:sub(1, -2)
        elseif key == "return" or key == "escape" then
            self.editingName = false
        end
        return true
    end
    if key == "escape" then
        if self.loadOpen then self.loadOpen = false else return "menu" end
    end
    return false
end

function Editor:textinput(text)
    if not self.editingName then return end
    if #self.mapName < 24 then
        self.mapName = self.mapName .. text
    end
end

return Editor
