-- renderer.lua
-- Responsible for rendering the game. Called from love.draw(state).
local renderer = {}
local ui = require("ui.ui")
local visual = require("system.visual_effects")
local status = require("system.status")
local combat = require("combat.combat")
local hex_utils = require("grid.hex_utils")
local global_abilities = require("system.global_abilities")
local objectives = require("system.objectives")
local fonts = require("util.fonts")

function renderer.draw(state)
    if not state or not state.hex then return end
    local hex = state.hex

    -- Collect cell overlays for grid rendering
    local cellOverlays = {}
    ui.collectPreparedAttackOverlays(hex, state.entities, cellOverlays)
    if state.attackMode and not state.flipTargetActor and not state.mightyThrowTarget and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn then
        ui.collectAttackableCellOverlays(hex, state.selectedActor, state.selectedAttack, state.entities, state.terrainMap, cellOverlays)
    end
    if state.flipTargetActor then
        ui.collectFlipDestOverlays(state.hex, state.selectedActor, state.flipTargetActor, state.selectedAttack, state.entities, cellOverlays)
    end
    global_abilities.collectOverlays(hex, cellOverlays, state)
    if state.attackMode and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn and not state.flipTargetActor and not state.mightyThrowTarget and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local ovCells = {}
        ui.collectAttackPreviewOverlays(hex, state.selectedActor, state.selectedAttack, hex.hoverQ, hex.hoverR, state.entities, ovCells)
        for _, c in ipairs(ovCells) do
            local key = c.q .. "," .. c.r
            if not cellOverlays[key] then
                cellOverlays[key] = {preview = true}
            end
        end
    end

    -- Collect preview damaged entities (for entity blinking), collision icons, drown overlays, and push arrows
    local previewPushArrows = nil
    local previewCollisionIcons = nil
    local drownCells = nil
    state.previewDamaged = {}
    if state.attackMode and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn and not state.flipTargetActor and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        state.previewDamaged = ui.collectPreviewDamagedEntities(hex, state.selectedActor, state.selectedAttack, hex.hoverQ, hex.hoverR, state.entities) or {}
        previewCollisionIcons = ui.collectPreviewCollisionIcons(hex, state.selectedActor, state.selectedAttack, hex.hoverQ, hex.hoverR, state.entities)
        previewPushArrows = ui.collectPreviewPushArrows(hex, state.selectedActor, state.selectedAttack, hex.hoverQ, hex.hoverR, state.entities)
        drownCells = ui.collectPreviewDrownOverlays(hex, state.selectedActor, state.selectedAttack, hex.hoverQ, hex.hoverR, state.entities)
    elseif not state.attackMode and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity:isCharacter() and not hoverEntity.isPlayable and hoverEntity.hasPreparedAttack and hoverEntity.health > 0 then
            local attack = hoverEntity.preparedAttack
            if attack then
                local targetCell = ui.getPreparedAttackTarget(hoverEntity, state.entities, hex)
                if targetCell and hex:isValidHex(targetCell.q, targetCell.r) then
                    local dmg = ui.collectPreviewDamagedEntities(hex, hoverEntity, attack, targetCell.q, targetCell.r, state.entities)
                    if dmg then state.previewDamaged = dmg end
                    previewCollisionIcons = ui.collectPreviewCollisionIcons(hex, hoverEntity, attack, targetCell.q, targetCell.r, state.entities)
                    drownCells = ui.collectPreviewDrownOverlays(hex, hoverEntity, attack, targetCell.q, targetCell.r, state.entities)
                end
            end
        end
        -- StonePillar hover: show where it falls and what gets crushed
        if hoverEntity and hoverEntity.name == "StonePillar" and not hoverEntity.isDying and hoverEntity.health > 0 then
            local pv = previewPillarFall and previewPillarFall(hoverEntity) or nil
            if pv then
                local function markFallCell(c, primary)
                    local key = c.q .. "," .. c.r
                    local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4)
                    if primary then
                        cellOverlays[key] = { fill = {0.9, 0.15, 0.1, 0.25 + 0.2 * pulse}, line = {1, 0.3, 0.15, 0.7 + 0.3 * pulse} }
                    else
                        cellOverlays[key] = { fill = {0.9, 0.45, 0.1, 0.12 + 0.08 * pulse}, line = {1, 0.55, 0.2, 0.35} }
                    end
                end
                if pv.target then
                    markFallCell(pv.target, true)
                else
                    for _, c in ipairs(pv.fallbacks) do markFallCell(c, false) end
                end
                for _, v in ipairs(pv.victims) do
                    state.previewDamaged[v] = { totalDamage = (v.health or 1) + 9999, willKill = true }
                end
            end
        end
    end
    -- Double Cleave re-aim: highlight the two allowed cells + total damage hints
    if state.attackMode and state.selectedAttack and state.selectedAttack.name == "Double Cleave"
        and cleaveTargetCell and state.selectedActor then
        local t = cleaveTargetCell
        local stepX, stepY, stepZ = state.selectedAttack:getLineDirection(state.selectedActor.q, state.selectedActor.r, t.q, t.r, hex)
        if stepX then
            local rx, ry, rz = hex_utils.rotateCubeDir(stepX, stepY, stepZ, true)
            local rq, rr = hex_utils.applyCubeStep(state.selectedActor.q, state.selectedActor.r, rx, ry, rz)
            local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 4)
            cellOverlays[t.q .. "," .. t.r] = { fill = {1, 0.75, 0.2, 0.2 + 0.15 * pulse}, line = {1, 0.8, 0.3, 0.9} }
            if hex:isActiveHex(rq, rr) then
                cellOverlays[rq .. "," .. rr] = { fill = {1, 0.75, 0.2, 0.2 + 0.15 * pulse}, line = {1, 0.8, 0.3, 0.9} }
            end

            -- Damage hints across BOTH strikes: hovering an option previews its
            -- total; a unit clipped by both swings shows 2 blinking pips.
            local hoverAim = nil
            if hex.hoverQ == t.q and hex.hoverR == t.r then
                hoverAim = { q = t.q, r = t.r }
            elseif hex.hoverQ == rq and hex.hoverR == rr then
                hoverAim = { q = rq, r = rr }
            end
            if hoverAim then
                local function strikeCells(aq, ar)
                    local sx, sy, sz = state.selectedAttack:getLineDirection(state.selectedActor.q, state.selectedActor.r, aq, ar, hex)
                    local list = { { q = aq, r = ar } }
                    if sx then
                        local lx, ly, lz = hex_utils.rotateCubeDir(sx, sy, sz, false)
                        local lq, lr = hex_utils.applyCubeStep(state.selectedActor.q, state.selectedActor.r, lx, ly, lz)
                        table.insert(list, { q = lq, r = lr })
                    end
                    return list
                end
                local totals = {}
                for _, aim in ipairs({ { q = t.q, r = t.r }, hoverAim }) do
                    for _, cc in ipairs(strikeCells(aim.q, aim.r)) do
                        local e = getEntityAtHex(cc.q, cc.r, state.entities)
                        if e and e ~= state.selectedActor and e.health > 0 then
                            totals[e] = (totals[e] or 0) + 1
                        end
                    end
                end
                for e, n in pairs(totals) do
                    state.previewDamaged[e] = { totalDamage = n, willKill = n >= e.health }
                end
            end
        end
    end
    -- Pending delayed attacks: preview what they will do (e.g. Heavy Charge)
    for _, e in ipairs(state.entities) do
        local pa = e.pendingDelayedAttack
        if e.isPlayable and pa and pa.attack and pa.attack.visualType == "line" and e.health and e.health > 0 then
            local dmg = ui.collectPreviewDamagedEntities(hex, e, pa.attack, pa.q, pa.r, state.entities)
            if dmg then state.previewDamaged = dmg end
            previewCollisionIcons = ui.collectPreviewCollisionIcons(hex, e, pa.attack, pa.q, pa.r, state.entities) or previewCollisionIcons
            previewPushArrows = ui.collectPreviewPushArrows(hex, e, pa.attack, pa.q, pa.r, state.entities) or previewPushArrows
            drownCells = ui.collectPreviewDrownOverlays(hex, e, pa.attack, pa.q, pa.r, state.entities) or drownCells
        end
    end
    if drownCells then
        for _, c in ipairs(drownCells) do
            local key = c.q .. "," .. c.r
            if not cellOverlays[key] then
                cellOverlays[key] = {drownDest = true}
            end
        end
    end

    -- Normalize overlay data
    local t = love.timer.getTime()
    local hexRadius = hex.radius
    local hazardTex = ui.getHazardTexture()
    for key, info in pairs(cellOverlays) do
        if info == true then
            -- Attackable cell
            cellOverlays[key] = {fill = {0.9, 0.8, 0.2, 0.25}, line = {0.9, 0.8, 0.2, 0.7}}
        elseif info.preview then
            -- Attack preview
            cellOverlays[key] = {fill = {1, 0.5, 0, 0.3}, line = {1, 0.7, 0, 0.8}}
        elseif info.threatCount then
            -- Prepared attack (stencil + hazard texture)
            local threatCount = info.threatCount
            local fillR, fillG, fillB, fillA
            local scaleMod
            if threatCount == 1 then
                fillR, fillG, fillB, fillA = 1, 0.5, 0.2, 0.5
                scaleMod = 1.0
            elseif threatCount == 2 then
                fillR, fillG, fillB, fillA = 1, 0.3, 0.1, 0.75
                scaleMod = 1.2
            else
                fillR, fillG, fillB, fillA = 1, 0, 0, 1
                scaleMod = 1.4
            end
            local baseA = fillA
            if threatCount <= 2 then
                local pulse = 0.7 + 0.3 * math.sin(t * 4)
                fillA = fillA * pulse
            end
            info.draw = function(vertices, ox, oy)
                love.graphics.stencil(function()
                    love.graphics.polygon("fill", vertices)
                end, "replace", 1)
                love.graphics.setStencilTest("greater", 0)
                love.graphics.setColor(fillR, fillG, fillB, fillA)
                if threatCount >= 2 then
                    love.graphics.draw(hazardTex, ox - hexRadius - 2, oy - hexRadius - 2, 0,
                        hexRadius * 2 / hazardTex:getWidth() * scaleMod,
                        hexRadius * 2 / hazardTex:getHeight() * scaleMod)
                    love.graphics.draw(hazardTex, ox - hexRadius + 2, oy - hexRadius + 2, 0,
                        hexRadius * 2 / hazardTex:getWidth() * scaleMod,
                        hexRadius * 2 / hazardTex:getHeight() * scaleMod)
                end
                love.graphics.draw(hazardTex, ox - hexRadius, oy - hexRadius, 0,
                    hexRadius * 2 / hazardTex:getWidth() * scaleMod,
                    hexRadius * 2 / hazardTex:getHeight() * scaleMod)
                love.graphics.setStencilTest()
                love.graphics.setColor(fillR, fillG, fillB, 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.polygon("line", vertices)
                love.graphics.setLineWidth(1)
            end
        elseif info.threatDirection then
            local pulse = 0.5 + 0.5 * math.sin(t * 4)
            info.draw = function(vertices, ox, oy)
                love.graphics.stencil(function()
                    love.graphics.polygon("fill", vertices)
                end, "replace", 1)
                love.graphics.setStencilTest("greater", 0)
                love.graphics.setColor(1, 0.3, 0.2, 0.5 + 0.3 * pulse)
                love.graphics.draw(hazardTex, ox - hexRadius, oy - hexRadius, 0,
                    hexRadius * 2 / hazardTex:getWidth(),
                    hexRadius * 2 / hazardTex:getHeight())
                love.graphics.setStencilTest()
                love.graphics.setColor(1, 0.3, 0.2, 0.4 + 0.3 * pulse)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", vertices)
                love.graphics.setLineWidth(1)
            end
        elseif info.flipDest then
            local pulse = 0.6 + 0.4 * math.sin(t * 4)
            cellOverlays[key] = {fill = {0.2, 0.7, 1, 0.25 * pulse}, line = {0.2, 0.7, 1, 0.8 * pulse}}
        elseif info.drownDest then
            local pulse = 0.5 + 0.5 * math.sin(t * 4)
            cellOverlays[key] = {fill = {0.1, 0.35, 0.85, 0.25 + 0.2 * pulse}, line = {0.2, 0.5, 1, 0.6 + 0.3 * pulse}}
        elseif info.windTorrentDest then
            cellOverlays[key] = {fill = {0.3, 0.6, 1, 0.4}, line = {0.3, 0.6, 1, 0.8}}
        end
    end

    drawHexGrid(state, cellOverlays)
    ui.drawPreparedAttackHealthBars(hex, state.entities)
    ui.drawDigSites(hex, status.getAllDigSites())

    if global_abilities.hasPendingRemains() then
        for _, remains in ipairs(global_abilities.pendingRemains) do
            local rx, ry = getDrawCoords(remains.q, remains.r)
            local verts = hex:drawInsetHexagon(rx, ry, hex.radius, 0.92)
            local pulse = 0.6 + 0.4 * math.sin(t * 4)
            love.graphics.setColor(0.9, 0.2, 0.1, 0.3 * pulse)
            love.graphics.polygon("fill", verts)
            love.graphics.setColor(0.9, 0.2, 0.1, 0.8 * pulse)
            love.graphics.setLineWidth(3)
            love.graphics.polygon("line", verts)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 0.4, 0.2, 0.9)
            local arrowSize = hex.radius * 0.3
            love.graphics.setLineWidth(2)
            love.graphics.line(rx, ry - arrowSize * 2, rx, ry - arrowSize * 0.5)
            love.graphics.line(rx - arrowSize * 0.4, ry - arrowSize * 1.2, rx, ry - arrowSize * 0.5, rx + arrowSize * 0.4, ry - arrowSize * 1.2)
            love.graphics.setLineWidth(1)
        end
    end

    if lightningWarning and lightningTargetQ >= 0 and lightningTargetR >= 0 then
        local wx, wy = getDrawCoords(lightningTargetQ, lightningTargetR)
        local verts = hex:drawInsetHexagon(wx, wy, hex.radius, 0.92)
        love.graphics.setColor(1, 0.9, 0.2, 0.3)
        love.graphics.polygon("fill", verts)
        love.graphics.setColor(1, 0.9, 0.2, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.polygon("line", verts)
        love.graphics.setLineWidth(1)
        local ls = hex.radius * 0.4
        love.graphics.setColor(1, 0.9, 0.2, 1)
        love.graphics.setLineWidth(3)
        local lx, ly = wx, wy
        love.graphics.line(lx, ly - ls * 0.6, lx + ls * 0.25, ly - ls * 0.1, lx + ls * 0.05, ly + ls * 0.05, lx + ls * 0.3, ly + ls * 0.6)
        love.graphics.setLineWidth(1)
    end
    if state.vortexTargetCell and state.selectedAttack then
        local vx, vy = getDrawCoords(state.vortexTargetCell.q, state.vortexTargetCell.r)
        local targetVerts = hex:drawInsetHexagon(vx, vy, hex.radius, 0.92)
        love.graphics.setColor(0.2, 0.6, 1, 0.4)
        love.graphics.polygon("fill", targetVerts)
        love.graphics.setColor(0.2, 0.6, 1, 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.polygon("line", targetVerts)
        if state.selectedAttack.name == "Vortex Strike" then
            local dests = state.selectedAttack:getShiftDestinations(state.selectedActor, state.vortexTargetCell.q, state.vortexTargetCell.r, hex)
            for _, dc in ipairs(dests) do
                local dx, dy = getDrawCoords(dc.q, dc.r)
                local dv = hex:drawInsetHexagon(dx, dy, hex.radius, 0.92)
                love.graphics.setColor(0.4, 0.8, 1, 0.3)
                love.graphics.polygon("fill", dv)
                love.graphics.setColor(0.4, 0.8, 1, 0.8)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", dv)
                love.graphics.setLineWidth(1)
            end
        elseif state.selectedAttack.name == "Wide Vortex" then
            local stepX, stepY, stepZ = state.selectedAttack:getLineDirection(state.selectedActor.q, state.selectedActor.r, state.vortexTargetCell.q, state.vortexTargetCell.r, hex)
            local ax, ay, az = hex_utils.axialToCube(state.selectedActor.q, state.selectedActor.r)
            local dests = state.selectedAttack:getShiftDestinations(state.selectedActor, state.vortexTargetCell.q, state.vortexTargetCell.r, hex)
            for _, dc in ipairs(dests) do
                local dx, dy = getDrawCoords(dc.q, dc.r)
                local dv = hex:drawInsetHexagon(dx, dy, hex.radius, 0.92)
                love.graphics.setColor(0.4, 0.8, 1, 0.3)
                love.graphics.polygon("fill", dv)
                love.graphics.setColor(0.4, 0.8, 1, 0.8)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", dv)
                love.graphics.setLineWidth(1)
                -- Second target B: 60° further around attacker
                local occupant = getEntityAtHex(dc.q, dc.r)
                if occupant and occupant:isCharacter() and occupant.health > 0 then
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
        love.graphics.setLineWidth(1)
    end
    if state.mightyThrowTarget and state.selectedAttack and state.selectedActor then
        local mtx, mty = getDrawCoords(state.mightyThrowTarget.q, state.mightyThrowTarget.r)
        local mtVerts = hex:drawInsetHexagon(mtx, mty, hex.radius, 0.92)
        love.graphics.setColor(0.9, 0.3, 0.1, 0.4)
        love.graphics.polygon("fill", mtVerts)
        love.graphics.setColor(0.9, 0.3, 0.1, 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.polygon("line", mtVerts)
        love.graphics.setLineWidth(1)
        if hex.hoverQ >= 0 and hex.hoverR >= 0 then
            local stepX, stepY, stepZ = state.selectedAttack:getLineDirection(state.selectedActor.q, state.selectedActor.r, hex.hoverQ, hex.hoverR, hex)
            if stepX then
                local endCell = combat.getFarthestActiveCellOnLine(state.selectedActor.q, state.selectedActor.r, stepX, stepY, stepZ, hex)
                if endCell then
                    local ex, ey = getDrawCoords(endCell.q, endCell.r)
                    love.graphics.setColor(0.9, 0.3, 0.1, 0.5)
                    love.graphics.setLineWidth(3)
                    love.graphics.line(mtx, mty, ex, ey)
                    love.graphics.setLineWidth(1)
                end
                local curQ, curR = state.selectedActor.q, state.selectedActor.r
                while true do
                    local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
                    if not hex:isActiveHex(nextQ, nextR) then break end
                    local e = getEntityAtHex(nextQ, nextR, state.entities)
                    if e and e ~= state.mightyThrowTarget and e.health > 0 then
                        local sx, sy = getDrawCoords(nextQ, nextR)
                        local sv = hex:drawInsetHexagon(sx, sy, hex.radius, 0.92)
                        love.graphics.setColor(1, 0.2, 0.1, 0.4)
                        love.graphics.polygon("fill", sv)
                        love.graphics.setColor(1, 0.2, 0.1, 0.9)
                        love.graphics.setLineWidth(3)
                        love.graphics.polygon("line", sv)
                        love.graphics.setLineWidth(1)
                        local rightX, rightY, rightZ = -stepY, -stepZ, -stepX
                        local leftX, leftY, leftZ = -stepZ, -stepX, -stepY
                        local rq, rr = hex_utils.applyCubeStep(nextQ, nextR, rightX, rightY, rightZ)
                        local lq, lr = hex_utils.applyCubeStep(nextQ, nextR, leftX, leftY, leftZ)
                        local sideQ, sideR
                        if hex:isActiveHex(rq, rr) and not getEntityAtHex(rq, rr, state.entities) then
                            sideQ, sideR = rq, rr
                        elseif hex:isActiveHex(lq, lr) and not getEntityAtHex(lq, lr, state.entities) then
                            sideQ, sideR = lq, lr
                        end
                        if sideQ then
                            local sdx, sdy = getDrawCoords(sideQ, sideR)
                            local sdv = hex:drawInsetHexagon(sdx, sdy, hex.radius, 0.92)
                            love.graphics.setColor(0.4, 0.8, 1, 0.3)
                            love.graphics.polygon("fill", sdv)
                            love.graphics.setColor(0.4, 0.8, 1, 0.8)
                            love.graphics.setLineWidth(2)
                            love.graphics.polygon("line", sdv)
                            love.graphics.setLineWidth(1)
                        end
                        break
                    end
                    curQ, curR = nextQ, nextR
                end
            end
        end
    end
    for _, entity in ipairs(state.entities) do
        -- Highlighting of summoning rod target cell
        if entity.isSummoningRod and entity.hasPreparedAttack and entity.summonTargetQ and entity.summonTargetR then
            local sx, sy = getDrawCoords(entity.summonTargetQ, entity.summonTargetR)
            local verts = hex:drawInsetHexagon(sx, sy, hex.radius, 0.92)
            local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 4)
            love.graphics.setColor(0.8, 0.4, 0.2, 0.2 + 0.3 * pulse)
            love.graphics.polygon("fill", verts)
            love.graphics.setColor(0.8, 0.4, 0.2, 0.5 + 0.3 * pulse)
            love.graphics.setLineWidth(3)
            love.graphics.polygon("line", verts)
            love.graphics.setLineWidth(1)
        end
    end
    drawAllEntities(state)
    ui.drawPreviewIcons(hex, previewCollisionIcons)
    ui.drawPreviewPushArrows(previewPushArrows)
    visual.draw()
    ui.drawDelayedHints(state.entities)

    if not state.attackMode then
        local sel = state.selectedActor
        if sel and not sel.isMoving and state.turnState.phase == "player" then
            local isRooted = status and status.hasEntityStatus and status.hasEntityStatus(sel, "rooted") and not sel.rootImmune
            local canShowMove = not isRooted and (not sel.hasActedThisTurn or sel.canMoveAfterAttack) and (not sel.hasMovedThisTurn or sel.canMoveAfterAttack)
                and (not sel.soloActions or (sel.movesLeft or 0) > 0)
            if canShowMove then
                ui.drawMovementRange(hex, sel, state.entities, state.terrainMap)
                if sel.isPlayable and hex.hoverQ >= 0 and hex.hoverR >= 0 then
                    ui.drawPathPreview(hex, sel, hex.hoverQ, hex.hoverR, state.entities, state.terrainMap)
                end
            end
        end
    end

    -- Enemy prepared-attack previews draw ABOVE the green move-range fill so
    -- their direction/overlay stays readable over cells the hero can reach.
    for _, entity in ipairs(state.entities) do
        if (entity:isCharacter() and not entity.isPlayable or entity.isTrainAttack) and entity.hasPreparedAttack and entity.health > 0 then
            ui.drawPreparedAttackDirection(hex, entity, love.timer.getTime(), state.entities)
        end
    end

    if state.attackMode and state.selectedAttack and state.selectedActor and not state.selectedActor.hasActedThisTurn and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        ui.drawAttackPreview(hex, state.selectedActor, state.selectedAttack, state.attackMode, hex.hoverQ, hex.hoverR, state.entities)
    end

    -- Enemy attack preview on hover (only when not in player attack mode)
    if not state.attackMode and hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity:isCharacter() and not hoverEntity.isPlayable and hoverEntity.hasPreparedAttack and hoverEntity.health > 0 then
            local attack = hoverEntity.preparedAttack
            if attack then
                local targetQ, targetR = hoverEntity.q, hoverEntity.r
                if attack.name == "Ghost Bolt" and hoverEntity.attackDirection then
                    local step = hoverEntity.attackDirection
                    local curQ, curR = hoverEntity.q, hoverEntity.r
                    while true do
                        local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, step.dx, step.dy, step.dz)
                        if not hex:isActiveHex(nextQ, nextR) then break end
                        local ent = getEntityAtHex(nextQ, nextR, state.entities)
                        if ent and ent ~= hoverEntity and ent.health > 0 then
                            targetQ, targetR = nextQ, nextR
                            break
                        end
                        curQ, curR = nextQ, nextR
                    end
                elseif attack.name == "Magic Bolt" and hoverEntity.preparedTargetOffset then
                    targetQ, targetR = hex_utils.applyCubeDiff(
                        hoverEntity.q, hoverEntity.r,
                        hoverEntity.preparedTargetOffset.dx,
                        hoverEntity.preparedTargetOffset.dy,
                        hoverEntity.preparedTargetOffset.dz
                    )
                elseif attack.name == "Bite" and hoverEntity.preparedTargetOffset then
                    targetQ, targetR = hex_utils.applyCubeDiff(
                        hoverEntity.q, hoverEntity.r,
                        hoverEntity.preparedTargetOffset.dx,
                        hoverEntity.preparedTargetOffset.dy,
                        hoverEntity.preparedTargetOffset.dz
                    )
                elseif hoverEntity.attackDirection then
                    local step = hoverEntity.attackDirection
                    targetQ, targetR = hex_utils.applyCubeStep(hoverEntity.q, hoverEntity.r, step.dx, step.dy, step.dz)
                end
                if hex:isValidHex(targetQ, targetR) then
                    ui.drawAttackPreview(hex, hoverEntity, attack, true, targetQ, targetR, state.entities)
                end
            end
        end
    end

    local mx, my = love.mouse.getPosition()
    mx = mx / state.dpiScale
    my = my / state.dpiScale

    local hoverOrder = ui.drawEnemyOrderButton(mx, my)
    ui.drawUndoButton(undo.history, state.maxUndoCount, state.selectedActor)
    ui.drawEndTurnButton(state.turnState, state.entities, state.turnCount, state.maxTurns, state)
    ui.drawAbilitiesToggleButton(state, mx, my)
    ui.drawMechanismButton(state)
    ui.drawAbilityButtons(state)

    global_abilities.drawPreview(hex, state)

    -- Dead-hero indicator: actions locked until redeploy, abilities still usable
    if soloMode and heroRevivePending then
        local msg = "The hero has fallen! Actions locked until redeploy next turn"
        local f = fonts.get(18)
        local tw = f:getWidth(msg)
        local w = love.graphics.getWidth() / (state.dpiScale or 1)
        love.graphics.setColor(0.12, 0.05, 0.05, 0.8)
        love.graphics.rectangle("fill", w / 2 - tw / 2 - 14, 8, tw + 28, 32)
        love.graphics.setColor(1, 0.4, 0.3, 1)
        love.graphics.setFont(f)
        love.graphics.print(msg, w / 2 - tw / 2, 15)
        love.graphics.setColor(1, 1, 1, 1)
    end

    ui.drawAttackPanel(state.selectedActor, state.attackButtons, state.selectedAttack, state.attackMode)
    ui.drawGentleTouch(state.selectedActor)
    if state.selectedActor then
        ui.drawSelectedStats(state.selectedActor, state.entities, hex)
    elseif global_abilities.activeAbility then
        ui.drawAbilityStats(global_abilities.activeAbility)
    end

    local showOrder = hoverOrder or state.showEnemyOrder or love.keyboard.isDown("o")
    if showOrder then
        -- Heatmap: red = first to attack, yellow = last
        local orderMap = getEnemyAttackOrder(state.entities, state.turnState)
        local maxN = 0
        for _, enemy in ipairs(state.entities) do
            local n = orderMap[enemy]
            if n then maxN = math.max(maxN, n) end
        end
        for _, enemy in ipairs(state.entities) do
            local n = orderMap[enemy]
            if n and enemy.health > 0 then
                local t = maxN > 1 and (n - 1) / (maxN - 1) or 0
                local x, y = getDrawCoords(enemy.q, enemy.r)
                love.graphics.setColor(1, t, 0, 0.9)
                love.graphics.circle("fill", x + 15, y - 20, 12)
                love.graphics.setColor(0, 0, 0, 1)
                love.graphics.print(tostring(n), x + 11, y - 28)
            end
        end
    end

    if hex.hoverQ >= 0 and hex.hoverR >= 0 then
        local hoverEntity = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if hoverEntity and hoverEntity.health > 0 and (hoverEntity:isObstacle() or (hoverEntity:isBuilding() and hoverEntity.moveRange == 0)) then
            ui.drawEntityTooltip(hoverEntity, state.terrainMap, hex, state.entities)
        elseif hex:isActiveHex(hex.hoverQ, hex.hoverR) then
            local terrain = state.terrainMap and state.terrainMap[hex.hoverQ] and state.terrainMap[hex.hoverQ][hex.hoverR] or "grass"
            ui.drawCellTooltip(hex.hoverQ, hex.hoverR, terrain, hex)
        end
    end

    ui.drawChaosBar(mx, my)
    ui.drawLeaderHPBar(mx, my)
    objectives.draw()

    if not state.gameActive then
        local width = logicalW
        local height = logicalH
        local oldFont = love.graphics.getFont()

        if isProgressionRun and state.win then
            if progressionOverlay == "complete" then
                drawProgressionComplete(width, height)
            end
        else
            love.graphics.setColor(0, 0, 0, 0.85)
            love.graphics.rectangle("fill", 0, 0, width, height)

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(fonts.get(48))
            if state.win then
                love.graphics.printf("VICTORY!", 0, height/2 - 100, width, "center")
                local total = objectives.getTotalCount()
                local completed = objectives.getCompletedCount()
                love.graphics.setFont(fonts.get(18))
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
                love.graphics.printf("Objectives: " .. completed .. " / " .. total .. " completed", 0, height/2 - 50, width, "center")
            elseif state.loss then
                love.graphics.printf("DEFEAT!", 0, height/2 - 100, width, "center")
            end

            local btnW, btnH = 200, 50
            local btnX = width/2 - btnW/2
            local btnY = height/2 + 20
            love.graphics.setFont(fonts.get(24))
            love.graphics.setColor(0.2, 0.2, 0.6, 0.9)
            love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 8)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("New Game (Enter)", btnX + 20, btnY + 12)
            love.graphics.setFont(oldFont)
        end
    end
