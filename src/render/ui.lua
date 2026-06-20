-- src/render/ui.lua
-- All in-game UI: HUD, bottom buttons, ability bar, deploy panel, progression
-- menu, game-over overlay, and the main menu. Design-space coordinates (720x1280).

local abilities = require("src.content.abilities")
local objectives = require("src.content.objectives")
local progression = require("src.content.progression")
local attacks = require("src.content.attacks")
local sprites = require("src.assets.sprites")

local ui = {}

local W, H = 720, 1280

local function font(size)
    return love.graphics.newFont(size)
end

local function hit(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function button(rect, label, opts)
    opts = opts or {}
    local mx, my = love.mouse.getPosition()
    -- mx/my are screen pixels; UI is drawn in design space, so compare in design space
    -- (caller passes design coords; for hover we approximate using current camera scale)
    local hover = opts.hover
    love.graphics.setColor(opts.bg or { 0.2, 0.22, 0.3, 0.95 })
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 6)
    love.graphics.setColor(opts.line or { 0.5, 0.6, 0.8, hover and 0.9 or 0.5 })
    love.graphics.setLineWidth(hover and 2 or 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 6)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(opts.fg or { 1, 1, 1, 1 })
    love.graphics.setFont(font(opts.fontSize or 14))
    love.graphics.printf(label, rect.x, rect.y + rect.h / 2 - 8, rect.w, "center")
end

-- ======================================================================
-- HUD
-- ======================================================================
function ui.drawHUD(game)
    -- objective text
    love.graphics.setFont(font(14))
    love.graphics.setColor(0.15, 0.17, 0.25, 0.8)
    love.graphics.rectangle("fill", 8, 8, 330, 30, 6)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.printf(objectives.describe(game.objective), 14, 14, 318, "left")

    -- turn counter
    love.graphics.setColor(0.15, 0.17, 0.25, 0.8)
    love.graphics.rectangle("fill", 350, 8, 130, 30, 6)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.printf("Turn " .. game.turn.count .. "/" .. game.maxTurns, 356, 14, 118, "center")

    -- chaos meter
    love.graphics.setColor(0.15, 0.17, 0.25, 0.8)
    love.graphics.rectangle("fill", 8, 44, 200, 22, 5)
    love.graphics.setColor(0.8, 0.2, 0.2, 1)
    local cw = (game.chaos / game.chaosMax) * 190
    love.graphics.rectangle("fill", 13, 49, cw, 12, 3)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(font(11))
    love.graphics.printf("Chaos " .. game.chaos .. "/" .. game.chaosMax, 14, 47, 190, "center")
end

-- ======================================================================
-- Bottom buttons & switch attack
-- ======================================================================
function ui.buttonRects()
    return {
        undo    = { x = 10,  y = 1218, w = 130, h = 52 },
        endTurn = { x = 270, y = 1218, w = 180, h = 52 },
        restart = { x = 580, y = 1218, w = 130, h = 52 },
        switch  = { x = 270, y = 1160, w = 180, h = 44 },
    }
end

function ui.drawBottom(game)
    local r = ui.buttonRects()
    button(r.undo, "Undo", { hover = game:canUndo() })
    button(r.endTurn, "End Turn", { hover = true, bg = { 0.2, 0.35, 0.25, 0.95 } })
    button(r.restart, "Restart", { hover = true, bg = { 0.35, 0.2, 0.2, 0.95 } })

    if game.selectedActor and #game.selectedActor.attackIds > 1 and not game.selectedActor.hasActedThisTurn then
        local aid = game.selectedActor:getCurrentAttackId()
        local def = attacks.get(aid)
        button(r.switch, "⚔ " .. (def and def.name or "Attack"), { hover = true, bg = { 0.3, 0.25, 0.15, 0.95 } })
    end

    -- current attack hint when in attack mode
    if game.attackMode and game.selectedActor then
        local def = attacks.get(game.selectedAttackId)
        if def then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", 200, 1120, 320, 36, 6)
            love.graphics.setColor(1, 0.9, 0.6, 1)
            love.graphics.setFont(font(13))
            love.graphics.printf(def.name .. ": " .. def.description, 206, 1126, 308, "center")
        end
    end
end

function ui.handleBottom(game, x, y)
    if game.turn.phase ~= "player" or game:anyBusy() then return false end
    local r = ui.buttonRects()
    if hit(r.undo, x, y) then game:undo(); return true end
    if hit(r.endTurn, x, y) then
        game:endTurn()
        if game.sounds and game.sounds.turn then game.sounds.turn:play() end
        return true
    end
    if hit(r.restart, x, y) then
        if game.onRestart then game.onRestart() end
        return true
    end
    if game.selectedActor and #game.selectedActor.attackIds > 1 and not game.selectedActor.hasActedThisTurn
       and hit(r.switch, x, y) then
        game:switchAttack()
        if not game.attackMode then game:selectAttack(game.selectedActor:getCurrentAttackId()) end
        return true
    end
    return false
