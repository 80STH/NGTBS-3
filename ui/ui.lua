-- ui.lua
-- All UI functions (buttons, panels, attack preview, movement, etc.)
local ui = {}
local pathfinding = require("grid.pathfinding")
local combat = require("combat.combat")
local visual = require("system.visual_effects")
local hex_utils = require("grid.hex_utils")
local cell_rules = require("grid.cell_rules")
local fonts = require("util.fonts")
local trains = require("system.trains")
local attack_preview = require("ui.attack_preview")
require("ui.ui_buttons")(ui)
require("ui.ui_status_effects")(ui)
-- ============================================================
-- HELPER FUNCTIONS FOR ATTACK PREVIEW
-- ============================================================
local hazardTexture = nil
-- Returns real coordinates for entity rendering (accounting for animations)
local function getEntityDisplayPosition(entity, hex)
    if not entity then return nil, nil end
    if entity.currentDrawX and entity.currentDrawY then
        return entity.currentDrawX, entity.currentDrawY
    end
    return getDrawCoords(entity.q, entity.r)
end
function ui.getHazardTexture()
    if hazardTexture then return hazardTexture end
    local size = 64
    local canvas = love.graphics.newCanvas(size, size)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 0.2, 0.2, 0.85)
    love.graphics.setLineWidth(2)
    for i = -size, size, 10 do
        love.graphics.line(i, 0, i + size, size)
        love.graphics.line(0, i, size, i + size)
    end
    love.graphics.setCanvas()
    hazardTexture = canvas
    return hazardTexture
end
-- Checks whether the actor can reach the cell (considering obstacles and path length)
function ui.getEffectiveMoveRange(actor, entities, hex)
    if actor.teleporting then return math.huge end
    if status and status.hasEntityStatus and status.hasEntityStatus(actor, "rooted") and not actor.rootImmune then
        return 0
    end
    if status and status.hasEntityStatus and status.hasEntityStatus(actor, "stasis") then
        return 0
    end
    local base = actor.moveRange or 0
    if status and status.hasEntityStatus and status.hasEntityStatus(actor, "empowered") then
        base = base + 1
    end
    if status and status.isWounded and status.isWounded(actor) then
        base = base - 1
    end
    if combat and combat.isInSlowingAura and entities and hex then
        if combat.isInSlowingAura(actor, entities, hex) then
            base = math.max(1, base - 2)
        end
    end
    return math.max(0, base)
end
function ui.isCellReachable(actor, targetQ, targetR, entities, terrainMap, hex)
    if not hex:isActiveHex(targetQ, targetR) then return false end
    
    if actor.teleporting then
        if cell_rules.isOccupiedForStop(targetQ, targetR, actor) then
            return false
        end
        return true
    end
    
    -- Water is impassable (except for flying/hovering)
    if terrainMap and terrainMap[targetQ] and terrainMap[targetQ][targetR] == "water" then
        if not (actor and (actor.flying or actor.hovering)) then
            return false
        end
    end
    -- The cell must not be occupied (for stopping)
    if cell_rules.isOccupiedForStop(targetQ, targetR, actor) then
        return false
    end
    
    -- Pathfinding with range limit and blockers
    local effectiveRange = ui.getEffectiveMoveRange(actor, entities, hex)
    local isBlockedFn
    local isOccupiedFn
    if actor.flying then
        isBlockedFn = function(q, r) return not hex:isActiveHex(q, r) end
    else
        isBlockedFn = function(q, r) return cell_rules.isOccupied(q, r, actor) end
        isOccupiedFn = function(q, r)
            local e = getEntityAtHex(q, r)
            return e and e ~= actor and not e.isHazard
        end
    end
    local path = pathfinding.findPath(actor.q, actor.r, targetQ, targetR, effectiveRange,
        isBlockedFn, hex, isOccupiedFn)
    
    return path ~= nil and #path > 0
