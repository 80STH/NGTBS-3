-- attack_effects.lua
-- Visual effects for each attack

local visual = require("system.visual_effects")
local hex_utils = require("grid.hex_utils")

local attack_effects = {}

-- Helper: get the hex center coordinates
local function getHexCenter(entity, hex)
    if not entity then return 0, 0 end
    return hex:hexToPixel(entity.q, entity.r)
end

-- Effect for Dash (lunge with strike)
function attack_effects.dash(attacker, target, targetQ, targetR, hex)
    -- Movement effect from attacker to target cell
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = hex:hexToPixel(targetQ, targetR)
    visual.addDashEffect(fromX, fromY, toX, toY)
    -- Hit on target
    if target then
        local x, y = getHexCenter(target, hex)
        visual.addEffect(x, y, "hit", 0.3)
        visual.addShockwave(x, y, 15)
    end
end

-- Effect for Flip
function attack_effects.flip(attacker, target, behindQ, behindR, hex)
    local fromX, fromY = getHexCenter(target, hex)
    local toX, toY = hex:hexToPixel(behindQ, behindR)
    -- Flip arc
    visual.addArcEffect(fromX, fromY, toX, toY, 0.2, 0.8, 0.2)
    -- Small flash at the landing spot
    visual.addEffect(toX, toY, "hit", 0.2)
end

