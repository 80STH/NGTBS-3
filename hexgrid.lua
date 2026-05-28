-- hexgrid.lua
-- Система гексагональной сетки (flat-top, углом вверх)

local HexGrid = {}

function HexGrid.new(radius, gridWidth, gridHeight)
    local self = setmetatable({}, {__index = HexGrid})
    
    self.radius = radius
    -- Расстояние между центрами гексов
    self.hexWidth = radius * 1.732          -- горизонтальный шаг
    self.hexHeight = radius * 1.5     -- вертикальный шаг
    
    self.gridWidth = gridWidth
    self.gridHeight = gridHeight
    
    self.offsetX = 0
    self.offsetY = 0
    
    self.hoverQ = -1
    self.hoverR = -1
    self.selectedQ = -1
    self.selectedR = -1
    
    return self
end

-- Корректное преобразование пикселей в координаты гекса (flat-top)
function HexGrid:pixelToHex(px, py)
    -- Применяем смещение
    local x = px - self.offsetX
    local y = py - self.offsetY
    
    -- Грубое определение строки
    local r = math.floor(y / self.hexHeight)
    
    -- Ширина гекса + учёт смещения для чётных/нечётных строк
    local hexWidthFull = self.hexWidth
    local xOffsetForRow = (r % 2) * (hexWidthFull / 2)
    
    -- Грубое определение колонки
    local q = math.floor((x - xOffsetForRow) / hexWidthFull)
    
    -- Ограничиваем, чтобы не выходить за границы
    q = math.max(0, math.min(q, self.gridWidth - 1))
    r = math.max(0, math.min(r, self.gridHeight - 1))
    
    -- Уточняем, проверяя соседние гексы
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

-- Конвертация координат гекса в пиксели (центр гекса)
function HexGrid:hexToPixel(q, r)
    local x = (q + (r % 2) * 0.5) * self.hexWidth
    local y = r * self.hexHeight
    return x + self.offsetX, y + self.offsetY
end

-- Получение соседей гекса
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

function HexGrid:isValidHex(q, r)
    return q >= 0 and q < self.gridWidth and r >= 0 and r < self.gridHeight
end

-- Расстояние между гексами (кубические координаты)
function HexGrid:getDistance(q1, r1, q2, r2)
    local function axialToCube(q, r)
        local x = q
        local z = r - (q - (q % 2)) / 2
        local y = -x - z
        return x, y, z
    end
    
    local x1, y1, z1 = axialToCube(q1, r1)
    local x2, y2, z2 = axialToCube(q2, r2)
    return (math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)) / 2
end

-- Отрисовка шестиугольника с возможностью перекрытия (только визуал)
function HexGrid:drawHexagon(x, y, radius)
    local drawRadius = radius
    local vertices = {}
    for i = 0, 5 do
        local angle = math.rad(60 * i + 30)  -- flat-top
        local vx = x + math.cos(angle) * drawRadius
        local vy = y + math.sin(angle) * drawRadius
        table.insert(vertices, vx)
        table.insert(vertices, vy)
    end
    return vertices
end

function HexGrid:centerOnScreen(screenWidth, screenHeight)
    local mapWidth = (self.gridWidth + 0.5) * self.hexWidth
    local mapHeight = self.gridHeight * self.hexHeight
    self.offsetX = (screenWidth - mapWidth) / 2
    self.offsetY = (screenHeight - mapHeight) / 2
end

return HexGrid