end
function ui.drawPathPreview(hex, actor, hoverQ, hoverR, entities, terrainMap)
    if actor.hasMovedThisTurn and not actor.canMoveAfterAttack then return end
    if actor.hasActedThisTurn and not actor.canMoveAfterAttack then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end
    if actor.teleporting then return end
    local effectiveRange = ui.getEffectiveMoveRange(actor, entities, hex)
    local dist = hex:getDistance(actor.q, actor.r, hoverQ, hoverR)
    if dist > effectiveRange then return end
    -- Don't show path if the cell is occupied (by ally or enemy)
    if cell_rules.isOccupiedForStop(hoverQ, hoverR, actor) then
        return
    end
    local path = pathfinding.findPath(actor.q, actor.r, hoverQ, hoverR, effectiveRange,
        function(q, r) return not cell_rules.isPassable(q, r, actor) end, hex,
        function(q, r) local e = getEntityAtHex(q, r); return e and e ~= actor and not e.isHazard end)
    if not path or #path == 0 then return end
    -- Draw line
    local points = {}
    local startX, startY = getDrawCoords(actor.q, actor.r)
    table.insert(points, {x = startX, y = startY})
    for _, step in ipairs(path) do
        local x, y = getDrawCoords(step.q, step.r)
        table.insert(points, {x = x, y = y})
    end
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.2, 0.8, 0.2, 0.8)
    for i = 1, #points - 1 do
        love.graphics.line(points[i].x, points[i].y, points[i+1].x, points[i+1].y)
    end
    local targetX, targetY = points[#points].x, points[#points].y
    -- Draw transparent silhouette at origin (no blinking)
    if actor.sprite then
        love.graphics.setColor(1, 1, 1, 0.5)
        local sw, sh = actor.sprite:getDimensions()
        local scale = 5.9
        love.graphics.draw(actor.sprite, startX, startY, 0, scale, scale, sw/2, sh/2)
    else
        love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
        love.graphics.circle("fill", startX, startY, hex.radius * 0.5)
    end
    -- Draw unit at target (opaque)
    if actor.sprite then
        love.graphics.setColor(1, 1, 1, 1)
        local sw, sh = actor.sprite:getDimensions()
        local scale = 6
        love.graphics.draw(actor.sprite, targetX, targetY, 0, scale, scale, sw/2, sh/2)
    else
        love.graphics.setColor(0.2, 0.8, 0.2, 1)
        love.graphics.circle("fill", targetX, targetY, hex.radius * 0.5)
    end
    local vertices = hex:drawHexagon(targetX, targetY, hex.radius)
    love.graphics.setColor(0.2, 0.8, 0.2, 0.6)
    love.graphics.polygon("line", vertices)
    love.graphics.setLineWidth(1)
end
-- Kept for external callers; new code uses attack_preview.predictCollision.
function ui.checkCollisionDamage(entity, fromQ, fromR, toQ, toR, hex, entities)
    local col = attack_preview.predictCollision(entity, fromQ, fromR, toQ, toR, hex, entities)
    return col.damage, col.reason, col.occupant
end
-- Draw push arrow (with offset from centers)
function ui.drawPushArrow(fromX, fromY, toX, toY, r, g, b, alpha, fromQ, fromR, toQ, toR, scale)
    local isLowTerrain = function(q, r) local t = terrainMap and terrainMap[q] and terrainMap[q][r]; return t == "water" end
    if fromQ ~= nil and isLowTerrain(fromQ, fromR) then
        fromY = fromY - config.WATER_Y_OFFSET
    end
    if toQ ~= nil and isLowTerrain(toQ, toR) then
        toY = toY - config.WATER_Y_OFFSET
    end
    local angle = math.atan2(toY - fromY, toX - fromX)
    local s = scale or 1
    local arrowSize = 8 * s
    local lineWidth = 2 * s
    local radius = hex.radius
    local offset = radius * 0.3
    local startX = fromX + math.cos(angle) * offset
    local startY = fromY + math.sin(angle) * offset
    local endX = toX - math.cos(angle) * offset
    local endY = toY - math.sin(angle) * offset
    local cr = r or 1
    local cg = g or 0.8
    local cb = b or 0.2
    local ca = alpha or 0.9
    -- Shadow
    local shadowOff = 2 * s
    love.graphics.setColor(0, 0, 0, ca * 0.35)
    love.graphics.setLineWidth(lineWidth + 2 * s)
    love.graphics.line(startX + shadowOff, startY + shadowOff, endX + shadowOff, endY + shadowOff)
    -- Arrow (line)
    love.graphics.setColor(cr, cg, cb, ca)
    love.graphics.setLineWidth(lineWidth)
    love.graphics.line(startX, startY, endX, endY)
    love.graphics.setLineWidth(1)
    -- Triangular arrowhead
    local headLen = arrowSize
    local headWidth = headLen * 0.5
    local lx = endX + math.cos(angle + math.pi * 0.85) * headWidth
    local ly = endY + math.sin(angle + math.pi * 0.85) * headWidth
    local rx = endX + math.cos(angle - math.pi * 0.85) * headWidth
    local ry = endY + math.sin(angle - math.pi * 0.85) * headWidth
    local tipX = endX + math.cos(angle) * headLen
    local tipY = endY + math.sin(angle) * headLen
    love.graphics.setColor(0, 0, 0, ca * 0.35)
    love.graphics.polygon("fill", tipX + shadowOff * 0.5, tipY + shadowOff * 0.5, lx + shadowOff * 0.5, ly + shadowOff * 0.5, rx + shadowOff * 0.5, ry + shadowOff * 0.5)
    love.graphics.setColor(cr, cg, cb, ca)
    love.graphics.polygon("fill", tipX, tipY, lx, ly, rx, ry)
end
function ui.drawVerticalArrow(x, y, direction, r, g, b, alpha)
    local sz = 38
    local hw = 12
    local cr, cg, cb = r or 1, g or 0.25, b or 0.25
    local ca = alpha or 0.9
    local dy = direction == "up" and -1 or 1
    local tipY = y + dy * sz * 0.5
    local baseY = y - dy * sz * 0.5
    love.graphics.setColor(0, 0, 0, ca * 0.4)
    love.graphics.setLineWidth(5)
    love.graphics.line(x + 2, baseY + 2, x + 2, tipY + 2)
    love.graphics.setColor(cr, cg, cb, ca)
    love.graphics.setLineWidth(3)
    love.graphics.line(x, baseY, x, tipY)
    love.graphics.setLineWidth(1)
    local lx, ly = x - hw, tipY - dy * hw
    local rx, ry = x + hw, tipY - dy * hw
    love.graphics.setColor(0, 0, 0, ca * 0.4)
    love.graphics.polygon("fill", x + 2, tipY + 2, lx + 2, ly + 2, rx + 2, ry + 2)
    love.graphics.setColor(cr, cg, cb, ca)
    love.graphics.polygon("fill", x, tipY, lx, ly, rx, ry)
end
function ui.drawRedCircleWithShadow(x, y, radius, alpha)
    alpha = alpha or 0.85
    local scale = alpha / 0.85
    love.graphics.setColor(0, 0, 0, 0.4 * scale)
    love.graphics.circle("fill", x + 2, y + 4, radius)
    love.graphics.setColor(0.85, 0.15, 0.15, alpha)
    love.graphics.circle("fill", x, y, radius)
end
local icon_cache = require("ui.icon_cache")

function ui.willKillTarget(target, attacker, baseDamage, directionIndex, dist)
    local eff = attack_preview.calculateEffectiveDamage(target, attacker, baseDamage, directionIndex, dist)
    return attack_preview.willKill(target, eff)
end

function ui.willKillByCollision(target, collisionDamage)
    return attack_preview.willKill(target, collisionDamage)
end

function ui.getEffectIcon(entity, attackDmg, collisionDmg, attacker, directionIndex, dist)
    local total = (attackDmg or 0) + (collisionDmg or 0)
    if total <= 0 then return nil end
    return attack_preview.getDamageIcon(entity, total)
end

function ui.drawPreviewIcons(hex, icons)
    if not icons then return end
    for _, ic in ipairs(icons) do
        icon_cache.draw(ic.icon, ic.x, ic.y, 0.95)
    end
end

function ui.drawPreviewPushArrows(arrows)
    if not arrows then return end
    for _, arrow in ipairs(arrows) do
        ui.drawPushArrow(arrow.fromX, arrow.fromY, arrow.toX, arrow.toY, nil, nil, nil, nil, arrow.fromQ, arrow.fromR, arrow.toQ, arrow.toR)
    end
end

function ui.collectPreviewIcons(hex, attacker, attack, hoverQ, hoverR, entities)
    if not attack or not attacker then return nil end
    local p = attack_preview.compute(hex, attacker, attack, hoverQ, hoverR, entities)
    return attack_preview.buildIcons(p, hex)
end

function ui.collectPreviewPushArrows(hex, attacker, attack, hoverQ, hoverR, entities)
    if not attack or not attacker then return nil end
    local p = attack_preview.compute(hex, attacker, attack, hoverQ, hoverR, entities)
    return attack_preview.buildPushArrows(p, hex)
end
-- ============================================================
-- MAIN UI FUNCTIONS, CALLED FROM MAIN.LUA
-- ============================================================
function ui.drawPreparedAttacks(hex, entities)
    local threatMap = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.preparedAttack then
            local cell = ui.getPreparedAttackTarget(e, entities, hex)
            if cell then
                local key = cell.q .. "," .. cell.r
                if not threatMap[key] then threatMap[key] = 0 end
                threatMap[key] = threatMap[key] + 1
                local targetEntity = getEntityAtHex(cell.q, cell.r, entities)
                local x, y
                if targetEntity and targetEntity.currentDrawX and targetEntity.currentDrawY then
                    x, y = targetEntity.currentDrawX, targetEntity.currentDrawY
                else
                    x, y = getDrawCoords(cell.q, cell.r)
                end
                if targetEntity and targetEntity.health > 0 then
                end
            end
        end
    end
    for cellKey, count in pairs(threatMap) do
        local q, r = cellKey:match("^(%d+),(%d+)$")
        q, r = tonumber(q), tonumber(r)
        local x, y = getDrawCoords(q, r)
        local vertices = hex:drawInsetHexagon(x, y, hex.radius, 0.92)
        local threatCount = math.min(count, 3)
        local alpha, rCol, gCol, bCol, scaleMod
        if threatCount == 1 then
            alpha, rCol, gCol, bCol, scaleMod = 0.5, 1, 0.5, 0.2, 1.0
        elseif threatCount == 2 then
            alpha, rCol, gCol, bCol, scaleMod = 0.75, 1, 0.3, 0.1, 1.2
        else
            alpha, rCol, gCol, bCol, scaleMod = 1.0, 1, 0, 0, 1.4
        end
        local pulse = 1.0
        if threatCount <= 2 then
            local t = love.timer.getTime()
            pulse = 0.7 + 0.3 * math.sin(t * (5 + threatCount * 3))
            alpha = alpha * pulse
        end
        love.graphics.stencil(function()
            love.graphics.polygon("fill", vertices)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        local tex = ui.getHazardTexture()
        love.graphics.setColor(rCol, gCol, bCol, alpha)
        if threatCount >= 2 then
            love.graphics.draw(tex, x - hex.radius - 2, y - hex.radius - 2, 0,
                               hex.radius * 2 / tex:getWidth() * scaleMod,
                               hex.radius * 2 / tex:getHeight() * scaleMod)
            love.graphics.draw(tex, x - hex.radius + 2, y - hex.radius + 2, 0,
                               hex.radius * 2 / tex:getWidth() * scaleMod,
                               hex.radius * 2 / tex:getHeight() * scaleMod)
        end
        love.graphics.draw(tex, x - hex.radius, y - hex.radius, 0,
                           hex.radius * 2 / tex:getWidth() * scaleMod,
                           hex.radius * 2 / tex:getHeight() * scaleMod)
        love.graphics.setStencilTest()
        love.graphics.setColor(rCol, gCol, bCol, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.polygon("line", vertices)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
end
function ui.getPreparedAttackTarget(enemy, entities, hex)
    if not enemy then return nil end
    if enemy.isTrainAttack then
        local group = trains.getCarGroup(enemy)
        if not group or not group.active then return nil end
        local newIdx = group.currentIdx + 1
        if newIdx < 1 or newIdx > #group.path then return nil end
        local target = group.path[newIdx]
        return {q = target.q, r = target.r}
    end
    if not enemy.preparedAttack then return nil end
    local attack = enemy.preparedAttack
    if attack.name == "Ghost Bolt" or attack.name == "Shoot" or attack.name == "Dash" or attack.name == "Piercing Shot" then
        if enemy.attackDirection then
            local step = enemy.attackDirection
            local curQ, curR = enemy.q, enemy.r
            local lastValidQ, lastValidR = curQ, curR
            while true do
                local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                if not hex:isActiveHex(nextQ, nextR) then break end
                local ent = getEntityAtHex(nextQ, nextR, entities)
                if ent and ent ~= enemy and ent.health > 0 then
                    lastValidQ, lastValidR = nextQ, nextR
                    break
                end
                lastValidQ, lastValidR = nextQ, nextR
                curQ, curR = nextQ, nextR
            end
            if lastValidQ ~= enemy.q or lastValidR ~= enemy.r then
                return {q = lastValidQ, r = lastValidR}
            end
        end
    elseif attack.name == "Bite" or attack.name == "Magic Bolt" then
        if enemy.preparedTargetOffset then
            local targetQ, targetR = hex_utils.applyCubeDiff(enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz)
            if hex:isActiveHex(targetQ, targetR) then
                return {q = targetQ, r = targetR}
            end
        end
    end
    return nil
end
function ui.collectPreparedAttackOverlays(hex, entities, out)
    for _, e in ipairs(entities) do
        if ((e:isCharacter() and not e.isPlayable) or e.isTrainAttack) and e.hasPreparedAttack then
            local targetCell = ui.getPreparedAttackTarget(e, entities, hex)
            if targetCell then
                local key = targetCell.q .. "," .. targetCell.r
                if not out[key] then out[key] = {threatCount = 0} end
                out[key].threatCount = out[key].threatCount + 1
            end
        end
    end
    for _, info in pairs(out) do
        info.threatCount = math.min(info.threatCount, 3)
    end
    -- Collect direction hatching cells for each enemy's prepared attack
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.preparedAttack then
            local attack = e.preparedAttack
            if attack.getAffectedCells then
                local targetQ, targetR
                if attack.visualType == "line" and e.attackDirection then
                    local step = e.attackDirection
                    local curQ, curR = e.q, e.r
                    while true do
                        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                        if not hex:isActiveHex(nextQ, nextR) then break end
                        local ent = getEntityAtHex(nextQ, nextR, entities)
                        if ent and ent ~= e and ent.health > 0 then
                            targetQ, targetR = nextQ, nextR
                            break
                        end
                        curQ, curR = nextQ, nextR
                    end
                elseif e.preparedTargetOffset then
                    targetQ, targetR = hex_utils.applyCubeDiff(
                        e.q, e.r,
                        e.preparedTargetOffset.dx,
                        e.preparedTargetOffset.dy,
                        e.preparedTargetOffset.dz
                    )
                end
                if targetQ and targetR and hex:isActiveHex(targetQ, targetR) then
                    local cells = attack:getAffectedCells(e, targetQ, targetR, hex, entities)
                    for _, c in ipairs(cells) do
                        local key = c.q .. "," .. c.r
                        if not out[key] then out[key] = {threatDirection = true} end
                    end
                end
            end
        end
    end
end
-- Collects Flip destination overlays into out table when flipTargetActor is selected
function ui.collectFlipDestOverlays(hex, selectedActor, flipTargetActor, attack, entities, out)
    if not selectedActor or not flipTargetActor or not attack then return end
    if attack.name ~= "Flip" then return end
    local cells = attack:getFlipCells(selectedActor, flipTargetActor.q, flipTargetActor.r, hex, entities)
    for _, cell in ipairs(cells) do
        local key = cell.q .. "," .. cell.r
        out[key] = {flipDest = true}
    end
end
function ui.getAttackableCellKeys(hex, attacker, attack, entities)
    local keys = {}
    if not attacker or not attack then return keys end
    if attacker.hasActedThisTurn then return keys end
    -- Precompute common keys for new attacks
    local genericKeys = attack.getTargetCell and attack:getValidTargets(attacker, hex, entities) or nil
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if not hex:isActiveHex(q, r) then
                goto continue
            end
            local dist = hex:getDistance(attacker.q, attacker.r, q, r)
            if dist > attack.range then goto continue end
            local canApply = false
            if attack.name == "Bite" then
                if dist == 1 then
                    local target = getEntityAtHex(q, r, entities)
                    if target and target:isCharacter() and not target.isPlayable then canApply = true end
                end
            elseif attack.name == "Flip" then
                if dist == 1 then
                    local target = getEntityAtHex(q, r, entities)
                    if target and target:isCharacter() and not target:isBuilding() then
                        local cells = attack:getFlipCells(attacker, q, r, hex, entities)
                        if #cells > 0 then canApply = true end
                    end
                end
            elseif attack.name == "Stone Throw" or attack.name == "Cone Blast" then
                local minRange = attack.minRange or 1
                if dist >= minRange then
                    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                    if stepX then canApply = true end
                end
            elseif attack.name == "Magic Bolt" then
                local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                if stepX then
                    local target = getEntityAtHex(q, r, entities)
                    if target and (target:isCharacter() and not target.isPlayable or target:isBuilding()) then canApply = true end
                end
            elseif attack.name == "Ghost Bolt" or attack.name == "Dash" then
                local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                if stepX then
                    local firstTarget, _ = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                    if firstTarget then canApply = true end
                end
            elseif attack.name == "Shoot" or attack.name == "Piercing Shot" or attack.name == "Push" then
                local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                if stepX then canApply = true end
            elseif attack.name == "Summon" or attack.name == "Split" then
                local minRange = attack.minRange or 1
                if dist >= minRange then
                    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                    if stepX then
                        local occupant = getEntityAtHex(q, r, entities)
                        if not occupant then canApply = true end
                    end
                end
            elseif attack.name == "Vortex Strike" or attack.name == "Wide Vortex" then
                if dist >= 1 and dist <= attack.range then
                    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                    if stepX then
                        local occupant = getEntityAtHex(q, r, entities)
                        if occupant and occupant:isCharacter() and occupant.health > 0 and not occupant.isPlayable then
                            canApply = true
                        end
                    end
                end
            elseif attack.name == "Electric Hook" then
                local minRange = attack.minRange or 2
                if dist >= minRange then
                    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, q, r, hex)
                    if stepX then canApply = true end
                end
            elseif genericKeys then
                if genericKeys[q .. "," .. r] then
                    canApply = true
                end
            end
            if canApply then
                keys[q .. "," .. r] = true
            end
            ::continue::
        end
    end
    return keys
end
function ui.collectAttackableCellOverlays(hex, attacker, attack, entities, terrainMap, out)
    local keys = ui.getAttackableCellKeys(hex, attacker, attack, entities)
    for key in pairs(keys) do
        out[key] = true
    end
end
-- Draws health bars for prepared attack targets (called AFTER grid rendering)
function ui.drawPreparedAttackHealthBars(hex, entities)
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.preparedAttack then
            local attack = e.preparedAttack
            local targetCell = ui.getPreparedAttackTarget(e, entities, hex)
            if targetCell then
                local targetEntity = getEntityAtHex(targetCell.q, targetCell.r, entities)
                local x, y
                if targetEntity and targetEntity.currentDrawX and targetEntity.currentDrawY then
                    x, y = targetEntity.currentDrawX, targetEntity.currentDrawY
                else
                    x, y = getDrawCoords(targetCell.q, targetCell.r)
                end
                if targetEntity and targetEntity.health > 0 then
                end
            end
        end
    end
end
-- MAIN ATTACK PREVIEW FUNCTION (called on mouse hover)
function ui.drawAttackPreview(hex, attacker, attack, attackMode, hoverQ, hoverR, entities)
    if not attackMode or not attack then return end
    if not attacker or attacker.hasActedThisTurn then return end
    -- Check whether the attack can be applied to this cell at all
    local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if distance > attack.range then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end
    if attack.getLineDirection then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if not stepX then return end
    end
    -- Analyze attack type and get preview details
    local previewData = nil
    -- Flip: 1 damage, 3 cells for flip
    if attack.name == "Flip" then
        if flipTargetActor then
            local cells = attack:getFlipCells(attacker, flipTargetActor.q, flipTargetActor.r, hex, entities)
            local isValidDest = false
            for _, cell in ipairs(cells) do
                if cell.q == hoverQ and cell.r == hoverR then
                    isValidDest = true
                    break
                end
            end
            if isValidDest then
                local fromX, fromY = getDrawCoords(flipTargetActor.q, flipTargetActor.r)
                local toX, toY = getDrawCoords(hoverQ, hoverR)
                ui.drawPushArrow(fromX, fromY, toX, toY, nil, nil,
                    nil, nil, flipTargetActor.q, flipTargetActor.r, hoverQ, hoverR)
            end
        else
            local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
            if distance == 1 then
                local target = getEntityAtHex(hoverQ, hoverR, entities)
                if target and target.health > 0 then
                    local targetX, targetY = getDrawCoords(hoverQ, hoverR)
                    if target:isBuilding() then
                    end
                    local cells = attack:getFlipCells(attacker, hoverQ, hoverR, hex, entities)
                    local fromX, fromY = getDrawCoords(target.q, target.r)
                    for _, cell in ipairs(cells) do
                        local toX, toY = getDrawCoords(cell.q, cell.r)
                        ui.drawPushArrow(fromX, fromY, toX, toY, nil, nil,
                            nil, nil, target.q, target.r, cell.q, cell.r)
                    end
                end
            end
        end
        return
    end
    -- Ghost Bolt
    if attack.name == "Ghost Bolt" then
        return
    end
    -- Zombie Bite
    if attack.name == "Bite" then
        local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if distance == 1 then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then
                local x, y = getDrawCoords(hoverQ, hoverR)
                if target:isBuilding() then
                end
            end
        end
        return
    end
if attack.name == "Magic Bolt" then
    local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if distance <= attack.range then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then
                local toX, toY = getDrawCoords(hoverQ, hoverR)
                local fromX, fromY = getDrawCoords(attacker.q, attacker.r)
                if target:isBuilding() or (target:isCharacter() and not target.isPlayable) then
                    local dmg = attack.damage or 1
                    if target:isBuilding() then
                    end
                end
            end
        end
    end
    return
end
    if attack.name == "Dash" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex, lastFree = attack:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)
            
            -- Arrow should point to the target, not the cursor
            local indicatorQ, indicatorR
            if firstTarget and targetHex then
                indicatorQ, indicatorR = targetHex.q, targetHex.r
            else
                indicatorQ, indicatorR = hoverQ, hoverR
            end
            
            -- Draw dash trail from attacker to target
            local fromX, fromY = getDrawCoords(attacker.q, attacker.r)
            local toX, toY = getDrawCoords(indicatorQ, indicatorR)
            local trailPulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 6)
            love.graphics.setLineWidth(6)
            love.graphics.setColor(0.3, 1, 0.3, 0.15 * trailPulse)
            love.graphics.line(fromX, fromY, toX, toY)
            love.graphics.setLineWidth(2)
            love.graphics.setColor(0.6, 1, 0.6, 0.4 * trailPulse)
            love.graphics.line(fromX, fromY, toX, toY)
            love.graphics.setLineWidth(1)
            ui.drawPushArrow(fromX, fromY, toX, toY, nil, nil, nil, nil, attacker.q, attacker.r, indicatorQ, indicatorR)
            -- Target marker at impact point
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
            local alpha = 0.4 + 0.4 * pulse
            love.graphics.setColor(1, 1, 0.4, alpha)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", toX, toY, hex.radius * 0.35)
            love.graphics.setLineWidth(1)
            -- Damage to first target + possible knockback damage
            if firstTarget then
                local targetX, targetY = getDrawCoords(firstTarget.q, firstTarget.r)
                local totalDamage = attack.damage or 1
                local pushQ, pushR, isEdge
                if targetHex then
                    pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
                    isEdge = not hex:isActiveHex(pushQ, pushR)
                    if isEdge then
                        totalDamage = totalDamage + 1
                    else
                        local collisionDamage, reason, second = ui.checkCollisionDamage(
                            firstTarget, targetHex.q, targetHex.r, pushQ, pushR, hex, entities
                        )
                        totalDamage = totalDamage + (collisionDamage or 0)
                        if collisionDamage > 0 and second and reason == "collision_both" then
                            local secX, secY = getDrawCoords(second.q, second.r)
                            if second:isBuilding() then
                            end
                        end
                    end
                end
                if firstTarget:isBuilding() then
                end
                
                if targetHex and not isEdge and firstTarget.isPushable then
                    if not combat.getEntityAtHex(pushQ, pushR, entities) then
                        local pushX, pushY = getDrawCoords(pushQ, pushR)
                        ui.drawPushArrow(targetX, targetY, pushX, pushY, nil, nil, nil, nil, firstTarget.q, firstTarget.r, pushQ, pushR)
                    end
                end
            end
            return
        end
    end
    -- Vortex Strike
    if attack.name == "Vortex Strike" then
        local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if distance ~= 1 then return end
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if not stepX then return end
        if not vortexTargetCell then
            -- First click phase: show direction cells only (no damage preview)
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target and target:isCharacter() and target.health > 0 and not target.isPlayable then
                local tx, ty = getDrawCoords(hoverQ, hoverR)
                local dests = attack:getShiftDestinations(attacker, hoverQ, hoverR, hex)
                for _, dc in ipairs(dests) do
                    local dx, dy = getDrawCoords(dc.q, dc.r)
                    love.graphics.setColor(0.4, 0.8, 1, 0.3)
                    local dv = hex:drawInsetHexagon(dx, dy, hex.radius, 0.92)
                    love.graphics.polygon("fill", dv)
                    love.graphics.setColor(0.4, 0.8, 1, 0.8)
                    love.graphics.setLineWidth(2)
                    love.graphics.polygon("line", dv)
                    love.graphics.setLineWidth(1)
                end
            end
        elseif vortexTargetCell then
            -- Second click phase: show push arrow on destination hover
            local target = getEntityAtHex(vortexTargetCell.q, vortexTargetCell.r, entities)
            if target then
                local dests = attack:getShiftDestinations(attacker, vortexTargetCell.q, vortexTargetCell.r, hex)
                local isDest = false
                for _, dc in ipairs(dests) do
                    if dc.q == hoverQ and dc.r == hoverR then
                        isDest = true
                        break
                    end
                end
                if isDest then
                    local tx, ty = getDrawCoords(vortexTargetCell.q, vortexTargetCell.r)
                    local hx, hy = getDrawCoords(hoverQ, hoverR)
                    local occupant = getEntityAtHex(hoverQ, hoverR, entities)
                    ui.drawPushArrow(tx, ty, hx, hy, nil, nil, nil, nil, vortexTargetCell.q, vortexTargetCell.r, hoverQ, hoverR)
                    if occupant then
                    else
                    end
                    if target:isBuilding() then
                    end
                end
            end
        end
        return
    end
    -- Wide Vortex
    if attack.name == "Wide Vortex" then
        local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if distance ~= 1 then return end
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if not stepX then return end
        if not vortexTargetCell then
            -- First click phase: show direction cells only
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target and target:isCharacter() and target.health > 0 and not target.isPlayable then
                local dests = attack:getShiftDestinations(attacker, hoverQ, hoverR, hex)
                for _, dc in ipairs(dests) do
                    local dx, dy = getDrawCoords(dc.q, dc.r)
                    love.graphics.setColor(0.4, 0.8, 1, 0.3)
                    local dv = hex:drawInsetHexagon(dx, dy, hex.radius, 0.92)
                    love.graphics.polygon("fill", dv)
                    love.graphics.setColor(0.4, 0.8, 1, 0.8)
                    love.graphics.setLineWidth(2)
                    love.graphics.polygon("line", dv)
                    love.graphics.setLineWidth(1)
                    -- Show B's further destination / collision hint if occupant exists
                    local occupant = getEntityAtHex(dc.q, dc.r, entities)
                    if occupant and occupant.health > 0 then
                        if occupant:isCharacter() and occupant.isPushable ~= false then
                            local ax, ay, az = hex_utils.axialToCube(attacker.q, attacker.r)
                            local bq, br
                            if dc.dir == "right" then
                                bq, br = hex_utils.cubeToAxial(ax + stepZ, ay + stepX, az + stepY)
                            else
                                bq, br = hex_utils.cubeToAxial(ax + stepY, ay + stepZ, az + stepX)
                            end
                            if hex:isActiveHex(bq, br) then
                                local bx, by = getDrawCoords(bq, br)
                                local bv = hex:drawInsetHexagon(bx, by, hex.radius, 0.92)
                                love.graphics.setColor(1, 1, 0.4, 0.3)
                                love.graphics.polygon("fill", bv)
                                love.graphics.setColor(1, 1, 0.4, 0.8)
                                love.graphics.polygon("line", bv)
                            end
                        end
                    end
                end
            end
        elseif vortexTargetCell then
            -- Second click phase: show arrows for Aв†’dest and Bв†’further + damage preview
            local target = getEntityAtHex(vortexTargetCell.q, vortexTargetCell.r, entities)
            if target then
                local dests = attack:getShiftDestinations(attacker, vortexTargetCell.q, vortexTargetCell.r, hex)
                local isDest = false
                local hoverDir
                for _, dc in ipairs(dests) do
                    if dc.q == hoverQ and dc.r == hoverR then
                        isDest = true
                        hoverDir = dc.dir
                        break
                    end
                end
                if isDest then
                    local tx, ty = getDrawCoords(vortexTargetCell.q, vortexTargetCell.r)
                    local hx, hy = getDrawCoords(hoverQ, hoverR)
                    local occupant = getEntityAtHex(hoverQ, hoverR, entities)
                    -- Arrow: A в†’ destination
                    ui.drawPushArrow(tx, ty, hx, hy, nil, nil, nil, nil, vortexTargetCell.q, vortexTargetCell.r, hoverQ, hoverR)
                    local hasCollision = false
                    local occDamaged = false
                    local occDmgAmount = 1
                    local b2BuildingDmg = 0
                    if occupant then
                        if occupant.isHazard then
                            -- pass through, no damage
                        elseif occupant.isPushable == false then
                            -- Immovable (building/obstacle): collision, both take 1
                            hasCollision = true
                            occDamaged = true
                        else
                            -- Pushable character: try to show further arrow
                            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, vortexTargetCell.q, vortexTargetCell.r, hex)
                            if stepX then
                                local ax, ay, az = hex_utils.axialToCube(attacker.q, attacker.r)
                                local bq, br
                                if hoverDir == "right" then
                                    bq, br = hex_utils.cubeToAxial(ax + stepZ, ay + stepX, az + stepY)
                                else
                                    bq, br = hex_utils.cubeToAxial(ax + stepY, ay + stepZ, az + stepX)
                                end
                                if hex:isActiveHex(bq, br) and not getEntityAtHex(bq, br) then
                                    local bx, by = getDrawCoords(bq, br)
                                    ui.drawPushArrow(hx, hy, bx, by, nil, nil, nil, nil, hoverQ, hoverR, bq, br)
                                else
                                    hasCollision = true
                                    occDamaged = true
                                    occDmgAmount = 2
                                    -- Check if there's an entity at b2 for damage preview
                                    local occupantAtB2 = hex:isActiveHex(bq, br) and getEntityAtHex(bq, br) or nil
                                    if occupantAtB2 and not occupantAtB2.noCollisionDamage then
                                        local b2x, b2y = getDrawCoords(bq, br)
                                        if occupantAtB2:isBuilding() then
                                            b2BuildingDmg = math.min(1, occupantAtB2.health)
                                        end
                                    end
                                end
                            end
                        end
                        if hasCollision then
                            if occDamaged then
                            end
                            if target:isBuilding() then
                            end
                            if occupant:isBuilding() then
                            end
                            if b2BuildingDmg > 0 then
                            end
                        end
                    end
                end
            end
        end
        return
    end
    -- Pull Hook
    if attack.name == "Pull Hook" then
        if not pullHookTargetCell then
            -- First click phase: highlight target on line
            local target = attack:getLineTarget(attacker, hoverQ, hoverR, hex, entities)
            if target then
                local tx, ty = getDrawCoords(target.q, target.r)
                local tv = hex:drawInsetHexagon(tx, ty, hex.radius, 0.92)
                love.graphics.setColor(1, 0.8, 0.2, 0.3)
                love.graphics.polygon("fill", tv)
                love.graphics.setColor(1, 0.8, 0.2, 0.8)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", tv)
                love.graphics.setLineWidth(1)
                local fx, fy = getDrawCoords(attacker.q, attacker.r)
                ui.drawHexLineDots(hex, attacker.q, attacker.r, target.q, target.r, 0.3, 0.8, 1, 4, nil, hoverQ, hoverR)
            end
        else
            -- Second click phase: show move cells for attacker and pull destination.
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, pullHookTargetCell.q, pullHookTargetCell.r, hex)
            if stepX then
                local moveCells = attack:getPullHookMoveCells(attacker, stepX, stepY, stepZ, pullHookTargetCell.q, pullHookTargetCell.r, hex, entities)
                local hoverIsMoveCell = false
                for _, c in ipairs(moveCells) do
                    local cx, cy = getDrawCoords(c.q, c.r)
                    local cv = hex:drawInsetHexagon(cx, cy, hex.radius, 0.92)
                    love.graphics.setColor(0.4, 0.8, 1, 0.3)
                    love.graphics.polygon("fill", cv)
                    love.graphics.setColor(0.4, 0.8, 1, 0.8)
                    love.graphics.setLineWidth(2)
                    love.graphics.polygon("line", cv)
                    love.graphics.setLineWidth(1)
                    if c.q == hoverQ and c.r == hoverR then
                        hoverIsMoveCell = true
                        -- Show where target will be pulled after attacker moves here
                        local pullQ, pullR = hex_utils.applyCubeStep(c.q, c.r, stepX, stepY, stepZ)
                        if hex:isActiveHex(pullQ, pullR) then
                            local px, py = getDrawCoords(pullQ, pullR)
                            local pv = hex:drawInsetHexagon(px, py, hex.radius, 0.92)
                            love.graphics.setColor(1, 1, 0.4, 0.3)
                            love.graphics.polygon("fill", pv)
                            love.graphics.setColor(1, 1, 0.4, 0.8)
                            love.graphics.polygon("line", pv)
                            ui.drawPushArrow(cx, cy, px, py, nil, nil, nil, nil, c.q, c.r, pullQ, pullR)
                        end
                    end
                    -- Mark attacker's own cell with a special indicator (stay in place)
                    if c.q == attacker.q and c.r == attacker.r then
                        love.graphics.setColor(1, 1, 1, 0.5)
                        love.graphics.circle("line", cx, cy, hex.radius * 0.2)
                    end
                end
                -- Show target cell
                local tx, ty = getDrawCoords(pullHookTargetCell.q, pullHookTargetCell.r)
                local tv = hex:drawInsetHexagon(tx, ty, hex.radius, 0.92)
                love.graphics.setColor(1, 0.8, 0.2, 0.3)
                love.graphics.polygon("fill", tv)
                love.graphics.setColor(1, 0.8, 0.2, 0.8)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", tv)
                love.graphics.setLineWidth(1)
            end
        end
        return
    end
    -- Electric Hook
    if attack.name == "Electric Hook" then
        local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
        if dist >= 2 then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then
                local fx, fy = getDrawCoords(attacker.q, attacker.r)
                local tx, ty = getDrawCoords(hoverQ, hoverR)
                -- Show damage preview for attacker
                local totalPreviewDamage = 0
                -- Highlight all cells on the line between attacker and target
                local curQ, curR = attacker.q, attacker.r
                while true do
                    local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
                    if not hex:isValidHex(nextQ, nextR) then break end
                    local cx, cy = getDrawCoords(nextQ, nextR)
                    local cv = hex:drawInsetHexagon(cx, cy, hex.radius, 0.92)
                    if nextQ == hoverQ and nextR == hoverR then
                        -- Target cell
                        love.graphics.setColor(0.3, 0.8, 1, 0.4)
                        love.graphics.polygon("fill", cv)
                        love.graphics.setColor(0.3, 0.8, 1, 0.9)
                        love.graphics.setLineWidth(3)
                        love.graphics.polygon("line", cv)
                        love.graphics.setLineWidth(1)
                        -- Damage preview for target
                        local targetEntity = getEntityAtHex(nextQ, nextR, entities)
                        if targetEntity and targetEntity.health > 0 then
                            if targetEntity:isBuilding() then
                                totalPreviewDamage = totalPreviewDamage + math.min(1, targetEntity.health)
                            end
                        end
                        break
                    end
                    -- Intermediate cell
                    love.graphics.setColor(0.3, 0.8, 1, 0.4)
                    love.graphics.polygon("fill", cv)
                    love.graphics.setColor(0.3, 0.8, 1, 0.6)
                    love.graphics.setLineWidth(2)
                    love.graphics.polygon("line", cv)
                    love.graphics.setLineWidth(1)
                    -- Damage preview for entities on the line
                    local ent = getEntityAtHex(nextQ, nextR, entities)
                    if ent and ent.health > 0 then
                        if ent:isBuilding() then
                            totalPreviewDamage = totalPreviewDamage + math.min(1, ent.health)
                        end
                    end
                    curQ, curR = nextQ, nextR
                end
                -- Dotted line from attacker to target
                ui.drawHexLineDots(hex, attacker.q, attacker.r, hoverQ, hoverR, 0.3, 0.8, 1, 4, nil, hoverQ, hoverR)
            end
        end
        return
    end
    -- Heavy Punch / Empower Punch: melee + push
    if attack.name == "Heavy Punch" or attack.name == "Empower Punch" then
        if distance == 1 then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target and target.health > 0 then
                local tx, ty = getDrawCoords(hoverQ, hoverR)
                local totalDmg = attack.damage or 0
                local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
                if stepX then
                    if attacker.choosePushDir and not pushDirTargetCell then
                        -- Show 3 push direction choices for Puncher lvl3
                        local dirs = getPushDirChoices(stepX, stepY, stepZ)
                        for _, d in ipairs(dirs) do
                            local pushQ, pushR = hex_utils.applyCubeStep(hoverQ, hoverR, d.x, d.y, d.z)
                            if hex:isValidHex(pushQ, pushR) then
                                local pushX, pushY = getDrawCoords(pushQ, pushR)
                                love.graphics.setColor(0.4, 0.8, 1, 0.3)
                                local dv = hex:drawInsetHexagon(pushX, pushY, hex.radius, 0.92)
                                love.graphics.polygon("fill", dv)
                                love.graphics.setColor(0.4, 0.8, 1, 0.8)
                                love.graphics.setLineWidth(2)
                                love.graphics.polygon("line", dv)
                                love.graphics.setLineWidth(1)
                                ui.drawPushArrow(tx, ty, pushX, pushY, nil, nil, nil, nil, hoverQ, hoverR, pushQ, pushR)
                            end
                        end
                    else
                        local pushQ, pushR = hex_utils.applyCubeStep(hoverQ, hoverR, stepX, stepY, stepZ)
                        local pushX, pushY
                        if hex:isValidHex(pushQ, pushR) then
                            pushX, pushY = getDrawCoords(pushQ, pushR)
                        end
                        ui.drawPushArrow(tx, ty, pushX or tx, pushY or ty, nil, nil, nil, nil, hoverQ, hoverR, pushQ, pushR)
                        local colDmg, colReason, colOcc = ui.checkCollisionDamage(target, hoverQ, hoverR, pushQ, pushR, hex, entities)
                        if colDmg > 0 then
                            totalDmg = totalDmg + colDmg
                            if colReason == "edge" then
                                local crashX, crashY = pushX or tx, pushY or ty
                            elseif colOcc then
                                local occX, occY = getDrawCoords(colOcc.q, colOcc.r)
                                if colReason == "collision_both" then
                                else
                                end
                                if colOcc:isBuilding() then
                                end
                            end
                        end
                    end
                end
                if target:isBuilding() then
                end
            end
        end
        return
    end
    -- Shoot: damage + knockback + collision
    if attack.name == "Shoot" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
            if firstTarget and targetHex then
                local fromX, fromY = getDrawCoords(targetHex.q, targetHex.r)
                local pushQ, pushR = hex_utils.applyCubeStep(targetHex.q, targetHex.r, stepX, stepY, stepZ)
                local toX, toY = getDrawCoords(pushQ, pushR)
                if firstTarget.isPushable ~= false then
                    ui.drawPushArrow(fromX, fromY, toX, toY, nil, nil, nil, nil, targetHex.q, targetHex.r, pushQ, pushR)
                end
            end
        end
        return
    end
    -- Piercing Shot: two targets, damage + knockback
    if attack.name == "Piercing Shot" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, firstHex, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
            for _, t in ipairs({{firstTarget, firstHex}, {secondTarget, secondHex}}) do
                local tgt, tHex = t[1], t[2]
                if tgt and tHex and tgt.isPushable ~= false then
                    local pushQ, pushR = hex_utils.applyCubeStep(tHex.q, tHex.r, stepX, stepY, stepZ)
                    local fromX, fromY = getDrawCoords(tHex.q, tHex.r)
                    local toX, toY = getDrawCoords(pushQ, pushR)
                    ui.drawPushArrow(fromX, fromY, toX, toY, nil, nil, nil, nil, tHex.q, tHex.r, pushQ, pushR)
                end
            end
        end
        return
    end
    -- For attacks that have getPushCell (Shoot etc.)
    if attack.getPushCell then
        local pushCell = attack:getPushCell(attacker, hoverQ, hoverR, hex, entities)
        if pushCell then
            local firstTarget = nil
            local stepX, stepY, stepZ
            if attack.getLineDirection then
                stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
                if stepX then
                    local target, targetHex = nil, nil
                    if attack.findFirstTargetOnLine then
                        target, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                    end
                    if not target then
                        target = getEntityAtHex(hoverQ, hoverR, entities)
                    end
                    if target then firstTarget = target end
                end
            else
                firstTarget = getEntityAtHex(hoverQ, hoverR, entities)
            end
            if firstTarget then
                previewData = {
                    {
                        target = firstTarget,
                        fromCell = {q = firstTarget.q, r = firstTarget.r},
                        pushTo = pushCell,
                        attackDamage = attack.damage or 0,
                    }
                }
                if attack.getPushCells then
                    local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
                    if #pushCells >= 2 then
                        if stepX then
                            local _, _, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                            if secondTarget then
                                table.insert(previewData, {
                                    target = secondTarget,
                                    fromCell = {q = secondTarget.q, r = secondTarget.r},
                                    pushTo = pushCells[2],
                                    attackDamage = 1,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    -- Piercing Shot (two targets on the line)
    if attack.getPushCells and not previewData and attack.name == "Piercing Shot" then
        local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
        if pushCells and #pushCells > 0 then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then
                local firstTarget, firstHex, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                previewData = {}
                if firstTarget and firstHex then
                    local isPushable = firstTarget.isPushable ~= false
                    table.insert(previewData, {
                        target = firstTarget,
                        fromCell = {q = firstHex.q, r = firstHex.r},
                        pushTo = isPushable and pushCells[1] or nil,
                        attackDamage = 0,
                    })
                end
                if secondTarget and secondHex and #pushCells >= 2 then
                    local isPushable = secondTarget.isPushable ~= false
                    table.insert(previewData, {
                        target = secondTarget,
                        fromCell = {q = secondHex.q, r = secondHex.r},
                        pushTo = isPushable and pushCells[2] or nil,
                        attackDamage = 1,
                    })
                end
            end
        end
    end
-- ================= STONE THROW (AoePushAttack) =================
if attack.name == "Stone Throw" then
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 2) or dist > attack.range then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end
    local dirQ, dirR = hoverQ - attacker.q, hoverR - attacker.r
    -- Straight line check
    local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
    if not stepX then return end
    -- Damage, if there is a target
    local targetEntity = getEntityAtHex(hoverQ, hoverR, entities)
    if targetEntity and targetEntity.health > 0 then
        if targetEntity:isBuilding() then
        end
    end
    local neighbors = attack:getNeighborsInDirection(hoverQ, hoverR, dirQ, dirR, hex)
    for _, nb in ipairs(neighbors) do
        if hex:isActiveHex(nb.q, nb.r) then
            local cX, cY, cZ = hex_utils.axialToCube(hoverQ, hoverR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dirX, dirY, dirZ)
            -- inside Stone Throw block
local target = getEntityAtHex(nb.q, nb.r, entities)
local hasTarget = target and target:isCharacter() and target.health > 0
            local fromX, fromY = getDrawCoords(nb.q, nb.r)
            local toX, toY = getDrawCoords(pushQ, pushR)
            if hasTarget then
                ui.drawPushArrow(fromX, fromY, toX, toY, 1, 0.8, 0.2, 0.9, nb.q, nb.r, pushQ, pushR)
                local colDamage, colReason, colOccupant = ui.checkCollisionDamage(
                    target, nb.q, nb.r, pushQ, pushR, hex, entities
                )
                if colDamage > 0 then
                    if colOccupant then
                        if colOccupant:isBuilding() then
                        end
                    end
                end
            else
                ui.drawPushArrow(fromX, fromY, toX, toY, 0.7, 0.7, 0.7, 0.6, nb.q, nb.r, pushQ, pushR)
            end
        end
    end
    return
end
-- ================= CONE BLAST (AoeDirectionalAttack) =================
if attack.name == "Cone Blast" then
    local dist = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if dist < (attack.minRange or 2) or dist > attack.range then return end
    local dirQ, dirR = hoverQ - attacker.q, hoverR - attacker.r
    local centerX, centerY = getDrawCoords(hoverQ, hoverR)
    local centerTarget = getEntityAtHex(hoverQ, hoverR, entities)
    -- Neighbors in direction
    local allNeighbors = hex:getNeighbors(hoverQ, hoverR)
    for _, nb in ipairs(allNeighbors) do
        if hex:isActiveHex(nb.q, nb.r) then
            local cX, cY, cZ = hex_utils.axialToCube(hoverQ, hoverR)
            local nX, nY, nZ = hex_utils.axialToCube(nb.q, nb.r)
            local dirX, dirY, dirZ = nX - cX, nY - cY, nZ - cZ
            local pushQ, pushR = hex_utils.applyCubeStep(nb.q, nb.r, dirX, dirY, dirZ)
            local target = getEntityAtHex(nb.q, nb.r, entities)
local hasTarget = target and target:isCharacter() and target.health > 0
            local fromX, fromY = getDrawCoords(nb.q, nb.r)
            local toX, toY = getDrawCoords(pushQ, pushR)
            if hasTarget then
                ui.drawPushArrow(fromX, fromY, toX, toY, 1, 0.8, 0.2, 0.9, nb.q, nb.r, pushQ, pushR)
                local colDamage, colReason, colOccupant = ui.checkCollisionDamage(
                    target, nb.q, nb.r, pushQ, pushR, hex, entities
                )
                if colDamage > 0 then
                    if colOccupant then
                        if colOccupant:isBuilding() then
                        end
                    end
                end
            else
                ui.drawPushArrow(fromX, fromY, toX, toY, 0.7, 0.7, 0.7, 0.6, nb.q, nb.r, pushQ, pushR)
            end
        end
    end
    return
end
    -- Generic method: getAffectedCells (for new attacks)
    if attack.getAffectedCells then
        local cells = attack:getAffectedCells(attacker, hoverQ, hoverR, hex, entities)
        for _, c in ipairs(cells) do
            local e = getEntityAtHex(c.q, c.r, entities)
            if e and e.health > 0 then
                local ex, ey = getDrawCoords(e.q, e.r)
                local dmg = c.damage or 1
                if e:isBuilding() then
                end
            end
        end
        return
    end
    if not previewData or #previewData == 0 then
        return
    end
    -- Collect buildings already counted as direct targets
    local directBuildingIds = {}
    for _, pd in ipairs(previewData) do
        if pd.target and pd.target:isBuilding() and pd.attackDamage > 0 then
            directBuildingIds[pd.target.q .. "," .. pd.target.r] = true
        end
    end
    -- Build set of all preview targets (to know which have their own health bar)
    local previewTargetKeys = {}
    for _, pd in ipairs(previewData) do
        if pd.target and pd.target.health > 0 then
            previewTargetKeys[pd.target.q .. "," .. pd.target.r] = true
        end
    end
    -- First pass: accumulate all damage per entity (base + all collisions)
    local entityDamage = {}
    for _, pd in ipairs(previewData) do
        local target = pd.target
        if target and target.health > 0 then
            local key = target.q .. "," .. target.r
            local dmg = pd.attackDamage or 0
            if pd.pushTo then
                local collisionDamage, reason, second = ui.checkCollisionDamage(
                    target, pd.fromCell.q, pd.fromCell.r,
                    pd.pushTo.q, pd.pushTo.r, hex, entities
                )
                dmg = dmg + (collisionDamage or 0)
                if collisionDamage > 0 and second then
                    local secKey = second.q .. "," .. second.r
                    entityDamage[secKey] = (entityDamage[secKey] or 0) + 1
                end
            end
            entityDamage[key] = (entityDamage[key] or 0) + dmg
        end
    end
    -- Second pass: draw health bars with total damage, then push visuals
    for _, pd in ipairs(previewData) do
        local target = pd.target
        if target and target.health > 0 then
            local fromX, fromY = getDrawCoords(pd.fromCell.q, pd.fromCell.r)
            local key = target.q .. "," .. target.r
            local totalDamage = entityDamage[key] or 0
            if totalDamage > 0 then
                if target:isBuilding() then
                end
            end
            -- Knockback
            if pd.pushTo then
                local toX, toY = getDrawCoords(pd.pushTo.q, pd.pushTo.r)
                ui.drawPushArrow(fromX, fromY, toX, toY, nil, nil, nil, nil, pd.fromCell.q, pd.fromCell.r, pd.pushTo.q, pd.pushTo.r)
                local collisionDamage, reason, second = ui.checkCollisionDamage(
                    target, pd.fromCell.q, pd.fromCell.r,
                    pd.pushTo.q, pd.pushTo.r, hex, entities
                )
                if collisionDamage > 0 then
                    local crashX, crashY = toX, toY
                    if reason == "collision_both" and second then
                        local secX, secY = getDrawCoords(second.q, second.r)
                        if not previewTargetKeys[second.q .. "," .. second.r] then
                        end
                        if second:isBuilding() and not directBuildingIds[second.q .. "," .. second.r] then
                        end
                    elseif reason == "collision_immovable" then
                        if second then
                            local secX, secY = getDrawCoords(second.q, second.r)
                            if not previewTargetKeys[second.q .. "," .. second.r] then
                            end
                            if second:isBuilding() and not directBuildingIds[second.q .. "," .. second.r] then
                            end
                        end
                    elseif reason == "edge" then
                    end
                end
            end
        end
    end
end
function ui.drawMovementRange(hex, actor, entities, terrainMap)
    if actor.hasMovedThisTurn and not actor.canMoveAfterAttack then return end
    if actor.hasActedThisTurn and not actor.canMoveAfterAttack then return end

    -- Cache: recompute only when actor/position changes
    local cacheKey = actor.q .. "," .. actor.r .. "," .. tostring(actor)
    if ui._moveRangeCacheKey ~= cacheKey then
        ui._moveRangeCacheKey = cacheKey
        local reachable = {}
        for _, ac in ipairs(hex._activeCells) do
            if ui.isCellReachable(actor, ac.q, ac.r, entities, terrainMap, hex) then
                reachable[#reachable + 1] = {q = ac.q, r = ac.r}
            end
        end
        ui._moveRangeCache = reachable
    end

    for _, cell in ipairs(ui._moveRangeCache) do
        local x, y = getDrawCoords(cell.q, cell.r)
        local vertices = hex:drawInsetHexagon(x, y, hex.radius, 0.92)
        love.graphics.setColor(0.2, 0.8, 0.2, 0.2)
        love.graphics.polygon("fill", vertices)
        love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
        love.graphics.polygon("line", vertices)
    end
end
-- Undo button
function ui.getEffectiveStatuses(entity)
    local statuses = {}
    for _, st in ipairs(status.getEntityStatuses(entity)) do
        table.insert(statuses, st)
    end
    if status.hasDigSite(entity.q, entity.r) then
        table.insert(statuses, "dig_site")
    end
    if status.isWounded and status.isWounded(entity) then
        table.insert(statuses, "wounded")
    end
    return statuses
end
function ui.drawEntityTooltip(entity, terrainMap, hex, entities)
    local bgColor = {0.15, 0.15, 0.15, 0.9}
    local borderColor = {1, 1, 1, 1}
    local font = love.graphics.getFont()
    local pad = 8
    local margin = 10
    local lines = {}
    table.insert(lines, { text = entity.name, color = {1,1,1} })
    if entity:isBuilding() then
        table.insert(lines, { text = "Building", color = {0.7, 0.7, 0.7} })
    else
        table.insert(lines, { text = "Obstacle", color = {0.7, 0.7, 0.7} })
    end
    if entity.indestructible then
        table.insert(lines, { text = "Indestructible", color = {0.6, 0.9, 1} })
    else
        table.insert(lines, { text = "HP: " .. entity.health .. "/" .. entity.maxHealth, color = {1, 0.4, 0.4} })
    end
    if entity.direction then
        table.insert(lines, { text = "Directional barrier", color = {0.4, 0.9, 0.4} })
        table.insert(lines, { text = "Green = safe push, Red = damaging", color = {0.8, 0.8, 0.7} })
    end
    if entity.lethalCollision then
        table.insert(lines, { text = "Lethal collision", color = {1, 0.3, 0.3} })
    end
    if entity.isHazard then
        table.insert(lines, { text = "Hazard zone", color = {1, 0.5, 0} })
    end
    local minWidth = 180
    local maxWidth = 320
    local contentWidth = minWidth
    for _, l in ipairs(lines) do
        local w = font:getWidth(l.text)
        if w > contentWidth then contentWidth = w end
    end
    contentWidth = math.max(minWidth, math.min(maxWidth, contentWidth + pad * 2))
    local panelHeight = pad + #lines * 16 + pad
    local px = logicalW - contentWidth - margin
    local py = 46
    love.graphics.setColor(bgColor)
    love.graphics.rectangle("fill", px, py, contentWidth, panelHeight, 8)
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", px, py, contentWidth, panelHeight, 8)
    local curY = py + pad
    for _, l in ipairs(lines) do
        love.graphics.setColor(l.color[1], l.color[2], l.color[3], 1)
        love.graphics.print(l.text, px + pad, curY)
        curY = curY + 16
    end
end
function ui.drawTerrainOnlyTooltip(terrain, x, y)
    local panelWidth = 120
    local panelHeight = 30
    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 5)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Terrain: " .. terrain, x + 8, y + 8)
end
function ui.drawPreparedAttackDirection(hex, enemy, time, entities)
    if not enemy.hasPreparedAttack then return end
    local attack = enemy.preparedAttack
    if not attack then return end
    local fromQ = enemy.preparedFromQ or enemy.q
    local fromR = enemy.preparedFromR or enemy.r
    local fromX, fromY = getDrawCoords(fromQ, fromR)
    if not fromX then return end
    if attack.name == "TrainShunt" then
        if enemy.preparedTargetOffset then
            local targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
            if hex:isActiveHex(targetQ, targetR) then
                local toX, toY = getDrawCoords(targetQ, targetR)
                local pulse = 0.5 + 0.5 * math.sin(time * 6)
                local alpha = 0.5 + 0.3 * pulse
                ui.drawPushArrow(fromX, fromY, toX, toY, 0.3, 0.5, 1, alpha, fromQ, fromR, targetQ, targetR)
            end
        end
        return
    end
    if attack.visualType == "arc" then
        if enemy.preparedTargetOffset then
            local targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
            if hex:isActiveHex(targetQ, targetR) then
                local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
                local toX, toY = getDrawCoords(targetQ, targetR)
                local angle = math.atan2(toY - fromY, toX - fromX)
                local edgeOffset = hex.radius * 0.7
                local startX = fromX + math.cos(angle) * edgeOffset
                local startY = fromY + math.sin(angle) * edgeOffset
                local endX = toX - math.cos(angle) * edgeOffset
                local endY = toY - math.sin(angle) * edgeOffset
                ui.drawVerticalArrow(startX, startY, "up", 0.7, 0.2, 1, 0.9)
                ui.drawVerticalArrow(endX, endY, "down", 0.7, 0.2, 1, 0.9)
            end
        end
        return
    end
    if attack.visualType == "line" then
        local targetQ, targetR
        if enemy.attackDirection then
            local step = enemy.attackDirection
            local curQ, curR = enemy.q, enemy.r
            local lastQ, lastR = curQ, curR
            while true do
                local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                if not hex:isActiveHex(nextQ, nextR) then
                    targetQ, targetR = lastQ, lastR
                    break
                end
                local ent = combat.getEntityAtHex(nextQ, nextR, entities)
                if ent and ent ~= enemy and ent.health > 0 then
                    targetQ, targetR = nextQ, nextR
                    break
                end
                lastQ, lastR = nextQ, nextR
                curQ, curR = nextQ, nextR
            end
        elseif enemy.preparedTargetOffset then
            targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
        else
            return
        end
        local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
        local toX, toY = getDrawCoords(targetQ, targetR)
        if not fromX or not toX then return end
        local dx = toX - fromX
        local dy = toY - fromY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1 then return end
        -- Blink when the cursor hovers the attacker
        local hovered = (hex.hoverQ == enemy.q and hex.hoverR == enemy.r)
        local alpha = 0.85
        if hovered then
            alpha = 0.15 + 0.7 * (0.5 + 0.5 * math.sin(time * 8))
        end
        local dotRadius = hex.radius * 0.12
        local spacing = hex.radius * 0.4
        local count = math.max(1, math.floor(dist / spacing))
        for i = 0, count do
            local t = i / count
            ui.drawRedCircleWithShadow(fromX + dx * t, fromY + dy * t, dotRadius, alpha)
        end
        return
    end
    if attack.name == "Bite" then
        if enemy.preparedTargetOffset then
            local targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
            if hex:isActiveHex(targetQ, targetR) then
                local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
                local toX, toY = getDrawCoords(targetQ, targetR)
                local dx = toX - fromX
                local dy = toY - fromY
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist >= 1 then
                    local nx = dx / dist
                    local ny = dy / dist
                    local perpX = -ny
                    local perpY = nx
                    local size = dist * 0.25
                    -- Arrow: tip at target, base shifted toward target (center offset)
                    local v1x, v1y = toX, toY
                    local baseX = fromX + nx * (dist * 0.6)
                    local baseY = fromY + ny * (dist * 0.6)
                    local backLen = size * 0.8
                    local fwdLen = size * 0.3
                    local v2x, v2y = baseX - nx * backLen + perpX * size, baseY - ny * backLen + perpY * size
                    local v3x, v3y = baseX - nx * backLen - perpX * size, baseY - ny * backLen - perpY * size
                    local hovered = (hex.hoverQ == enemy.q and hex.hoverR == enemy.r)
                    local alpha
                    if hovered then
                        local pulse = 0.5 + 0.5 * math.sin(time * 8)
                        alpha = 0.5 + 0.3 * pulse
                    else
                        alpha = 0.5
                    end
                    love.graphics.setColor(1, 0.2, 0.2, alpha)
                    love.graphics.polygon("fill", v1x, v1y, v2x, v2y, v3x, v3y)
                    love.graphics.setColor(1, 0.2, 0.2, alpha * 1.2)
                    love.graphics.setLineWidth(2)
                    love.graphics.polygon("line", v1x, v1y, v2x, v2y, v3x, v3y)
                    love.graphics.setLineWidth(1)
                end
            end
        end
        return
    end
    if attack.getAffectedCells and enemy.preparedTargetOffset then
        local targetQ, targetR = hex_utils.applyCubeDiff(
            enemy.q, enemy.r,
            enemy.preparedTargetOffset.dx,
            enemy.preparedTargetOffset.dy,
            enemy.preparedTargetOffset.dz
        )
        if hex:isActiveHex(targetQ, targetR) then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            local pulse = 0.5 + 0.5 * math.sin(time * 8)
            local alpha = 0.5 + 0.3 * pulse
            ui.drawPushArrow(fromX, fromY, toX, toY, 1, 0.2, 0.2, alpha, enemy.q, enemy.r, targetQ, targetR, 0.55)
        end
        return
    end
end
-- Preview Wind Torrent: draws arrows from each movable object to its new position
-- ui.lua
-- ui.lua
function ui.drawCellTooltip(q, r, terrain, hex)
    local margin = 10
    local pad = 8
    local font = love.graphics.getFont()
    local statuses = status.getAtHex(q, r)
    local hasDig = status.hasDigSite(q, r)
    local digInfo = nil
    if hasDig then
        local digSites = status.getAllDigSites()
        for _, site in ipairs(digSites) do
            if site.q == q and site.r == r then
                digInfo = site
                break
            end
        end
    end
    local lightningWarningHere = lightningWarning and lightningTargetQ == q and lightningTargetR == r
    local upperTerrain = _G.upperTerrainMap and _G.upperTerrainMap[q] and _G.upperTerrainMap[q][r]
    local effectDescriptions = {
        fire = { name = "Fire", color = {1, 0.5, 0}, desc = "Burns for 1 damage at end of turn. Extinguished by water." },
        acid = { name = "Acid", color = {0.3, 0.9, 0.3}, desc = "Any damage is instantly lethal." },
        decay = { name = "Decay", color = {0.7, 0.2, 0.8}, desc = "Takes 1 damage per move and at end of turn." },
    }
    local content = {}
    local hasSpecial = false
    if terrain == "water" then
        table.insert(content, { text = "Water", color = {0.4, 0.7, 1} })
        hasSpecial = true
    elseif terrain == "lava" then
        table.insert(content, { text = "Lava", color = {1, 0.4, 0.2} })
        hasSpecial = true
    end
    if #statuses > 0 then
        for _, st in ipairs(statuses) do
            local info = effectDescriptions[st]
            if info then
                table.insert(content, { text = info.name, color = info.color })
                table.insert(content, { text = "  " .. info.desc, color = {0.8, 0.8, 0.8} })
                hasSpecial = true
            end
        end
    end
    if upperTerrain then
        local upperName = upperTerrain:gsub("_", " "):gsub("^%l", string.upper)
        table.insert(content, { text = upperName, color = {0.7, 0.7, 0.7} })
        hasSpecial = true
    end
    if hasDig and digInfo then
        table.insert(content, { text = "Dig Site (" .. (digInfo.spawnType or "?") .. ")", color = {0.8, 0.6, 0.2} })
        table.insert(content, { text = "  in " .. digInfo.timer .. " turn(s), age " .. digInfo.age .. "/3", color = {1, 0.9, 0.5} })
        hasSpecial = true
    end
    if lightningWarningHere then
        table.insert(content, { text = "! Lightning target !", color = {1, 0.9, 0.2} })
        hasSpecial = true
    end
    if not hasSpecial then
        table.insert(content, { text = "Ground Tile", color = {0.7, 0.7, 0.7} })
    end
    local minWidth = 160
    local maxWidth = 280
    local contentWidth = minWidth
    for _, l in ipairs(content) do
        local w = font:getWidth(l.text)
        if w > contentWidth then contentWidth = w end
    end
    contentWidth = math.max(minWidth, math.min(maxWidth, contentWidth + pad * 2))
    local panelHeight = pad + #content * 16 + pad
    local px = logicalW - contentWidth - margin
    local py = 46
    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", px, py, contentWidth, panelHeight, 5)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.rectangle("line", px, py, contentWidth, panelHeight, 5)
    local curY = py + pad
    for _, l in ipairs(content) do
        love.graphics.setColor(l.color[1], l.color[2], l.color[3], 1)
        love.graphics.print(l.text, px + pad, curY)
        curY = curY + 16
    end
end
-- ui.lua
function ui.drawEnemyMovementRange(hex, enemy, entities, terrainMap)
    if not enemy or enemy.isPlayable or not enemy:isCharacter() or enemy.health <= 0 then return end
    if enemy.hasActedThisTurn or enemy.isMoving then return end
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) and ui.isCellReachableForEnemy(enemy, q, r, entities, terrainMap, hex) then
                local x, y = getDrawCoords(q, r)
                local vertices = hex:drawInsetHexagon(x, y, hex.radius, 0.92)
                love.graphics.setColor(0.8, 0.2, 0.2, 0.2)
                love.graphics.polygon("fill", vertices)
                love.graphics.setColor(0.8, 0.2, 0.2, 0.5)
                love.graphics.polygon("line", vertices)
            end
        end
    end
