-- attack_effects.lua
-- Визуальные эффекты для каждой атаки

local visual = require("visual_effects")
local hex_utils = require("hex_utils")

local attack_effects = {}

-- Вспомогательная: получить координаты центра гекса
local function getHexCenter(entity, hex)
    if not entity then return 0, 0 end
    return hex:hexToPixel(entity.q, entity.r)
end

-- Эффект для Dash (рывок с ударом)
function attack_effects.dash(attacker, target, lastFreeCell, hex)
    -- Эффект движения от атакующего до последней свободной клетки
    if lastFreeCell then
        local fromX, fromY = getHexCenter(attacker, hex)
        local toX, toY = hex:hexToPixel(lastFreeCell.q, lastFreeCell.r)
        visual.addDashEffect(fromX, fromY, toX, toY)
    end
end

-- Эффект для Flip (переворот)
function attack_effects.flip(attacker, target, behindQ, behindR, hex)
    local fromX, fromY = getHexCenter(target, hex)
    local toX, toY = hex:hexToPixel(behindQ, behindR)
    -- Дуга переворота
    visual.addArcEffect(fromX, fromY, toX, toY, 0.2, 0.8, 0.2)
    -- Маленькая вспышка в месте приземления
    visual.addEffect(toX, toY, "hit", 0.2)
end

-- Эффект для Shoot (выстрел с отталкиванием)
function attack_effects.shoot(attacker, target, pushToQ, pushToR, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local targetX, targetY = getHexCenter(target, hex)
    -- Линия выстрела
    visual.addLineEffect(fromX, fromY, targetX, targetY, 0.9, 0.7, 0.2, 3)
    -- Попадание
    visual.addEffect(targetX, targetY, "hit", 0.3)
    -- Эффект отталкивания (если есть)
    if pushToQ and pushToR then
        local pushX, pushY = hex:hexToPixel(pushToQ, pushToR)
        visual.addPushEffect(targetX, targetY, pushX, pushY, 0.2)
    end
end

-- Эффект для Piercing Shot (пронзающий выстрел)
function attack_effects.piercingShoot(attacker, firstTarget, secondTarget, stepX, stepY, stepZ, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    -- Линия на всю длину до второй цели
    local lastTarget = secondTarget or firstTarget
    local toX, toY = getHexCenter(lastTarget, hex)
    visual.addLineEffect(fromX, fromY, toX, toY, 0.8, 0.5, 1.0, 4)
    -- Попадание в первую цель
    if firstTarget then
        local fx, fy = getHexCenter(firstTarget, hex)
        visual.addEffect(fx, fy, "hit", 0.25)
        -- Искры
        visual.addSpark(fx, fy, 6)
    end
    -- Попадание во вторую цель (основной урон)
    if secondTarget then
        local sx, sy = getHexCenter(secondTarget, hex)
        visual.addEffect(sx, sy, "hit", 0.4)
        visual.addBloodSplat(sx, sy)
    end
end

-- Эффект для Stone Throw (AoePushAttack)
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

-- Эффект для Cone Blast (AoeDirectionalAttack)
function attack_effects.coneBlast(centerQ, centerR, hex)
    local cx, cy = hex:hexToPixel(centerQ, centerR)
    visual.addEffect(cx, cy, "hit", 0.35)
    -- Расходящиеся линии
    for i = 1, 3 do
        local angle = math.rad(30 + i * 40)
        local dx = math.cos(angle) * 40
        local dy = math.sin(angle) * 40
        visual.addLineEffect(cx, cy, cx + dx, cy + dy, 1, 0.5, 0, 2)
    end
end

-- Эффект для Magic Bolt (Луч)
function attack_effects.magicBolt(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    local midX = (fromX + toX) / 2
    local midY = (fromY + toY) / 2
    local ctrlX = midX
    local ctrlY = midY - 60   -- всегда вверх
    visual.addArcEffect(fromX, fromY, toX, toY, 0.6, 0.2, 1.0, 0.25, ctrlX, ctrlY)
    visual.addEffect(toX, toY, "hit", 0.4)
    visual.addMagicExplosion(toX, toY, 0.8, 0.2, 1.0)
end

-- Эффект для Ghost Bolt (призрачный снаряд)
function attack_effects.ghostBolt(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    -- Полупрозрачная линия с "призрачным" свечением
    visual.addLineEffect(fromX, fromY, toX, toY, 0.7, 0.3, 1.0, 2, 0.6)
    -- Эффект "призрачного" попадания
    visual.addEffect(toX, toY, "ghost_hit", 0.4)
end

-- Эффект для Bite (укус зомби)
function attack_effects.bite(attacker, target, hex)
    local fromX, fromY = getHexCenter(attacker, hex)
    local toX, toY = getHexCenter(target, hex)
    -- Красная вспышка и кровь
    visual.addEffect(toX, toY, "hit", 0.25)
    visual.addBloodSplat(toX, toY)
    -- Анимация челюстей (линия от атакующего к цели)
    visual.addLineEffect(fromX, fromY, toX, toY, 0.9, 0.2, 0.2, 4, 0.8)
end

return attack_effects