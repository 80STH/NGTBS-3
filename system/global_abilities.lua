-- global_abilities.lua
-- Modular system of one-time abilities.
-- Each ability is an independent object with its own hasBeenUsed, button.
-- All abilities are available simultaneously (not mutually exclusive in terms of usage,
-- but only one can be in target selection mode).

local ui = require("ui.ui")
local attack_preview = require("ui.attack_preview")
local combat = require("combat.combat")
local hex_utils = require("grid.hex_utils")
local status = require("system.status")
local environment = require("entity.environment")
local visual = require("system.visual_effects")
local log = require("util.log")
local undo = require("system.undo")
local fonts = require("util.fonts")

local global_abilities = {}

global_abilities.registry = {}
global_abilities.activeAbility = nil
global_abilities.dropdownOpen = false
global_abilities.mana = 3
global_abilities.maxMana = 3
global_abilities.abilityUsedThisTurn = false
global_abilities.scrollOffset = 0
global_abilities.maxVisibleItems = 6

global_abilities.abilityOrder = {"Heal", "Extra Move", "Wind Torrent", "Unearth", "Mind Control", "Accelerate Decay", "Force Attack", "Rage", "The Big One", "Air Strike", "Stasis Overload", "Chain Lightning", "Invulnerability"}

global_abilities.unlocked = {}

function global_abilities.setUnlocked(name)
    if name then global_abilities.unlocked[name] = true end
end

function global_abilities.unlockAll(names)
    for _, name in ipairs(names) do
        global_abilities.unlocked[name] = true
    end
end

function global_abilities.resetUnlocks()
    global_abilities.unlocked = {}
end

function global_abilities.initWithCommander(commanderName)
    local commanders = require("system.commanders")
    local cmd = commanders.get(commanderName)
    if not cmd then
        global_abilities.unlocked = { Heal = true }
        global_abilities.mana = 3
        global_abilities.maxMana = 3
        return
    end
    global_abilities.unlocked = {}
    for _, ab in ipairs(cmd.startAbilities) do
        global_abilities.unlocked[ab] = true
    end
    global_abilities.mana = cmd.startMana
    global_abilities.maxMana = cmd.startMaxMana
end

function global_abilities.getDisplayOrder(state)
    local result = {}
    local unlimited = state and state.unlimitedAbilities
    for _, name in ipairs(global_abilities.abilityOrder) do
        if unlimited or global_abilities.unlocked[name] then
            table.insert(result, name)
        end
    end
    return result
end

local function getDropdownHeader()
    local w = 145
    local x = logicalW - w - 10
    return { x = x, y = logicalH - 310, w = w, h = 26 }
end

function global_abilities.register(obj)
    global_abilities.registry[obj.name] = obj
end

function global_abilities.spendAbility(ab)
    if not _G.unlimitedAbilities then
        global_abilities.mana = global_abilities.mana - ab.manaCost
        global_abilities.abilityUsedThisTurn = true
    end
    ab.hasBeenUsed = true
    local abilitySounds = {
        ["Heal"] = "heal_ability",
        ["Extra Move"] = "extra_move",
        ["Wind Torrent"] = "wind_torrent",
        ["Unearth"] = "unearth",
        ["Mind Control"] = "mind_control",
        ["Accelerate Decay"] = "accelerate_decay",
    }
    local soundName = abilitySounds[ab.name]
    if soundName then sounds.play(soundName) end
end

function global_abilities.reset()
    global_abilities.activeAbility = nil
    global_abilities.mana = global_abilities.maxMana
    global_abilities.abilityUsedThisTurn = false
    for _, ab in pairs(global_abilities.registry) do
        if ab.reset then ab:reset() end
        ab.hasBeenUsed = false
    end
end

local itemH = 28

local function getAbilityItemRect(index)
    local h = getDropdownHeader()
    local itemY = h.y + h.h + (index - global_abilities.scrollOffset - 1) * itemH
    return h.x, itemY, h.w, itemH
end