end
function ui.isCellReachableForEnemy(enemy, targetQ, targetR, entities, terrainMap, hex)
    if not hex:isActiveHex(targetQ, targetR) then return false end
    
    if enemy.teleporting then
        for _, e in ipairs(entities) do
            if e ~= enemy and e.q == targetQ and e.r == targetR then
                return false
            end
        end
        return true
    end
    
    if terrainMap and terrainMap[targetQ] and terrainMap[targetQ][targetR] == "water" then
        if not (enemy and (enemy.flying or enemy.hovering)) then
            return false
        end
    end
    -- Cell must not be occupied (by ally or enemy)
    for _, e in ipairs(entities) do
        if e ~= enemy and e.q == targetQ and e.r == targetR then
            return false
        end
    end
    local effectiveRange = ui.getEffectiveMoveRange(enemy, entities, hex)
    local isBlockedFn
    local isOccupiedFn
    if enemy.flying then
        isBlockedFn = function(q, r) return not hex:isActiveHex(q, r) end
    else
        isBlockedFn = function(q, r) return cell_rules.isOccupied(q, r, enemy, { entities = entities, hex = hex, allowPhaseThroughEnemies = false }) end
        isOccupiedFn = function(q, r)
            for _, e in ipairs(entities) do
                if e ~= enemy and e.q == q and e.r == r and not e.isHazard then return true end
            end
            return false
        end
    end
    local path = pathfinding.findPath(enemy.q, enemy.r, targetQ, targetR, effectiveRange,
        isBlockedFn, hex, isOccupiedFn)
    return path ~= nil and #path > 0
