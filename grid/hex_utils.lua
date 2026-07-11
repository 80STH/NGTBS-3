local hex_utils = {}
hex_utils.orientation = "pointy"

function hex_utils.setOrientation(orientation)
    hex_utils.orientation = orientation
end

function hex_utils.axialToCube(q, r)
    local x, z
    if hex_utils.orientation == "flat" then
        x = q
        z = r - math.floor((q - (q % 2)) / 2)
    else
        x = q - math.floor((r - (r % 2)) / 2)
        z = r
    end
    local y = -x - z
    return x, y, z
end

function hex_utils.cubeToAxial(x, y, z)
    local q, r
    if hex_utils.orientation == "flat" then
        q = x
        r = z + math.floor((x - (x % 2)) / 2)
    else
        q = x + math.floor((z - (z % 2)) / 2)
        r = z
    end
    return q, r
end

function hex_utils.applyCubeStep(q, r, stepX, stepY, stepZ)
    local x, y, z = hex_utils.axialToCube(q, r)
    x = x + stepX
    y = y + stepY
    z = z + stepZ
    return hex_utils.cubeToAxial(x, y, z)
end

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

hex_utils.applyCubeDiff = hex_utils.applyCubeStep

-- Step one hex from (fromQ, fromR) toward (toQ, toR) along the straight cube line.
-- Standard axial-cube rounding: pick the cube direction closest to the diff by
-- taking the sign of the two largest-magnitude components (smallest stays 0),
-- and flipping the third sign so the step is a valid cube neighbor.
function hex_utils.axialStepToward(fromQ, fromR, toQ, toR)
    if fromQ == toQ and fromR == toR then return fromQ, fromR end
    local x, y, z = hex_utils.axialToCube(fromQ, fromR)
    local tx, ty, tz = hex_utils.axialToCube(toQ, toR)
    local dx, dy, dz = tx - x, ty - y, tz - z
    if dx == 0 and dy == 0 and dz == 0 then return fromQ, fromR end
    local function sgn(v) if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end end
    local sx, sy, sz = sgn(dx), sgn(dy), sgn(dz)
    local ax, ay, az = math.abs(dx), math.abs(dy), math.abs(dz)
    -- Adjust the smallest-magnitude sign so that sx+sy+sz == 0 (cube step).
    if ax <= ay and ax <= az then
        sx = -(sy + sz)
    elseif ay <= ax and ay <= az then
        sy = -(sx + sz)
    else
        sz = -(sx + sy)
    end
    return hex_utils.cubeToAxial(x + sx, y + sy, z + sz)
end

function hex_utils.rotateCubeDir(dx, dy, dz, clockwise)
    if clockwise then
        return -dy, -dz, -dx
    else
        return -dz, -dx, -dy
    end
end

hex_utils.CUBE_DIRECTIONS = {
    {dx = 1, dy = -1, dz = 0},
    {dx = 1, dy = 0, dz = -1},
    {dx = 0, dy = 1, dz = -1},
    {dx = -1, dy = 1, dz = 0},
    {dx = -1, dy = 0, dz = 1},
    {dx = 0, dy = -1, dz = 1},
}

function hex_utils.isPushFromSafeSide(entity, fromQ, fromR)
    if not entity.direction then return true end
    local toQ, toR = entity.q, entity.r
    local dx, dy, dz = hex_utils.getCubeDiff(toQ, toR, fromQ, fromR)
    local dot = dx * entity.direction.dx + dy * entity.direction.dy + dz * entity.direction.dz
    return dot <= 0
end

return hex_utils