function global_abilities.handleButtonClick(x, y, state)
    local h = getDropdownHeader()
    if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then
        global_abilities.dropdownOpen = not global_abilities.dropdownOpen
        if global_abilities.dropdownOpen then
            global_abilities.scrollOffset = 0
        end
        return true
    end
    if not global_abilities.dropdownOpen then return false end
    local displayOrder = global_abilities.getDisplayOrder(state)
    local scrollStart = global_abilities.scrollOffset + 1
    local scrollEnd = math.min(#displayOrder, global_abilities.scrollOffset + global_abilities.maxVisibleItems)
    for i = scrollStart, scrollEnd do
        local name = displayOrder[i]
        local ab = global_abilities.registry[name]
        if ab then
            local ix, iy, iw, ih = getAbilityItemRect(i)
            if x >= ix and x <= ix + iw and y >= iy and y <= iy + ih then
            if state.turnState.phase == "player" and not (state.selectedActor and state.selectedActor.isMoving) then
                    local unlimited = state.unlimitedAbilities
                    if not unlimited and ab.hasBeenUsed then
                        log.infof("abilities", "%s has already been used this game!", ab.name)
                        return true
                    end
                    if not unlimited and global_abilities.abilityUsedThisTurn then
                        log.info("abilities", "Already used an ability this turn!")
                        return true
                    end
                    if not unlimited and global_abilities.mana < ab.manaCost then
                        log.infof("abilities", "%s costs %s mana, only %s left!", ab.name, ab.manaCost, global_abilities.mana)
                        return true
                    end
                    if global_abilities.activeAbility then
                        global_abilities.activeAbility:onDeactivate(state)
                    end
                    global_abilities.activeAbility = ab
                    ab:onActivate(state)
                    global_abilities.dropdownOpen = false
                elseif not state.unlimitedAbilities and ab.hasBeenUsed then
                    log.infof("abilities", "%s has already been used this game!", ab.name)
                elseif state.turnState.phase ~= "player" then
                    log.info("abilities", "Can only use abilities during your turn!")
                end
                return true
            end
        end
    end
    return false
end

function global_abilities.handleWheelMoved(x, y, scrollY, state)
    if not global_abilities.dropdownOpen then return false end
    local h = getDropdownHeader()
    local itemAreaY = h.y + h.h
    local itemAreaH = global_abilities.maxVisibleItems * itemH
    if x >= h.x and x <= h.x + h.w and y >= itemAreaY and y <= itemAreaY + itemAreaH then
        local displayOrder = global_abilities.getDisplayOrder(state)
        local maxScroll = math.max(0, #displayOrder - global_abilities.maxVisibleItems)
        if scrollY > 0 then
            global_abilities.scrollOffset = math.max(0, global_abilities.scrollOffset - 1)
            return true
        elseif scrollY < 0 then
            global_abilities.scrollOffset = math.min(maxScroll, global_abilities.scrollOffset + 1)
            return true
        end
    end
    return false
end

function global_abilities.handleClick(x, y, state)
    local ab = global_abilities.activeAbility
    if not ab then return false end
    local hex = state.hex
    local tq, tr = hex:pixelToHex(x, y)
    if hex:isActiveHex(tq, tr) then
        return ab:onClickHex(tq, tr, hex, state)
    else
        ab:onDeactivate(state)
        global_abilities.activeAbility = nil
        log.infof("abilities", "%s cancelled", ab.name)
        return true
    end
end

function global_abilities.collectOverlays(hex, cellOverlays, state)
    local ab = global_abilities.activeAbility
    if ab and ab.collectOverlays then
        ab:collectOverlays(hex, cellOverlays, state)
    end
end

function global_abilities.drawPreview(hex, state)
    local ab = global_abilities.activeAbility
    if ab and ab.drawPreview then
        ab:drawPreview(hex, state)
    end
end

function global_abilities.drawButtons(mx, my, state)
    local h = getDropdownHeader()
    local buttonFont = fonts.get(11)

    -- Header
    local isHover = mx and my and mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h
    love.graphics.setColor(0.25, 0.25, 0.35, 0.95)
    love.graphics.rectangle("fill", h.x, h.y, h.w, h.h, 4)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.rectangle("line", h.x, h.y, h.w, h.h, 4)
    local oldFont = love.graphics.getFont()
    love.graphics.setFont(buttonFont)
    love.graphics.setColor(1, 1, 1, 1)
    local icon = global_abilities.dropdownOpen and "▼" or "▶"
    love.graphics.printf("Abilities " .. icon .. " [" .. global_abilities.mana .. "/" .. global_abilities.maxMana .. "]", h.x, h.y + 7, h.w, "center")
    love.graphics.setFont(oldFont)

    if not global_abilities.dropdownOpen then return end

    -- Items visible area clip
    local displayOrder = global_abilities.getDisplayOrder(state)
    local itemAreaY = h.y + h.h
    local itemAreaH = global_abilities.maxVisibleItems * itemH
    love.graphics.setScissor(h.x, itemAreaY, h.w, itemAreaH)

    local scrollStart = global_abilities.scrollOffset + 1
    local scrollEnd = math.min(#displayOrder, global_abilities.scrollOffset + global_abilities.maxVisibleItems)
    for i = scrollStart, scrollEnd do
        local name = displayOrder[i]
        local ab = global_abilities.registry[name]
        if ab then
            local ix, iy, iw, ih = getAbilityItemRect(i)
            ab.button.x = ix + 2
            ab.button.y = iy + 2
            ab.button.width = iw - 4
            ab.button.height = ih - 4
            ab:drawButton(mx, my, state)
        end
    end

    -- Scroll indicators
    if global_abilities.scrollOffset > 0 then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("▲", h.x + h.w - 16, itemAreaY + 2)
    end
    if #displayOrder > global_abilities.scrollOffset + global_abilities.maxVisibleItems then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("▼", h.x + h.w - 16, itemAreaY + itemAreaH - 18)
    end

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end



function global_abilities.drawAbilityButton(self, mx, my, state, cfg)
    local isActive = (global_abilities.activeAbility == self)
    local enoughMana = global_abilities.mana >= self.manaCost
    local unlimited = state.unlimitedAbilities
    local available = (state.turnState.phase == "player" and (unlimited or (not self.hasBeenUsed and not global_abilities.abilityUsedThisTurn and enoughMana)))
    local x, y, w, h = self.button.x, self.button.y, self.button.width, self.button.height
    local buttonFont = fonts.get(11)
    local logicalW = love.graphics.getWidth()

    local cr, cg, cb = cfg.color[1], cfg.color[2], cfg.color[3]
    love.graphics.setColor(available and cr or 0.5, available and cg or 0.5, available and cb or 0.5, isActive and 0.5 or 0.8)
    love.graphics.rectangle("fill", x, y, w, h, 5)
    love.graphics.setColor(1, 1, 1, 1)
    local old = love.graphics.getFont()
    love.graphics.setFont(buttonFont)
    local label = (isActive and cfg.activeLabel or cfg.label)
    love.graphics.printf(label, x + 4, y + 9, w - 28, "left")
    -- Mana cost badge
    love.graphics.setColor(1, 1, 1, enoughMana and 1 or 0.4)
    love.graphics.print("[" .. self.manaCost .. "]", x + w - 26, y + 9)
    love.graphics.setFont(old)

    local isHover = mx and my and mx >= x and mx <= x + w and my >= y and my <= y + h
    if isHover then
        local usedText = self.hasBeenUsed and " (used)" or ""
        local manaText = " Cost: " .. self.manaCost .. " mana"
        local tooltipW = 260
        local tx, ty = x + w + 6, y
        if tx + tooltipW > logicalW - 10 then tx = x - tooltipW - 6 end
        if ty + cfg.tooltipH > logicalH - 10 then ty = logicalH - cfg.tooltipH - 10 end
        love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
        love.graphics.rectangle("fill", tx, ty, tooltipW, cfg.tooltipH, 6)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.rectangle("line", tx, ty, tooltipW, cfg.tooltipH, 6)
        love.graphics.setColor(1, 1, 0.6, 1)
        love.graphics.print(cfg.tooltipTitle .. usedText .. manaText, tx + 8, ty + 6)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        for i, line in ipairs(cfg.tooltipLines) do
            love.graphics.print(line, tx + 8, ty + 20 + (i - 1) * 16)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- ============================================================
-- UNEARTH: all dig sites trigger immediately
-- ============================================================
local UnearthAbility = {}
UnearthAbility.__index = UnearthAbility

function UnearthAbility.new()
    local self = {
        name = "Unearth",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, UnearthAbility)
end

function UnearthAbility:reset()
    self.hasBeenUsed = false
end

function UnearthAbility:onActivate(state)
    local digSites = status.getAllDigSites()
    if #digSites == 0 then
        log.info("abilities", "Unearth: No dig sites to unearth!")
        global_abilities.activeAbility = nil
        return
    end
    local spawned = 0
    for _, site in ipairs(digSites) do
        local occupied = false
        for _, e in ipairs(state.entities) do
            if e.q == site.q and e.r == site.r then
                occupied = true
                break
            end
        end
        if not occupied then
            local terrain = state.terrainMap and state.terrainMap[site.q] and state.terrainMap[site.q][site.r] or "grass"
            if terrain ~= "water" and terrain ~= "underwater_mines" and terrain ~= "railway" and not status.hasNegativeHexStatus(site.q, site.r) then
                local newEnemy = environment.createRandomEnemy(site.q, site.r)
                table.insert(state.entities, newEnemy)
                spawned = spawned + 1
            end
        end
        status.removeDigSite(site.q, site.r)
    end
    global_abilities.spendAbility(self)
    undo.snapshot()
    sounds.play("unearth")
    global_abilities.activeAbility = nil
    log.infof("abilities", "Unearth: %d enemies emerged!", spawned)
    if _G.checkGameEnd then _G.checkGameEnd() end
end

function UnearthAbility:onDeactivate(state)
end

function UnearthAbility:onClickHex(q, r, hex, state)
    return false
end

function UnearthAbility:hasDigSites(state)
    return #status.getAllDigSites() > 0
end

function UnearthAbility:drawButton(mx, my, state)
    local hasSites = self:hasDigSites(state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = hasSites and {0.7, 0.5, 0.2} or {0.4, 0.4, 0.4},
        label = "Unearth",
        activeLabel = "Unearth",
        tooltipH = 64,
        tooltipTitle = "Unearth",
        tooltipLines = hasSites and {
            "All enemies in dig sites",
            "immediately emerge.",
        } or {
            "No dig sites on the map.",
        },
    })
end

-- ============================================================
-- MIND CONTROL: move an enemy 1 cell
-- ============================================================
local MindControlAbility = {}
MindControlAbility.__index = MindControlAbility

function MindControlAbility.new()
    local self = {
        name = "Mind Control",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        target = nil,
    }
    return setmetatable(self, MindControlAbility)
end

function MindControlAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.target = nil
end

function MindControlAbility:onActivate(state)
    self.phase = "select_enemy"
    self.target = nil
    log.info("abilities", "Click on an enemy to mind control, or press ESC to cancel")
end

function MindControlAbility:onDeactivate(state)
    self.phase = nil
    self.target = nil
    restoreSelectedActor()
        log.infof("abilities", "%s cancelled", self.name)
end

function MindControlAbility:onClickHex(q, r, hex, state)
    if self.phase == "select_enemy" then
        local target = nil
        for _, e in ipairs(state.entities) do
            if e.q == q and e.r == r and e.health > 0 and e:isCharacter() and not e.isPlayable then
                target = e
                break
            end
        end
        if not target then
            log.warn("abilities", "No valid enemy at this cell!")
            return true
        end
        self.target = target
        self.phase = "select_dest"
        log.infof("abilities", "Now click on an adjacent empty cell to move %s to", tostring(target.name))
        return true
    end

    if self.phase == "select_dest" then
        if not self.target then
            self:onDeactivate(state)
            return true
        end
        if q == self.target.q and r == self.target.r then
            log.info("abilities", "Target is already at this cell!")
            return true
        end
        local dist = hex:getDistance(self.target.q, self.target.r, q, r)
        if dist ~= 1 then
            log.warn("abilities", "Destination must be adjacent!")
            return true
        end
        if not hex:isActiveHex(q, r) then
            log.warn("abilities", "Invalid destination!")
            return true
        end
        local occupied = false
        for _, e in ipairs(state.entities) do
            if e.q == q and e.r == r and e.health > 0 then
                occupied = true
                break
            end
        end
        if occupied then
            log.warn("abilities", "Destination is occupied!")
            return true
        end
        self.target.q = q
        self.target.r = r
        global_abilities.spendAbility(self)
        undo.snapshot()
        log.infof("abilities", "%s moved by mind control!", tostring(self.target.name))
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        self.phase = nil
        self.target = nil
        return true
    end

    return false
end

function MindControlAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.8, 0.3, 0.8},
        label = "Mind Control",
        activeLabel = self.phase == "select_dest" and "Choose destination" or "Select enemy",
        tooltipH = 96,
        tooltipTitle = "Mind Control",
        tooltipLines = {
            "Move an enemy 1 cell.",
            "The enemy retains its",
            "prepared attack direction.",
        },
    })