end


function drawProgressionComplete(w, h)
    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.get(26))
    love.graphics.printf("PROGRESSION TEST", 0, h/2 - 140, w, "center")
    love.graphics.setFont(fonts.get(32))
    love.graphics.setColor(0.4, 1, 0.4, 1)
    love.graphics.printf("COMPLETE!", 0, h/2 - 100, w, "center")

    local surplus = _G.chaosSurplus or 0
    if surplus >= 9 then
        love.graphics.setFont(fonts.get(14))
        love.graphics.setColor(0.6, 0.9, 0.6, 1)
        love.graphics.printf("Perfect victory! Surplus: " .. surplus, 0, h/2 - 60, w, "center")
    end

    local choices = progressionChoices or {}
    if #choices > 0 then
        love.graphics.setFont(fonts.get(14))
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        local startY = surplus >= 9 and h/2 - 30 or h/2 - 50
        love.graphics.printf("Upgrades chosen:", 0, startY, w, "center")

        local typeLabels = { spell = "Spell", unit = "Unit", generic = "Generic", commander = "Commander", heroic = "Heroic" }
        local typeColors = { spell = {0.8, 0.5, 1.0}, unit = {0.8, 0.8, 0.4}, generic = {0.5, 0.9, 0.5}, commander = {0.4, 0.8, 1.0}, heroic = {1.0, 0.6, 0.2} }
        local listStartY = startY + 25
        local lineH = 20
        for i, ch in ipairs(choices) do
            local c = typeColors[ch.type] or {1, 1, 1}
            love.graphics.setColor(c[1], c[2], c[3], 0.9)
            love.graphics.setFont(fonts.get(11))
            love.graphics.print("[" .. (typeLabels[ch.type] or ch.type) .. "]", w/2 - 180, listStartY + (i-1) * lineH)
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setFont(fonts.get(12))
            love.graphics.print(ch.name, w/2 - 100, listStartY + (i-1) * lineH)
        end
    end

    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale

    local btnW, btnH = 240, 50
    local btnX = w/2 - btnW/2
    local btnY = h/2 + 100
    local btnHover = mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH

    love.graphics.setFont(fonts.get(16))
    love.graphics.setColor(btnHover and 0.4 or 0.2, btnHover and 0.25 or 0.15, btnHover and 0.2 or 0.1, 0.9)
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 8)
    love.graphics.setColor(0.6, 0.4, 0.2, btnHover and 0.8 or 0.4)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Back to Menu", btnX, btnY + 15, btnW, "center")