end
function cell_rules.isPassableForEnemy(q, r, enemy, entities, terrainMap, hex)
    -- Delegates to cell_rules.isPassable with passableSide = "enemy".
    -- Enemies can pass through other enemies, but not through allies/obstacles.
    return cell_rules.isPassable(q, r, enemy, {
        entities = entities, terrainMap = terrainMap, hex = hex,
        passableSide = "enemy",
        allowPhaseThroughEnemies = false,
    })
end
function ui.drawLichDoubleArrow(fromX, fromY, toX, toY, time)
    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.1 then return end
    local diveX = fromX + dx * 0.33
    local diveY = fromY + dy * 0.33 + 35
    local riseX = fromX + dx * 0.66
    local riseY = fromY + dy * 0.66 - 35
    local pulse = 0.6 + 0.4 * math.sin(time * 6)
    local alpha = 0.6 + 0.4 * pulse
    -- ===== 1. Arrow from Lich to dive point =====
    local function drawArrow(ax, ay, bx, by, a)
        local angle = math.atan2(by - ay, bx - ax)
        love.graphics.setLineWidth(4)
        love.graphics.setColor(0.7, 0.2, 1, a)
        love.graphics.line(ax, ay, bx, by)
        local arrowSize = 18
        local leftAngle = angle + math.pi * 0.7
        local rightAngle = angle - math.pi * 0.7
        love.graphics.line(bx, by,
            bx + math.cos(leftAngle) * arrowSize,
            by + math.sin(leftAngle) * arrowSize)
        love.graphics.line(bx, by,
            bx + math.cos(rightAngle) * arrowSize,
            by + math.sin(rightAngle) * arrowSize)
    end
    drawArrow(fromX, fromY, diveX, diveY, alpha)
    -- ===== 2. "Dive" effect (ground tears apart) =====
    love.graphics.setColor(0.5, 0.2, 0.8, alpha * 0.9)
    love.graphics.circle("fill", diveX, diveY, 14)
    love.graphics.setColor(0.9, 0.4, 1, alpha)
    love.graphics.circle("line", diveX, diveY, 18)
    -- Sparks
    for i = 1, 5 do
        local angleOff = time * 12 + i
        local offX = math.cos(angleOff) * 12 * pulse
        local offY = math.sin(angleOff) * 8 * pulse
        love.graphics.setColor(1, 0.5, 1, alpha)
        love.graphics.circle("fill", diveX + offX, diveY + offY, 3)
    end
    -- ===== 3. Underground path (wave-like dots) =====
    local numDots = 10
    for i = 1, numDots do
        local t = i / numDots
        local px = diveX + (riseX - diveX) * t
        local py = diveY + (riseY - diveY) * t + math.sin(t * math.pi * 3) * 12
        local dotSize = 6 * (0.4 + 0.6 * math.sin(time * 10 + i))
        love.graphics.setColor(0.4, 0.1, 0.7, alpha * 0.7)
        love.graphics.circle("fill", px, py, dotSize)
        love.graphics.setColor(0.8, 0.3, 1, alpha * 0.5)
        love.graphics.circle("line", px, py, dotSize + 2)
    end
    -- ===== 4. Arrow from emergence point to target =====
    drawArrow(riseX, riseY, toX, toY, alpha)
    -- ===== 5. "Emergence" effect (magic surge) =====
    love.graphics.setColor(0.8, 0.3, 1, alpha * 0.9)
    love.graphics.circle("fill", riseX, riseY, 14)
    love.graphics.setColor(1, 0.6, 1, alpha)
    love.graphics.circle("line", riseX, riseY, 18)
    for i = 1, 5 do
        local angleOff = time * 12 + i
        local offX = math.cos(angleOff) * 10 * pulse
        local offY = math.sin(angleOff) * 10 * pulse
        love.graphics.setColor(1, 0.4, 1, alpha)
        love.graphics.circle("fill", riseX + offX, riseY + offY, 3)
    end
    love.graphics.setLineWidth(1)