end

-- ============================================================
-- ACCELERATE DECAY: reduces max turns until decay by 1
-- ============================================================
local AccelerateDecayAbility = {}
AccelerateDecayAbility.__index = AccelerateDecayAbility

function AccelerateDecayAbility.new()
    local self = {
        name = "Accelerate Decay",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, AccelerateDecayAbility)
end

function AccelerateDecayAbility:reset()
    self.hasBeenUsed = false
end

function AccelerateDecayAbility:onActivate(state)
    if state.maxTurns then
        state.maxTurns = math.max(state.turnCount + 1, state.maxTurns - 1)
        maxTurns = state.maxTurns
        log.infof("abilities", "Decay accelerated! Max turns reduced to %s", state.maxTurns)
    end
    global_abilities.spendAbility(self)
    undo.snapshot()
    global_abilities.activeAbility = nil
end

function AccelerateDecayAbility:onDeactivate(state)
end

function AccelerateDecayAbility:onClickHex(q, r, hex, state)
    return false
end

function AccelerateDecayAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.8, 0.2, 0.2},
        label = "Accel. Decay",
        activeLabel = "Accel. Decay",
        tooltipH = 80,
        tooltipTitle = "Accelerate Decay",
        tooltipLines = {
            "Reduce the number of turns",
            "until Decay activates by 1.",
        },
    })
end

-- ============================================================
-- HEAL
-- ============================================================
local HealAbility = {}
HealAbility.__index = HealAbility

function HealAbility.new()
    local self = {
        name = "Heal",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, HealAbility)
end

function HealAbility:reset()
    self.hasBeenUsed = false
end

function HealAbility:onActivate(state)
    log.info("abilities", "Click on an ally to heal, or press ESC to cancel")
end

function HealAbility:onDeactivate(state)
    restoreSelectedActor()
        log.infof("abilities", "%s cancelled", self.name)
end

function HealAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r then
            target = e
            break
        end
    end

    if not target or target:isBuilding() then
        log.warn("abilities", "No valid target!")
        return true
    end
    if target.health <= 0 and not status.hasEntityStatus(target, "stasis") then
        log.warn("abilities", "Cannot heal dead units!")
        return true
    end

    local hasDebuffs = #status.getEntityStatuses(target) > 0 or status.hasDigSite(target.q, target.r)
    if target.health >= target.maxHealth and not hasDebuffs then
        log.infof("abilities", "%s is at full health with no debuffs to cure!", tostring(target.name))
        return true
    end

    local wasStasis = status.hasEntityStatus(target, "stasis")
    target.health = target.maxHealth
    status.entityStatuses[target] = nil
    if wasStasis then
        log.infof("abilities", "%s revived from stasis!", tostring(target.name))
    end
    if status.hasAtHex(target.q, target.r, "fire") then
        status.removeFromHex(target.q, target.r, "fire")
        log.info("abilities", "Fire on the ground extinguished!")
    end
    global_abilities.spendAbility(self)
    undo.snapshot()
    log.infof("abilities", "%s fully healed and all negative effects removed!", tostring(target.name))
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function HealAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.8, 0.3},
        label = "Heal",
        activeLabel = "Select target",
        tooltipH = 64,
        tooltipTitle = "Heal",
        tooltipLines = {
            "Fully restore HP and remove all",
            "debuffs for one allied unit.",
        },
    })
end

-- ============================================================
-- EXTRA MOVE
-- ============================================================
local ExtraMoveAbility = {}
ExtraMoveAbility.__index = ExtraMoveAbility

function ExtraMoveAbility.new()
    local self = {
        name = "Extra Move",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        target = nil,
    }
    return setmetatable(self, ExtraMoveAbility)
end

function ExtraMoveAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.target = nil
end

function ExtraMoveAbility:onActivate(state)
    self.phase = "select_ally"
    self.target = nil
    log.info("abilities", "Click on an ally to cleanse and shift, or press ESC to cancel")
end

function ExtraMoveAbility:onDeactivate(state)
    self.phase = nil
    self.target = nil
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function ExtraMoveAbility:onClickHex(q, r, hex, state)
    if self.phase == "select_ally" then
        local target = nil
        for _, e in ipairs(state.entities) do
            if e.q == q and e.r == r then
                target = e
                break
            end
        end
        if not target or not target.isPlayable then
            log.warn("abilities", "No valid ally at this cell!")
            return true
        end
        if target.health <= 0 and not status.hasEntityStatus(target, "stasis") then
            log.warn("abilities", "Cannot target dead units!")
            return true
        end
        self.target = target
        self.phase = "select_dest"
        log.infof("abilities", "Now click on an adjacent empty cell to shift %s to", tostring(target.name))
        return true
    end

    if self.phase == "select_dest" then
        if not self.target then
            self:onDeactivate(state)
            return true
        end
        if q == self.target.q and r == self.target.r then
            log.info("abilities", "Target is already at this cell!")
            return true
        end
        local dist = hex:getDistance(self.target.q, self.target.r, q, r)
        if dist ~= 1 then
            log.warn("abilities", "Destination must be adjacent!")
            return true
        end
        if not hex:isActiveHex(q, r) then
            log.warn("abilities", "Invalid destination!")
            return true
        end
        -- Check terrain
        local terrain = state.terrainMap and state.terrainMap[q] and state.terrainMap[q][r] or "grass"
        if terrain == "water" and not (self.target.waterWalker or self.target.flying or self.target.hovering) then
            log.warn("abilities", "Cannot shift into water!")
            return true
        end
        if terrain == "underwater_mines" then
            log.warn("abilities", "Cannot shift into underwater mines!")
            return true
        end
        -- Check occupancy
        for _, e in ipairs(state.entities) do
            if e.q == q and e.r == r and e.health > 0 then
                log.warn("abilities", "Destination is occupied!")
                return true
            end
        end

        -- Remove all negative statuses
        local wasStasis = status.hasEntityStatus(self.target, "stasis")
        local statuses = status.getEntityStatuses(self.target)
        for _, st in ipairs(statuses) do
            if st ~= "empowered" then
                status.removeFromEntity(self.target, st)
            end
        end
        if wasStasis then
            self.target.health = 1
            log.infof("abilities", "%s revived from stasis with 1 HP!", tostring(self.target.name))
        end
        if status.hasAtHex(self.target.q, self.target.r, "fire") then
            status.removeFromHex(self.target.q, self.target.r, "fire")
            log.info("abilities", "Fire on the ground extinguished!")
        end

        -- Animate the 1-cell shift
        local fromQ, fromR = self.target.q, self.target.r
        self.target.q = q
        self.target.r = r
        if _G.hex then _G.hex.selectedQ, _G.hex.selectedR = q, r end

        global_abilities.spendAbility(self)
        undo.snapshot()
        log.infof("abilities", "%s cleansed and shifted to (%d,%d)!", tostring(self.target.name), q, r)
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        return true
    end

    return false
