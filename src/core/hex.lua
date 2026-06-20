-- src/core/hex.lua
-- Axial hex coordinates (flat-top). Math + active-cell set.
-- A "grid" instance knows its hex size, origin, and the set of active cells.

local hex = {}
hex.__index = hex

local SQRT3 = math.sqrt(3)

-- Cube <-> axial
function hex.axialToCube(q, r) return q, -q - r, r end
function hex.cubeToAxial(x, y, z) return x, z end

-- 6 axial neighbour directions (flat-top)
hex.DIRECTIONS = {
    { q =  1, r = -1 },  -- NE
    { q =  1, r =  0 },  -- SE
    { q =  0, r =  1 },  -- S
    { q = -1, r =  1 },  -- SW
    { q = -1, r =  0 },  -- NW
    { q =  0, r = -1 },  -- N
}

-- Distance between two axial cells
function hex.distance(q1, r1, q2, r2)
    return (math.abs(q1 - q2) + math.abs(q1 + r1 - q2 - r2) + math.abs(r1 - r2)) / 2
end

-- Linear interpolation line between two cells (inclusive)
function hex.line(q1, r1, q2, r2)
    return hex.lineCells(q1, r1, q2, r2)
end

function hex.cubeRound(x, y, z)
    local rx = math.floor(x + 0.5)
    local ry = math.floor(y + 0.5)
    local rz = math.floor(z + 0.5)
    local dx = math.abs(rx - x)
    local dy = math.abs(ry - y)
    local dz = math.abs(rz - z)
    if dx > dy and dx > dz then
        rx = -ry - rz
    elseif dy > dz then
        ry = -rx - rz
    else
        rz = -rx - ry
    end
    return rx, ry, rz
end

-- direction (one of 6 axial deltas) from (fq,fr) towards (tq,tr), or nil if not aligned
hex.DELTAS = {
    { dq =  1, dr = -1 }, { dq =  1, dr = 0 }, { dq =  0, dr = 1 },
    { dq = -1, dr =  1 }, { dq = -1, dr = 0 }, { dq =  0, dr = -1 },
}
function hex.dirTowards(fq, fr, tq, tr)
    for _, d in ipairs(hex.DELTAS) do
        local cq, cr = fq + d.dq, fr + d.dr
        for _ = 1, 32 do
            if cq == tq and cr == tr then return d.dq, d.dr end
            if hex.distance(fq, fr, cq, cr) > 32 then break end
            cq, cr = cq + d.dq, cr + d.dr
        end
    end
    return nil
end

function hex.lineCells(q1, r1, q2, r2)
    local x1, y1, z1 = hex.axialToCube(q1, r1)
    local x2, y2, z2 = hex.axialToCube(q2, r2)
    local n = hex.distance(q1, r1, q2, r2)
    local out = {}
    for i = 0, n do
        local t = i / n
        local x = x1 + (x2 - x1) * t
        local y = y1 + (y2 - y1) * t
        local z = z1 + (z2 - z1) * t
        local cx, cy, cz = hex.cubeRound(x, y, z)
        local cq, cr = hex.cubeToAxial(cx, cy, cz)
        table.insert(out, { q = cq, r = cr })
    end
    return out
end

-- pixel conversion (flat-top), size = center->vertex
-- Module-level (no `self`); instance methods below wrap these.
function hex.toPixel(q, r, size, ox, oy)
    ox = ox or 0; oy = oy or 0
    local x = size * 1.5 * q
    local y = size * SQRT3 * (r + q / 2)
    return x + ox, y + oy
end

function hex.toHex(px, py, size, ox, oy)
    ox = ox or 0; oy = oy or 0
    px = px - ox; py = py - oy
    local q = (2 / 3 * px) / size
    local r = (SQRT3 / 3 * py - 1 / 3 * px) / size
    return hex.axialRound(q, r)
end

function hex.axialRound(q, r)
    local x, y, z = hex.axialToCube(q, r)
    local cx, cy, cz = hex.cubeRound(x, y, z)
    return hex.cubeToAxial(cx, cy, cz)
end

-- The 6 corner points of a flat-top hex at pixel (cx,cy)
function hex.corners(cx, cy, size)
    local pts = {}
    for i = 0, 5 do
        local angle = math.pi / 180 * (60 * i)
        table.insert(pts, { x = cx + size * math.cos(angle), y = cy + size * math.sin(angle) })
    end
    return pts
end

-- Build a grid instance with an explicit set of active cells.
-- activeCells: list of {q=,r=} (optional). If nil, builds a hex shape of `radius`.
function hex.new(size, radius, activeCells, centerQ, centerR)
    local self = setmetatable({}, hex)
    self.size = size or 48
    self.radius = radius or 4
    self.centerQ = centerQ or 0
    self.centerR = centerR or 0
    self.originX = 0
    self.originY = 0
    self.hoverQ = nil
    self.hoverR = nil
    self.active = {}  -- "q,r" -> true
    self.activeList = {}
    if activeCells then
        for _, c in ipairs(activeCells) do
            local key = c.q .. "," .. c.r
            self.active[key] = true
            table.insert(self.activeList, { q = c.q, r = c.r })
        end
    else
        for q = -self.radius, self.radius do
            for r = -self.radius, self.radius do
                if hex.distance(self.centerQ, self.centerR, q, r) <= self.radius then
                    local key = q .. "," .. r
                    self.active[key] = true
                    table.insert(self.activeList, { q = q, r = r })
                end
            end
        end
    end
    return self
end

function hex:key(q, r) return q .. "," .. r end

function hex:isActiveHex(q, r) return self.active[q .. "," .. r] == true end

function hex:neighbors(q, r)
    local out = {}
    for _, d in ipairs(hex.DIRECTIONS) do
        local nq, nr = q + d.q, r + d.r
        if self:isActiveHex(nq, nr) then
            table.insert(out, { q = nq, r = nr, dq = d.q, dr = d.r })
        end
    end
    return out
end

function hex:getDistance(q1, r1, q2, r2) return hex.distance(q1, r1, q2, r2) end

function hex:hexToPixel(q, r)
    return hex.toPixel(q, r, self.size, self.originX, self.originY)
end

function hex:pixelToHex(px, py)
    return hex.toHex(px, py, self.size, self.originX, self.originY)
end

-- Center the grid inside a rectangle (w,h) in design pixels.
function hex:centerOnScreen(w, h)
    -- bounding box of active cells
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(self.activeList) do
        local x, y = hex.toPixel(c.q, c.r, self.size, 0, 0)
        minX = math.min(minX, x); maxX = math.max(maxX, x)
        minY = math.min(minY, y); maxY = math.max(maxY, y)
    end
    local gw = (maxX - minX) + self.size * 2
    local gh = (maxY - minY) + self.size * SQRT3
    self.originX = (w - gw) / 2 - minX + self.size
    self.originY = (h - gh) / 2 - minY + self.size * SQRT3 / 2
    -- shift down a bit to leave room for top HUD
    self.originY = self.originY + 40
end

return hex