end
-- ui.lua, function drawDigSites
local dig_site_shader = require("ui.dig_site_shader")

function ui.drawDigSites(hex, digSites)
    local time = love.timer.getTime()
    for _, site in ipairs(digSites) do
        local x, y = getDrawCoords(site.q, site.r)
        local radius = hex.radius
        
        -- Urgency increases as timer decreases
        local urgency = 1.0 + (3.0 - math.min(site.timer, 3.0)) * 0.3
        
        dig_site_shader.drawDigSite(x, y, radius, time, urgency)
        
        -- Timer (number of turns until spawn) if >1
        if site.timer > 1 then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(tostring(site.timer), x + 10, y - 14)
        end
    end
end
-- ponytail: straight-line aim hint. Red dots with shadow on each hex.
-- Dots blink when cursor is on target hex.
function ui.drawHexLineDots(hex, fromQ, fromR, toQ, toR, cR, cG, cB, dotRadius, targetCells, hoverQ, hoverR)
    if not hex or not hex:isValidHex(fromQ, fromR) then return end
    if not hex:isValidHex(toQ, toR) then return end
    local time = love.timer.getTime()
    local r = dotRadius or 5

    local isHoverOnTarget = hoverQ and hoverR and (hoverQ == toQ and hoverR == toR)
    local function isTarget(q, r)
        if q == toQ and r == toR then return true end
        for _, t in ipairs(targetCells or {}) do
            if t[1] == q and t[2] == r then return true end
        end
        return false
    end

    local curQ, curR = fromQ, fromR
    local safety = 64
    while safety > 0 do
        safety = safety - 1
        local x, y = getDrawCoords(curQ, curR)
        local alpha
        if isHoverOnTarget then
            alpha = 0.3 + 0.7 * math.abs(math.sin(time * 10))
        else
            alpha = 0.6 + 0.4 * math.sin(time * 4)
        end
        love.graphics.setColor(0, 0, 0, 0.45 * alpha)
        love.graphics.circle("fill", x + 2, y + 3, r)
        love.graphics.setColor(cR or 0.95, cG or 0.2, cB or 0.2, alpha)
        love.graphics.circle("fill", x, y, r)
        if curQ == toQ and curR == toR then return end
        local nq, nr = hex_utils.axialStepToward(curQ, curR, toQ, toR)
        if nq == curQ and nr == curR then return end
        curQ, curR = nq, nr
    end