end

function ExtraMoveAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.4, 0.8},
        label = "Extra Move",
        activeLabel = "Select target",
        tooltipH = 64,
        tooltipTitle = "Extra Move",
        tooltipLines = {
            "Cleanse an ally of all debuffs",
            "and shift them 1 cell.",
        },
    })
end

-- ============================================================
-- WIND TORRENT
-- ============================================================
local WindTorrent = {}
WindTorrent.__index = WindTorrent

function WindTorrent.new()
    local self = {
        name = "Wind Torrent",
        manaCost = 3,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, WindTorrent)
end

function WindTorrent:reset()
    self.hasBeenUsed = false
end

local stepMap = {
    E  = {dx = 1, dy = -1, dz = 0},
    NE = {dx = 1, dy = 0, dz = -1},
    NW = {dx = 0, dy = 1, dz = -1},
    W  = {dx = -1, dy = 1, dz = 0},
    SW = {dx = -1, dy = 0, dz = 1},
    SE = {dx = 0, dy = -1, dz = 1},
}

function WindTorrent:_getDirectionFromHex(q, r, centerQ, centerR)
    local cx, cy, cz = hex_utils.axialToCube(centerQ, centerR)
    local x, y, z = hex_utils.axialToCube(q, r)
    local dx, dy, dz = x - cx, y - cy, z - cz
    if dx == 0 and dy == 0 and dz == 0 then return nil end

    local absDx, absDy, absDz = math.abs(dx), math.abs(dy), math.abs(dz)
    local maxVal = math.max(absDx, absDy, absDz)
    local ndx = math.floor(dx / maxVal + 0.5)
    local ndy = math.floor(dy / maxVal + 0.5)
    local ndz = math.floor(dz / maxVal + 0.5)
    if ndx + ndy + ndz ~= 0 then return nil end

    local directionMap = {
        {dx=1, dy=-1, dz=0, name="E"},
        {dx=1, dy=0, dz=-1, name="NE"},
        {dx=0, dy=1, dz=-1, name="NW"},
        {dx=-1, dy=1, dz=0, name="W"},
        {dx=-1, dy=0, dz=1, name="SW"},
        {dx=0, dy=-1, dz=1, name="SE"},
    }
    for _, dir in ipairs(directionMap) do
        if dir.dx == ndx and dir.dy == ndy and dir.dz == ndz then
            return dir.name
        end
    end
    return nil
end

function WindTorrent:onActivate(state)
    clearSelectedActor()
    log.info("abilities", "Click on any hex to choose wind direction, or press ESC to cancel")
end

function WindTorrent:onDeactivate(state)
    restoreSelectedActor()
        log.infof("abilities", "%s cancelled", self.name)
end

function WindTorrent:onClickHex(q, r, hex, state)
    local direction = self:_getDirectionFromHex(q, r, hex.centerQ, hex.centerR, hex)
    if not direction then
        log.warn("abilities", "Cannot determine direction from center")
        restoreSelectedActor()
        return true
    end

    self:executeGlobalWithAnimation(direction, hex, state.entities, state.sounds, state.terrainMap, function(success, message)
        if success then
            undo.snapshot()
            log.info("abilities", "Wind Torrent used!")
        else
            log.warnf("abilities", "Wind Torrent failed: %s", (message or "unknown error"))
        end
        restoreSelectedActor()
    end)
    global_abilities.activeAbility = nil
    return true
end

function WindTorrent:collectOverlays(hex, cellOverlays, state)
    if hex.hoverQ < 0 or hex.hoverR < 0 then return end
    local direction = self:_getDirectionFromHex(hex.hoverQ, hex.hoverR, hex.centerQ, hex.centerR, hex)
    if not direction then return end

    local step = stepMap[direction]
    if not step then return end

    for _, entity in ipairs(state.entities) do
        if entity.isPushable and entity.health > 0 then
            local newQ, newR = hex_utils.applyCubeDiff(entity.q, entity.r, step.dx, step.dy, step.dz)
            if hex:isActiveHex(newQ, newR) then
                local key = newQ .. "," .. newR
                if not cellOverlays[key] then
                    cellOverlays[key] = { windTorrentDest = true }
                end
            end
        end
    end
end

function WindTorrent:drawPreview(hex, state)
    local hq, hr = hex.hoverQ, hex.hoverR
    if hq < 0 or hr < 0 then return end
    local direction = self:_getDirectionFromHex(hq, hr, hex.centerQ, hex.centerR, hex)
    if not direction then return end

    local step = stepMap[direction]
    if not step then return end

    local movableObjects = {}
    for _, entity in ipairs(state.entities) do
        if entity.isPushable and entity.health > 0 then
            table.insert(movableObjects, entity)
        end
    end

    table.sort(movableObjects, function(a, b)
        local function getProjection(obj)
            local x, y, z = hex_utils.axialToCube(obj.q, obj.r)
            return x * step.dx + y * step.dy + z * step.dz
        end
        return getProjection(a) > getProjection(b)
    end)

    local immovableMap = {}
    for _, entity in ipairs(state.entities) do
        if not entity.isPushable and entity.health > 0 then
            local key = entity.q .. "," .. entity.r
            immovableMap[key] = entity
        end
    end

    local targetMap = {}
    local previewData = {}
    local damagedEntities = {}

    for _, obj in ipairs(movableObjects) do
        if obj.health <= 0 then goto continue end

        local newQ, newR = hex_utils.applyCubeDiff(obj.q, obj.r, step.dx, step.dy, step.dz)
        local fromX, fromY = getDrawCoords(obj.q, obj.r)
        local toX, toY = getDrawCoords(newQ, newR)

        if not hex:isActiveHex(newQ, newR) then
            local damage = 1
            table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isEdge=true, entity=obj, fromQ=obj.q, fromR=obj.r, toQ=newQ, toR=newR})
            table.insert(damagedEntities, {entity=obj, damage=damage, x=fromX, y=fromY})
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                local damage = 1
                table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isCollision=true, entity=obj, fromQ=obj.q, fromR=obj.r, toQ=newQ, toR=newR})
                table.insert(damagedEntities, {entity=obj, damage=damage, x=fromX, y=fromY})
                local immX, immY = getDrawCoords(immovableMap[immovableKey].q, immovableMap[immovableKey].r)
                table.insert(damagedEntities, {entity=immovableMap[immovableKey], damage=damage, x=immX, y=immY})
            else
                local targetOcc = targetMap[newQ .. "," .. newR]
                if targetOcc then
                    local damage = 1
                    table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=damage, isCollision=true, doubleDamage=true, entity=obj, with=targetOcc, fromQ=obj.q, fromR=obj.r, toQ=newQ, toR=newR})
                    table.insert(damagedEntities, {entity=obj, damage=damage, x=fromX, y=fromY})
                    local otherX, otherY = getDrawCoords(targetOcc.q, targetOcc.r)
                    table.insert(damagedEntities, {entity=targetOcc, damage=damage, x=otherX, y=otherY})
                else
                    targetMap[newQ .. "," .. newR] = obj
                    table.insert(previewData, {fromX=fromX, fromY=fromY, toX=toX, toY=toY, damage=0, entity=obj, fromQ=obj.q, fromR=obj.r, toQ=newQ, toR=newR})
                end
            end
        end
        ::continue::
    end

    for _, pd in ipairs(previewData) do
        ui.drawPushArrow(pd.fromX, pd.fromY, pd.toX, pd.toY, nil, nil, nil, nil, pd.fromQ, pd.fromR, pd.toQ, pd.toR)
    end

