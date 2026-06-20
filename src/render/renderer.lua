-- src/render/renderer.lua
-- Draws the hex grid, terrain, entities, overlays, effects and HUD.
-- All drawing happens in design-space (720x1280); the camera transform is applied
-- by main before calling renderer.draw.

local hexmath = require("src.core.hex")
local terrain = require("src.content.terrain")
local statuses = require("src.content.statuses")
local abilities = require("src.content.abilities")
local sprites = require("src.assets.sprites")
local terrainSprite = require("src.assets.sprites.terrain")
local effectsIcons = require("src.assets.sprites.effects")

local renderer = {}

local fontCache = {}
local function font(size)
    size = math.floor(size)
    if not fontCache[size] then fontCache[size] = love.graphics.newFont(size) end
    return fontCache[size]
end

local function hexCorners(g, q, r)
    local cx, cy = g:hexToPixel(q, r)
    return hexmath.corners(cx, cy, g.size), cx, cy
end

local function drawHexShape(g, q, r, mode, color)
    local pts, cx, cy = hexCorners(g, q, r)
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    local flat = {}
    for _, p in ipairs(pts) do table.insert(flat, p.x); table.insert(flat, p.y) end
    love.graphics.polygon(mode, flat)
end

-- ---- terrain ----
local function drawTerrain(g, q, r)
    local ter = g.terrain[q .. "," .. r] or "grass"
    local cx, cy = g:hexToPixel(q, r)
    local tex = terrainSprite.get(ter)
    local scale = g.size / terrainSprite.refSize
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(tex, cx - terrainSprite.CX * scale, cy - terrainSprite.CY * scale, 0, scale, scale)
    -- outline
    local pts = hexmath.corners(cx, cy, g.size)
    local flat = {}
    for _, p in ipairs(pts) do table.insert(flat, p.x); table.insert(flat, p.y) end
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.setLineWidth(1.5)
    love.graphics.polygon("line", flat)
    love.graphics.setLineWidth(1)
end

-- ---- hex statuses (fire/acid/decay + dig sites) ----
local function drawHexStatuses(g, q, r)
    local cx, cy = g:hexToPixel(q, r)
    local list = statuses.getAtHex(q, r)
    for _, s in ipairs(list) do
        local icon = effectsIcons.get(s.type)
        if icon then
            local sz = g.size * 0.5
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.draw(icon, cx - sz / 2, cy - sz / 2, 0, sz / effectsIcons.size, sz / effectsIcons.size)
        end
    end
    if statuses.hasDigSite(q, r) then
        local icon = effectsIcons.get("dig")
        local sz = g.size * 0.5
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.draw(icon, cx - sz / 2, cy - sz / 2, 0, sz / effectsIcons.size, sz / effectsIcons.size)
    end
end