-- Effect for Shoot (shot with knockback)
function attack_effects.shoot(attacker, target, pushToQ, pushToR, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local targetX, targetY = getHexCenter(target, hex)
    -- Shot line
    visual.addLineEffect(fromX, fromY, targetX, targetY, 0.9, 0.7, 0.2, 3)
    -- Hit
    visual.addEffect(targetX, targetY, "hit", 0.3)
    -- Knockback effect (if any)
    if pushToQ and pushToR then
        local pushX, pushY = hex:hexToPixel(pushToQ, pushToR)
        visual.addPushEffect(targetX, targetY, pushX, pushY, 0.2)
    end
end

-- Effect for Piercing Shot
function attack_effects.piercingShoot(attacker, firstTarget, secondTarget, firstPushQ, firstPushR, secondPushQ, secondPushR, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    -- Line across the full length to the second target
    local lastTarget = secondTarget or firstTarget
    local toX, toY = getHexCenter(lastTarget, hex)
    visual.addLineEffect(fromX, fromY, toX, toY, 0.8, 0.5, 1.0, 4)
    -- Hit on the first target
    if firstTarget then
        local fx, fy = getHexCenter(firstTarget, hex)
        visual.addEffect(fx, fy, "hit", 0.25)
        -- Sparks
        visual.addSpark(fx, fy, 6)
        -- Knockback effect for the first target
        if firstPushQ and firstPushR then
            local pushX, pushY = hex:hexToPixel(firstPushQ, firstPushR)
            visual.addPushEffect(fx, fy, pushX, pushY, 0.2)
        end
    end
    -- Hit on the second target (main damage)
    if secondTarget then
        local sx, sy = getHexCenter(secondTarget, hex)
        visual.addEffect(sx, sy, "hit", 0.4)
        visual.addBloodSplat(sx, sy)
        -- Knockback effect for the second target
        if secondPushQ and secondPushR then
            local pushX, pushY = hex:hexToPixel(secondPushQ, secondPushR)
            visual.addPushEffect(sx, sy, pushX, pushY, 0.2)
        end
    end
end

-- Effect for Stone Throw (AoePushAttack)
function attack_effects.stoneThrow(centerQ, centerR, pushedTargets, hex)
    local centerX, centerY = hex:hexToPixel(centerQ, centerR)
    if terrainMap and terrainMap[centerQ] and terrainMap[centerQ][centerR] == "water" then
        visual.addEffect(centerX, centerY, "drown", 0.4)
        for _, target in ipairs(pushedTargets) do
            if target and target.entity then
                local tx, ty = hex:hexToPixel(target.entity.q, target.entity.r)
                local ptx, pty = hex:hexToPixel(target.pushTo.q, target.pushTo.r)
                visual.addPushEffect(tx, ty, ptx, pty, 0.2)
            end
        end
    else
        visual.addGroundSlam(centerX, centerY, hex)
    end
end

-- Effect for Cone Blast (AoeDirectionalAttack)
function attack_effects.coneBlast(centerQ, centerR, hex)
    local cx, cy = hex:hexToPixel(centerQ, centerR)
    visual.addEffect(cx, cy, "hit", 0.35)
    -- Diverging lines
    for i = 1, 3 do
        local angle = math.rad(30 + i * 40)
        local dx = math.cos(angle) * 40
        local dy = math.sin(angle) * 40
        visual.addLineEffect(cx, cy, cx + dx, cy + dy, 1, 0.5, 0, 2)
    end
end

-- Effect for Magic Bolt (Beam)
function attack_effects.magicBolt(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    local midX = (fromX + toX) / 2
    local midY = (fromY + toY) / 2
    local ctrlX = midX
    local ctrlY = midY - 60   -- always upward
    visual.addArcEffect(fromX, fromY, toX, toY, 0.6, 0.2, 1.0, 0.25, ctrlX, ctrlY)
    visual.addEffect(toX, toY, "hit", 0.4)
    visual.addMagicExplosion(toX, toY, 0.8, 0.2, 1.0)
end

-- Effect for Ghost Bolt (ghostly projectile)
function attack_effects.ghostBolt(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    -- Semi-transparent line with "ghostly" glow
    visual.addLineEffect(fromX, fromY, toX, toY, 0.7, 0.3, 1.0, 2, 0.6)
    -- "Ghostly" hit effect
    visual.addEffect(toX, toY, "ghost_hit", 0.4)
end

-- Effect for Bite (zombie bite)
function attack_effects.bite(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    -- Red flash and blood
    visual.addEffect(toX, toY, "hit", 0.25)
    visual.addBloodSplat(toX, toY)
    -- Jaw animation (line from attacker to target)
    visual.addLineEffect(fromX, fromY, toX, toY, 0.9, 0.2, 0.2, 4, 0.8)
end

-- Effect for Rampage (Colossus charge)
function attack_effects.rampage(attacker, target, targetQ, targetR, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = hex:hexToPixel(targetQ, targetR)
    visual.addDashEffect(fromX, fromY, toX, toY)
    if target then
        local x, y = getHexCenter(target, hex)
        visual.addEffect(x, y, "hit", 0.5)
        visual.addShockwave(x, y, 25)
        visual.addBloodSplat(x, y)
    end
end

-- Effect for Frenzy (Provoker)
function attack_effects.frenzy(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    visual.addLineEffect(fromX, fromY, toX, toY, 1.0, 0.15, 0.1, 5, 1.0)
    visual.addEffect(toX, toY, "hit", 0.5)
    visual.addBloodSplat(toX, toY)
end

-- Effect for Hunt (Provoker push into Colossus)
function attack_effects.hunt(attacker, target, colossus, hex)
    if target then
        local tx, ty = getHexCenter(target, hex)
        visual.addEffect(tx, ty, "hit", 0.4)
        visual.addBloodSplat(tx, ty)
    end
    if colossus then
        local cx, cy = getHexCenter(colossus, hex)
        visual.addEffect(cx, cy, "collision", 0.3)
    end
end

-- Effect for Mighty Throw (Colossus throws a target)
function attack_effects.mightyThrow(attacker, thrownTarget, struckTarget, impactQ, impactR, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = hex:hexToPixel(impactQ, impactR)
    local midX = (fromX + toX) / 2
    local midY = (fromY + toY) / 2
    local ctrlX = midX
    local ctrlY = midY - 50
    visual.addArcEffect(fromX, fromY, toX, toY, 0.9, 0.4, 0.1, 0.3, ctrlX, ctrlY)
    if struckTarget then
        visual.addEffect(toX, toY, "hit", 0.5)
        visual.addShockwave(toX, toY, 20)
        visual.addBloodSplat(toX, toY)
    else
        visual.addEffect(toX, toY, "slam", 0.4)
    end
end

return attack_effects