end

function WindTorrent:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.6, 0.8},
        label = "Wind Torrent",
        activeLabel = "Select direction",
        tooltipH = 80,
        tooltipTitle = "Wind Torrent",
        tooltipLines = {
            "Click on any hex to push all",
            "units (friend and foe) away from",
            "that hex in a line.",
        },
    })
end

function WindTorrent:executeGlobalWithAnimation(direction, hex, entities, sounds, terrainMap, onComplete)
    if self.hasBeenUsed then
        if onComplete then onComplete(false, "Already used") end
        return false
    end

    local step = stepMap[direction]
    if not step then
        if onComplete then onComplete(false, "Invalid direction") end
        return false
    end

    log.infof("abilities", "WIND TORRENT: Pushing everything %s!", direction)

    local movableObjects = {}
    for _, entity in ipairs(entities) do
        if entity.isPushable then
            table.insert(movableObjects, entity)
        end
    end

    table.sort(movableObjects, function(a, b)
        local function getProjection(obj)
            local x, y, z = hex_utils.axialToCube(obj.q, obj.r)
            return x * step.dx + y * step.dy + z * step.dz
        end
        return getProjection(a) > getProjection(b)
    end)

    local immovableMap = {}
    for _, entity in ipairs(entities) do
        if not entity.isPushable then
            local key = entity.q .. "," .. entity.r
            immovableMap[key] = entity
        end
    end

    local occupied = {}

    for _, obj in ipairs(movableObjects) do
        if obj.health <= 0 then goto continue end

        local fromKey = obj.q .. "," .. obj.r
        if occupied[fromKey] and occupied[fromKey] ~= obj then
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, obj.q, obj.r, hex, entities, sounds, occupied[fromKey])
            occupied[fromKey] = obj
            goto continue
        end

        local newQ, newR = hex_utils.applyCubeDiff(obj.q, obj.r, step.dx, step.dy, step.dz)
        if not hex:isActiveHex(newQ, newR) then
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, nil)
            occupied[fromKey] = obj
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, immovableMap[immovableKey])
                occupied[fromKey] = obj
            else
                local targetOcc = occupied[newQ .. "," .. newR]
                if targetOcc then
                    combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, targetOcc)
                    occupied[fromKey] = obj
                else
                    combat.addDirectPushAnimation(obj, obj.q, obj.r, newQ, newR)
                    occupied[newQ .. "," .. newR] = obj
                end
            end
        end
        ::continue::
    end

    combat.startPushAnimations(hex, function()
        global_abilities.spendAbility(self)
        sounds.play("wind_torrent")
        if onComplete then onComplete(true, nil) end
        if _G.checkGameEnd then _G.checkGameEnd() end
    end)
    return true
end

-- ============================================================
-- FORCE ATTACK: mark an enemy to attack first
-- ============================================================
local ForceAttackAbility = {}
ForceAttackAbility.__index = ForceAttackAbility

function ForceAttackAbility.new()
    local self = {
        name = "Force Attack",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, ForceAttackAbility)
end

function ForceAttackAbility:reset()
    self.hasBeenUsed = false
end

function ForceAttackAbility:onActivate(state)
    _G.showEnemyOrder = true
    log.info("abilities", "Click on an enemy to mark it as first attacker, or press ESC to cancel")
end

function ForceAttackAbility:onDeactivate(state)
    _G.showEnemyOrder = false
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function ForceAttackAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e:isCharacter() and not e.isPlayable then
            target = e
            break
        end
    end

    if not target then
        log.warn("abilities", "No valid enemy at this cell!")
        return true
    end

    if target.attacksFirst then
        log.warn("abilities", "This enemy already attacks first!")
        return true
    end

    target.attacksFirst = true
    global_abilities.spendAbility(self)
    undo.snapshot()
    log.infof("abilities", "%s marked to attack first!", tostring(target.name))
    _G.showEnemyOrder = false
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function ForceAttackAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.9, 0.6, 0.1},
        label = "Force Attack",
        activeLabel = "Select enemy",
        tooltipH = 80,
        tooltipTitle = "Force Attack",
        tooltipLines = {
            "Mark an enemy to attack first",
            "in the turn order.",
        },
    })
end

-- ============================================================
-- RAGE: applied to a unit, all 1-damage attacks become fatal
-- ============================================================
local RageAbility = {}
RageAbility.__index = RageAbility

function RageAbility.new()
    local self = {
        name = "Rage",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, RageAbility)
end

function RageAbility:reset()
    self.hasBeenUsed = false
end

function RageAbility:onActivate(state)
    log.info("abilities", "Click on a unit to apply Rage, or press ESC to cancel")
end

function RageAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function RageAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e:isCharacter() then
            target = e
            break
        end
    end

    if not target then
        log.warn("abilities", "No valid target at this cell!")
        return true
    end

    status.applyToEntity(target, "rage")
    global_abilities.spendAbility(self)
    undo.snapshot()
    log.infof("abilities", "Rage applied to %s!", tostring(target.name))
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function RageAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.9, 0.2, 0.1},
        label = "Rage",
        activeLabel = "Select target",
        tooltipH = 64,
        tooltipTitle = "Rage",
        tooltipLines = {
            "All attacks dealing 1 damage",
            "become fatal for 1 turn.",
        },
    })
end

-- ============================================================
-- THE BIG ONE: vector triangle blast, fatal damage
-- ============================================================
local TheBigOneAbility = {}
TheBigOneAbility.__index = TheBigOneAbility

function TheBigOneAbility.new()
    local self = {
        name = "The Big One",
        manaCost = 3,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        origin = nil,
    }
    return setmetatable(self, TheBigOneAbility)
end

function TheBigOneAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.origin = nil
end

function TheBigOneAbility:_getDirection(fromQ, fromR, toQ, toR)
    local ax, ay, az = hex_utils.axialToCube(fromQ, fromR)
    local bx, by, bz = hex_utils.axialToCube(toQ, toR)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    if dx == 0 and dy == 0 and dz == 0 then return nil end

    local absDx, absDy, absDz = math.abs(dx), math.abs(dy), math.abs(dz)
    local maxVal = math.max(absDx, absDy, absDz)
    local ndx = math.floor(dx / maxVal + 0.5)
    local ndy = math.floor(dy / maxVal + 0.5)
    local ndz = math.floor(dz / maxVal + 0.5)
    if ndx + ndy + ndz ~= 0 then return nil end

    return ndx, ndy, ndz
end

function TheBigOneAbility:_getConeCells(oq, or_, stepX, stepY, stepZ, hex, startDist)
    local cells = {}
    local ox, oy, oz = hex_utils.axialToCube(oq, or_)
    -- 60-degree CCW direction from step direction
    local lx, ly, lz = hex_utils.rotateCubeDir(stepX, stepY, stepZ, false)

    for d = (startDist or 1), 50 do
        local anyAdded = false
        for a = 0, d do
            local b = d - a
            local x = ox + a * stepX + b * lx
            local y = oy + a * stepY + b * ly
            local z = oz + a * stepZ + b * lz
            local q, r = hex_utils.cubeToAxial(x, y, z)
            if hex:isActiveHex(q, r) then
                table.insert(cells, {q = q, r = r})
                anyAdded = true
            end
        end
        if not anyAdded then break end
    end
    return cells
end

function TheBigOneAbility:onActivate(state)
    self.phase = "select_origin"
    self.origin = nil
    log.info("abilities", "Click on a hex to set the blast origin, or press ESC to cancel")
end