-- ---- entities ----
local function drawEntity(game, e)
    local g = game.grid
    local dq, dr = game:entityDrawPos(e)
    local cx, cy = g:hexToPixel(dq, dr)
    local sprite = sprites.forEntity(e)
    local sw = sprite:getWidth() or 96
    local sh = sprite:getHeight() or 96
    local scale = (g.size * 1.5) / sw
    -- death fade
    local alpha = 1
    if e.isDying then
        local t = e.deathTimer / e.deathDuration
        alpha = math.max(0, 1 - t)
        scale = scale * (1 + t * 0.4)
    end
    -- selection ring
    if game.selectedActor == e and e:isAlive() then
        love.graphics.setColor(1, 0.95, 0.3, 0.9)
        love.graphics.setLineWidth(3)
        local pts = hexmath.corners(cx, cy, g.size * 0.92)
        local flat = {}
        for _, p in ipairs(pts) do table.insert(flat, p.x); table.insert(flat, p.y) end
        love.graphics.polygon("line", flat)
        love.graphics.setLineWidth(1)
    end
    -- ally/enemy ring
    if e:isCharacter() and e:isAlive() then
        love.graphics.setColor(e:isAlly() and { 0.3, 0.8, 0.4, 0.5 } or { 0.9, 0.3, 0.3, 0.5 })
        love.graphics.circle("fill", cx, cy + g.size * 0.55, g.size * 0.5)
    end
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(sprite, cx - sw * scale / 2, cy - sh * scale / 2 - g.size * 0.2, 0, scale, scale)

    if not e:isAlive() then return end

    -- HP pips
    local pipR = 3
    local pipGap = 8
    local totalW = (e.maxHealth - 1) * pipGap
    local px = cx - totalW / 2
    local py = cy + g.size * 0.7
    for i = 1, e.maxHealth do
        local filled = i <= e.health
        if e.healthCellSize and i <= e.healthCellSize then
            love.graphics.setColor(filled and { 0.2, 0.9, 0.3, 1 } or { 0.1, 0.3, 0.1, 1 })
        else
            love.graphics.setColor(filled and { 1, 0.3, 0.3, 1 } or { 0.2, 0.1, 0.1, 1 })
        end
        love.graphics.circle("fill", px + (i - 1) * pipGap, py, pipR)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.circle("line", px + (i - 1) * pipGap, py, pipR)
    end

    -- status icons
    if #e.statuses > 0 then
        local ix = cx - (#e.statuses * 14) / 2
        for i, s in ipairs(e.statuses) do
            local icon = effectsIcons.get(s.type)
            if icon then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(icon, ix + (i - 1) * 14, cy - g.size * 0.9, 0, 14 / effectsIcons.size, 14 / effectsIcons.size)
            end
        end
    end

    -- "acted" dim
    if e:isAlly() and e.hasActedThisTurn and e.hasMovedThisTurn then
        love.graphics.setColor(0, 0, 0, 0.35)
        local pts = hexmath.corners(cx, cy, g.size * 0.9)
        local flat = {}
        for _, p in ipairs(pts) do table.insert(flat, p.x); table.insert(flat, p.y) end
        love.graphics.polygon("fill", flat)
    end
end

-- ---- effects ----
local function drawEffect(game, ef)
    local g = game.grid
    local cx, cy = g:hexToPixel(ef.q, ef.r)
    local p = ef.t / ef.dur
    if ef.name == "hit" then
        love.graphics.setColor(1, 0.8, 0.2, 1 - p)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", cx, cy, g.size * 0.4 + p * g.size * 0.5)
        love.graphics.setLineWidth(1)
    elseif ef.name == "blast" then
        love.graphics.setColor(0.4, 0.8, 1, 1 - p)
        love.graphics.setLineWidth(4)
        love.graphics.circle("line", cx, cy, g.size * 0.3 + p * g.size * 0.8)
        love.graphics.setLineWidth(1)
    elseif ef.name == "shoot" or ef.name == "bolt" then
        local tq, tr = ef.data.toQ, ef.data.toR
        if tq then
            local tx, ty = g:hexToPixel(tq, tr)
            local col = (ef.name == "bolt") and { 0.7, 0.4, 1, 1 - p } or { 1, 0.9, 0.4, 1 - p }
            love.graphics.setColor(col[1], col[2], col[3], col[4])
            love.graphics.setLineWidth(ef.name == "bolt" and 4 or 2)
            local head = p
            local hx = cx + (tx - cx) * math.min(1, p * 1.5)
            local hy = cy + (ty - cy) * math.min(1, p * 1.5)
            love.graphics.line(cx, cy, hx, hy)
            love.graphics.setLineWidth(1)
        end
    elseif ef.name == "summon" then
        love.graphics.setColor(0.7, 0.5, 1, 1 - p)
        for i = 1, 6 do
            local a = i / 6 * math.pi * 2
            local d = g.size * 0.3 + p * g.size * 0.6
            love.graphics.circle("fill", cx + math.cos(a) * d, cy + math.sin(a) * d, 3 * (1 - p))
        end
    elseif ef.name == "empower" then
        love.graphics.setColor(1, 0.85, 0.2, 1 - p)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", cx, cy, g.size * 0.5 * (0.6 + p * 0.6))
        love.graphics.setLineWidth(1)
    elseif ef.name == "heal" then
        love.graphics.setColor(0.3, 1, 0.4, 1 - p)
        love.graphics.setLineWidth(4)
        local s = g.size * 0.3
        love.graphics.line(cx - s, cy, cx + s, cy)
        love.graphics.line(cx, cy - s, cx, cy + s)
        love.graphics.setLineWidth(1)
    end
end

-- ---- main draw ----
function renderer.draw(game)
    local g = game.grid
    if not g then return end

    -- background
    love.graphics.setColor(0.06, 0.07, 0.11, 1)
    love.graphics.rectangle("fill", 0, 0, 720, 1280)

    -- terrain
    for _, c in ipairs(g.activeList) do
        drawTerrain(g, c.q, c.r)
    end

    -- hex statuses
    for _, c in ipairs(g.activeList) do
        drawHexStatuses(g, c.q, c.r)
    end

    -- move targets
    for k, _ in pairs(game.moveTargets) do
        local q, r = k:match("(-?%d+),(-?%d+)")
        drawHexShape(g, tonumber(q), tonumber(r), "fill", { 0.3, 0.7, 1, 0.28 })
    end
    -- attack targets
    for k, _ in pairs(game.attackTargets) do
        local q, r = k:match("(-?%d+),(-?%d+)")
        drawHexShape(g, tonumber(q), tonumber(r), "fill", { 1, 0.3, 0.3, 0.30 })
    end
    -- deploy zone
    if game.phase == "deploy" then
        for _, z in ipairs(game.deploy.zones) do
            drawHexShape(g, z.q, z.r, "fill", { 0.3, 0.8, 0.4, 0.22 })
        end
    end
    -- ability overlays
    if abilities.activeAbility then
        local ov = {}
        abilities.collectOverlays(game, ov)
        for k, _ in pairs(ov) do
            local q, r = k:match("(-?%d+),(-?%d+)")
            drawHexShape(g, tonumber(q), tonumber(r), "fill", { 0.3, 1, 0.8, 0.28 })
        end
    end

    -- hover
    if g.hoverQ and g:isActiveHex(g.hoverQ, g.hoverR) then
        drawHexShape(g, g.hoverQ, g.hoverR, "line", { 1, 1, 1, 0.5 })
    end

    -- entities sorted by r for depth
    local sorted = {}
    for _, e in ipairs(game.entities) do table.insert(sorted, e) end
    table.sort(sorted, function(a, b)
        local aq, ar = game:entityDrawPos(a)
        local bq, br = game:entityDrawPos(b)
        if ar == br then return aq < bq end
        return ar < br
    end)
    for _, e in ipairs(sorted) do
        if e:isAlive() or e.isDying then drawEntity(game, e) end
    end

    -- effects on top
    for _, ef in ipairs(game.effects) do drawEffect(game, ef) end
end

return renderer
