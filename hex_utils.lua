-- hex_utils.lua
-- Утилиты для работы с гексагональными координатами (pointy-top, odd-r)
local hex_utils = {}

-- Преобразование axial (q,r) в кубические координаты (x,y,z)
function hex_utils.axialToCube(q, r)
    local x = q - (r - (r % 2)) / 2
    local z = r
    local y = -x - z
    return x, y, z
end

-- Преобразование кубических координат в axial
function hex_utils.cubeToAxial(x, y, z)
    local q = x + (z - (z % 2)) / 2
    local r = z
    return q, r
end

-- Применение шага в кубических координатах к axial координатам
function hex_utils.applyCubeStep(q, r, stepX, stepY, stepZ)
    local x, y, z = hex_utils.axialToCube(q, r)
    x = x + stepX
    y = y + stepY
    z = z + stepZ
    return hex_utils.cubeToAxial(x, y, z)
end

-- Расстояние между двумя гексами в axial координатах
function hex_utils.getDistance(q1, r1, q2, r2)
    local x1, y1, z1 = hex_utils.axialToCube(q1, r1)
    local x2, y2, z2 = hex_utils.axialToCube(q2, r2)
    return (math.abs(x1 - x2) + math.abs(y1 - y2) + math.abs(z1 - z2)) / 2
end

-- Возвращает индекс стороны (0..5) от атакующего к цели
-- Стороны: 0=E, 1=NE, 2=NW, 3=W, 4=SW, 5=SE (для flat-top)
function hex_utils.getDirectionIndex(attackerQ, attackerR, targetQ, targetR)
    local ax, ay, az = hex_utils.axialToCube(attackerQ, attackerR)
    local tx, ty, tz = hex_utils.axialToCube(targetQ, targetR)
    local dx = tx - ax
    local dy = ty - ay
    local dz = tz - az
    -- Нормализация до единичного шага
    local function gcd(a,b) while b~=0 do a,b=b,a%b end return math.abs(a) end
    local g = gcd(gcd(dx, dy), dz)
    if g == 0 then return nil end
    dx = dx / g
    dy = dy / g
    dz = dz / g
    -- Сопоставление с направлениями
    local dirs = {
        {1,-1,0}, {1,0,-1}, {0,1,-1},
        {-1,1,0}, {-1,0,1}, {0,-1,1}
    }
    for i, d in ipairs(dirs) do
        if dx == d[1] and dy == d[2] and dz == d[3] then
            return i-1  -- 0..5
        end
    end
    return nil
end

return hex_utils