function TheBigOneAbility:onDeactivate(state)
    self.phase = nil
    self.origin = nil
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function TheBigOneAbility:onClickHex(q, r, hex, state)
    if self.phase == "select_origin" then
        self.origin = {q = q, r = r}
        self.phase = "select_direction"
        log.info("abilities", "Now click in the direction of the blast, or click origin to cancel direction")
        return true
    end

    if self.phase == "select_direction" then
        if q == self.origin.q and r == self.origin.r then
            log.info("abilities", "Click on a cell to choose blast direction")
            return true
        end
        local stepX, stepY, stepZ = self:_getDirection(self.origin.q, self.origin.r, q, r)
        if not stepX then
            log.warn("abilities", "Cannot determine direction from origin!")
            return true
        end

        -- Damage starts from distance 2 (skip origin + first row)
        local damageCells = self:_getConeCells(self.origin.q, self.origin.r, stepX, stepY, stepZ, hex, 2)
        if #damageCells == 0 then
            log.warn("abilities", "No valid blast cells in that direction!")
            return true
        end

        for _, c in ipairs(damageCells) do
            local target = combat.getEntityAtHex(c.q, c.r, state.entities)
            if target and target.health > 0 then
                local wasDestroyed = target:takeDamage(99)
                if wasDestroyed then target:startDeath() end
            end
            if visual then
                local x, y = getDrawCoords(c.q, c.r)
                visual.addEffect(x, y, "hit", 0.4)
            end
        end

        global_abilities.spendAbility(self)
        undo.snapshot()
        log.info("abilities", "The Big One detonated!")
        if _G.checkGameEnd then _G.checkGameEnd() end
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        self.phase = nil
        self.origin = nil
        return true
    end

    return false
end

function TheBigOneAbility:collectOverlays(hex, cellOverlays, state)
    if self.phase == "select_origin" then
        -- Highlight all active hexes as possible origins
        if hex.hoverQ >= 0 and hex.hoverR >= 0 and hex:isActiveHex(hex.hoverQ, hex.hoverR) then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.5, 0.5, 1, 0.3}, line = {0.5, 0.5, 1, 0.7}}
        end
    elseif self.phase == "select_direction" and self.origin then
        -- Show origin
        local okey = self.origin.q .. "," .. self.origin.r
        cellOverlays[okey] = {fill = {0.5, 0.5, 1, 0.4}, line = {0.5, 0.5, 1, 0.8}}
        -- Show cone cells on hover
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        if hq == self.origin.q and hr == self.origin.r then return end
        local stepX, stepY, stepZ = self:_getDirection(self.origin.q, self.origin.r, hq, hr)
        if not stepX then return end
        -- All cone cells (full visual)
        local cells = self:_getConeCells(self.origin.q, self.origin.r, stepX, stepY, stepZ, hex)
        -- Damage cells only (from d=2 onward)
        local damageCells = self:_getConeCells(self.origin.q, self.origin.r, stepX, stepY, stepZ, hex, 2)
        local damageSet = {}
        for _, c in ipairs(damageCells) do
            damageSet[c.q .. "," .. c.r] = true
        end
        for _, c in ipairs(cells) do
            local key = c.q .. "," .. c.r
            if damageSet[key] then
                cellOverlays[key] = {fill = {1, 0.2, 0.2, 0.5}, line = {1, 0, 0, 0.9}}
            else
                cellOverlays[key] = {fill = {0.5, 0.5, 0.5, 0.3}, line = {0.5, 0.5, 0.5, 0.6}}
            end
        end
    end
end

function TheBigOneAbility:drawPreview(hex, state)
    if self.phase == "select_direction" and self.origin then
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        if hq == self.origin.q and hr == self.origin.r then return end
        local stepX, stepY, stepZ = self:_getDirection(self.origin.q, self.origin.r, hq, hr)
        if not stepX then return end
        -- Only show damage icons for cells that actually get damaged (d>=2)
        local damageCells = self:_getConeCells(self.origin.q, self.origin.r, stepX, stepY, stepZ, hex, 2)
        local icon_cache = require("ui.icon_cache")
        for _, c in ipairs(damageCells) do
            local target = combat.getEntityAtHex(c.q, c.r, state.entities)
            if target and target.health > 0 and not target.indestructible then
                local eff = attack_preview.calculateEffectiveDamage(target, target, 99, nil, nil)
                local icon = attack_preview.getDamageIcon(target, eff)
                if icon then
                    local x, y = getDrawCoords(c.q, c.r)
                    icon_cache.draw(icon, x, y, 0.95)
                end
            end
        end
    end
end

function TheBigOneAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.9, 0.1, 0.1},
        label = "The Big One",
        activeLabel = self.phase == "select_direction" and "Choose direction" or "Select origin",
        tooltipH = 80,
        tooltipTitle = "The Big One",
        tooltipLines = {
            "Deal fatal damage to all units",
            "in a triangular sector.",
            "Origin cell is unaffected.",
        },
    })
end

-- ============================================================
-- AIR STRIKE: vector line attack, 1 damage to all units on line
-- ============================================================
local AirStrikeAbility = {}
AirStrikeAbility.__index = AirStrikeAbility

function AirStrikeAbility.new()
    local self = {
        name = "Air Strike",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        startCell = nil,
    }
    return setmetatable(self, AirStrikeAbility)
end

function AirStrikeAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.startCell = nil
end

function AirStrikeAbility:_getDirection(fromQ, fromR, toQ, toR)
    local ax, ay, az = hex_utils.axialToCube(fromQ, fromR)
    local bx, by, bz = hex_utils.axialToCube(toQ, toR)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    if dx == 0 and dy == 0 and dz == 0 then return nil end

    local absDx, absDy, absDz = math.abs(dx), math.abs(dy), math.abs(dz)
    local maxVal = math.max(absDx, absDy, absDz)
    local ndx = math.floor(dx / maxVal + 0.5)
    local ndy = math.floor(dy / maxVal + 0.5)
    local ndz = math.floor(dz / maxVal + 0.5)
    if ndx + ndy + ndz ~= 0 then return nil end

    return ndx, ndy, ndz
end

function AirStrikeAbility:onActivate(state)
    self.phase = "select_start"
    self.startCell = nil
    log.info("abilities", "Click on a hex to start the air strike line, or press ESC to cancel")
end

function AirStrikeAbility:onDeactivate(state)
    self.phase = nil
    self.startCell = nil
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function AirStrikeAbility:onClickHex(q, r, hex, state)
    if self.phase == "select_start" then
        self.startCell = {q = q, r = r}
        self.phase = "select_direction"
        log.info("abilities", "Now click in the direction of the strike")
        return true
    end

    if self.phase == "select_direction" then
        if q == self.startCell.q and r == self.startCell.r then
            log.info("abilities", "Click on another cell to choose the strike direction")
            return true
        end
        local stepX, stepY, stepZ = self:_getDirection(self.startCell.q, self.startCell.r, q, r)
        if not stepX then
            log.warn("abilities", "Cannot determine direction!")
            return true
        end

        -- Walk along the line in both directions from start cell
        local function processLine(startQ, startR, stepX, stepY, stepZ, hex, state)
            local curQ, curR = startQ, startR
            while true do
                curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
                if not hex:isActiveHex(curQ, curR) then break end
                local target = combat.getEntityAtHex(curQ, curR, state.entities)
                if target and target.health > 0 then
                    local wasDestroyed = target:takeDamage(1)
                    if wasDestroyed then target:startDeath() end
                end
                if visual then
                    local x, y = getDrawCoords(curQ, curR)
                    visual.addEffect(x, y, "hit", 0.25)
                end
            end
        end

        -- Also go in the opposite direction
        processLine(self.startCell.q, self.startCell.r, stepX, stepY, stepZ, hex, state)
        processLine(self.startCell.q, self.startCell.r, -stepX, -stepY, -stepZ, hex, state)

        global_abilities.spendAbility(self)
        undo.snapshot()
        log.info("abilities", "Air Strike executed!")
        if _G.checkGameEnd then _G.checkGameEnd() end
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        self.phase = nil
        self.startCell = nil
        return true
    end

    return false
end