end
function ui.drawAttackableCells(hex, attacker, attack, entities, terrainMap)
    local keys = ui.getAttackableCellKeys(hex, attacker, attack, entities)
    for key in pairs(keys) do
        local q, r = key:match("^(%d+),(%d+)$")
        q, r = tonumber(q), tonumber(r)
        local x, y = getDrawCoords(q, r)
        local vertices = hex:drawInsetHexagon(x, y, hex.radius, 0.92)
        love.graphics.setColor(0.9, 0.8, 0.2, 0.25)
        love.graphics.polygon("fill", vertices)
        love.graphics.setColor(0.9, 0.8, 0.2, 0.7)
        love.graphics.polygon("line", vertices)
    end
end
-- ======================================================
-- ============================================================
-- AUXILIARY SELECTION MANAGEMENT FUNCTIONS
-- ============================================================
function updateAttackButtons(actor)
    attackButtons = {}
    if not actor or not actor.attacks or #actor.attacks == 0 then
        return
    end
    local startX = logicalW - 155
    local startY = 100
    local idx = 0
    for i, attackInfo in ipairs(actor.attacks) do
        -- If chain is active, only show the chained attack
        if actor.chainAttack and actor.chainAttack ~= attackInfo.name then
            -- skip
        else
            idx = idx + 1
            local btn = {
                x = startX,
                y = startY + (idx-1) * 32,
                width = 145,
                height = 28,
                attack = attackInfo.attack,
                name = attackInfo.name,
                desc = attackInfo.description
            }
            table.insert(attackButtons, btn)
        end
    end