end

-- ============================================================
-- RENDERING FUNCTIONS (moved from main.lua)
-- ============================================================

function drawHexGrid(state, cellOverlays)
    local hex = state.hex
    love.graphics.setLineWidth(1)
    local gridW = hex.gridWidth
    local gridH = hex.gridHeight
    if not gridW or not gridH then return end

    local baseCells = hex:getSortedCells(state.terrainMap, state.config.WATER_Y_OFFSET, state.elevationMap)


    -- Build frame-specific cells (add testView offset)
    local cells = {}
    for i, bc in ipairs(baseCells) do
        local testY = 0
        if testViewActive and bc.q == hex.centerQ and bc.r == hex.centerR then
            testY = testViewOffsetY
        end
        cells[i] = { q = bc.q, r = bc.r, x = bc.x, y = bc.y, terrain = bc.terrain, depth = bc.depth, testY = testY }
    end

    if testViewActive then
        table.sort(cells, function(a, b) return a.depth < b.depth end)
    end

    local hoveredBoundaryEntity = nil
    if hex.hoverQ >= 0 then
        local he = getEntityAtHex(hex.hoverQ, hex.hoverR)
        if he and he.cells and he:isObstacle() then
            hoveredBoundaryEntity = he
        end
    end
    local selectedBoundaryEntity = boundarySelected

    for _, cell in ipairs(cells) do
        local drawY = cell.y + (cell.testY or 0)
        local yOffset = hex:getCellYOffset(cell.q, cell.r, cell.terrain, state.config.WATER_Y_OFFSET, state.elevationMap)
        hex:drawTerrainHex(cell.q, cell.r, cell.terrain, cell.x, drawY, state.elevationMap)
        local upperType = state.upperTerrainMap[cell.q] and state.upperTerrainMap[cell.q][cell.r]
        if upperType then
            hex:drawUpperTerrain(cell.q, cell.r, upperType, cell.x, drawY, yOffset)
        end
        local hexStatuses = status.getAtHex(cell.q, cell.r)
        if #hexStatuses > 0 then
            ui.drawCellStatusEffects(cell.x, drawY + yOffset, hex.radius, hexStatuses, love.timer.getTime())
        end

        local cellKey = cell.q .. "," .. cell.r
        local overlay = cellOverlays and cellOverlays[cellKey]
        if overlay then
            local verts = hex:drawInsetHexagon(cell.x, drawY + yOffset, hex.radius, 1.0)
            if overlay.fill then
                love.graphics.setColor(overlay.fill[1], overlay.fill[2], overlay.fill[3], overlay.fill[4])
                love.graphics.polygon("fill", verts)
            end
            if overlay.line then
                love.graphics.setColor(overlay.line[1], overlay.line[2], overlay.line[3], overlay.line[4])
                love.graphics.polygon("line", verts)
            end
            if overlay.draw then
                overlay.draw(verts, cell.x, drawY + yOffset)
            end
        end

        local insetVerts = hex:drawHexagon(cell.x, drawY + yOffset, hex.radius)

        local isCurrentActor = state.selectedActor and state.selectedActor.q == cell.q and state.selectedActor.r == cell.r
            and not state.selectedActor.isMoving
        local isSelected = (hex.selectedQ == cell.q and hex.selectedR == cell.r)
            and not (state.selectedActor and state.selectedActor.isMoving)
        local isHovered = (hex.hoverQ == cell.q and hex.hoverR == cell.r)

        local cellEntity = getEntityAtHex(cell.q, cell.r)
        local inGroup = cellEntity and cellEntity.cells and (cellEntity:isObstacle() or cellEntity:isEdge())
        local isHoveredGroup = inGroup and cellEntity == hoveredBoundaryEntity
        local isSelectedGroup = inGroup and cellEntity == selectedBoundaryEntity

        if isSelectedGroup or isHoveredGroup then
            local a = isSelectedGroup and 0.55 or 0.3
            love.graphics.setColor(0.4, 0.35, 0.25, a)
            love.graphics.polygon("fill", insetVerts)
            love.graphics.setColor(0.4, 0.35, 0.25, 0.85)
            love.graphics.setLineWidth(3)
            love.graphics.polygon("line", insetVerts)
        elseif inGroup then
            -- boundary cell, no hex outline
        elseif isCurrentActor then
            love.graphics.setColor(0.2, 0.8, 0.2, 0.5)
            love.graphics.polygon("fill", insetVerts)
            love.graphics.setColor(0.2, 0.8, 0.2, 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.polygon("line", insetVerts)
        elseif isSelected then
            love.graphics.setColor(0.2, 0.4, 0.8, 0.5)
            love.graphics.polygon("fill", insetVerts)
            love.graphics.setColor(0.2, 0.4, 0.8, 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.polygon("line", insetVerts)
        elseif isHovered then
            local hoverEntity = cellEntity
            if hoverEntity and hoverEntity:isBuilding() then
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.polygon("fill", insetVerts)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.polygon("line", insetVerts)
            else
                love.graphics.setColor(0.5, 0.8, 0.3, 0.5)
                love.graphics.polygon("fill", insetVerts)
                love.graphics.setColor(0.5, 0.8, 0.3, 0.9)
                love.graphics.setLineWidth(3)
                love.graphics.polygon("line", insetVerts)
            end
        end

        -- Directional entities: edge color marking (green = safe, red = dangerous)
        if cellEntity and cellEntity.direction and not cellEntity.noSidedPush then
            local edgeVerts = hex:drawHexagon(cell.x, drawY + yOffset, hex.radius - 1)
            local edgeDirs = {
                {dx = 0,  dy = 1,  dz = -1},  -- edge 0: SE
                {dx = -1, dy = 1,  dz = 0},   -- edge 1: SW
                {dx = -1, dy = 0,  dz = 1},   -- edge 2: W
                {dx = 0,  dy = -1, dz = 1},   -- edge 3: NW
                {dx = 1,  dy = -1, dz = 0},   -- edge 4: NE
                {dx = 1,  dy = 0,  dz = -1},  -- edge 5: E
            }
            love.graphics.setLineWidth(4)
            for edgeIdx = 1, 6 do
                local dir = edgeDirs[edgeIdx]
                local neighborQ, neighborR = hex_utils.applyCubeStep(cellEntity.q, cellEntity.r, dir.dx, dir.dy, dir.dz)
                local safe = hex_utils.isPushFromSafeSide(cellEntity, neighborQ, neighborR)
                local i1 = (edgeIdx - 1) * 2 + 1
                local i2 = (edgeIdx % 6) * 2 + 1
                local x1, y1 = edgeVerts[i1], edgeVerts[i1 + 1]
                local x2, y2 = edgeVerts[i2], edgeVerts[i2 + 1]
                if safe then
                    love.graphics.setColor(0.2, 0.9, 0.3, 0.85)
                else
                    love.graphics.setColor(0.9, 0.2, 0.2, 0.85)
                end
                love.graphics.line(x1, y1, x2, y2)
            end
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1, 1)
        end

        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function getEntityDrawPosition(entity, state)
    if entity.currentDrawX and entity.currentDrawY then
        return entity.currentDrawX, entity.currentDrawY
    end

    if state.pushAnimations and state.pushAnimations.queue then
        for _, anim in ipairs(state.pushAnimations.queue) do
            if anim.obj == entity and anim.isMoving then
                local t = math.min(1, anim.timer / anim.duration)
                local ease = 1 - (1 - t) * (1 - t)

                if anim.isShake then
                    if anim.offsetX and anim.offsetY then
                        local x, y = getDrawCoords(anim.obj.q, anim.obj.r)
                        local curX = x + anim.offsetX * (1 - ease)
                        local curY = y + anim.offsetY * (1 - ease)
                        return curX, curY
                    else
                        return getDrawCoords(entity.q, entity.r)
                    end
                else
                    if anim.startX and anim.endX then
                        local x = anim.startX + (anim.endX - anim.startX) * ease
                        local y = anim.startY + (anim.endY - anim.startY) * ease
                        return x, y
                    else
                        return getDrawCoords(entity.q, entity.r)
                    end
                end
            end
        end
    end

    if entity.isMoving then
        local t = entity.timer / entity.speed
        if t > 1 then t = 1 end
        local ease = t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
        local x = entity.startX + (entity.endX - entity.startX) * ease
        local y = entity.startY + (entity.endY - entity.startY) * ease
        return x, y
    end

    return getDrawCoords(entity.q, entity.r)
end

-- Into-the-Breach style health pips above a unit: thick cells on a black
-- backing strip. Pips that would be lost to the hovered attack
-- (state.previewDamaged) blink.
function drawHealthPips(entity, x, y, state)
    if entity.isDying or entity:isEdge() or entity.indestructible then return end
    if not entity.health or entity.maxHealth <= 1 then return end

    local preview = state.previewDamaged and state.previewDamaged[entity]
    local lost = 0
    if preview then
        lost = math.min(preview.totalDamage or 0, entity.health)
    end

    local pipW, pipH, gap = 8, 5, 2
    local totalW = entity.maxHealth * pipW + (entity.maxHealth - 1) * gap
    local px = x - totalW / 2
    local py = y - 26
    local t = love.timer.getTime()

    -- black backing around the whole bar
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", px - 2, py - 2, totalW + 4, pipH + 4)

    local r, g, b
    if entity:isCharacter() then
        if entity.isPlayable then r, g, b = 0.35, 0.85, 0.4
        else r, g, b = 0.9, 0.25, 0.25 end
    else
        r, g, b = 0.75, 0.68, 0.55
    end

    for i = 1, entity.maxHealth do
        local filled = i <= entity.health
        if filled then
            local pulse = 1
            if i > entity.health - lost then
                pulse = 0.55 + 0.45 * math.sin(t * 4)
            end
            love.graphics.setColor(r * pulse, g * pulse, b * pulse, 0.95)
            love.graphics.rectangle("fill", px + (i - 1) * (pipW + gap), py, pipW, pipH)
        else
            love.graphics.setColor(0.15, 0.15, 0.18, 0.7)
            love.graphics.rectangle("fill", px + (i - 1) * (pipW + gap), py, pipW, pipH)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function drawActionIndicator(entity, x, y)
    if not entity:isCharacter() then return end
    if entity.hasActedThisTurn then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.8)
        love.graphics.circle("fill", x + 15, y - 15, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("\xE2\x9C\x93", x + 11, y - 20)
    elseif entity.isPlayable and not entity.hasMovedThisTurn then
        local isRooted = status and status.hasEntityStatus and status.hasEntityStatus(entity, "rooted") and not entity.rootImmune
        if isRooted then
            love.graphics.setColor(0.6, 0.8, 0.2, 0.9)
        else
            love.graphics.setColor(0.2, 0.9, 0.2, 0.9)
        end
        love.graphics.circle("fill", x + 15, y - 15, 8)
    elseif entity.isPlayable and entity.hasMovedThisTurn then
        love.graphics.setColor(1, 0.7, 0, 0.9)
        love.graphics.circle("fill", x + 15, y - 15, 8)
    end
end

function drawEntity(entity, state)
    love.graphics.setColor(1, 1, 1, 1)
    local x, y = getEntityDrawPosition(entity, state)

    local alpha = 1
    local scale = 1
    if entity.isDying then
        local t = entity.deathTimer / entity.deathDuration
        alpha = 1 - t
        scale = 1 - t * 0.7
        love.graphics.setColor(1, 1, 1, alpha)
    end

    local wounded = entity:isCharacter() and entity.health > 0 and entity.health < entity.maxHealth

    -- Highlight shuntable train cars
    local shuntHighlight = false
    if entity.isTrainCar and state.turnState and state.turnState.phase == "player" then
        shuntHighlight = true
    end

    if entity.sprite then
        local sw, sh = entity.sprite:getDimensions()
        local baseScale = 6
        if entity:isObstacle() or entity:isBuilding() or entity:isEdge() then
            baseScale = 5
        end
        local finalScale = baseScale * scale
        local drawY = y
        if entity:isObstacle() or entity:isBuilding() or entity:isEdge() then
            drawY = y - 6
        end
        if wounded then
            love.graphics.setColor(1, 0.3, 0.3, alpha)
        elseif shuntHighlight then
            love.graphics.setColor(0.3, 0.6, 1, alpha)
        end
        -- Directional entities: rotate sprite to match direction
        local spriteRotation = 0
        if entity.direction then
            for i = 1, 6 do
                local cd = hex_utils.CUBE_DIRECTIONS[i]
                if cd.dx == entity.direction.dx and cd.dy == entity.direction.dy and cd.dz == entity.direction.dz then
                    spriteRotation = (i - 2) * math.pi / 3
                    break
                end
            end
        end
        if entity.cells then
            for _, c in ipairs(entity.cells) do
                local cx, cy = getDrawCoords(c.q, c.r)
                local cdrawY = cy
                if entity:isObstacle() or entity:isBuilding() or entity:isEdge() then
                    cdrawY = cy - 6
                end
                love.graphics.draw(entity.sprite, cx, cdrawY, spriteRotation, finalScale, finalScale, sw/2, sh/2)
            end
        else
            love.graphics.draw(entity.sprite, x, drawY, spriteRotation, finalScale, finalScale, sw/2, sh/2)
        end

        -- Outline for selected entity (4-pass sprite outline)
        if state.selectedActor == entity and not entity.isDying then
            local outlineR, outlineG, outlineB
            if entity.isPlayable then
                outlineR, outlineG, outlineB = 0.3, 0.9, 0.3
            elseif entity:isCharacter() then
                outlineR, outlineG, outlineB = 0.9, 0.3, 0.3
            else
                outlineR, outlineG, outlineB = 1, 1, 1
            end
            local off = 4
            local sw2, sh2 = entity.sprite:getDimensions()
            love.graphics.setColor(outlineR, outlineG, outlineB, 0.9)
            love.graphics.draw(entity.sprite, x - off, drawY, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x + off, drawY, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x, drawY - off, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x, drawY + off, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x - off, drawY - off, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x + off, drawY - off, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x - off, drawY + off, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.draw(entity.sprite, x + off, drawY + off, spriteRotation, finalScale, finalScale, sw2/2, sh2/2)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(entity.sprite, x, drawY, spriteRotation, finalScale, finalScale, sw/2, sh/2)
        end

        -- Cracks on damaged buildings (not indestructible ones)
        if entity:isBuilding() and entity.health > 0 and entity.health < entity.maxHealth and not entity.indestructible then
            local crackAlpha = 0.7 * alpha
            love.graphics.setColor(0.15, 0.1, 0.05, crackAlpha)
            love.graphics.setLineWidth(2)
            local cr = 12 * scale
            -- Main crack
            love.graphics.line(x - cr*0.3, drawY - cr*0.6, x + cr*0.1, drawY - cr*0.1, x - cr*0.2, drawY + cr*0.4)
            -- Branch
            if entity.health <= math.floor(entity.maxHealth / 2) then
                love.graphics.line(x + cr*0.1, drawY - cr*0.1, x + cr*0.5, drawY + cr*0.2)
            end
            love.graphics.setLineWidth(1)
        end

    else
        love.graphics.setColor(entity.color or {1, 1, 1, 1})
        love.graphics.circle("fill", x, y, 14)
        -- Cracks on damaged buildings (fallback, no sprite)
        if entity:isBuilding() and entity.health > 0 and entity.health < entity.maxHealth and not entity.indestructible then
            love.graphics.setColor(0.15, 0.1, 0.05, 0.7 * alpha)
            love.graphics.setLineWidth(2)
            love.graphics.line(x - 4, y - 8, x + 2, y, x - 3, y + 6)
            love.graphics.setLineWidth(1)
        end
    end

    if entity.isDying then
        love.graphics.setColor(1, 0.2, 0.2, alpha)
        love.graphics.circle("fill", x, y, 18)
    end

    local entityStatuses = status.getEntityStatuses(entity)
    if #entityStatuses > 0 then
        local overlayRadius = 22
        if entity.sprite then
            local sw, sh = entity.sprite:getDimensions()
            overlayRadius = math.max(sw, sh) * 6 / 2
        end
        ui.drawEntityStatusEffects(x, y, entity, overlayRadius, love.timer.getTime())
    end

    drawHealthPips(entity, x, y, state)
    drawActionIndicator(entity, x, y)
end

function drawAllEntities(state)
    for _, entity in ipairs(state.entities) do
        drawEntity(entity, state)
    end
end

-- Preview of the landing-damage an ally would deal if dropped at the given
-- cell: returns a map enemy -> {totalDamage, willKill} for every non-playable
-- character within `radius` of (q,r). Empty/dead excluded.
local function computeDeployDamagePreview(ally, entities, hex, q, r)
    local out = {}
    local eff = ally and ally.deployEffect
    if not eff or eff.type ~= "damage_nearby" then return out end
    if not q or not r then return out end
    local rad = eff.radius or 1
    local dmg = eff.damage or 1
    for _, e in ipairs(entities) do
        if e ~= ally and e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isDying
            and e.q ~= nil and hex:getDistance(q, r, e.q, e.r) <= rad then
            out[e] = { totalDamage = dmg, willKill = dmg >= e.health }
        end
    end
    return out
end
renderer.computeDeployDamagePreview = computeDeployDamagePreview

function renderer.drawDeployPhase(state, unplacedAllies, placedAllies, deploySelectedIdx)
    if not state or not state.hex then return end
    local hex = state.hex
    local hexRadius = hex.radius

    drawHexGrid(state, {})

    -- Landing-damage hint: if the ally about to be placed damages enemies near
    -- the hovered cell, mark those enemies so their health pips blink. Only for
    -- cells the unit can actually be dropped on (empty + in the deployable zone).
    state.previewDamaged = {}
    local pendingLand = nil
    local function inAllowedDeployZone(q, r)
        if heroRevivePending then
            if heroDeathPos then
                return hex:getDistance(q, r, heroDeathPos.q, heroDeathPos.r) <= 2
            end
            return hex:isActiveHex(q, r)
        end
        -- normal deploy is limited to the left columns
        return q >= 0 and q <= (state.config and state.config.DEPLOY_COLS or 3)
    end
    do
        local function isLandable(q, r)
            if not hex:isActiveHex(q, r) then return false end
            if not inAllowedDeployZone(q, r) then return false end
            local terr = state.terrainMap and state.terrainMap[q] and state.terrainMap[q][r] or "grass"
            if terr == "water" then return false end
            for _, e in ipairs(state.entities) do
                if (e.q == q and e.r == r) then return false end
                if e.cells then
                    for _, c in ipairs(e.cells) do
                        if c.q == q and c.r == r then return false end
                    end
                end
            end
            for _, p in ipairs(placedAllies) do
                if p.q == q and p.r == r then return false end
            end
            return true
        end

        local hq, hr = hex.hoverQ, hex.hoverR
        local ally = nil
        if #unplacedAllies > 0 then
            ally = unplacedAllies[1]
        elseif deploySelectedIdx and placedAllies[deploySelectedIdx] then
            ally = placedAllies[deploySelectedIdx]
        end
        if ally and ally.deployEffect and ally.deployEffect.type == "damage_nearby"
            and hq ~= nil and hr ~= nil and isLandable(hq, hr) then
            state.previewDamaged = computeDeployDamagePreview(ally, state.entities, hex, hq, hr)
            pendingLand = { q = hq, r = hr, radius = ally.deployEffect.radius or 1 }
        end
    end

    for _, entity in ipairs(state.entities) do
        drawEntity(entity, state)
    end

    for _, ally in ipairs(placedAllies) do
        drawEntity(ally, state)
    end

    -- A revived hero comes back only within radius 2 of the cell it fell on.
    local reviveRange = (heroRevivePending and heroDeathPos) and heroDeathPos or nil
    local qLo, qHi = 0, 3
    if reviveRange then qLo, qHi = 0, hex.gridWidth - 1 end
    local function cellAllowed(q, r)
        if reviveRange then
            if hex:getDistance(q, r, reviveRange.q, reviveRange.r) > 2 then return false end
        end
        return true
    end

    local deployCells = {}
    for q = qLo, qHi do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) and cellAllowed(q, r) then
                local terrain = state.terrainMap and state.terrainMap[q] and state.terrainMap[q][r] or "grass"
                if terrain ~= "water" then
                    local occupied = false
                    for _, e in ipairs(state.entities) do
                        if e.q == q and e.r == r then
                            occupied = true
                            break
                        end
                        if e.cells then
                            for _, c in ipairs(e.cells) do
                                if c.q == q and c.r == r then
                                    occupied = true
                                    break
                                end
                            end
                        end
                    end
                    if not occupied then
                        local hasAlly = false
                        for _, ally in ipairs(placedAllies) do
                            if ally.q == q and ally.r == r then
                                hasAlly = true
                                break
                            end
                        end
                        if not hasAlly then
                            deployCells[q .. "," .. r] = true
                            local x, y = getDrawCoords(q, r)
                            local verts = hex:drawHexagon(x, y, hexRadius)
                            love.graphics.setColor(0.2, 0.8, 0.2, 0.3)
                            love.graphics.polygon("fill", verts)
                        end
                    end
                end
            end
        end
    end
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.2, 0.8, 0.2, 1)
    ui.drawSetOutline(hex, deployCells, 1.0)
    love.graphics.setLineWidth(1)

    -- Landing-damage threat area: tint every cell that the drop would hit.
    if pendingLand then
        local rad = pendingLand.radius
        love.graphics.setLineWidth(2)
        for q = 0, hex.gridWidth - 1 do
            for r = 0, hex.gridHeight - 1 do
                if hex:isActiveHex(q, r) and hex:getDistance(q, r, pendingLand.q, pendingLand.r) <= rad then
                    local x, y = getDrawCoords(q, r)
                    local verts = hex:drawHexagon(x, y, hexRadius)
                    love.graphics.setColor(0.9, 0.25, 0.2, 0.28)
                    love.graphics.polygon("fill", verts)
                end
            end
        end
        -- ring around the landing cell marks the centre of the blast
        local lx, ly = getDrawCoords(pendingLand.q, pendingLand.r)
        love.graphics.setColor(0.95, 0.4, 0.3, 0.9)
        love.graphics.polygon("line", hex:drawInsetHexagon(lx, ly, hexRadius, 0.82))
        love.graphics.setLineWidth(1)
    end

    if deploySelectedIdx and placedAllies[deploySelectedIdx] then
        local sel = placedAllies[deploySelectedIdx]
        local x, y = getDrawCoords(sel.q, sel.r)
        local verts = hex:drawInsetHexagon(x, y, hexRadius, 0.92)
        love.graphics.setColor(1, 1, 0, 0.3)
        love.graphics.polygon("fill", verts)
        love.graphics.setColor(1, 1, 0, 0.8)
        love.graphics.polygon("line", verts)
    end

    local panelX = 10
    local panelY = 80
    local panelW = 180
    local panelH = 30 + #unplacedAllies * 22 + 10

    love.graphics.setColor(0.1, 0.1, 0.2, 0.9)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6)
    love.graphics.setColor(0.6, 0.6, 0.6, 0.9)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("To Deploy:", panelX + 8, panelY + 6)

    for i, ally in ipairs(unplacedAllies) do
        local ty = panelY + 26 + (i - 1) * 22
        love.graphics.setColor(0.4, 0.9, 0.4, 1)
        love.graphics.print(ally.name, panelX + 12, ty)
    end

    local mx, my = love.mouse.getPosition()
    mx = mx / state.dpiScale
    my = my / state.dpiScale

    local infoY = panelY + panelH + 8
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.setFont(fonts.get(11))
    love.graphics.print("Click green cells to place", panelX + 8, infoY)
    love.graphics.print("Click placed unit to select", panelX + 8, infoY + 16)
    love.graphics.print("Click two units to swap", panelX + 8, infoY + 32)
    love.graphics.print("Click empty cell to move", panelX + 8, infoY + 48)
    love.graphics.print("Enter/Space to confirm", panelX + 8, infoY + 64)

    local canConfirm = #unplacedAllies == 0

    local btnX = panelX
    local btnY = infoY + 88
    local btnW = panelW
    local btnH = 30
    local hover = canConfirm and mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH

    if canConfirm then
        love.graphics.setColor(hover and 0.3 or 0.2, hover and 0.7 or 0.5, hover and 0.3 or 0.2, 0.9)
    else
        love.graphics.setColor(0.2, 0.2, 0.2, 0.6)
    end
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 4)
    if canConfirm then
        love.graphics.setColor(0.4, 0.9, 0.4, hover and 0.8 or 0.5)
    else
        love.graphics.setColor(0.4, 0.4, 0.4, 0.4)
    end
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 4)
    love.graphics.setColor(canConfirm and 1 or 0.5, 1, canConfirm and 1 or 0.5, canConfirm and 1 or 0.4)
    love.graphics.setFont(fonts.get(12))
    love.graphics.printf("Confirm Deployment" .. (canConfirm and "" or " (" .. #unplacedAllies .. " left)"), btnX, btnY + 6, btnW, "center")

    state.deployConfirmBtn = canConfirm and {x = btnX, y = btnY, w = btnW, h = btnH} or nil

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("DEPLOYMENT PHASE — Place your units", 10, 55)
end

return renderer