function AirStrikeAbility:collectOverlays(hex, cellOverlays, state)
    if self.phase == "select_start" then
        if hex.hoverQ >= 0 and hex.hoverR >= 0 and hex:isActiveHex(hex.hoverQ, hex.hoverR) then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.5, 0.8, 0.5, 0.3}, line = {0.5, 0.8, 0.5, 0.7}}
        end
    elseif self.phase == "select_direction" and self.startCell then
        local skey = self.startCell.q .. "," .. self.startCell.r
        cellOverlays[skey] = {fill = {0.5, 0.8, 0.5, 0.4}, line = {0.5, 0.8, 0.5, 0.8}}

        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        if hq == self.startCell.q and hr == self.startCell.r then return end
        local stepX, stepY, stepZ = self:_getDirection(self.startCell.q, self.startCell.r, hq, hr)
        if not stepX then return end

        -- Show forward line
        local curQ, curR = self.startCell.q, self.startCell.r
        while true do
            curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
            if not hex:isActiveHex(curQ, curR) then break end
            local key = curQ .. "," .. curR
            cellOverlays[key] = {fill = {1, 0.8, 0.2, 0.4}, line = {1, 0.8, 0.2, 0.8}}
        end

        -- Show backward line
        curQ, curR = self.startCell.q, self.startCell.r
        while true do
            curQ, curR = hex_utils.applyCubeStep(curQ, curR, -stepX, -stepY, -stepZ)
            if not hex:isActiveHex(curQ, curR) then break end
            local key = curQ .. "," .. curR
            cellOverlays[key] = {fill = {1, 0.8, 0.2, 0.4}, line = {1, 0.8, 0.2, 0.8}}
        end
    end
end

function AirStrikeAbility:drawPreview(hex, state)
    if self.phase == "select_direction" and self.startCell then
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        if hq == self.startCell.q and hr == self.startCell.r then return end
        local stepX, stepY, stepZ = self:_getDirection(self.startCell.q, self.startCell.r, hq, hr)
        if not stepX then return end

        -- Draw a line along the strike path
        local curQ, curR = self.startCell.q, self.startCell.r
        local lastQ, lastR = curQ, curR
        while true do
            local nq, nr = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
            if not hex:isActiveHex(nq, nr) then break end
            lastQ, lastR = nq, nr
            curQ, curR = nq, nr
        end
        local endQ, endR = lastQ, lastR

        -- Also find far end in opposite direction
        curQ, curR = self.startCell.q, self.startCell.r
        lastQ, lastR = curQ, curR
        while true do
            local nq, nr = hex_utils.applyCubeStep(curQ, curR, -stepX, -stepY, -stepZ)
            if not hex:isActiveHex(nq, nr) then break end
            lastQ, lastR = nq, nr
            curQ, curR = nq, nr
        end

        local fx, fy = getDrawCoords(lastQ, lastR)
        local tx, ty = getDrawCoords(endQ, endR)
        love.graphics.setLineWidth(3)
        love.graphics.setColor(1, 0.8, 0.2, 0.5)
        love.graphics.line(fx, fy, tx, ty)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function AirStrikeAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.6, 0.8, 0.2},
        label = "Air Strike",
        activeLabel = self.phase == "select_direction" and "Choose direction" or "Select start",
        tooltipH = 64,
        tooltipTitle = "Air Strike",
        tooltipLines = {
            "Wound all units in a straight",
            "line for 1 damage.",
        },
    })
end

-- ============================================================
-- STASIS OVERLOAD: fatal damage to ally and all adjacent
-- ============================================================
local StasisOverloadAbility = {}
StasisOverloadAbility.__index = StasisOverloadAbility

function StasisOverloadAbility.new()
    local self = {
        name = "Stasis Overload",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, StasisOverloadAbility)
end

function StasisOverloadAbility:reset()
    self.hasBeenUsed = false
end

function StasisOverloadAbility:onActivate(state)
    log.info("abilities", "Click on an ally to trigger Stasis Overload, or press ESC to cancel")
end

function StasisOverloadAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function StasisOverloadAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e.isPlayable then
            target = e
            break
        end
    end

    if not target then
        log.warn("abilities", "No valid ally at this cell!")
        return true
    end

    -- Deal fatal damage to target and all adjacent cells
    local toDamage = {target}
    local neighbors = hex:getNeighbors(q, r)
    for _, n in ipairs(neighbors) do
        if hex:isActiveHex(n.q, n.r) then
            local e = combat.getEntityAtHex(n.q, n.r, state.entities)
            if e and e.health > 0 and not e.indestructible then
                table.insert(toDamage, e)
            end
        end
    end

    for _, e in ipairs(toDamage) do
        local wasDestroyed = e:takeDamage(99)
        if wasDestroyed then e:startDeath() end
        if visual then
            local x, y = getDrawCoords(e.q, e.r)
            visual.addEffect(x, y, "hit", 0.3)
        end
    end

    global_abilities.spendAbility(self)
    undo.snapshot()
    log.info("abilities", "Stasis Overload activated!")
    if _G.checkGameEnd then _G.checkGameEnd() end
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function StasisOverloadAbility:collectOverlays(hex, cellOverlays, state)
    local hq, hr = hex.hoverQ, hex.hoverR
    if hq < 0 or hr < 0 then return end

    -- Highlight valid ally targets
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == hq and e.r == hr and e.health > 0 and e.isPlayable then
            target = e
            break
        end
    end
    if not target then
        -- Just highlight character cells on hover
        for _, e in ipairs(state.entities) do
            if e.q == hq and e.r == hr and e.health > 0 and e.isPlayable then
                local key = hq .. "," .. hr
                cellOverlays[key] = {fill = {0.5, 0.5, 0.5, 0.2}, line = {0.5, 0.5, 0.5, 0.5}}
                return
            end
        end
        return
    end

    -- Show target and all neighbors that will take damage
    local tkey = hq .. "," .. hr
    cellOverlays[tkey] = {fill = {0.8, 0.2, 0.8, 0.5}, line = {0.8, 0.2, 0.8, 0.9}}

    local neighbors = hex:getNeighbors(hq, hr)
    for _, n in ipairs(neighbors) do
        if hex:isActiveHex(n.q, n.r) then
            local key = n.q .. "," .. n.r
            cellOverlays[key] = {fill = {1, 0.4, 0.4, 0.4}, line = {1, 0.4, 0.4, 0.8}}
        end
    end
end

function StasisOverloadAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.8, 0.2, 0.8},
        label = "Stasis Overload",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Stasis Overload",
        tooltipLines = {
            "Deal fatal damage to an ally",
            "and all units adjacent to it.",
        },
    })
end

-- ============================================================
-- CHAIN LIGHTNING: 1 dmg to first target, fatal to adjacent second
-- ============================================================
local ChainLightningAbility = {}
ChainLightningAbility.__index = ChainLightningAbility

function ChainLightningAbility.new()
    local self = {
        name = "Chain Lightning",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        firstTarget = nil,
    }
    return setmetatable(self, ChainLightningAbility)
end

function ChainLightningAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.firstTarget = nil
end

local function isValidLightningTarget(e)
    return e and e.health > 0 and not e.indestructible and not e:isBuilding() and not e:isObstacle()
end

function ChainLightningAbility:onActivate(state)
    self.phase = "select_first"
    self.firstTarget = nil
    log.info("abilities", "Click on the first target, or press ESC to cancel")
end