end
function clearSelectedActor()
    selectedActor = nil
    hex.selectedQ = -1
    hex.selectedR = -1
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
end
function restoreSelectedActor()
    for _, a in ipairs(entities) do
        if a.isPlayable and a.health > 0 then
            selectedActor = a
            hex.selectedQ, hex.selectedR = a.q, a.r
            updateAttackButtons(selectedActor)
            break
        end
    end
end
-- Collects attack preview hex overlays into out table
function ui.collectAttackPreviewOverlays(hex, attacker, attack, hoverQ, hoverR, entities, out)
    if not attack or not attacker then return end
    if attacker.hasActedThisTurn then return end
    local distance = hex:getDistance(attacker.q, attacker.r, hoverQ, hoverR)
    if distance > attack.range then return end
    if not hex:isActiveHex(hoverQ, hoverR) then return end
    if attack.getLineDirection then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if not stepX then return end
    end
    -- Specific branches for existing attacks (backwards compatibility)
    if attack.name == "Flip" then
        if distance == 1 then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then table.insert(out, {q = target.q, r = target.r}) end
        end
        return
    end
    if attack.name == "Ghost Bolt" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
            if firstTarget and targetHex then table.insert(out, {q = targetHex.q, r = targetHex.r}) end
        end
        return
    end
    if attack.name == "Bite" then
        if distance == 1 then
            local target = getEntityAtHex(hoverQ, hoverR, entities)
            if target then table.insert(out, {q = hoverQ, r = hoverR}) end
        end
        return
    end
    if attack.name == "Magic Bolt" then
        if distance <= attack.range then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then
                local target = getEntityAtHex(hoverQ, hoverR, entities)
                if target then table.insert(out, {q = hoverQ, r = hoverR}) end
            end
        end
        return
    end
    if attack.name == "Dash" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex = attack:getFirstTargetAndLastFree(attacker, stepX, stepY, stepZ, hex, entities)
            if firstTarget and targetHex then table.insert(out, {q = targetHex.q, r = targetHex.r}) end
        end
        return
    end
    if attack.name == "Stone Throw" then
        local minRange = attack.minRange or 1
        if distance >= minRange and distance <= attack.range then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then table.insert(out, {q = hoverQ, r = hoverR}) end
        end
        return
    end
    if attack.name == "Vortex Strike" or attack.name == "Wide Vortex" then
        if distance >= 1 and distance <= attack.range then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then
                local occupant = getEntityAtHex(hoverQ, hoverR, entities)
                if occupant and occupant:isCharacter() and occupant.health > 0 and not occupant.isPlayable then
                    table.insert(out, {q = hoverQ, r = hoverR})
                end
            end
        end
        return
    end
    if attack.name == "Rampage" then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, firstHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
            if firstTarget and firstHex then
                table.insert(out, {q = firstHex.q, r = firstHex.r})
            end
            -- Walk the path and show adjacent enemies that will be pushed aside (including attacker's starting cell)
            local curQ, curR = attacker.q, attacker.r
            while true do
                local sideX1, sideY1, sideZ1 = -stepY, -stepZ, -stepX
                local sideX2, sideY2, sideZ2 = -stepZ, -stepX, -stepY
                for _, side in ipairs({{sideX1, sideY1, sideZ1}, {sideX2, sideY2, sideZ2}}) do
                    local sideQ, sideR = hex_utils.applyCubeStep(curQ, curR, side[1], side[2], side[3])
                    local e = getEntityAtHex(sideQ, sideR, entities)
                    if e and e:isCharacter() and e.health > 0 and e.isPushable ~= false and not e.isPlayable then
                        table.insert(out, {q = sideQ, r = sideR})
                    end
                end

                local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
                if not hex:isActiveHex(nextQ, nextR) then break end
                if firstTarget and firstHex and nextQ == firstHex.q and nextR == firstHex.r then break end
                curQ, curR = nextQ, nextR
            end
        end
        return
    end
    if attack.name == "Electric Hook" then
        local minRange = attack.minRange or 2
        if distance >= minRange then
            local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
            if stepX then
                table.insert(out, {q = hoverQ, r = hoverR})
            end
        end
        return
    end
    -- Shoot, Piercing Shot, and other getPushCell attacks
    if attack.getPushCell then
        local stepX, stepY, stepZ = attack:getLineDirection(attacker.q, attacker.r, hoverQ, hoverR, hex)
        if stepX then
            local firstTarget, targetHex
            if attack.findFirstTargetOnLine then
                firstTarget, targetHex = attack:findFirstTargetOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
            else
                firstTarget = getEntityAtHex(hoverQ, hoverR, entities)
                if firstTarget then targetHex = {q = hoverQ, r = hoverR} end
            end
            if firstTarget and targetHex then
                table.insert(out, {q = targetHex.q, r = targetHex.r})
            else
                -- Show the farthest reachable cell on the line, capped by attack range
                local maxDist = attack.range or math.huge
                if maxDist == math.huge then maxDist = nil end
                local endCell = combat.getFarthestActiveCellOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, maxDist)
                if endCell then
                    table.insert(out, {q = endCell.q, r = endCell.r})
                end
            end
            if attack.getPushCells then
                local pushCells = attack:getPushCells(attacker, hoverQ, hoverR, hex, entities)
                if pushCells and #pushCells >= 2 then
                    local _, _, secondTarget, secondHex = attack:findFirstTwoTargetsOnLine(attacker.q, attacker.r, stepX, stepY, stepZ, hex, entities)
                    if secondTarget and secondHex then
                        table.insert(out, {q = secondHex.q, r = secondHex.r})
                    end
                end
            end
        end
        return
    end
    -- Generic method: getAffectedCells (for new attacks)
    if attack.getAffectedCells then
        local cells = attack:getAffectedCells(attacker, hoverQ, hoverR, hex, entities)
        for _, c in ipairs(cells) do
            table.insert(out, {q = c.q, r = c.r})
        end
        return
    end
