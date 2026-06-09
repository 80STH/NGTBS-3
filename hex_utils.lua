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

function hex_utils.getCubeDiff(fromQ, fromR, toQ, toR)
    local fx, fy, fz = hex_utils.axialToCube(fromQ, fromR)
    local tx, ty, tz = hex_utils.axialToCube(toQ, toR)
    return tx - fx, ty - fy, tz - fz
end

function hex_utils.applyCubeDiff(q, r, dx, dy, dz)
    local x, y, z = hex_utils.axialToCube(q, r)
    return hex_utils.cubeToAxial(x + dx, y + dy, z + dz)
end

-- Поворот кубического направления на 60°
-- clockwise=true: по часовой стрелке, false: против часовой
function hex_utils.rotateCubeDir(dx, dy, dz, clockwise)
    if clockwise then
        return -dy, -dz, -dx
    else
        return -dz, -dx, -dy
    end
end

return hex_utils