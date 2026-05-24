-- hexgrid.lua
-- Система гексагональной сетки

local HexGrid = {}

function HexGrid.new(radius, gridWidth, gridHeight)
    local self = setmetatable({}, {__index = HexGrid})
    
    self.radius = radius
    self.width = radius * 2
    self.height = radius * 1.75
    self.gridWidth = gridWidth
    self.gridHeight = gridHeight
    
    -- Смещение для центрирования
    self.offsetX = 0
    self.offsetY = 0
    
    -- Подсветка гексов
    self.hoverQ = -1
    self.hoverR = -1
    self.selectedQ = -1
    self.selectedR = -1
    
    return self
end

-- Конвертация пикселей в координаты гекса
function HexGrid:pixelToHex(px, py)
    local x = px - self.offsetX
    local y = py - self.offsetY
    
    local q = math.floor(x / (self.width * 0.75))
    local r = math.floor(y / self.height)
    
    if q < 0 then q = 0 end
    if q >= self.gridWidth then q = self.gridWidth - 1 end
    if r < 0 then r = 0 end
    if r >= self.gridHeight then r = self.gridHeight - 1 end
    
    local bestQ, bestR = q, r
    local bestDist = math.huge
    
    for dq = -1, 1 do
        for dr = -1, 1 do
            local checkQ = q + dq
            local checkR = r + dr
            if checkQ >= 0 and checkQ < self.gridWidth and checkR >= 0 and checkR < self.gridHeight then
                local hexX, hexY = self:hexToPixel(checkQ, checkR)
                local dist = math.sqrt((px - hexX)^2 + (py - hexY)^2)
                if dist < bestDist then
                    bestDist = dist
                    bestQ, bestR = checkQ, checkR
                end
            end
        end
    end
    
    return bestQ, bestR
end

-- Конвертация координат гекса в пиксели
function HexGrid:hexToPixel(q, r)
    local x = q * self.width * 0.75
    local y = r * self.height + (q % 2) * (self.height / 2)
    return x + self.radius + self.offsetX, y + self.radius + self.offsetY
end

-- Получение соседей гекса
function HexGrid:getNeighbors(q, r)
    local directions
    if q % 2 == 0 then
        directions = {
            {q=1, r=0}, {q=-1, r=0}, {q=0, r=1},
            {q=0, r=-1}, {q=1, r=-1}, {q=-1, r=-1}
        }
    else
        directions = {
            {q=1, r=0}, {q=-1, r=0}, {q=0, r=1},
            {q=0, r=-1}, {q=1, r=1}, {q=-1, r=1}
        }
    end
    
    local neighbors = {}
    for _, dir in ipairs(directions) do
        neighbors[#neighbors+1] = {q = q + dir.q, r = r + dir.r}
    end
    return neighbors
end

-- Проверка валидности координат
function HexGrid:isValidHex(q, r)
    return q >= 0 and q < self.gridWidth and r >= 0 and r < self.gridHeight
end

-- Расчет расстояния между двумя гексами
function HexGrid:getDistance(q1, r1, q2, r2)
    -- Конвертируем в кубические координаты для простоты расчета
    local x1 = q1
    local z1 = r1 - (q1 - (q1 % 2)) / 2
    local y1 = -x1 - z1
    
    local x2 = q2
    local z2 = r2 - (q2 - (q2 % 2)) / 2
    local y2 = -x2 - z2
    
    return (math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)) / 2
end

-- Отрисовка шестиугольника (возвращает вершины)
function HexGrid:drawHexagon(x, y, radius)
    local vertices = {}
    for i = 0, 5 do
        local angle = math.rad(60 * i)
        local vx = x + math.cos(angle) * radius
        local vy = y + math.sin(angle) * radius
        table.insert(vertices, vx)
        table.insert(vertices, vy)
    end
    return vertices
end

-- Центрирование карты на экране
function HexGrid:centerOnScreen(screenWidth, screenHeight)
    local mapWidth = self.gridWidth * self.width * 0.75 + self.radius
    local mapHeight = self.gridHeight * self.height + self.radius
    self.offsetX = (screenWidth - mapWidth) / 2
    self.offsetY = (screenHeight - mapHeight) / 2
end

function axialToCube(q, r)
    local x = q
    local z = r - (q - (q % 2)) / 2
    return x, -x - z, z
end
function cubeToAxial(x, y, z)
    local q = x
    local r = z + (x - (x % 2)) / 2
    return q, r
end

return HexGrid