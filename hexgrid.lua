-- hexgrid.lua
-- Система гексагональной сетки (flat-top, углом вверх)

local HexGrid = {}

function HexGrid.new(radius, gridWidth, gridHeight, activeRadius, centerQ, centerR)
    local self = setmetatable({}, {__index = HexGrid})
    self.radius = radius
    self.hexWidth = radius * 1.732
    self.hexHeight = radius * 1.5
    self.gridWidth = gridWidth
    self.gridHeight = gridHeight
    self.activeRadius = activeRadius or 5
    self.centerQ = centerQ or math.floor(gridWidth / 2)
    self.centerR = centerR or math.floor(gridHeight / 2)
    
    self.offsetX = 0
    self.offsetY = 0
    
    self.hoverQ = -1
    self.hoverR = -1
    self.selectedQ = -1
    self.selectedR = -1
    
    return self
end

function HexGrid:pixelToHex(px, py)
    local x = px - self.offsetX
    local y = py - self.offsetY
    
    local r = math.floor(y / self.hexHeight)
    local hexWidthFull = self.hexWidth
    local xOffsetForRow = (r % 2) * (hexWidthFull / 2)
    local q = math.floor((x - xOffsetForRow) / hexWidthFull)
    
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
    local x = (q + (r % 2) * 0.5) * self.hexWidth
    local y = r * self.hexHeight
    return x + self.offsetX, y + self.offsetY
end

function HexGrid:getNeighbors(q, r)
    local directions
    if r % 2 == 1 then
        directions = {
            {q=1, r=0}, {q=-1, r=0},
            {q=0, r=1}, {q=1, r=1},
            {q=0, r=-1}, {q=1, r=-1},
        }
    else
        directions = {
            {q=1, r=0}, {q=-1, r=0},
            {q=0, r=1}, {q=-1, r=1},
            {q=0, r=-1}, {q=-1, r=-1},
        }
    end
    
    local neighbors = {}
    for _, dir in ipairs(directions) do
        neighbors[#neighbors+1] = {q = q + dir.q, r = r + dir.r}
    end
    return neighbors
end

-- Проверка, что координаты в пределах загруженной прямоугольной сетки
function HexGrid:isValidHex(q, r)
    return q >= 0 and q < self.gridWidth and r >= 0 and r < self.gridHeight
end

-- Проверка, принадлежит ли клетка правильному шестиугольнику (радиус 5, центр 5,5)
function HexGrid:isActiveHex(q, r)
    if not self:isValidHex(q, r) then return false end
    local function axialToCube(q, r)
        local x = q - (r - (r % 2)) / 2
        local z = r
        local y = -x - z
        return x, y, z
    end
    local cx, cy, cz = axialToCube(self.centerQ, self.centerR)
    local x, y, z = axialToCube(q, r)
    local dist = (math.abs(x - cx) + math.abs(y - cy) + math.abs(z - cz)) / 2
    return dist <= self.activeRadius
end

function HexGrid:getDistance(q1, r1, q2, r2)
    local function axialToCube(q, r)
        local x = q - (r - (r % 2)) / 2
        local z = r
        local y = -x - z
        return x, y, z
    end
    
    local x1, y1, z1 = axialToCube(q1, r1)
    local x2, y2, z2 = axialToCube(q2, r2)
    return (math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)) / 2
end

function HexGrid:drawHexagon(x, y, radius)
    local drawRadius = radius
    local vertices = {}
    for i = 0, 5 do
        local angle = math.rad(60 * i + 30)
        local vx = x + math.cos(angle) * drawRadius
        local vy = y + math.sin(angle) * drawRadius
        table.insert(vertices, vx)
        table.insert(vertices, vy)
    end
    return vertices
end

-- hexgrid.lua
function HexGrid:centerOnScreen(screenWidth, screenHeight)
    local mapWidth = (self.gridWidth + 0.5) * self.hexWidth
    local mapHeight = self.gridHeight * self.hexHeight
    self.offsetX = (screenWidth - mapWidth) / 2
    self.offsetY = (screenHeight - mapHeight) / 2
end

function HexGrid:drawTerrainHex(q, r, terrainType, x, y)
    local radius = self.radius
    local extrude = 1  -- высота "бортика" вниз

    -- Цвета в зависимости от типа местности
    local topColor, sideColor
    if terrainType == "grass" then
        topColor = {0.4, 0.7, 0.2, 1}
        sideColor = {0.2, 0.5, 0.1, 1}
    elseif terrainType == "water" then
        topColor = {0.2, 0.5, 0.8, 1}
        sideColor = {0.1, 0.3, 0.6, 1}
    elseif terrainType == "lava" then
        topColor = {0.9, 0.4, 0.1, 1}
        sideColor = {0.6, 0.2, 0.05, 1}
    elseif terrainType == "stone" then
        topColor = {0.5, 0.5, 0.5, 1}
        sideColor = {0.3, 0.3, 0.3, 1}
    elseif terrainType == "sand" then
        topColor = {0.9, 0.8, 0.6, 1}
        sideColor = {0.7, 0.6, 0.4, 1}
    elseif terrainType == "dirt" then
        topColor = {0.6, 0.4, 0.2, 1}
        sideColor = {0.4, 0.3, 0.1, 1}
    elseif terrainType == "snow" then
        topColor = {0.9, 0.95, 1, 1}
        sideColor = {0.7, 0.75, 0.8, 1}
    elseif terrainType == "swamp" then
        topColor = {0.4, 0.6, 0.3, 1}
        sideColor = {0.3, 0.5, 0.2, 1}
    else -- emptiness или дефолт
        topColor = {0.3, 0.3, 0.3, 1}
        sideColor = {0.2, 0.2, 0.2, 1}
    end

    -- Верхняя грань (основание)
    local topVertices = self:drawHexagon(x, y, radius)

    -- Нижние вершины (сдвинуты вниз)
    local bottomVertices = {}
    for i = 1, #topVertices, 2 do
        bottomVertices[i] = topVertices[i]
        bottomVertices[i+1] = topVertices[i+1] + extrude
    end

    -- 1. Боковые грани (от основания вниз)
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

    -- 2. Верхняя грань (основание) – рисуем поверх боковых граней
    love.graphics.setColor(topColor)
    love.graphics.polygon("fill", topVertices)

    -- 3. Обводка (опционально)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.polygon("line", topVertices)
end
return HexGrid