function ChainLightningAbility:onDeactivate(state)
    self.phase = nil
    self.firstTarget = nil
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function ChainLightningAbility:onClickHex(q, r, hex, state)
    if self.phase == "select_first" then
        local target = nil
        for _, e in ipairs(state.entities) do
            if e.q == q and e.r == r and isValidLightningTarget(e) then
                target = e
                break
            end
        end
        if not target then
            log.warn("abilities", "Must target a character (not a building or obstacle)!")
            return true
        end
        self.firstTarget = target
        self.phase = "select_direction"
        log.info("abilities", "Now click on an adjacent hex for the chain to jump to")
        return true
    end

    if self.phase == "select_direction" and self.firstTarget then
        local dist = hex:getDistance(self.firstTarget.q, self.firstTarget.r, q, r)
        if dist ~= 1 then
            log.warn("abilities", "Second target must be adjacent to the first!")
            return true
        end
        local secondTarget = nil
        for _, e in ipairs(state.entities) do
            if e.q == q and e.r == r and e ~= self.firstTarget and isValidLightningTarget(e) then
                secondTarget = e
                break
            end
        end
        if not secondTarget then
            log.warn("abilities", "No valid target in that direction!")
            return true
        end

        -- Apply 1 damage to first target
        local wasDestroyed = self.firstTarget:takeDamage(1)
        if wasDestroyed then self.firstTarget:startDeath() end
        if visual then
            local x, y = getDrawCoords(self.firstTarget.q, self.firstTarget.r)
            visual.addEffect(x, y, "hit", 0.3)
        end

        -- Apply fatal damage to second target
        wasDestroyed = secondTarget:takeDamage(99)
        if wasDestroyed then secondTarget:startDeath() end
        if visual then
            local x, y = getDrawCoords(secondTarget.q, secondTarget.r)
            visual.addEffect(x, y, "hit", 0.4)
        end

        global_abilities.spendAbility(self)
        undo.snapshot()
        log.infof("abilities", "Chain Lightning: %s wounded, %s destroyed!", self.firstTarget.name, secondTarget.name)
        if _G.checkGameEnd then _G.checkGameEnd() end
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        self.phase = nil
        self.firstTarget = nil
        return true
    end

    return false
end

function ChainLightningAbility:collectOverlays(hex, cellOverlays, state)
    if self.phase == "select_first" then
        if hex.hoverQ < 0 or hex.hoverR < 0 then return end
        local first = nil
        for _, e in ipairs(state.entities) do
            if e.q == hex.hoverQ and e.r == hex.hoverR and isValidLightningTarget(e) then
                first = e
                break
            end
        end
        if first then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.6, 0.6, 1, 0.3}, line = {0.6, 0.6, 1, 0.7}}
        end
    elseif self.phase == "select_direction" and self.firstTarget then
        local skey = self.firstTarget.q .. "," .. self.firstTarget.r
        cellOverlays[skey] = {fill = {0.6, 0.6, 1, 0.4}, line = {0.6, 0.6, 1, 0.8}}
        -- Highlight adjacent valid targets on hover
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        local dist = hex:getDistance(self.firstTarget.q, self.firstTarget.r, hq, hr)
        if dist ~= 1 then return end
        local second = nil
        for _, e in ipairs(state.entities) do
            if e.q == hq and e.r == hr and e ~= self.firstTarget and isValidLightningTarget(e) then
                second = e
                break
            end
        end
        if second then
            local key = hq .. "," .. hr
            cellOverlays[key] = {fill = {1, 0.2, 0.6, 0.5}, line = {1, 0.2, 0.6, 0.9}}
        end
    end
end

function ChainLightningAbility:drawPreview(hex, state)
    if self.phase == "select_direction" and self.firstTarget then
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        local dist = hex:getDistance(self.firstTarget.q, self.firstTarget.r, hq, hr)
        if dist ~= 1 then return end
        local second = nil
        for _, e in ipairs(state.entities) do
            if e.q == hq and e.r == hr and e ~= self.firstTarget and isValidLightningTarget(e) then
                second = e
                break
            end
        end
        if second then
            local icon_cache = require("ui.icon_cache")
            -- First target: wound icon
            local fx, fy = getDrawCoords(self.firstTarget.q, self.firstTarget.r)
            local ficon = attack_preview.getDamageIcon(self.firstTarget, math.min(attack_preview.calculateEffectiveDamage(self.firstTarget, self.firstTarget, 1, nil, nil), self.firstTarget.health))
            if ficon then icon_cache.draw(ficon, fx, fy, 0.95) end
            -- Second target: fatal icon
            local sx, sy = getDrawCoords(second.q, second.r)
            local sicon = attack_preview.getDamageIcon(second, attack_preview.calculateEffectiveDamage(second, second, 99, nil, nil))
            if sicon then icon_cache.draw(sicon, sx, sy, 0.95) end
            -- Draw lightning bolt line
            love.graphics.setLineWidth(4)
            love.graphics.setColor(0.8, 0.2, 1, 0.7)
            love.graphics.line(fx, fy, sx, sy)
            love.graphics.setLineWidth(2)
            local midx, midy = (fx + sx) / 2, (fy + sy) / 2
            love.graphics.line(midx - 4, midy - 4, midx + 4, midy + 4)
            love.graphics.line(midx + 4, midy - 4, midx - 4, midy + 4)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
end

function ChainLightningAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.6, 0.2, 1},
        label = "Chain Lightning",
        activeLabel = self.phase == "select_direction" and "Choose direction" or "Select target",
        tooltipH = 80,
        tooltipTitle = "Chain Lightning",
        tooltipLines = {
            "1 damage to first target,",
            "fatal damage to adjacent",
            "second target.",
        },
    })
end

-- ============================================================
-- INVULNERABILITY: remove all debuffs, become indestructible
-- ============================================================
local InvulnerabilityAbility = {}
InvulnerabilityAbility.__index = InvulnerabilityAbility

function InvulnerabilityAbility.new()
    local self = {
        name = "Invulnerability",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, InvulnerabilityAbility)
end

function InvulnerabilityAbility:reset()
    self.hasBeenUsed = false
end

function InvulnerabilityAbility:onActivate(state)
    log.info("abilities", "Click on an ally to make them invulnerable, or press ESC to cancel")
end

function InvulnerabilityAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function InvulnerabilityAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e.isPlayable then
            target = e
            break
        end
    end

    if not target then
        log.warn("abilities", "No valid ally at this cell!")
        return true
    end

    -- Clear all negative statuses (keep empowered)
    local wasStasis = status.hasEntityStatus(target, "stasis")
    local sts = status.getEntityStatuses(target)
    for _, st in ipairs(sts) do
        if st ~= "empowered" then
            status.removeFromEntity(target, st)
        end
    end

    -- Heal to full if was in stasis
    if wasStasis then
        target.health = target.maxHealth
        log.infof("abilities", "%s revived from stasis!", tostring(target.name))
    end

    -- Make indestructible
    target.indestructible = true

    global_abilities.spendAbility(self)
    undo.snapshot()
    log.infof("abilities", "%s is now invulnerable!", tostring(target.name))
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function InvulnerabilityAbility:collectOverlays(hex, cellOverlays, state)
    if hex.hoverQ < 0 or hex.hoverR < 0 then return end
    for _, e in ipairs(state.entities) do
        if e.q == hex.hoverQ and e.r == hex.hoverR and e.health > 0 and e.isPlayable then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.4, 0.4, 0.8, 0.3}, line = {0.4, 0.4, 0.8, 0.7}}
            return
        end
    end
end

function InvulnerabilityAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.4, 0.3, 0.9},
        label = "Invulnerability",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Invulnerability",
        tooltipLines = {
            "Remove all negative effects",
            "and become immune to all",
            "damage for the rest of the game.",
        },
    })
end

-- Register all abilities
global_abilities.register(HealAbility.new())
global_abilities.register(ExtraMoveAbility.new())
global_abilities.register(WindTorrent.new())
global_abilities.register(UnearthAbility.new())
global_abilities.register(MindControlAbility.new())
global_abilities.register(AccelerateDecayAbility.new())
global_abilities.register(ForceAttackAbility.new())
global_abilities.register(RageAbility.new())
global_abilities.register(TheBigOneAbility.new())
global_abilities.register(AirStrikeAbility.new())
global_abilities.register(StasisOverloadAbility.new())
global_abilities.register(ChainLightningAbility.new())
global_abilities.register(InvulnerabilityAbility.new())

return global_abilities
