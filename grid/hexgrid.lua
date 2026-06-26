local HexGrid = {}
local hex_utils = require("grid.hex_utils")

-- Pre-computed direction tables (module-level constants)
local FLAT_DIRS_EVEN = {
    {q=1, r=0}, {q=1, r=-1}, {q=0, r=-1},
    {q=-1, r=-1}, {q=-1, r=0}, {q=0, r=1},
}
local FLAT_DIRS_ODD = {
    {q=1, r=1}, {q=1, r=0}, {q=0, r=-1},
    {q=-1, r=0}, {q=-1, r=1}, {q=0, r=1},
}
local POINTY_DIRS_ODD = {
    {q=1, r=0}, {q=-1, r=0},
    {q=0, r=1}, {q=1, r=1},
    {q=0, r=-1}, {q=1, r=-1},
}
local POINTY_DIRS_EVEN = {
    {q=1, r=0}, {q=-1, r=0},
    {q=0, r=1}, {q=-1, r=1},
    {q=0, r=-1}, {q=-1, r=-1},
}

-- Reusable vertex buffer (avoids allocation per hex draw)
local vertBuf = {}

function HexGrid.new(radius, gridWidth, gridHeight, activeRadius, centerQ, centerR, orientation)
    local self = setmetatable({}, {__index = HexGrid})
    self.radius = radius
    self.orientation = orientation or "pointy"
    self.gridWidth = gridWidth
    self.gridHeight = gridHeight
    self.activeRadius = activeRadius or 5
    self.centerQ = centerQ or math.floor(gridWidth / 2)
    self.centerR = centerR or math.floor(gridHeight / 2)

    if self.orientation == "flat" then
        self.hexWidth = radius * 1.5
        self.hexHeight = radius * 1.732
    else
        self.hexWidth = radius * 1.732
        self.hexHeight = radius * 1.5
    end

    self.offsetX = 0
    self.offsetY = 0
    self.rotation = 0
    self.centerPixelX = 0
    self.centerPixelY = 0

    self.hoverQ = -1
    self.hoverR = -1
    self.selectedQ = -1
    self.selectedR = -1

    -- Cache center cube coords (#6)
    local cx, cy, cz = hex_utils.axialToCube(self.centerQ, self.centerR)
    self._centerCubeX = cx
    self._centerCubeY = cy
    self._centerCubeZ = cz

    -- Pre-compute sorted active cells (#7)
    self._sortedCells = nil

    -- Pre-compute list of active cell coordinates
    self._activeCells = {}
    for row = 0, self.gridHeight - 1 do
        for col = 0, self.gridWidth - 1 do
            if self:isActiveHex(col, row) then
                self._activeCells[#self._activeCells + 1] = {q = col, r = row}
            end
        end
    end

    return self
end

function HexGrid:pixelToHex(px, py)
    local x = px - self.offsetX
    local y = py - self.offsetY

    if self.rotation ~= 0 then
        local cos_a = math.cos(-self.rotation)
        local sin_a = math.sin(-self.rotation)
        local dx = x - self.centerPixelX
        local dy = y - self.centerPixelY
        x = self.centerPixelX + dx * cos_a - dy * sin_a
        y = self.centerPixelY + dx * sin_a + dy * cos_a
    end

    local q, r
    if self.orientation == "flat" then
        q = math.floor(x / self.hexWidth)
        local yOffset = (q % 2) * (self.hexHeight / 2)
        r = math.floor((y - yOffset) / self.hexHeight)
    else
        r = math.floor(y / self.hexHeight)
        local xOffset = (r % 2) * (self.hexWidth / 2)
        q = math.floor((x - xOffset) / self.hexWidth)
    end

    q = math.max(0, math.min(q, self.gridWidth - 1))
    r = math.max(0, math.min(r, self.gridHeight - 1))

    local bestQ, bestR = q, r
    local bestDist = math.huge

    for dq = -1, 1 do
        for dr = -1, 1 do
            local checkQ = q + dq
            local checkR = r + dr
            if checkQ >= 0 and checkQ < self.gridWidth and checkR >= 0 and checkR < self.gridHeight then
                local hexX, hexY = self:hexToPixel(checkQ, checkR)
                local dist = (px - hexX)^2 + (py - hexY)^2
                if dist < bestDist then
                    bestDist = dist
                    bestQ, bestR = checkQ, checkR
                end
            end
        end
    end

    return bestQ, bestR
end

function HexGrid:hexToPixel(q, r)
    local x, y
    if self.orientation == "flat" then
        x = q * self.hexWidth
        y = (r + (q % 2) * 0.5) * self.hexHeight
    else
        x = (q + (r % 2) * 0.5) * self.hexWidth
        y = r * self.hexHeight
    end
    if self.rotation ~= 0 then
        local cos_a = math.cos(self.rotation)
        local sin_a = math.sin(self.rotation)
        local dx = x - self.centerPixelX
        local dy = y - self.centerPixelY
        x = self.centerPixelX + dx * cos_a - dy * sin_a
        y = self.centerPixelY + dx * sin_a + dy * cos_a
    end
    return x + self.offsetX, y + self.offsetY
end

function HexGrid:getNeighbors(q, r)
    local directions
    if self.orientation == "flat" then
        directions = (q % 2 == 0) and FLAT_DIRS_EVEN or FLAT_DIRS_ODD
    else
        directions = (r % 2 == 1) and POINTY_DIRS_ODD or POINTY_DIRS_EVEN
    end

    local neighbors = {}
    for i = 1, 6 do
        local dir = directions[i]
        neighbors[i] = {q = q + dir.q, r = r + dir.r}
    end
    return neighbors
end

function HexGrid:isValidHex(q, r)
    return q >= 0 and q < self.gridWidth and r >= 0 and r < self.gridHeight
end

function HexGrid:isActiveHex(q, r)
    if not self:isValidHex(q, r) then return false end
    local x, y, z = hex_utils.axialToCube(q, r)
    local dist = (math.abs(x - self._centerCubeX) + math.abs(y - self._centerCubeY) + math.abs(z - self._centerCubeZ)) / 2
    return dist <= self.activeRadius
end

function HexGrid:getDistance(q1, r1, q2, r2)
    return hex_utils.getDistance(q1, r1, q2, r2)
end

function HexGrid:drawHexagon(x, y, radius)
    local rot = self.rotation or 0
    local angleOffset = (self.orientation == "flat") and 0 or 30
    for i = 0, 5 do
        local angle = math.rad(60 * i + angleOffset) + rot
        vertBuf[i*2+1] = x + math.cos(angle) * radius
        vertBuf[i*2+2] = y + math.sin(angle) * radius
    end
    return vertBuf
end

function HexGrid:drawInsetHexagon(x, y, radius, scale)
    scale = scale or 0.92
    local r = radius * scale
    local rot = self.rotation or 0
    local angleOffset = (self.orientation == "flat") and 0 or 30
    for i = 0, 5 do
        local angle = math.rad(60 * i + angleOffset) + rot
        vertBuf[i*2+1] = x + math.cos(angle) * r
        vertBuf[i*2+2] = y + math.sin(angle) * r
    end
    return vertBuf
end

function HexGrid:getSortedCells(terrainMap, waterYOffset)
    if self._sortedCells then return self._sortedCells end
    local cells = {}
    for _, ac in ipairs(self._activeCells) do
        local col, row = ac.q, ac.r
        local terrainType = terrainMap and terrainMap[col] and terrainMap[col][row] or "grass"
        local cellX, cellY = self:hexToPixel(col, row)
        local yOffset = (terrainType == "water" or terrainType == "underwater_mines") and waterYOffset or 0
        local depth = cellY + yOffset
        cells[#cells + 1] = { q = col, r = row, x = cellX, y = cellY, terrain = terrainType, depth = depth }
    end
    table.sort(cells, function(a, b) return a.depth < b.depth end)
    self._sortedCells = cells
    return cells
end

function HexGrid:invalidateSortedCells()
    self._sortedCells = nil
end

function HexGrid:centerOnScreen(screenWidth, screenHeight)
    self:invalidateSortedCells()
    local mapWidth, mapHeight
    if self.orientation == "flat" then
        mapWidth = self.gridWidth * self.hexWidth
        mapHeight = self.gridHeight * self.hexHeight + self.hexHeight * 0.5
    else
        mapWidth = (self.gridWidth + 0.5) * self.hexWidth
        mapHeight = self.gridHeight * self.hexHeight
    end
    self.offsetX = (screenWidth - mapWidth) / 2 + config.GRID_OFFSET_X
    self.offsetY = (screenHeight - mapHeight) / 2
    if self.orientation == "flat" then
        self.centerPixelX = self.centerQ * self.hexWidth
        self.centerPixelY = (self.centerR + (self.centerQ % 2) * 0.5) * self.hexHeight
    else
        self.centerPixelX = (self.centerQ + (self.centerR % 2) * 0.5) * self.hexWidth
        self.centerPixelY = self.centerR * self.hexHeight
    end
end

function HexGrid:drawTerrainHex(q, r, terrainType, x, y)
    local radius = self.radius
    local extrude = 36
    local waterExtrude = 18
    local isLowTerrain = terrainType == "water" or terrainType == "underwater_mines"
    local actualExtrude = isLowTerrain and waterExtrude or extrude

    local yOffset = 0
    if isLowTerrain then
        yOffset = extrude - waterExtrude
    end

    local topColor, sideColor, edgeColor
    if terrainType == "grass" then
        topColor = {0.35, 0.65, 0.2, 1}
        sideColor = {0.2, 0.45, 0.1, 1}
        edgeColor = {0.15, 0.4, 0.05, 1}
    elseif terrainType == "water" then
        topColor = {0.2, 0.5, 0.85, 1}
        sideColor = {0.1, 0.35, 0.65, 1}
        edgeColor = {0.05, 0.25, 0.5, 1}
    elseif terrainType == "lava" then
        topColor = {0.95, 0.45, 0.1, 1}
        sideColor = {0.7, 0.3, 0.05, 1}
        edgeColor = {0.5, 0.2, 0.0, 1}
    elseif terrainType == "stone" then
        topColor = {0.55, 0.55, 0.55, 1}
        sideColor = {0.4, 0.4, 0.4, 1}
        edgeColor = {0.3, 0.3, 0.3, 1}
    elseif terrainType == "sand" then
        topColor = {0.9, 0.85, 0.6, 1}
        sideColor = {0.7, 0.65, 0.4, 1}
        edgeColor = {0.5, 0.45, 0.25, 1}
    elseif terrainType == "dirt" then
        topColor = {0.65, 0.45, 0.25, 1}
        sideColor = {0.5, 0.35, 0.15, 1}
        edgeColor = {0.35, 0.25, 0.1, 1}
    elseif terrainType == "snow" then
        topColor = {0.9, 0.95, 1, 1}
        sideColor = {0.7, 0.75, 0.85, 1}
        edgeColor = {0.55, 0.6, 0.7, 1}
    elseif terrainType == "swamp" then
        topColor = {0.45, 0.65, 0.35, 1}
        sideColor = {0.3, 0.5, 0.2, 1}
        edgeColor = {0.2, 0.4, 0.15, 1}
    elseif terrainType == "underwater_mines" then
        topColor = {0.08, 0.25, 0.45, 1}
        sideColor = {0.05, 0.15, 0.35, 1}
        edgeColor = {0.02, 0.1, 0.25, 1}
    elseif terrainType == "railway" then
        topColor = {0.35, 0.3, 0.25, 1}
        sideColor = {0.25, 0.2, 0.15, 1}
        edgeColor = {0.15, 0.1, 0.05, 1}
    else
        topColor = {0.35, 0.35, 0.35, 1}
        sideColor = {0.25, 0.25, 0.25, 1}
        edgeColor = {0.15, 0.15, 0.15, 1}
    end

    local topVertices = self:drawHexagon(x, y + yOffset, radius)
    local bottomVertices = {}
    for i = 1, #topVertices, 2 do
        bottomVertices[i] = topVertices[i]
        bottomVertices[i+1] = topVertices[i+1] + actualExtrude
    end

    love.graphics.setColor(sideColor)
    local n = #topVertices / 2
    for i = 1, n do
        local next_i = i % n + 1
        local x1, y1 = topVertices[(i-1)*2+1], topVertices[(i-1)*2+2]
        local x2, y2 = topVertices[(next_i-1)*2+1], topVertices[(next_i-1)*2+2]
        local x3, y3 = bottomVertices[(next_i-1)*2+1], bottomVertices[(next_i-1)*2+2]
        local x4, y4 = bottomVertices[(i-1)*2+1], bottomVertices[(i-1)*2+2]
        love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3)
	love.graphics.polygon("fill", x1, y1, x3, y3, x4, y4)
	end

	love.graphics.setColor(edgeColor)
	love.graphics.setLineWidth(1.5)
	for i = 1, n do
		local x1, y1 = topVertices[(i-1)*2+1], topVertices[(i-1)*2+2]
		local x4, y4 = bottomVertices[(i-1)*2+1], bottomVertices[(i-1)*2+2]
		love.graphics.line(x1, y1, x4, y4)
	end

	love.graphics.setColor(topColor)
    love.graphics.polygon("fill", topVertices)

    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.polygon("fill", topVertices)

    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", topVertices)

    love.graphics.setColor(0, 0, 0, 0.25)
    local shadowVertices = {}
    for i = 1, #topVertices, 2 do
        shadowVertices[i] = topVertices[i] + 2
        shadowVertices[i+1] = topVertices[i+1]
    end
    love.graphics.polygon("fill", shadowVertices)

    if terrainType == "underwater_mines" then
        local cx, cy = x, y + yOffset
        love.graphics.setColor(0.8, 0.15, 0.15, 0.9)
        love.graphics.circle("fill", cx - radius * 0.25, cy - radius * 0.15, radius * 0.08)
        love.graphics.circle("fill", cx + radius * 0.3, cy + radius * 0.2, radius * 0.08)
        love.graphics.circle("fill", cx + radius * 0.05, cy - radius * 0.35, radius * 0.07)
        love.graphics.setColor(0.9, 0.6, 0.1, 0.8)
        love.graphics.circle("fill", cx - radius * 0.15, cy + radius * 0.3, radius * 0.06)
        love.graphics.circle("fill", cx + radius * 0.2, cy - radius * 0.2, radius * 0.06)
    end

    if terrainType == "railway" then
        local cx, cy = x, y + yOffset
        love.graphics.setColor(0.5, 0.4, 0.3, 0.8)
        love.graphics.setLineWidth(2)
        for angle = 0, 5 do
            local a1 = math.rad(60 * angle)
            local a2 = math.rad(60 * (angle + 1))
            local x1 = cx + math.cos(a1) * radius * 0.6
            local y1 = cy + math.sin(a1) * radius * 0.6
            local x2 = cx + math.cos(a2) * radius * 0.6
            local y2 = cy + math.sin(a2) * radius * 0.6
            love.graphics.line(x1, y1, x2, y2)
        end
        love.graphics.setColor(0.3, 0.25, 0.2, 0.6)
        love.graphics.circle("fill", cx, cy, radius * 0.15)
        love.graphics.setLineWidth(1)
    end

    love.graphics.setLineWidth(1)
end

function HexGrid:drawUpperTerrain(q, r, terrainType, x, y, yOffset)
	local radius = self.radius
	local function srand(seed)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local seed = q * 31 + r * 17 + 1

	if terrainType == "mountain_rubble" then
		for i = 0, 5 do
			local sx = srand(seed + i * 3) - 0.5
			local sy = srand(seed + i * 3 + 99) - 0.5
			local sz = 3 + srand(seed + i * 3 + 199) * 5
			local px = x + sx * radius * 1.1
			local py = y + yOffset + sy * radius * 1.1
			local dist = math.sqrt((px - x)^2 + (py - (y + yOffset))^2)
			if dist < radius * 0.75 then
				love.graphics.setColor(0.42, 0.38, 0.33, 0.85)
				love.graphics.circle("fill", px, py, sz)
				love.graphics.setColor(0.32, 0.28, 0.24, 0.85)
				love.graphics.circle("fill", px + sz * 0.3, py - sz * 0.3, sz * 0.5)
			end
		end
	elseif terrainType == "building_rubble" then
		for i = 0, 6 do
			local sx = srand(seed + i * 7) - 0.5
			local sy = srand(seed + i * 7 + 77) - 0.5
			local sz = 3 + srand(seed + i * 7 + 177) * 4
			local px = x + sx * radius * 1.1
			local py = y + yOffset + sy * radius * 1.1
			local dist = math.sqrt((px - x)^2 + (py - (y + yOffset))^2)
			if dist < radius * 0.7 then
				love.graphics.setColor(0.5, 0.33, 0.18, 0.85)
				love.graphics.rectangle("fill", px - sz, py - sz * 0.5, sz * 2, sz, sz * 0.3)
				love.graphics.setColor(0.38, 0.25, 0.13, 0.85)
				love.graphics.rectangle("fill", px - sz * 0.5, py - sz * 0.3, sz, sz * 0.6, sz * 0.2)
			end
		end
	end
end

return HexGrid