end

-- ======================================================================
-- Ability bar (dropdown)
-- ======================================================================
local function abilityHeader()
    return { x = W - 170, y = 44, w = 160, h = 30 }
end

function ui.drawAbilities(game)
    local h = abilityHeader()
    abilities.dropdownOpen = abilities.dropdownOpen or false
    love.graphics.setColor(0.2, 0.22, 0.35, 0.95)
    love.graphics.rectangle("fill", h.x, h.y, h.w, h.h, 5)
    love.graphics.setColor(0.5, 0.6, 0.9, 0.8)
    love.graphics.rectangle("line", h.x, h.y, h.w, h.h, 5)
    love.graphics.setFont(font(12))
    love.graphics.setColor(1, 1, 1, 1)
    local icon = abilities.dropdownOpen and "v" or ">"
    love.graphics.printf("Spells " .. icon .. " [" .. abilities.mana .. "/" .. abilities.maxMana .. "]", h.x, h.y + 8, h.w, "center")

    -- mana pips
    love.graphics.setColor(0.4, 0.6, 1, 1)
    for i = 1, abilities.maxMana do
        if i <= abilities.mana then love.graphics.circle("fill", h.x + 8 + (i - 1) * 12, h.y + h.h + 12, 4)
        else love.graphics.setColor(0.2, 0.25, 0.4, 1); love.graphics.circle("line", h.x + 8 + (i - 1) * 12, h.y + h.h + 12, 4); love.graphics.setColor(0.4, 0.6, 1, 1) end
    end

    if not abilities.dropdownOpen then return end
    local order = abilities.displayOrder()
    for i, id in ipairs(order) do
        local def = abilities.get(id)
        local iy = h.y + h.h + 6 + (i - 1) * 34
        local rect = { x = h.x, y = iy, w = h.w, h = 30 }
        local active = (abilities.activeAbility == def)
        local can = (abilities.unlocked[id] and not abilities.usedThisTurn and abilities.mana >= def.manaCost and game.turn.phase == "player")
        love.graphics.setColor(active and { 0.3, 0.4, 0.6, 0.95 } or (can and { 0.18, 0.2, 0.28, 0.95 } or { 0.12, 0.12, 0.16, 0.95 }))
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.setFont(font(11))
        love.graphics.printf(def.name, rect.x + 6, rect.y + 4, rect.w - 30, "left")
        love.graphics.setColor(0.4, 0.6, 1, can and 1 or 0.4)
        love.graphics.print("[" .. def.manaCost .. "]", rect.x + rect.w - 24, rect.y + 4)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.7)
        love.graphics.setFont(font(9))
        love.graphics.printf(def.description, rect.x + 6, rect.y + 18, rect.w - 12, "left")
    end
end

function ui.handleAbilities(game, x, y)
    local h = abilityHeader()
    if hit(h, x, y) then
        abilities.dropdownOpen = not abilities.dropdownOpen
        return true
    end
    if not abilities.dropdownOpen then return false end
    local order = abilities.displayOrder()
    for i, id in ipairs(order) do
        local iy = h.y + h.h + 6 + (i - 1) * 34
        local rect = { x = h.x, y = iy, w = h.w, h = 30 }
        if hit(rect, x, y) then
            local def = abilities.get(id)
            if def then abilities.activate(def, game) end
            abilities.dropdownOpen = false
            return true
        end
    end
    return false
end

-- ======================================================================
-- Deploy panel
-- ======================================================================
function ui.drawDeploy(game)
    love.graphics.setColor(0.15, 0.17, 0.25, 0.9)
    love.graphics.rectangle("fill", W - 170, 90, 162, 600, 8)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font(13))
    love.graphics.printf("Deploy", W - 170, 98, 162, "center")
    for i, ally in ipairs(game.deploy.unplaced) do
        local y = 124 + (i - 1) * 70
        local sel = (game.deploy.selectedIdx == i)
        love.graphics.setColor(sel and { 0.3, 0.4, 0.7, 0.95 } or { 0.2, 0.22, 0.3, 0.9 })
        love.graphics.rectangle("fill", W - 164, y, 150, 60, 6)
        local sp = sprites.forEntity(ally)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sp, W - 160, y + 4, 0, 48 / (sp:getWidth() or 96), 48 / (sp:getHeight() or 96))
        love.graphics.setFont(font(12))
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(ally.name, W - 104, y + 10, 86, "left")
        love.graphics.setColor(0.7, 0.8, 1, 0.8)
        love.graphics.setFont(font(10))
        love.graphics.printf("HP " .. ally.maxHealth .. "  MV " .. ally.moveRange, W - 104, y + 30, 86, "left")
    end
    love.graphics.setColor(0.6, 0.7, 0.9, 0.9)
    love.graphics.setFont(font(11))
    love.graphics.printf("Tap a hex to place. Tap unit to select.", W - 168, 700, 160, "center")