end
function ui.drawSelectedStats(actor, entities, hex)
    if not actor then return end
    if not actor:isCharacter() and not (actor:isBuilding() and actor.moveRange > 0) then return end
    local font = love.graphics.getFont()
    local pad = 8
    local lineH = 18
    local margin = 10
    local nameColor
    if actor.isPlayable then
        nameColor = {0.4, 0.9, 0.4}
    elseif actor:isCharacter() then
        nameColor = {0.9, 0.4, 0.4}
    else
        nameColor = {1, 1, 1}
    end

    -- Name panel (compact, just name)
    love.graphics.setFont(fonts.get(14))
    local nameText = actor.name
    if actor.hasActedThisTurn then nameText = nameText .. " (acted)" end
    local nameW = font:getWidth(nameText) + pad * 4 + 24
    local px, py = margin, 46
    love.graphics.setColor(0.1, 0.15, 0.1, 0.9)
    love.graphics.rectangle("fill", px, py, nameW, lineH + pad * 2, 8)
    love.graphics.setColor(nameColor[1], nameColor[2], nameColor[3], 1)
    love.graphics.rectangle("line", px, py, nameW, lineH + pad * 2, 8)
    love.graphics.setColor(nameColor)
    love.graphics.print(nameText, px + pad, py + pad)

    -- Right-side info (single line, outside frame)
    if not smallFont then smallFont = fonts.get(12) end
    love.graphics.setFont(smallFont)

    local statsParts = {}
    -- HP
    table.insert(statsParts, { icon = "health", text = actor.health .. "/" .. actor.maxHealth, color = {1, 0.4, 0.4} })
    -- Move
    local baseMove = actor.moveRange or 0
    local effMove = ui.getEffectiveMoveRange(actor, entities, hex)
    local moveText = effMove ~= baseMove and (baseMove .. ">" .. effMove) or tostring(baseMove)
    table.insert(statsParts, { icon = "move", text = moveText, color = {0.8, 0.8, 0.8} })
    -- Traits
    local flags = {}
    if actor.flying then table.insert(flags, "Flying") end
    if actor.hovering then table.insert(flags, "Hovering") end
    if actor.teleporting then table.insert(flags, "Teleporting") end
    if actor.waterWalker then table.insert(flags, "Water Walker") end
    if actor.indestructible then table.insert(flags, "Indestructible") end
    if actor.canMoveAfterAttack then table.insert(flags, "Move+Atk") end
    if #flags > 0 then
        table.insert(statsParts, { text = table.concat(flags, "/"), color = {0.6, 0.9, 1} })
    end
    -- Statuses
    local statuses = ui.getEffectiveStatuses(actor) or {}
    if #statuses > 0 then
        local sn = {}
        for _, st in ipairs(statuses) do
            sn[#sn + 1] = tostring(st):gsub("_", " "):gsub("^%l", string.upper)
        end
        table.insert(statsParts, { text = table.concat(sn, "/"), color = {1, 0.8, 0.4} })
    end

    local sep = "|"
    local infoX = px + nameW + 6
    local infoY = py + pad
    local lx = infoX
    for i, p in ipairs(statsParts) do
        if p.icon then
            icon_cache.drawSmall(p.icon, lx + 6, infoY + 8, 12)
            lx = lx + 14
        end
        love.graphics.setColor(p.color)
        love.graphics.print(p.text, lx, infoY + 2)
        lx = lx + love.graphics.getFont():getWidth(p.text)
        if i < #statsParts then
            love.graphics.setColor(0.4, 0.4, 0.5, 0.5)
            love.graphics.print(sep, lx + 3, infoY + 2)
            lx = lx + love.graphics.getFont():getWidth(sep) + 6
        end
    end
end
function ui.drawAbilityStats(ability)
    if not ability or not ability._cfg then return end
    local cfg = ability._cfg
    local pad = 10
    local lineH = 18
    local margin = 10
    local lines = {}
    local nameColor = cfg.color
    table.insert(lines, { text = ability.name, color = nameColor })
    local abilIcon = icon_cache.keyForAbility(ability.name) or "abil_heal"
    table.insert(lines, { text = "Mana: " .. ability.manaCost, color = {0.4, 0.6, 1}, icon = abilIcon, iconSize = 14 })
    if ability.hasBeenUsed then
        table.insert(lines, { text = "(already used)", color = {0.6, 0.6, 0.6} })
    end
    table.insert(lines, { text = "", color = {1,1,1} })
    for _, descLine in ipairs(cfg.tooltipLines or {}) do
        table.insert(lines, { text = descLine, color = {0.8, 0.8, 0.8} })
    end
    local minWidth = 200
    local maxWidth = 320
    local f14 = fonts.get(14)
    local contentWidth = minWidth
    for _, l in ipairs(lines) do
        local w = f14:getWidth(l.text)
        if w > contentWidth then contentWidth = w end
    end
    contentWidth = math.max(minWidth, math.min(maxWidth, contentWidth + pad * 2 + 18))
    local panelHeight = pad + #lines * lineH + pad
    local px = margin
    local py = 46
    love.graphics.setColor(0.1, 0.1, 0.2, 0.9)
    love.graphics.rectangle("fill", px, py, contentWidth, panelHeight, 8)
    love.graphics.setColor(nameColor[1], nameColor[2], nameColor[3], 1)
    love.graphics.rectangle("line", px, py, contentWidth, panelHeight, 8)
    love.graphics.setFont(fonts.get(14))
    local curY = py + pad
    for _, l in ipairs(lines) do
        local textX = px + pad
        if l.icon then
            icon_cache.drawSmall(l.icon, textX + (l.iconSize or 14) / 2, curY + lineH / 2, l.iconSize or 14)
            textX = textX + 18
        end
        love.graphics.setColor(l.color[1], l.color[2], l.color[3], 1)
        love.graphics.print(l.text, textX, curY)
        curY = curY + lineH
    end
end
function ui.drawAllyPanel(mx, my, entities, selectedActor)
    allyPanelButtons = {}
    local allies = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and e.isPlayable and e.health and (e.health > 0 or (status and status.hasEntityStatus and status.hasEntityStatus(e, "stasis"))) then
            table.insert(allies, e)
        end
    end
    if #allies == 0 then return end
    local x = 10
    local btnW = 135
    local btnH = 30
    local gap = 2
    local totalH = #allies * (btnH + gap) - gap
    local ab = attackButtons or {}
    local attackPanelH = #ab > 0 and (#ab * 28 + (#ab - 1) * 4 + 10) or 0
    local startY = logicalH - 60 - 10 - attackPanelH - 10 - totalH
    for i, ally in ipairs(allies) do
        local by = startY + (i - 1) * (btnH + gap)
        local hover = mx >= x and mx <= x + btnW and my >= by and my <= by + btnH
        local sel = selectedActor == ally
        local btn = {x = x, y = by, w = btnW, h = btnH, entity = ally}
        table.insert(allyPanelButtons, btn)
        if sel then
            love.graphics.setColor(0.25, 0.25, 0.25, 0.88)
        elseif hover then
            love.graphics.setColor(0.35, 0.25, 0.35, 0.85)
        else
            love.graphics.setColor(0.28, 0.15, 0.18, 0.82)
        end
        love.graphics.rectangle("fill", x, by, btnW, btnH, 4)
        love.graphics.setColor(0.45, 0.2, 0.2, 0.5)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", x, by, btnW, btnH, 4)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(ally.name, x + 5, by + 2)
        local inStasis = status and status.hasEntityStatus and status.hasEntityStatus(ally, "stasis")
        local indX = x + btnW - 16
        local indY = by + btnH / 2 - 1
        if inStasis then
            love.graphics.setColor(0.3, 0.5, 1, 1)
            love.graphics.print("STS", indX - 12, indY - 2)
        elseif ally.hasActedThisTurn then
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
            love.graphics.print("вњ—", indX, indY - 2)
        elseif not ally.hasMovedThisTurn then
            local isRooted = status and status.hasEntityStatus and status.hasEntityStatus(ally, "rooted") and not ally.rootImmune
            if isRooted then
                love.graphics.setColor(0.6, 0.8, 0.2, 1)
            else
                love.graphics.setColor(0.3, 1, 0.3, 1)
            end
            love.graphics.circle("fill", indX + 3, indY + 5, 4)
        else
            love.graphics.setColor(1, 0.9, 0.3, 1)
            love.graphics.circle("fill", indX + 3, indY + 5, 4)
        end
    end
end

local pauseBtnRect = { x = 0, y = 0, w = 36, h = 28 }

function ui.getPauseBtnRect()
    pauseBtnRect.x = logicalW - 46
    return pauseBtnRect
end

function ui.drawChaosBar(mx, my)
    local chaosVal = _G.chaos or 0
    local chaosMaxVal = (_G.chaosMax or 5) + (_G.chaosScaleBonus or 0)
    local surplus = _G.chaosSurplus or 0

    local cellW = 30
    local cellH = 14
    local gap = 3
    local pad = 4
    local totalW = (cellW + gap) * chaosMaxVal + pad * 2

    if not smallFont then smallFont = fonts.get(12) end

    local panelH = 36
    love.graphics.setColor(0.06, 0.06, 0.12, 0.9)
    love.graphics.rectangle("fill", 0, 0, logicalW, panelH)
    love.graphics.setColor(0.3, 0.2, 0.4, 0.4)
    love.graphics.line(0, panelH, logicalW, panelH)

    -- Decay timer (center)
    local turnCount = _G.turnCount or 0
    local maxTurns = _G.maxTurns or 5
    local decayActive = turnCount >= maxTurns
    if not smallFont then smallFont = fonts.get(12) end
    love.graphics.setFont(smallFont)
    local decayText = decayActive and "Decay!" or ("Decay: " .. (maxTurns - turnCount))
    local decayW = love.graphics.getFont():getWidth(decayText)
    love.graphics.setColor(decayActive and 1 or 0.7, decayActive and 0.3 or 0.7, decayActive and 0.3 or 0.9, 1)
    love.graphics.print(decayText, math.floor((logicalW - decayW) / 2), math.floor((panelH - 14) / 2))

    local barX = 10
    local barY = math.floor((panelH - (cellH + pad * 2)) / 2)

    love.graphics.setColor(0.08, 0.08, 0.15, 0.85)
    love.graphics.rectangle("fill", barX, barY, totalW, cellH + pad * 2, 4)
    love.graphics.setColor(0.3, 0.2, 0.4, 0.6)
    love.graphics.rectangle("line", barX, barY, totalW, cellH + pad * 2, 4)

    for i = 1, chaosMaxVal do
        local cx = barX + pad + (i - 1) * (cellW + gap)
        local cy = barY + pad
        local filled = i <= chaosVal
        if filled then
            local t = love.timer.getTime()
            local pulse = 0.8 + 0.2 * math.sin(t * 3 + i * 0.5)
            love.graphics.setColor(0.9 * pulse, 0.35 * pulse, 0.4 * pulse, 0.9)
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 0.6)
        end
        love.graphics.rectangle("fill", cx, cy, cellW, cellH, 2)
        love.graphics.setColor(0.4, 0.3, 0.5, 0.5)
        love.graphics.rectangle("line", cx, cy, cellW, cellH, 2)
    end

    if surplus > 0 then
        local surplusX = barX + totalW + 8
        love.graphics.setColor(0.6, 0.9, 0.6, 0.9)
        love.graphics.setFont(fonts.get(10))
        love.graphics.print("+" .. surplus, surplusX, barY + 6)
    end

    local pb = ui.getPauseBtnRect()
    local pbHover = mx >= pb.x and mx <= pb.x + pb.w and my >= pb.y and my <= pb.y + pb.h
    local pbY = math.floor((panelH - pb.h) / 2)
    pb.y = pbY

    -- Mana display (left of pause button)
    local manaVal = _G.global_abilities and global_abilities.mana or 0
    local manaMaxVal = _G.global_abilities and global_abilities.maxMana or 3
    local manaCellR = 7
    local manaGap = 4
    local manaW = manaMaxVal * (manaCellR * 2) + (manaMaxVal - 1) * manaGap + 6
    local manaX = pb.x - manaW - 8
    local manaCY = math.floor(panelH / 2)
    local manaBgX = manaX - 4
    local manaBgW = manaW + 8
    love.graphics.setColor(0.08, 0.08, 0.18, 0.7)
    love.graphics.rectangle("fill", manaBgX, 2, manaBgW, panelH - 4, 4)
    for i = 1, manaMaxVal do
        local mx2 = manaX + (i - 1) * (manaCellR * 2 + manaGap) + manaCellR
        love.graphics.setColor(i <= manaVal and 0.3 or 0.1, i <= manaVal and 0.5 or 0.1, i <= manaVal and 0.9 or 0.1, 0.9)
        love.graphics.circle("fill", mx2, manaCY, manaCellR)
        if i <= manaVal then
            love.graphics.setColor(0.5, 0.7, 1, 0.6)
            love.graphics.circle("line", mx2, manaCY, manaCellR)
        end
    end

    -- Mana tooltip on hover
    if mx >= manaBgX and mx <= manaBgX + manaBgW and my >= 0 and my <= panelH then
        local ttW = 160
        local ttH = 52
        local ttx = manaBgX + manaBgW / 2 - ttW / 2
        local tty = panelH + 6
        if ttx < 4 then ttx = 4 end
        love.graphics.setColor(0.08, 0.08, 0.2, 0.92)
        love.graphics.rectangle("fill", ttx, tty, ttW, ttH, 5)
        love.graphics.setColor(0.4, 0.5, 0.8, 0.6)
        love.graphics.rectangle("line", ttx, tty, ttW, ttH, 5)
        love.graphics.setColor(0.5, 0.7, 1, 1)
        love.graphics.setFont(smallFont)
        love.graphics.print("Mana", ttx + 6, tty + 5)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.print("Commander energy for abilities.", ttx + 6, tty + 22)
        love.graphics.setColor(0.5, 0.7, 1, 1)
        love.graphics.print(string.format("%d / %d available", manaVal, manaMaxVal), ttx + 6, tty + 38)
    end

    love.graphics.setColor(pbHover and 0.25 or 0.12, pbHover and 0.18 or 0.1, pbHover and 0.35 or 0.2, 0.9)
    love.graphics.rectangle("fill", pb.x, pbY, pb.w, pb.h, 4)
    love.graphics.setColor(0.5, 0.4, 0.6, pbHover and 0.9 or 0.5)
    love.graphics.rectangle("line", pb.x, pbY, pb.w, pb.h, 4)
    love.graphics.setColor(1, 1, 1, pbHover and 1 or 0.7)
    love.graphics.setFont(fonts.get(16))
    love.graphics.printf("II", pb.x, pbY + pb.h / 2 - 8, pb.w, "center")

    if mx >= barX and mx <= barX + totalW and my >= barY and my <= barY + cellH + pad * 2 then
        local ttW = 200
        local ttH = 110
        local ttx = barX
        local tty = barY + cellH + pad * 2 + 12
        love.graphics.setColor(0.1, 0.1, 0.2, 0.92)
        love.graphics.rectangle("fill", ttx, tty, ttW, ttH, 5)
        love.graphics.setColor(0.6, 0.4, 0.7, 0.8)
        love.graphics.rectangle("line", ttx, tty, ttW, ttH, 5)

        local lines = {
            {text = "Chaos", color = {0.9, 0.6, 0.8, 1}},
            {text = "", color = {1, 1, 1, 1}},
            {text = "Chaos rises when buildings take", color = {0.8, 0.8, 0.8, 1}},
            {text = "damage or secondary objectives fail.", color = {0.8, 0.8, 0.8, 1}},
            {text = "At maximum, the realm collapses.", color = {0.8, 0.8, 0.8, 1}},
            {text = "", color = {1, 1, 1, 1}},
            {text = string.format("Current: %d / %d", chaosVal, chaosMaxVal), color = chaosVal >= chaosMaxVal and {1, 0.3, 0.3, 1} or {1, 0.9, 0.2, 1}},
        }
        local curY = tty + 6
        for _, l in ipairs(lines) do
            love.graphics.setColor(l.color[1], l.color[2], l.color[3], l.color[4] or 1)
            love.graphics.print(l.text, ttx + 6, curY)
            curY = curY + 14
        end
    end
end

function ui.drawLeaderHPBar(mx, my)
    local isMap4 = _G.selectedMapPath and _G.selectedMapPath:match("map4")
    if not isMap4 then return end
    local leader = nil
    for _, e in ipairs(_G.entities or {}) do
        if e.isLeader and e.health and e.health > 0 then
            leader = e
            break
        end
    end
    if not leader then return end

    local barX = 10
    local barY = 46
    local barW = 150
    local barH = 18
    local cellW = 30
    local cellH = 14
    local gap = 3
    local pad = 4
    local cellCount = 2

    if not smallFont then smallFont = fonts.get(12) end
    love.graphics.setFont(smallFont)

    -- Label
    love.graphics.setColor(0.9, 0.1, 0.3, 1)
    love.graphics.print("Power Lich", barX, barY)

    -- Health bar background
    local bgY = barY + 16
    local totalW = (cellW + gap) * cellCount + pad * 2
    love.graphics.setColor(0.08, 0.08, 0.15, 0.85)
    love.graphics.rectangle("fill", barX, bgY, totalW, cellH + pad * 2, 4)
    love.graphics.setColor(0.5, 0.1, 0.2, 0.6)
    love.graphics.rectangle("line", barX, bgY, totalW, cellH + pad * 2, 4)

    -- Cells (2 cells, each divided into 3 sub-cells of 1 HP)
    local healthPerCell = 3
    local subGap = 3
    local subCellW = 8
    for i = 1, cellCount do
        local cx = barX + pad + (i - 1) * (cellW + gap)
        local cy = bgY + pad
        local remaining = leader.health - (i - 1) * healthPerCell
        local filledSubCells = math.max(0, math.min(healthPerCell, remaining))

        for j = 1, healthPerCell do
            local scx = cx + (j - 1) * (subCellW + subGap)
            if j <= filledSubCells then
                local t = love.timer.getTime()
                local pulse = 0.8 + 0.2 * math.sin(t * 3 + i * 1.5 + j * 0.8)
                love.graphics.setColor(0.9 * pulse, 0.1 * pulse, 0.2 * pulse, 0.9)
                love.graphics.rectangle("fill", scx, cy, subCellW, cellH, 2)
            end
            love.graphics.setColor(0.5, 0.1, 0.2, 0.35)
            love.graphics.rectangle("line", scx, cy, subCellW, cellH, 2)
        end

        love.graphics.setColor(0.5, 0.1, 0.2, 0.5)
        love.graphics.rectangle("line", cx, cy, cellW, cellH, 2)
    end

    -- Tooltip
    if mx >= barX and mx <= barX + totalW and my >= bgY and my <= bgY + cellH + pad * 2 then
        local ttW = 200
        local ttH = 80
        local ttx = barX
        local tty = bgY + cellH + pad * 2 + 6
        love.graphics.setColor(0.1, 0.1, 0.2, 0.92)
        love.graphics.rectangle("fill", ttx, tty, ttW, ttH, 5)
        love.graphics.setColor(0.5, 0.1, 0.2, 0.8)
        love.graphics.rectangle("line", ttx, tty, ttW, ttH, 5)

        local lines = {
            {text = string.format("HP: %d / 6", leader.health), color = {0.9, 0.1, 0.3, 1}},
            {text = "", color = {1, 1, 1, 1}},
            {text = "Kill the Power Lich to win!", color = {0.8, 0.8, 0.8, 1}},
            {text = "If it kills a hero, you lose.", color = {0.8, 0.3, 0.3, 1}},
        }
        local curY = tty + 6
        for _, l in ipairs(lines) do
            love.graphics.setColor(l.color[1], l.color[2], l.color[3], l.color[4] or 1)
            love.graphics.print(l.text, ttx + 6, curY)
            curY = curY + 14
        end
    end
end

return ui