end

function ui.handleDeployPanel(game, x, y)
    for i, _ in ipairs(game.deploy.unplaced) do
        local ry = 124 + (i - 1) * 70
        if x >= W - 164 and x <= W - 14 and y >= ry and y <= ry + 60 then
            game:selectDeployIdx(i)
            return true
        end
    end
    return false
end

-- ======================================================================
-- Game over overlay
-- ======================================================================
function ui.drawGameOver(game)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, W, H)
    local bw, bh = 420, 280
    local bx, by = (W - bw) / 2, (H - bh) / 2
    love.graphics.setColor(0.12, 0.14, 0.2, 0.97)
    love.graphics.rectangle("fill", bx, by, bw, bh, 12)
    love.graphics.setColor(game.win and { 0.3, 0.9, 0.4, 1 } or { 0.9, 0.3, 0.3, 1 })
    love.graphics.setFont(font(34))
    love.graphics.printf(game.win and "VICTORY" or "DEFEAT", bx, by + 30, bw, "center")
    love.graphics.setColor(0.8, 0.8, 0.85, 1)
    love.graphics.setFont(font(14))
    love.graphics.printf(objectives.describe(game.objective), bx + 20, by + 80, bw - 40, "center")

    local function gob(yy, label)
        return { x = (W - 240) / 2, y = by + yy, w = 240, h = 44 }
    end
    local r1 = gob(130, "Next")
    local r2 = gob(184, "Restart")
    if game.win and game.progressionRun and game.mapIndex < #game.mapList then
        button(r1, "Next Map", { hover = true, bg = { 0.2, 0.4, 0.25, 0.95 } })
    elseif game.win then
        button(r1, "Main Menu", { hover = true, bg = { 0.2, 0.4, 0.25, 0.95 } })
    else
        button(r1, "Main Menu", { hover = true, bg = { 0.35, 0.2, 0.2, 0.95 } })
    end
    button(r2, "Restart", { hover = true })
end

function ui.handleGameOver(game, x, y)
    local bh = 280
    local by = (H - bh) / 2
    local r1 = { x = (W - 240) / 2, y = by + 130, w = 240, h = 44 }
    local r2 = { x = (W - 240) / 2, y = by + 184, w = 240, h = 44 }
    if hit(r1, x, y) then
        if game.win and game.progressionRun and game.mapIndex < #game.mapList then
            if game.onNextMap then game.onNextMap() end
        else
            if game.onMenu then game.onMenu() end
        end
        return true
    end
    if hit(r2, x, y) then
        if game.onRestart then game.onRestart() end
        return true
    end
    return false
end

-- ======================================================================
-- Progression menu (after a map clear in a progression run)
-- ======================================================================
-- game.abilityMenu = { available = {}, mode = "pick", selectedItem = nil, selectedChoice = nil }

function ui.drawProgression(game)
    if not game.abilityMenu then return end
    local m = game.abilityMenu
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", 0, 0, W, H)
    local bw, bh = 460, 520
    local bx, by = (W - bw) / 2, (H - bh) / 2
    love.graphics.setColor(0.1, 0.12, 0.18, 0.98)
    love.graphics.rectangle("fill", bx, by, bw, bh, 12)
    love.graphics.setColor(1, 0.9, 0.4, 1)
    love.graphics.setFont(font(22))
    love.graphics.printf("Choose a Reward", bx, by + 20, bw, "center")

    local list = m.available
    if m.selectedItem and m.selectedItem.type == "unit" then
        -- stage 2: choices for the selected unit
        local choices = progression.upgrades[m.selectedItem.name] or {}
        love.graphics.setColor(0.8, 0.85, 1, 1)
        love.graphics.setFont(font(14))
        love.graphics.printf("Upgrade for " .. m.selectedItem.name, bx + 20, by + 60, bw - 40, "center")
        for i, ch in ipairs(choices) do
            local ry = by + 100 + (i - 1) * 70
            local sel = (m.selectedChoice == ch.id)
            love.graphics.setColor(sel and { 0.3, 0.4, 0.6, 0.95 } or { 0.18, 0.2, 0.28, 0.9 })
            love.graphics.rectangle("fill", bx + 20, ry, bw - 40, 60, 8)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(font(15))
            love.graphics.printf(ch.name, bx + 30, ry + 8, bw - 60, "left")
            love.graphics.setColor(0.7, 0.75, 0.8, 0.9)
            love.graphics.setFont(font(11))
            love.graphics.printf(ch.desc, bx + 30, ry + 32, bw - 60, "left")
        end
        local back = { x = bx + 20, y = by + 100 + #choices * 70 + 8, w = 100, h = 34 }
        button(back, "Back", { hover = true })
        if m.selectedChoice then
            local conf = { x = (W - 220) / 2, y = by + bh - 60, w = 220, h = 44 }
            button(conf, "Confirm", { hover = true, bg = { 0.2, 0.4, 0.25, 0.95 } })
        end
    else
        -- stage 1: list units (without upgrades) + artifacts
        for i, entry in ipairs(list) do
            local ry = by + 70 + (i - 1) * 64
            local sel = (m.selectedItem == entry) or (entry.type == "artifact" and m.selectedChoice == entry.id)
            love.graphics.setColor(sel and { 0.3, 0.4, 0.6, 0.95 } or { 0.18, 0.2, 0.28, 0.9 })
            love.graphics.rectangle("fill", bx + 20, ry, bw - 40, 56, 8)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(font(15))
            love.graphics.printf(entry.name, bx + 30, ry + 8, bw - 60, "left")
            love.graphics.setColor(0.7, 0.75, 0.8, 0.9)
            love.graphics.setFont(font(11))
            love.graphics.printf(entry.desc or ("Upgrade the " .. entry.name), bx + 30, ry + 30, bw - 60, "left")
        end
        if m.selectedChoice or m.selectedItem then
            local conf = { x = (W - 220) / 2, y = by + bh - 60, w = 220, h = 44 }
            button(conf, "Confirm", { hover = true, bg = { 0.2, 0.4, 0.25, 0.95 } })
        end
    end
end

function ui.handleProgression(game, x, y)
    if not game.abilityMenu then return false end
    local m = game.abilityMenu
    local bw, bh = 460, 520
    local bx, by = (W - bw) / 2, (H - bh) / 2

    if m.selectedItem and m.selectedItem.type == "unit" then
        local choices = progression.upgrades[m.selectedItem.name] or {}
        for i, ch in ipairs(choices) do
            local ry = by + 100 + (i - 1) * 70
            if x >= bx + 20 and x <= bx + bw - 20 and y >= ry and y <= ry + 60 then
                m.selectedChoice = ch.id
                return true
            end
        end
        local back = { x = bx + 20, y = by + 100 + #choices * 70 + 8, w = 100, h = 34 }
        if hit(back, x, y) then
            m.selectedItem = nil; m.selectedChoice = nil
            return true
        end
    else
        for i, entry in ipairs(m.available) do
            local ry = by + 70 + (i - 1) * 64
            if x >= bx + 20 and x <= bx + bw - 20 and y >= ry and y <= ry + 56 then
                m.selectedItem = entry
                if entry.type == "artifact" then m.selectedChoice = entry.id end
                return true
            end
        end
    end

    local conf = { x = (W - 220) / 2, y = by + bh - 60, w = 220, h = 44 }
    if hit(conf, x, y) and (m.selectedChoice or m.selectedItem) then
        if m.selectedItem and m.selectedItem.type == "unit" and m.selectedChoice then
            progression.addUpgrade(m.selectedItem.name, m.selectedChoice)
        elseif m.selectedItem and m.selectedItem.type == "artifact" then
            progression.addArtifact(m.selectedItem.id)
        end
        game.abilityMenu = nil
        if game.onProgressionConfirmed then game.onProgressionConfirmed() end
        return true
    end
    return false
end

-- ======================================================================
-- Main menu
-- ======================================================================
function ui.drawMenu(game)
    love.graphics.setColor(0.07, 0.08, 0.13, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setColor(0.4, 0.6, 0.9, 1)
    love.graphics.setFont(font(40))
    love.graphics.printf("HEX TACTICS", 0, 80, W, "center")
    love.graphics.setColor(0.6, 0.65, 0.75, 1)
    love.graphics.setFont(font(14))
    love.graphics.printf("a hex tactics roguelite", 0, 130, W, "center")

    love.graphics.setFont(font(18))
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Select Map", 0, 180, W, "center")
    local bw, bh = 320, 54
    local bx = (W - bw) / 2
    for i, path in ipairs(game.mapList) do
        local by = 220 + (i - 1) * (bh + 10)
        local name = path:match("([^/\\]+)%.lua$") or path
        button({ x = bx, y = by, w = bw, h = bh }, name, { hover = true, bg = { 0.15, 0.25, 0.4, 0.95 } })
    end

    local sStart = 220 + #game.mapList * (bh + 10) + 60
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font(18))
    love.graphics.printf("Select Squad", 0, sStart - 40, W, "center")
    local sbw, sbh = 320, 50
    local sbx = (W - sbw) / 2
    for i, sq in ipairs(game.squads) do
        local sby = sStart + (i - 1) * (sbh + 8)
        local sel = (game.selectedSquad == i)
        button({ x = sbx, y = sby, w = sbw, h = sbh }, sq.name, { hover = true,
            bg = sel and { 0.25, 0.3, 0.55, 0.95 } or { 0.15, 0.17, 0.25, 0.95 } })
        love.graphics.setColor(0.7, 0.75, 0.85, 0.8)
        love.graphics.setFont(font(11))
        local names = {}
        for _, u in ipairs(sq.units) do table.insert(names, u) end
        love.graphics.printf(table.concat(names, ", "), sbx + 12, sby + 30, sbw - 24, "left")
    end

    local pStart = sStart + #game.squads * (sbh + 8) + 30
    button({ x = bx, y = pStart, w = bw, h = bh }, "Progression Run", { hover = true, bg = { 0.2, 0.4, 0.25, 0.95 } })
    love.graphics.setColor(0.5, 0.55, 0.65, 0.9)
    love.graphics.setFont(font(11))
    love.graphics.printf("Tap a map to start  |  hold R to restart in-game", 0, pStart + bh + 14, W, "center")
end

function ui.handleMenu(game, x, y)
    local bw, bh = 320, 54
    local bx = (W - bw) / 2
    for i, path in ipairs(game.mapList) do
        local by = 220 + (i - 1) * (bh + 10)
        if x >= bx and x <= bx + bw and y >= by and y <= by + bh then
            if not game.selectedSquad then game.selectedSquad = 1 end
            game.progressionRun = false
            progression.reset()
            abilities.resetUnlocks()
            if game.onStartMap then game.onStartMap(path) end
            return true
        end
    end
    local sStart = 220 + #game.mapList * (bh + 10) + 60
    local sbw, sbh = 320, 50
    local sbx = (W - sbw) / 2
    for i in ipairs(game.squads) do
        local sby = sStart + (i - 1) * (sbh + 8)
        if x >= sbx and x <= sbx + sbw and y >= sby and y <= sby + sbh then
            game.selectedSquad = i
            return true
        end
    end
    local pStart = sStart + #game.squads * (sbh + 8) + 30
    if x >= bx and x <= bx + bw and y >= pStart and y <= pStart + bh then
        if not game.selectedSquad then game.selectedSquad = 1 end
        game.progressionRun = true
        progression.reset()
        abilities.resetUnlocks()
        game.mapIndex = 1
        if game.onStartMap then game.onStartMap(game.mapList[1]) end
        return true
    end
    return false
end

-- ======================================================================
-- Master draw
-- ======================================================================
function ui.draw(game)
    if game.phase == "menu" then
        ui.drawMenu(game)
        return
    end
    if game.phase == "deploy" then
        ui.drawDeploy(game)
        ui.drawHUD(game)
        return
    end
    if game.phase == "playing" then
        ui.drawHUD(game)
        ui.drawAbilities(game)
        ui.drawBottom(game)
        return
    end
    if game.phase == "gameover" then
        ui.drawHUD(game)
        ui.drawGameOver(game)
        ui.drawProgression(game)
        return
    end
end

-- Master press handler (returns true if UI consumed the press)
function ui.handlePress(game, x, y)
    if game.phase == "menu" then return ui.handleMenu(game, x, y) end
    if game.phase == "gameover" then
        if game.abilityMenu and ui.handleProgression(game, x, y) then return true end
        return ui.handleGameOver(game, x, y)
    end
    if game.phase == "deploy" then
        if ui.handleDeployPanel(game, x, y) then return true end
        return false
    end
    if game.phase == "playing" then
        if game.abilityMenu and ui.handleProgression(game, x, y) then return true end
        if ui.handleAbilities(game, x, y) then return true end
        if ui.handleBottom(game, x, y) then return true end
        return false
    end
    return false
end

return ui
