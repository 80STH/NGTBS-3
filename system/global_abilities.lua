-- global_abilities.lua
-- Modular system of one-time abilities.
-- Each ability is an independent object with its own hasBeenUsed, button.
-- All abilities are available simultaneously (not mutually exclusive in terms of usage,
-- but only one can be in target selection mode).

local Entity = require("entity.entity")
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
local icon_cache = require("ui.icon_cache")

local global_abilities = {}

global_abilities.registry = {}
global_abilities.activeAbility = nil
global_abilities.showPanel = false
global_abilities.mana = 3
global_abilities.maxMana = 3
global_abilities.abilityUsedThisTurn = false

global_abilities.abilityOrder = {"Heal", "Flash Heal", "Stim Pack", "Armor Pack", "Extra Move", "Wind Torrent", "Unearth", "Mind Control", "Accelerate Decay", "Force Attack", "Rage", "The Big One", "Air Strike", "Jumping Strike", "Overload", "Chain Lightning", "Invulnerability", "Vortex", "Hex", "Upside Down", "Teleport", "Speed Boost", "Void", "Infest"}

global_abilities.heroicAbilities = {
    ["Wind Torrent"] = true,
    ["Accelerate Decay"] = true,
    ["The Big One"] = true,
    ["Overload"] = true,
    ["Vortex"] = true,
}

global_abilities.unlocked = {}

-- Healing ability every squad/hero can always use; chosen in the main menu.
global_abilities.healAbilities = { "Heal", "Flash Heal", "Stim Pack", "Armor Pack" }
global_abilities.defaultHeal = "Heal"

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

-- Squad abilities come from the hero definition; the menu-chosen heal is always on.
-- "Revive <summon>" buttons are dynamic (graveyard) and need no unlocking.
function global_abilities.setSquadAbilities(names)
    global_abilities.unlocked = {}
    local heal = _G.healSpell or global_abilities.defaultHeal
    global_abilities.unlocked[heal] = true
    for _, ab in ipairs(names or {}) do
        global_abilities.unlocked[ab] = true
    end
end

function global_abilities.getDisplayOrder(state)
    global_abilities.syncGraveyardAbilities()
    local result = {}
    local unlimited = state and state.unlimitedAbilities
    for _, name in ipairs(global_abilities.abilityOrder) do
        if unlimited or global_abilities.unlocked[name] then
            local ab = global_abilities.registry[name]
            -- Abilities with a usability check stay hidden until they'd do something.
            if not (ab and ab.isUsable) or ab:isUsable(state) then
                table.insert(result, name)
            end
        end
    end
    -- Append dynamic graveyard buttons
    for name, ab in pairs(global_abilities.registry) do
        if ab.snapshot then
            local found = false
            for _, n in ipairs(result) do
                if n == name then found = true; break end
            end
            if not found then
                table.insert(result, name)
            end
        end
    end
    return result
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
        ["Vortex"] = "vortex_ability",
    }
    local soundName = abilitySounds[ab.name]
    if soundName then sounds.play(soundName) end
end

function global_abilities.reset()
    global_abilities.activeAbility = nil
    global_abilities.showPanel = false
    global_abilities.mana = global_abilities.maxMana
    global_abilities.abilityUsedThisTurn = false
    global_abilities.pendingRemains = {}
    global_abilities.clearGraveyardAbilities()
    for _, ab in pairs(global_abilities.registry) do
        if ab.reset then ab:reset() end
        ab.hasBeenUsed = false
    end
end

-- Abilities are reusable: clear the per-ability "used" latch at the start of
-- every player turn. The 1-per-turn limit is enforced by abilityUsedThisTurn.
function global_abilities.resetUsage()
    for _, ab in pairs(global_abilities.registry) do
        if ab.reset then ab:reset() end
        ab.hasBeenUsed = false
    end
end

function global_abilities.handleAbilityButtonClick(x, y, state)
    if not global_abilities.showPanel then return false end
    local displayOrder = global_abilities.getDisplayOrder(state)
    for _, name in ipairs(displayOrder) do
        local ab = global_abilities.registry[name]
        if ab then
            local bx, by, bw, bh = ab.button.x, ab.button.y, ab.button.width, ab.button.height
            if bw and x >= bx and x <= bx + bw and y >= by and y <= by + bh then
                if state.turnState.phase == "player" and not (state.selectedActor and state.selectedActor.isMoving) then
                    local unlimited = state.unlimitedAbilities
                    if not unlimited and ab.hasBeenUsed then return true end
                    if not unlimited and global_abilities.abilityUsedThisTurn then return true end
                    if not unlimited and global_abilities.mana < ab.manaCost then return true end
                    -- Healing that would do nothing cannot be used.
                    if ab.isEffective and not ab:isEffective(state) then return true end
                    if global_abilities.activeAbility then
                        global_abilities.activeAbility:onDeactivate(state)
                    end
                    global_abilities.activeAbility = ab
                    ab:onActivate(state)
                    clearSelectedActor()
                end
                return true
            end
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
    -- Hover preview: when the mouse is over an ability button (and none is
    -- active), let it highlight who it would affect. Button rects are cached
    -- by ui.drawAbilityButtons on the previous frame.
    if not ab and global_abilities.showPanel then
        local mx, my = love.mouse.getPosition()
        mx, my = mx / (state.dpiScale or 1), my / (state.dpiScale or 1)
        for _, name in ipairs(global_abilities.getDisplayOrder(state)) do
            local hab = global_abilities.registry[name]
            local b = hab and hab.button
            if b and b.width and mx >= b.x and mx <= b.x + b.width
                and my >= b.y and my <= b.y + b.height then
                if hab.collectHoverOverlays then hab:collectHoverOverlays(hex, cellOverlays, state) end
                break
            end
        end
    end
end

function global_abilities.drawPreview(hex, state)
    local ab = global_abilities.activeAbility
    if ab and ab.drawPreview then
        ab:drawPreview(hex, state)
    end
end

function global_abilities.drawButtons(mx, my, state)
    -- ability buttons are now drawn by ui.drawAbilityButtons(state)
end



function global_abilities.drawAbilityButton(self, mx, my, state, cfg)
    self._cfg = cfg
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
            if terrain ~= "water" and not cell_rules.isRailway(site.q, site.r) and not status.hasNegativeHexStatus(site.q, site.r) then
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
        combat.unrootForcedMove(self.target)
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

-- Heals are always available: the button must show even at full HP so the
-- player can find the chosen healing ability. Cleansing is the only effect.
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

-- Negative statuses removed by heal effects; positive ones (empowered, rage) survive.
local NEGATIVE_ENTITY_STATUSES = { fire = true, acid = true, decay = true, rooted = true, slow = true }

-- Strip every negative status from one entity (shared by all heal effects).
local function cleanseEntity(e)
    local toClear = {}
    for _, st in ipairs(status.getEntityStatuses(e)) do
        if NEGATIVE_ENTITY_STATUSES[st] then table.insert(toClear, st) end
    end
    for _, st in ipairs(toClear) do
        status.removeFromEntity(e, st)
    end
end

-- True if this living playable ally would benefit from healing (wounded or debuffed).
local function isWoundedOrDebuffed(e)
    if not (e.isPlayable and e:isCharacter() and e.health > 0) then return false end
    if e.health < e.maxHealth then return true end
    for _, st in ipairs(status.getEntityStatuses(e)) do
        if NEGATIVE_ENTITY_STATUSES[st] then return true end
    end
    return false
end

-- True if any living playable ally would benefit from a heal/cleanse.
local function anyAllyNeedsHeal(state)
    for _, e in ipairs((state and state.entities) or _G.entities or {}) do
        if isWoundedOrDebuffed(e) then return true end
    end
    return false
end

-- Highlight the allies a heal would affect.
--   onlyWounded = true  -> only allies that actually need healing (Heal / Flash Heal)
--   onlyWounded = false -> every living ally; wounded ones glow brighter.
local function highlightHealTargets(hex, cellOverlays, state, onlyWounded)
    for _, e in ipairs(state.entities or {}) do
        if e.isPlayable and e:isCharacter() and e.health > 0 then
            local wounded = isWoundedOrDebuffed(e)
            if not onlyWounded or wounded then
                local key = e.q .. "," .. e.r
                local hovered = hex and (hex.hoverQ == e.q and hex.hoverR == e.r)
                if wounded then
                    cellOverlays[key] = hovered
                        and { fill = {0.2, 0.9, 0.4, 0.55}, line = {0.2, 1.0, 0.4, 1.0} }
                        or { fill = {0.2, 0.8, 0.3, 0.4}, line = {0.3, 0.9, 0.4, 0.8} }
                else
                    -- Not wounded: still a valid target for Stim/Armor, but faint.
                    cellOverlays[key] = { fill = {0.2, 0.7, 0.3, 0.18}, line = {0.3, 0.8, 0.4, 0.4} }
                end
            end
        end
    end
end

-- Heal is effective only when some ally is wounded or debuffed.
function HealAbility:isEffective(state)
    return anyAllyNeedsHeal(state)
end

-- Hovering the button previews which allies it would heal.
function HealAbility:collectHoverOverlays(hex, cellOverlays, state)
    highlightHealTargets(hex, cellOverlays, state, true)
end

-- Heal acts on every living playable ally at once: +1 HP and cleanse debuffs.
function HealAbility:onActivate(state)
    local healed = 0
    undo.snapshot()
    for _, e in ipairs(state.entities or _G.entities) do
        if e.isPlayable and e:isCharacter() and e.health > 0 then
            if e.health < e.maxHealth then
                e.health = math.min(e.maxHealth, e.health + 1)
                healed = healed + 1
            end
            cleanseEntity(e)
        end
    end
    global_abilities.spendAbility(self)
    log.infof("abilities", "Heal: %d allies restored, debuffs cleansed", healed)
    global_abilities.activeAbility = nil
end

function HealAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.8, 0.3},
        label = "Heal",
        activeLabel = "Heal all",
        tooltipH = 64,
        tooltipTitle = "Heal",
        tooltipLines = {
            "Restore 1 HP and remove all",
            "debuffs for every allied unit.",
        },
    })
end

-- ============================================================
-- HEAL VARIANTS (menu-chosen healing ability)
-- All of them cleanse every negative effect from the target.
-- ============================================================

-- Shared targeting: pick one living playable ally.
local function findAllyAt(state, q, r)
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e:isCharacter() and e.isPlayable then
            return e
        end
    end
    return nil
end

-- FLASH HEAL: +1 HP to a single ally, free.
local FlashHealAbility = {}
FlashHealAbility.__index = FlashHealAbility

function FlashHealAbility.new()
    return setmetatable({
        name = "Flash Heal",
        manaCost = 0,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }, FlashHealAbility)
end

function FlashHealAbility:reset() self.hasBeenUsed = false end
-- Effective only when some ally is wounded or debuffed.
function FlashHealAbility:isEffective(state) return anyAllyNeedsHeal(state) end
function FlashHealAbility:onActivate(state)
    log.info("abilities", "Click on a wounded ally to heal, or press ESC to cancel")
end
function FlashHealAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end
function FlashHealAbility:collectOverlays(hex, cellOverlays, state) highlightHealTargets(hex, cellOverlays, state, true) end
function FlashHealAbility:collectHoverOverlays(hex, cellOverlays, state) highlightHealTargets(hex, cellOverlays, state, true) end
function FlashHealAbility:onClickHex(q, r, hex, state)
    local target = findAllyAt(state, q, r)
    if not target then
        log.warn("abilities", "No valid ally at this cell!")
        return true
    end
    -- Refuse to waste the heal on an ally that would not benefit.
    if not isWoundedOrDebuffed(target) then
        log.warn("abilities", "Target is at full HP with no debuffs!")
        return true
    end
    undo.snapshot()
    if target.health < target.maxHealth then
        target.health = math.min(target.maxHealth, target.health + 1)
    end
    cleanseEntity(target)
    global_abilities.spendAbility(self)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end
function FlashHealAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.3, 0.9, 0.5},
        label = "Flash Heal",
        activeLabel = "Select ally",
        tooltipH = 64,
        tooltipTitle = "Flash Heal",
        tooltipLines = {
            "Restore 1 HP to one ally and",
            "remove all debuffs. Free.",
        },
    })
end

-- STIM PACK: +1 movement for this turn only, free.
local StimPackAbility = {}
StimPackAbility.__index = StimPackAbility

function StimPackAbility.new()
    return setmetatable({
        name = "Stim Pack",
        manaCost = 0,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }, StimPackAbility)
end

function StimPackAbility:reset() self.hasBeenUsed = false end
function StimPackAbility:onActivate(state)
    log.info("abilities", "Click on an ally to boost movement, or press ESC to cancel")
end
function StimPackAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end
function StimPackAbility:collectOverlays(hex, cellOverlays, state) highlightHealTargets(hex, cellOverlays, state, false) end
function StimPackAbility:collectHoverOverlays(hex, cellOverlays, state) highlightHealTargets(hex, cellOverlays, state, false) end
function StimPackAbility:onClickHex(q, r, hex, state)
    local target = findAllyAt(state, q, r)
    if not target then
        log.warn("abilities", "No valid ally at this cell!")
        return true
    end
    undo.snapshot()
    -- Temporary: reverted at the start of the next player turn.
    target.stimPack = (target.stimPack or 0) + 1
    target.moveRange = (target.moveRange or 1) + 1
    cleanseEntity(target)
    global_abilities.spendAbility(self)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end
function StimPackAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.3, 0.8, 1.0},
        label = "Stim Pack",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Stim Pack",
        tooltipLines = {
            "Give one ally +1 movement",
            "this turn and remove all",
            "debuffs. Free; the bonus does",
            "not carry to the next turn.",
        },
    })
end

-- ARMOR PACK: +2 current and max HP to one ally, 1 mana.
local ArmorPackAbility = {}
ArmorPackAbility.__index = ArmorPackAbility

function ArmorPackAbility.new()
    return setmetatable({
        name = "Armor Pack",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }, ArmorPackAbility)
end

function ArmorPackAbility:reset() self.hasBeenUsed = false end
function ArmorPackAbility:onActivate(state)
    log.info("abilities", "Click on an ally to armor them, or press ESC to cancel")
end
function ArmorPackAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end
function ArmorPackAbility:collectOverlays(hex, cellOverlays, state) highlightHealTargets(hex, cellOverlays, state, false) end
function ArmorPackAbility:collectHoverOverlays(hex, cellOverlays, state) highlightHealTargets(hex, cellOverlays, state, false) end
function ArmorPackAbility:onClickHex(q, r, hex, state)
    local target = findAllyAt(state, q, r)
    if not target then
        log.warn("abilities", "No valid ally at this cell!")
        return true
    end
    undo.snapshot()
    target.maxHealth = (target.maxHealth or 0) + 2
    target.health = math.min(target.maxHealth, (target.health or 0) + 2)
    cleanseEntity(target)
    global_abilities.spendAbility(self)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end
function ArmorPackAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.7, 0.7, 0.4},
        label = "Armor Pack",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Armor Pack",
        tooltipLines = {
            "Give one ally +2 current and",
            "maximum HP and remove all",
            "debuffs. Costs 1 mana.",
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
        if target.health <= 0 then
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
        if (terrain == "water" and not (self.target.waterWalker or self.target.hovering))
            or (terrain == "emptiness" and not self.target.hovering) then
            log.warn("abilities", "Cannot shift into water or a void pit!")
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
        local statuses = status.getEntityStatuses(self.target)
        for _, st in ipairs(statuses) do
            if st ~= "empowered" then
                status.removeFromEntity(self.target, st)
            end
        end
        if status.hasAtHex(self.target.q, self.target.r, "fire") then
            status.removeFromHex(self.target.q, self.target.r, "fire")
            log.info("abilities", "Fire on the ground extinguished!")
        end

        -- Animate the 1-cell shift
        local fromQ, fromR = self.target.q, self.target.r
        self.target.q = q
        self.target.r = r
        combat.unrootForcedMove(self.target)
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

    local proxyToReal = {}
    local proxyOf = {}
    local virtualEntities = {}
    for _, e in ipairs(state.entities) do
        if e.health > 0 then
            local proxy = setmetatable({q = e.q, r = e.r}, {__index = e})
            proxyToReal[proxy] = e
            proxyOf[e] = proxy
            virtualEntities[#virtualEntities + 1] = proxy
        end
    end

    local p = attack_preview.new()

    for _, obj in ipairs(movableObjects) do
        if obj.health <= 0 then goto continue end

        local proxy = proxyOf[obj]
        local newQ, newR = hex_utils.applyCubeDiff(proxy.q, proxy.r, step.dx, step.dy, step.dz)

        attack_preview.addPushArrow(p, proxy.q, proxy.r, newQ, newR)

        local col = attack_preview.predictCollision(obj, proxy.q, proxy.r, newQ, newR, hex, virtualEntities)

        if col.type then
            local realOccupant = col.occupant and (proxyToReal[col.occupant] or col.occupant) or nil
            attack_preview.addCollisionHint(p, proxy.q, proxy.r, newQ, newR, col.type, obj, realOccupant, col.reason)
        end
        if col.damage > 0 then
            attack_preview.addCollisionDamage(p, obj, attack_preview.calculateEffectiveCollisionDamage(obj, col.damage))
        end
        if col.occupantDmg > 0 and col.occupant then
            local realOccupant = proxyToReal[col.occupant] or col.occupant
            attack_preview.addCollisionDamage(p, realOccupant, attack_preview.calculateEffectiveCollisionDamage(realOccupant, col.occupantDmg))
        end

        if not col.type then
            proxy.q = newQ
            proxy.r = newR
        end

        ::continue::
    end

    local arrows = attack_preview.buildPushArrows(p, hex)
    ui.drawPreviewPushArrows(arrows)

    local icons = attack_preview.buildIcons(p, hex)
    ui.drawPreviewIcons(hex, icons)
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
    return combat.withDeferredDeaths(function()
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
            local blocker = occupied[fromKey]
            combat.applyCollisionDamage(obj, blocker, sounds)
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, obj.q, obj.r, hex, entities, sounds, blocker)
            occupied[fromKey] = obj
            goto continue
        end

        local oldQ, oldR = obj.q, obj.r
        local newQ, newR = hex_utils.applyCubeDiff(oldQ, oldR, step.dx, step.dy, step.dz)
        if not hex:isActiveHex(newQ, newR) then
            if obj:isCharacter() then
                local wasDestroyed = obj:takeDamage(1)
                combat.notePushKill(obj, wasDestroyed)
                if sounds then sounds.play("collision") end
                if wasDestroyed then obj:startDeath() end
            end
            local fx, fy = getDrawCoords(oldQ, oldR)
            visual.addEffect(fx, fy, "slam")
            combat.addCollisionBounceAnimation(obj, oldQ, oldR, newQ, newR, hex, entities, sounds, nil)
            occupied[fromKey] = obj
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                local obstacle = immovableMap[immovableKey]
                combat.applyCollisionDamage(obj, obstacle, sounds)
                combat.addCollisionBounceAnimation(obj, oldQ, oldR, newQ, newR, hex, entities, sounds, obstacle)
                occupied[fromKey] = obj
            else
                local targetOcc = occupied[newQ .. "," .. newR]
                if targetOcc then
                    combat.applyCollisionDamage(obj, targetOcc, sounds)
                    combat.addCollisionBounceAnimation(obj, oldQ, oldR, newQ, newR, hex, entities, sounds, targetOcc)
                    occupied[fromKey] = obj
                else
                    obj.q = newQ
                    obj.r = newR
                    combat.unrootForcedMove(obj)
                    if terrainMap then
                        local died = effects.applyAllCellEffects(obj, newQ, newR, terrainMap, entities)
                        if died then obj:startDeath() end
                    end
                    combat.addDirectPushAnimation(obj, oldQ, oldR, newQ, newR)
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
    end)
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
        manaCost = 1,
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
        local pts = getElevationCurve(lastQ, lastR, endQ, endR, fx, fy, tx, ty)
        if pts then love.graphics.line(unpack(pts)) else love.graphics.line(fx, fy, tx, ty) end
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
-- JUMPING STRIKE: like Air Strike but damages every other cell
-- ============================================================
local JumpingStrikeAbility = {}
JumpingStrikeAbility.__index = JumpingStrikeAbility

function JumpingStrikeAbility.new()
    local self = {
        name = "Jumping Strike",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        startCell = nil,
    }
    return setmetatable(self, JumpingStrikeAbility)
end

function JumpingStrikeAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.startCell = nil
end

function JumpingStrikeAbility:_getDirection(fromQ, fromR, toQ, toR)
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

function JumpingStrikeAbility:onActivate(state)
    self.phase = "select_start"
    self.startCell = nil
    log.info("abilities", "Click on a hex to start the jumping strike line, or press ESC to cancel")
end

function JumpingStrikeAbility:onDeactivate(state)
    self.phase = nil
    self.startCell = nil
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function JumpingStrikeAbility:onClickHex(q, r, hex, state)
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

        local function processLine(startQ, startR, stepX, stepY, stepZ, hex, state)
            local curQ, curR = startQ, startR
            local distance = 0
            while true do
                curQ, curR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
                if not hex:isActiveHex(curQ, curR) then break end
                distance = distance + 1
                if distance % 2 == 0 then
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
        end

        processLine(self.startCell.q, self.startCell.r, stepX, stepY, stepZ, hex, state)
        processLine(self.startCell.q, self.startCell.r, -stepX, -stepY, -stepZ, hex, state)

        global_abilities.spendAbility(self)
        undo.snapshot()
        log.info("abilities", "Jumping Strike executed!")
        if _G.checkGameEnd then _G.checkGameEnd() end
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        self.phase = nil
        self.startCell = nil
        return true
    end

    return false
end

function JumpingStrikeAbility:collectOverlays(hex, cellOverlays, state)
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

        local function showLine(sx, sy, sz)
            local curQ, curR = self.startCell.q, self.startCell.r
            local distance = 0
            while true do
                curQ, curR = hex_utils.applyCubeStep(curQ, curR, sx, sy, sz)
                if not hex:isActiveHex(curQ, curR) then break end
                distance = distance + 1
                if distance % 2 == 0 then
                    local key = curQ .. "," .. curR
                    cellOverlays[key] = {fill = {1, 0.8, 0.2, 0.4}, line = {1, 0.8, 0.2, 0.8}}
                end
            end
        end

        showLine(stepX, stepY, stepZ)
        showLine(-stepX, -stepY, -stepZ)
    end
end

function JumpingStrikeAbility:drawPreview(hex, state)
    if self.phase == "select_direction" and self.startCell then
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        if hq == self.startCell.q and hr == self.startCell.r then return end
        local stepX, stepY, stepZ = self:_getDirection(self.startCell.q, self.startCell.r, hq, hr)
        if not stepX then return end

        local curQ, curR = self.startCell.q, self.startCell.r
        local lastQ, lastR = curQ, curR
        while true do
            local nq, nr = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
            if not hex:isActiveHex(nq, nr) then break end
            lastQ, lastR = nq, nr
            curQ, curR = nq, nr
        end
        local endQ, endR = lastQ, lastR

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
        local pts = getElevationCurve(lastQ, lastR, endQ, endR, fx, fy, tx, ty)
        if pts then love.graphics.line(unpack(pts)) else love.graphics.line(fx, fy, tx, ty) end
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)

        local icon_cache = require("ui.icon_cache")
        local function drawDamageIcons(sx, sy, sz)
            local cq, cr = self.startCell.q, self.startCell.r
            local distance = 0
            while true do
                cq, cr = hex_utils.applyCubeStep(cq, cr, sx, sy, sz)
                if not hex:isActiveHex(cq, cr) then break end
                distance = distance + 1
                if distance % 2 == 0 then
                    local target = combat.getEntityAtHex(cq, cr, state.entities)
                    if target and target.health > 0 and not target.indestructible then
                        local eff = attack_preview.calculateEffectiveDamage(target, target, 1, nil, nil)
                        local icon = attack_preview.getDamageIcon(target, eff)
                        if icon then
                            local x, y = getDrawCoords(cq, cr)
                            icon_cache.draw(icon, x, y, 0.95)
                        end
                    end
                end
            end
        end

        drawDamageIcons(stepX, stepY, stepZ)
        drawDamageIcons(-stepX, -stepY, -stepZ)
    end
end

function JumpingStrikeAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.6, 0.8, 0.2},
        label = "Jumping Strike",
        activeLabel = self.phase == "select_direction" and "Choose direction" or "Select start",
        tooltipH = 64,
        tooltipTitle = "Jumping Strike",
        tooltipLines = {
            "Wound every other unit in a",
            "straight line for 1 damage.",
        },
    })
end

-- ============================================================
-- OVERLOAD: fatal damage to ally and all adjacent
-- ============================================================
local OverloadAbility = {}
OverloadAbility.__index = OverloadAbility

function OverloadAbility.new()
    local self = {
        name = "Overload",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, OverloadAbility)
end

function OverloadAbility:reset()
    self.hasBeenUsed = false
end

function OverloadAbility:onActivate(state)
    log.info("abilities", "Click on an ally to trigger Overload, or press ESC to cancel")
end

function OverloadAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function OverloadAbility:onClickHex(q, r, hex, state)
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
    log.info("abilities", "Overload activated!")
    if _G.checkGameEnd then _G.checkGameEnd() end
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function OverloadAbility:collectOverlays(hex, cellOverlays, state)
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

function OverloadAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.8, 0.2, 0.8},
        label = "Overload",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Overload",
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
    return e and e.health > 0 and not e.indestructible and not e:isBuilding() and not e:isObstacle() and not e:isEdge()
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
local cell_rules = require("grid.cell_rules")
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
            local pts = getElevationCurve(self.firstTarget.q, self.firstTarget.r, second.q, second.r, fx, fy, sx, sy)
            if pts then love.graphics.line(unpack(pts)) else love.graphics.line(fx, fy, sx, sy) end
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
    local sts = status.getEntityStatuses(target)
    for _, st in ipairs(sts) do
        if st ~= "empowered" then
            status.removeFromEntity(target, st)
        end
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

-- ============================================================
-- VORTEX helper: rotate all units around a center cell
-- ============================================================
local function rotateAroundCenter(centerQ, centerR, unitQ, unitR, clockwise)
    local cx, cy, cz = hex_utils.axialToCube(centerQ, centerR)
    local ux, uy, uz = hex_utils.axialToCube(unitQ, unitR)
    local dx, dy, dz = ux - cx, uy - cy, uz - cz
    local ndx, ndy, ndz = hex_utils.rotateCubeDir(dx, dy, dz, clockwise)
    return hex_utils.cubeToAxial(cx + ndx, cy + ndy, cz + ndz)
end

local function determineRotationDirection(centerQ, centerR, clickQ, clickR)
    local cx, cy, _ = hex_utils.axialToCube(centerQ, centerR)
    local px, py, _ = hex_utils.axialToCube(clickQ, clickR)
    local dx, dy = px - cx, py - cy
    return dx > 0 or (dx == 0 and dy < 0)
end

local function getVortexMoves(centerQ, centerR, radius, clockwise, hex, entities)
    local moving = {}
    for _, e in ipairs(entities) do
        if e.health > 0 and e.isPushable then
            local dist = hex_utils.getDistance(centerQ, centerR, e.q, e.r)
            if dist > 0 and dist <= radius then
                local nq, nr = rotateAroundCenter(centerQ, centerR, e.q, e.r, clockwise)
                table.insert(moving, {entity = e, fromQ = e.q, fromR = e.r, toQ = nq, toR = nr, blocked = false})
            end
        end
    end

    local staticSet = {}
    for _, e in ipairs(entities) do
        if e.health > 0 then
            local isMoving = false
            for _, m in ipairs(moving) do
                if m.entity == e then isMoving = true; break end
            end
            if not isMoving then
                staticSet[e.q .. "," .. e.r] = e
            end
        end
    end

    -- Iteratively mark moves as blocked if their destination is occupied by static entities
    -- or by another rotating unit that cannot leave (blocked). Rotating units that can leave
    -- do not block each other because they all move simultaneously.
    local changed = true
    while changed do
        changed = false
        for i, m in ipairs(moving) do
            if not m.blocked then
                local destKey = m.toQ .. "," .. m.toR
                if not hex:isActiveHex(m.toQ, m.toR) or staticSet[destKey] then
                    m.blocked = true
                    changed = true
                else
                    for j, m2 in ipairs(moving) do
                        if i ~= j then
                            if m.toQ == m2.toQ and m.toR == m2.toR and m2.blocked then
                                m.blocked = true
                                changed = true
                                break
                            end
                            if m.toQ == m2.fromQ and m.toR == m2.fromR and m2.blocked then
                                m.blocked = true
                                changed = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    local moves = {}
    for _, m in ipairs(moving) do
        if m.blocked then
            table.insert(moves, {entity = m.entity, fromQ = m.fromQ, fromR = m.fromR, toQ = m.fromQ, toR = m.fromR, blocked = true})
        else
            table.insert(moves, {entity = m.entity, fromQ = m.fromQ, fromR = m.fromR, toQ = m.toQ, toR = m.toR, blocked = false})
        end
    end
    return moves
end

local function buildVortexCollisionEntities(entities, moves)
    local movingSet = {}
    for _, m in ipairs(moves) do
        movingSet[m.entity] = m.blocked
    end
    local collisionEntities = {}
    for _, e in ipairs(entities) do
        if e.health > 0 then
            local blocked = movingSet[e]
            if blocked == nil or blocked then
                table.insert(collisionEntities, e)
            end
        end
    end
    return collisionEntities
end

local function executeVortex(self, centerQ, centerR, radius, clockwise, hex, entities, sounds, onComplete)
    return combat.withDeferredDeaths(function()
    local moves = getVortexMoves(centerQ, centerR, radius, clockwise, hex, entities)
    local collisionEntities = buildVortexCollisionEntities(entities, moves)

    for _, m in ipairs(moves) do
        if not m.blocked then
            local col = attack_preview.predictCollision(m.entity, m.fromQ, m.fromR, m.toQ, m.toR, hex, collisionEntities)
            if col.type then
                if col.reason == "edge" then
                    local entity = m.entity
                    if entity:isCharacter() then
                        local wasDestroyed = entity:takeDamage(1)
                        combat.notePushKill(entity, wasDestroyed)
                        if sounds then sounds.play("collision") end
                        if wasDestroyed then entity:startDeath() end
                    end
                    local fx, fy = getDrawCoords(m.fromQ, m.fromR)
                    visual.addEffect(fx, fy, "slam")
                elseif col.occupant then
                    combat.applyCollisionDamage(m.entity, col.occupant, sounds)
                end
                combat.addCollisionBounceAnimation(m.entity, m.fromQ, m.fromR, m.toQ, m.toR, hex, collisionEntities, sounds, col.occupant)
            else
                local entity = m.entity
                entity.q = m.toQ
                entity.r = m.toR
                combat.unrootForcedMove(entity)
                if terrainMap then
                    local died = effects.applyAllCellEffects(entity, m.toQ, m.toR, terrainMap, collisionEntities)
                    if died then entity:startDeath() end
                end
                combat.addDirectPushAnimation(entity, m.fromQ, m.fromR, m.toQ, m.toR)
            end
        else
            combat.addCollisionBounceAnimation(m.entity, m.fromQ, m.fromR, m.fromQ, m.fromR, hex, collisionEntities, sounds, nil)
        end
    end
    combat.startPushAnimations(hex, function()
        global_abilities.spendAbility(self)
        if onComplete then onComplete(true) end
        if _G.checkGameEnd then _G.checkGameEnd() end
    end)
    end)
end

-- ============================================================
-- VORTEX (2 mana): rotate all units radius 1
-- ============================================================
local VortexAbility = {}
VortexAbility.__index = VortexAbility

function VortexAbility.new()
    local self = {
        name = "Vortex",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        phase = nil,
        center = nil,
    }
    return setmetatable(self, VortexAbility)
end

function VortexAbility:reset()
    self.hasBeenUsed = false
    self.phase = nil
    self.center = nil
end

function VortexAbility:onActivate(state)
    self.phase = "select_center"
    self.center = nil
    log.info("abilities", "Click on a hex to set the vortex center, or press ESC to cancel")
end

function VortexAbility:onDeactivate(state)
    self.phase = nil
    self.center = nil
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function VortexAbility:onClickHex(q, r, hex, state)
    if self.phase == "select_center" then
        self.center = {q = q, r = r}
        self.phase = "select_direction"
        log.info("abilities", "Click on a hex to choose rotation direction (right=CW, left=CCW)")
        return true
    end
    if self.phase == "select_direction" then
        if q == self.center.q and r == self.center.r then
            log.info("abilities", "Click on a different hex to choose rotation direction")
            return true
        end
        local clockwise = determineRotationDirection(self.center.q, self.center.r, q, r)
        clearSelectedActor()
        undo.snapshot()
        executeVortex(self, self.center.q, self.center.r, 1, clockwise, hex, state.entities, state.sounds, function()
            log.infof("abilities", "Vortex: rotated %s!", clockwise and "clockwise" or "counter-clockwise")
        end)
        restoreSelectedActor()
        global_abilities.activeAbility = nil
        self.phase = nil
        self.center = nil
        return true
    end
    return false
end

function VortexAbility:collectOverlays(hex, cellOverlays, state)
    if self.phase == "select_center" then
        if hex.hoverQ >= 0 and hex.hoverR >= 0 and hex:isActiveHex(hex.hoverQ, hex.hoverR) then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.3, 0.6, 0.9, 0.3}, line = {0.3, 0.6, 0.9, 0.7}}
            local neighbors = hex:getNeighbors(hex.hoverQ, hex.hoverR)
            for _, n in ipairs(neighbors) do
                if hex:isActiveHex(n.q, n.r) then
                    local nk = n.q .. "," .. n.r
                    cellOverlays[nk] = {fill = {0.3, 0.6, 0.9, 0.15}, line = {0.3, 0.6, 0.9, 0.4}}
                end
            end
        end
    elseif self.phase == "select_direction" and self.center then
        local ckey = self.center.q .. "," .. self.center.r
        cellOverlays[ckey] = {fill = {0.3, 0.6, 0.9, 0.4}, line = {0.3, 0.6, 0.9, 0.8}}
        local hq, hr = hex.hoverQ, hex.hoverR
        if hq < 0 or hr < 0 then return end
        if hq == self.center.q and hr == self.center.r then return end
        local clockwise = determineRotationDirection(self.center.q, self.center.r, hq, hr)
        local moves = getVortexMoves(self.center.q, self.center.r, 1, clockwise, hex, state.entities)
        for _, m in ipairs(moves) do
            local key = m.toQ .. "," .. m.toR
            if not m.blocked then
                cellOverlays[key] = {fill = {0.2, 0.8, 0.4, 0.4}, line = {0.2, 0.8, 0.4, 0.8}}
            else
                local fkey = m.fromQ .. "," .. m.fromR
                cellOverlays[fkey] = {fill = {0.8, 0.2, 0.2, 0.3}, line = {0.8, 0.2, 0.2, 0.6}}
            end
        end
    end
end

function VortexAbility:drawPreview(hex, state)
    if self.phase ~= "select_direction" or not self.center then return end
    local hq, hr = hex.hoverQ, hex.hoverR
    if hq < 0 or hr < 0 then return end
    if hq == self.center.q and hr == self.center.r then return end
    local clockwise = determineRotationDirection(self.center.q, self.center.r, hq, hr)
    local moves = getVortexMoves(self.center.q, self.center.r, 1, clockwise, hex, state.entities)
    local collisionEntities = buildVortexCollisionEntities(state.entities, moves)

    local p = attack_preview.new()
    for _, m in ipairs(moves) do
        if not m.blocked then
            attack_preview.addPushArrow(p, m.fromQ, m.fromR, m.toQ, m.toR)
            local col = attack_preview.predictCollision(m.entity, m.fromQ, m.fromR, m.toQ, m.toR, hex, collisionEntities)
            if col.type then
                attack_preview.addCollisionHint(p, m.fromQ, m.fromR, m.toQ, m.toR, col.type, m.entity, col.occupant, col.reason)
            end
            if col.damage > 0 then
                attack_preview.addCollisionDamage(p, m.entity, attack_preview.calculateEffectiveCollisionDamage(m.entity, col.damage))
            end
            if col.occupantDmg > 0 and col.occupant then
                attack_preview.addCollisionDamage(p, col.occupant, attack_preview.calculateEffectiveCollisionDamage(col.occupant, col.occupantDmg))
            end
        else
            attack_preview.addCollisionHint(p, m.fromQ, m.fromR, m.fromQ, m.fromR, "collision_no_damage", m.entity, nil, "blocked")
        end
    end

    local arrows = attack_preview.buildPushArrows(p, hex)
    ui.drawPreviewPushArrows(arrows)
    local icons = attack_preview.buildIcons(p, hex)
    ui.drawPreviewIcons(hex, icons)
end

function VortexAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.3, 0.6, 0.9},
        label = "Vortex",
        activeLabel = self.phase == "select_direction" and "Choose direction" or "Select center",
        tooltipH = 80,
        tooltipTitle = "Vortex",
        tooltipLines = {
            "Rotate all units 60 deg around",
            "a center cell. Right side = CW,",
            "left side = CCW. Radius: 1.",
        },
    })
end

-- ============================================================
-- HEX: permanently transform an enemy into a cowardly beast
-- ============================================================
local function generateCowardlyBeastSprite()
    local size = 16
    local canvas = love.graphics.newCanvas(size, size)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    -- Body (hunched, purple-beige)
    love.graphics.setColor(0.5, 0.35, 0.55, 1)
    love.graphics.ellipse("fill", 8, 11, 5, 4)
    -- Head (slightly tilted, wide eyes)
    love.graphics.setColor(0.55, 0.4, 0.5, 1)
    love.graphics.circle("fill", 7, 7, 3)
    -- Big scared eyes
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 5, 6, 2, 2)
    love.graphics.rectangle("fill", 9, 6, 2, 2)
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.rectangle("fill", 5, 7, 1, 1)
    love.graphics.rectangle("fill", 9, 7, 1, 1)
    -- Mouth (open, scared)
    love.graphics.setColor(0.1, 0.05, 0.05, 1)
    love.graphics.rectangle("fill", 6, 9, 2, 1)
    -- Tiny arms covering
    love.graphics.setColor(0.45, 0.3, 0.5, 1)
    love.graphics.rectangle("fill", 3, 9, 2, 3)
    love.graphics.rectangle("fill", 11, 9, 2, 3)
    -- Legs
    love.graphics.setColor(0.4, 0.28, 0.48, 1)
    love.graphics.rectangle("fill", 5, 14, 2, 2)
    love.graphics.rectangle("fill", 9, 14, 2, 2)
    love.graphics.setCanvas()
    return canvas
end

local HexAbility = {}
HexAbility.__index = HexAbility

function HexAbility.new()
    local self = {
        name = "Hex",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, HexAbility)
end

function HexAbility:reset()
    self.hasBeenUsed = false
end

function HexAbility:onActivate(state)
    log.info("abilities", "Click on an enemy to transform it into a cowardly beast, or press ESC to cancel")
end

function HexAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function HexAbility:onClickHex(q, r, hex, state)
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

    local originalName = target.name
    undo.snapshot()
    target.attacks = {}
    target.health = 1
    target.maxHealth = 1
    target.name = "CowardlyBeast"
    target.isCowardlyBeast = true
    target.sprite = generateCowardlyBeastSprite()
    target.color = nil
    target.hasPreparedAttack = false
    target.attackDirection = nil
    target.preparedTargetOffset = nil
    target.preparedAttack = nil
    target.preparedTargetQ = nil
    target.preparedTargetR = nil
    if target.rootedTarget then
        status.removeFromEntity(target.rootedTarget, "rooted")
        target.rootedTarget = nil
    end

    global_abilities.spendAbility(self)
    log.infof("abilities", "%s transformed into a cowardly beast!", originalName)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function HexAbility:collectOverlays(hex, cellOverlays, state)
    if hex.hoverQ < 0 or hex.hoverR < 0 then return end
    for _, e in ipairs(state.entities) do
        if e.q == hex.hoverQ and e.r == hex.hoverR and e.health > 0 and e:isCharacter() and not e.isPlayable then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.6, 0.2, 0.8, 0.4}, line = {0.6, 0.2, 0.8, 0.8}}
            break
        end
    end
end

function HexAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.6, 0.2, 0.8},
        label = "Hex",
        activeLabel = "Select enemy",
        tooltipH = 80,
        tooltipTitle = "Hex",
        tooltipLines = {
            "Transform an enemy into a",
            "cowardly beast (1 HP, no",
            "attacks, avoids players).",
        },
    })
end

-- ============================================================
-- VOID: turn a cell into empty (banish entities, clear statuses)
-- ============================================================
local VoidAbility = {}
VoidAbility.__index = VoidAbility

function VoidAbility.new()
    local self = {
        name = "Void",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, VoidAbility)
end

function VoidAbility:reset()
    self.hasBeenUsed = false
end

function VoidAbility:onActivate(state)
    log.info("abilities", "Click on a cell to turn it into empty, or press ESC to cancel")
end

function VoidAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function VoidAbility:onClickHex(q, r, hex, state)
    if not hex:isActiveHex(q, r) then return true end

    undo.snapshot()

    -- Banish every destructible non-playable entity on the cell
    for i = #state.entities, 1, -1 do
        local e = state.entities[i]
        if e.q == q and e.r == r and not e.isPlayable and not e.indestructible and e.health and e.health > 0 then
            table.remove(state.entities, i)
        end
    end

    -- Destroying a teleporter disables its pair forever (before clearing
    -- the marker — destroy reads it from the upper terrain)
    local teleporters = require("system.teleporters")
    teleporters.destroy(q, r, state.upperTerrainMap)

    -- Clear hex statuses (fire, acid, decay), dig sites and rubble
    status.hexStatuses[q .. "," .. r] = nil
    status.removeDigSite(q, r)
    if state.upperTerrainMap and state.upperTerrainMap[q] then
        state.upperTerrainMap[q][r] = nil
    end

    -- Turn the cell itself into emptiness
    if state.terrainMap then
        if not state.terrainMap[q] then state.terrainMap[q] = {} end
        state.terrainMap[q][r] = "emptiness"
    end
    if _G.hex and _G.hex.invalidateSortedCells then _G.hex:invalidateSortedCells() end

    if visual then
        local x, y = getDrawCoords(q, r)
        visual.addMagicExplosion(x, y, 1.0, 0.7, 0.2)
    end

    global_abilities.spendAbility(self)
    sounds.play("blip")
    if _G.rebuildEntityIndex then _G.rebuildEntityIndex() end
    if _G.checkGameEnd then _G.checkGameEnd() end
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function VoidAbility:collectOverlays(hex, cellOverlays, state)
    if hex.hoverQ < 0 or hex.hoverR < 0 then return end
    local key = hex.hoverQ .. "," .. hex.hoverR
    if hex:isActiveHex(hex.hoverQ, hex.hoverR) then
        cellOverlays[key] = {fill = {0.7, 0.4, 0.9, 0.35}, line = {0.7, 0.4, 0.9, 0.8}}
    end
end

function VoidAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.7, 0.4, 0.9},
        label = "Void",
        activeLabel = "Select cell",
        tooltipH = 80,
        tooltipTitle = "Void",
        tooltipLines = {
            "Turn a cell into emptiness:",
            "banish enemies, clear fire/",
            "acid, dig sites and rubble.",
        },
    })
end

-- ============================================================
-- UPSIDE DOWN: kill a creature, remains fly up, fall at end of turn
-- ============================================================
local UpsideDownAbility = {}
UpsideDownAbility.__index = UpsideDownAbility

function UpsideDownAbility.new()
    local self = {
        name = "Upside Down",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, UpsideDownAbility)
end

function UpsideDownAbility:reset()
    self.hasBeenUsed = false
end

function UpsideDownAbility:onActivate(state)
    log.info("abilities", "Click on a creature to launch it upward, or press ESC to cancel")
end

function UpsideDownAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function UpsideDownAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e:isCharacter() then
            target = e
            break
        end
    end

    if not target then
        log.warn("abilities", "No valid creature at this cell!")
        return true
    end

    local x, y = getDrawCoords(q, r)
    visual.addRisingRemains(x, y, target.sprite, target.color)

    target.health = 0
    target:startDeath()

    global_abilities.addPendingRemains(q, r)

    global_abilities.spendAbility(self)
    undo.snapshot()
    log.infof("abilities", "%s launched upward! Remains will fall at end of turn.", tostring(target.name))
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function UpsideDownAbility:collectOverlays(hex, cellOverlays, state)
    if hex.hoverQ < 0 or hex.hoverR < 0 then return end
    for _, e in ipairs(state.entities) do
        if e.q == hex.hoverQ and e.r == hex.hoverR and e.health > 0 and e:isCharacter() then
            local key = hex.hoverQ .. "," .. hex.hoverR
            cellOverlays[key] = {fill = {0.9, 0.3, 0.1, 0.4}, line = {0.9, 0.3, 0.1, 0.8}}
            break
        end
    end
end

function UpsideDownAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.9, 0.3, 0.1},
        label = "Upside Down",
        activeLabel = "Select creature",
        tooltipH = 96,
        tooltipTitle = "Upside Down",
        tooltipLines = {
            "Kill a creature. Its remains",
            "fly up and fall at end of turn,",
            "dealing fatal damage to that cell.",
        },
    })
end

-- Pending remains system
global_abilities.pendingRemains = {}

function global_abilities.addPendingRemains(q, r)
    table.insert(global_abilities.pendingRemains, {q = q, r = r})
end

function global_abilities.hasPendingRemains()
    return #global_abilities.pendingRemains > 0
end

function global_abilities.processPendingRemains(entities, hex, sounds)
    for _, remains in ipairs(global_abilities.pendingRemains) do
        local x, y = getDrawCoords(remains.q, remains.r)
        visual.addFallingRemains(x, y)

        for _, e in ipairs(entities) do
            if e.q == remains.q and e.r == remains.r and e.health > 0 and not e.indestructible and not e:isEdge() then
                e.health = 0
                e:startDeath()
                log.infof("abilities", "Remains fell on %s, dealing fatal damage!", tostring(e.name))
            end
        end
    end
    global_abilities.pendingRemains = {}
end

function global_abilities.resetPendingRemains()
    global_abilities.pendingRemains = {}
end

-- ============================================================
-- TELEPORT: grant chosen ally teleportation for the rest of the battle, 1 mana
-- ============================================================
local TeleportAbility = {}
TeleportAbility.__index = TeleportAbility

function TeleportAbility.new()
    local self = {
        name = "Teleport",
        manaCost = 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, TeleportAbility)
end

function TeleportAbility:reset()
    self.hasBeenUsed = false
end

function TeleportAbility:onActivate(state)
    log.info("abilities", "Click on an ally to grant teleportation, or press ESC to cancel")
end

function TeleportAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function TeleportAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 and e:isCharacter() and e.isPlayable then
            target = e
            break
        end
    end
    if not target then
        log.warn("abilities", "No valid ally at this cell!")
        return true
    end
    
    if target.teleporting then
        log.warn("abilities", "Ally already has teleportation!")
        return true
    end
    
    undo.snapshot()
    target.teleporting = true
    log.infof("abilities", "%s gained teleportation!", tostring(target.name))
    
    global_abilities.spendAbility(self)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function TeleportAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.4, 0.7, 1.0},
        label = "Teleport",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Teleport",
        tooltipLines = {
            "Grant an ally the ability",
            "to teleport anywhere on",
            "the map for the rest of",
            "the battle.",
        },
    })
end

-- ============================================================
-- SPEED BOOST
-- ============================================================
local SpeedBoostAbility = {}
SpeedBoostAbility.__index = SpeedBoostAbility

function SpeedBoostAbility.new()
    local self = {
        name = "Speed Boost",
        manaCost = 0,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, SpeedBoostAbility)
end

function SpeedBoostAbility:reset()
    self.hasBeenUsed = false
end

function SpeedBoostAbility:onActivate(state)
    log.info("abilities", "Click on an ally to boost their speed, or press ESC to cancel")
end

function SpeedBoostAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function SpeedBoostAbility:onClickHex(q, r, hex, state)
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
    if target.health <= 0 then
        log.warn("abilities", "Cannot target dead units!")
        return true
    end

    undo.snapshot()
    target.moveRange = (target.moveRange or 1) + 1
    log.infof("abilities", "%s movement speed increased to %d!", tostring(target.name), target.moveRange)
    
    global_abilities.spendAbility(self)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function SpeedBoostAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.9, 0.9, 0.2},
        label = "Speed Boost",
        activeLabel = "Select ally",
        tooltipH = 80,
        tooltipTitle = "Speed Boost",
        tooltipLines = {
            "Increase an ally's movement",
            "speed by 1 for the rest of",
            "the battle. Free ability.",
        },
    })
end

-- ============================================================
-- RESPAWN ALLY: per-ally ghost summon buttons.
-- `isSummon` snapshots get a "Revive <name>" button instead that brings back
-- the real summon (full HP, AP, movement spent for this turn), once per summon.
-- ============================================================
local RespawnAllyAbility = {}
RespawnAllyAbility.__index = RespawnAllyAbility

function RespawnAllyAbility.new(snapshot)
    local revive = snapshot.isSummon and true or false
    local self = {
        name = (revive and "Revive " or "Respawn ") .. snapshot.name,
        displayName = (revive and "Revive " or "Respawn ") .. snapshot.name,
        manaCost = revive and 2 or 1,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
        revive = revive,
        snapshot = snapshot,
    }
    return setmetatable(self, RespawnAllyAbility)
end

function RespawnAllyAbility:reset()
    self.hasBeenUsed = false
end

function RespawnAllyAbility:onActivate(state)
    log.infof("abilities", "Click an empty hex to summon %s's ghost, or press ESC to cancel", self.snapshot.name)
end

function RespawnAllyAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function RespawnAllyAbility:collectOverlays(hex, cellOverlays, state)
    for _, ac in ipairs(hex._activeCells) do
        local occupied = false
        for _, e in ipairs(state.entities) do
            if e.q == ac.q and e.r == ac.r and e.health > 0 then
                occupied = true
                break
            end
        end
        if not occupied then
            local terrain = state.terrainMap and state.terrainMap[ac.q] and state.terrainMap[ac.q][ac.r] or "grass"
            if terrain ~= "water" then
                table.insert(cellOverlays, { q = ac.q, r = ac.r, color = {0.4, 0.6, 1, 0.4}, label = "ghost" })
            end
        end
    end
end

function RespawnAllyAbility:onClickHex(q, r, hex, state)
    -- Check hex is empty
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r and e.health > 0 then
            log.warn("abilities", "That cell is occupied!")
            return true
        end
    end

    -- Check terrain is passable
    local terrain = state.terrainMap and state.terrainMap[q] and state.terrainMap[q][r] or "grass"
    if terrain == "water" then
        log.warn("abilities", "Cannot summon on water!")
        return true
    elseif terrain == "emptiness" then
        log.warn("abilities", "Cannot summon into a void pit!")
        return true
    end

    -- Remove snapshot from graveyard and unregister this button
    local g = _G.graveyard
    local snapshot = nil
    if g then
        for i, s in ipairs(g) do
            if s == self.snapshot then
                snapshot = table.remove(g, i)
                break
            end
        end
    end
    if not snapshot then
        log.warn("abilities", "This ally has already been respawned!")
        global_abilities.activeAbility = nil
        return true
    end

    global_abilities.registry[self.name] = nil

    undo.snapshot()

    local spawned
    if self.revive then
        _G.summonReviveUsed = _G.summonReviveUsed or {}
        _G.summonReviveUsed[snapshot.name] = true
        spawned = Entity.new(
            snapshot.name,
            Entity.TYPES.CHARACTER,
            q, r,
            snapshot.maxHealth or 2, true,
            snapshot.moveRange or 1,
            snapshot.sprite,
            snapshot.color,
            snapshot.attacks or {}
        )
        spawned.isSummon = true
        spawned.multiAction = true
        spawned.maxAttacks = snapshot.maxAttacks or 1
        spawned.maxMoves = snapshot.maxMoves or 1
        spawned.attacksLeft = spawned.maxAttacks
        -- Movement is spent for the turn of the revival; turn transition refills it.
        spawned.movesLeft = 0
        if snapshot.pushSpike then spawned.pushSpike = true end
        if snapshot.flipPad then spawned.flipPad = true end
        if snapshot.passives then spawned.passives = snapshot.passives end
        log.infof("abilities", "%s revived at (%d,%d) with movement spent this turn!", snapshot.name, q, r)
    else
        spawned = Entity.new(
            snapshot.name .. " Ghost",
            Entity.TYPES.CHARACTER,
            q, r,
            1, true,
            snapshot.moveRange or 1,
            snapshot.sprite,
            snapshot.color and {snapshot.color[1], snapshot.color[2], snapshot.color[3], 0.7} or {0.5, 0.7, 1, 0.7},
            {}
        )
        log.infof("abilities", "%s's ghost summoned at (%d,%d)! Move range: %d", snapshot.name, q, r, spawned.moveRange)
    end
    spawned.hovering = snapshot.hovering or false
    spawned.teleporting = snapshot.teleporting or false
    spawned.waterWalker = snapshot.waterWalker or false
    spawned.hasMovedThisTurn = false
    spawned.hasActedThisTurn = false

    table.insert(state.entities, spawned)

    local x, y = hex:hexToPixel(q, r)
    if visual and visual.addEffect then
        visual.addEffect(x, y, "heal", 0.6)
    end

    global_abilities.spendAbility(self)
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function RespawnAllyAbility:drawButton(mx, my, state)
    local lines, title
    if self.revive then
        title = "Revive " .. self.snapshot.name
        lines = {
            "Revive " .. self.snapshot.name .. " at full HP.",
            "Spawns with its actions, but",
            "cannot move this turn.",
        }
    else
        title = "Respawn " .. self.snapshot.name
        lines = {
            "Summon a ghost of " .. self.snapshot.name .. ".",
            "Inherits movement traits.",
            "Spawns with 1 HP.",
        }
    end
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = self.revive and {0.6, 0.4, 1} or {0.4, 0.6, 1},
        label = self.displayName,
        activeLabel = "Pick hex",
        tooltipH = 80,
        tooltipTitle = title,
        tooltipLines = lines,
    })
end

-- Sync graveyard entries with registry buttons
function global_abilities.syncGraveyardAbilities()
    local g = _G.graveyard
    if not g then return end

    -- Remove buttons for entries no longer in graveyard
    local toRemove = {}
    for name, ab in pairs(global_abilities.registry) do
        if ab.snapshot then
            local found = false
            for _, s in ipairs(g) do
                if s == ab.snapshot then found = true; break end
            end
            if not found then
                table.insert(toRemove, name)
            end
        end
    end
    for _, name in ipairs(toRemove) do
        global_abilities.registry[name] = nil
    end

    -- Add buttons for new graveyard entries
    for _, snapshot in ipairs(g) do
        local key = (snapshot.isSummon and "Revive " or "Respawn ") .. snapshot.name
        if not global_abilities.registry[key] then
            global_abilities.registry[key] = RespawnAllyAbility.new(snapshot)
        end
    end
end

function global_abilities.clearGraveyardAbilities()
    local toRemove = {}
    for name, ab in pairs(global_abilities.registry) do
        if ab.snapshot then
            table.insert(toRemove, name)
        end
    end
    for _, name in ipairs(toRemove) do
        global_abilities.registry[name] = nil
    end
end

-- ============================================================
-- INFEST: pick a specific enemy and deal 1 damage to it; the cast
-- harms no one (Blade survives). If that damage is lethal, an ally
-- (1 HP) spawns on the enemy's cell. That summoned "Infested" unit
-- is a disposable sacrifice: its shot pushes the first unit along a
-- line (no damage) and then it dies; it also dies at end of turn.
-- ============================================================
local InfestAbility = {}
InfestAbility.__index = InfestAbility

-- The summoned unit's shot: line push (no damage), then the attacker
-- (the Infested itself) is sacrificed.
local InfestedShotAttack = setmetatable({}, combat.LineShotAttack)
InfestedShotAttack.__index = InfestedShotAttack

function InfestedShotAttack.new()
    local self = combat.LineShotAttack.new("Infest Shot",
        "Shoot a line, pushing the first unit. The attacker is consumed.", math.huge, 0)
    return setmetatable(self, InfestedShotAttack)
end

function InfestedShotAttack:execute(attacker, q, r, hex, entities, sounds)
    local ok, err = combat.LineShotAttack.execute(self, attacker, q, r, hex, entities, sounds)
    if ok and attacker.health > 0 and not attacker.isDying then
        attacker.health = 0
        attacker:startDeath()
    end
    return ok, err
end

function InfestAbility.new()
    local self = {
        name = "Infest",
        manaCost = 2,
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, InfestAbility)
end

function InfestAbility:reset()
    self.hasBeenUsed = false
end

function InfestAbility:onActivate(state)
    clearSelectedActor()
    log.info("abilities", "Click an enemy to infest it, or press ESC to cancel")
end

function InfestAbility:onDeactivate(state)
    restoreSelectedActor()
    log.infof("abilities", "%s cancelled", self.name)
end

function InfestAbility:onClickHex(q, r, hex, state)
    local target = combat.getEntityAtHex(q, r, state.entities)
    if not target or not target:isCharacter() or target.isPlayable then
        log.warn("abilities", "Infest: click an enemy!")
        return true
    end
    if target.health <= 0 then
        log.warn("abilities", "Infest: target is already dead!")
        return true
    end

    local targetQ, targetR = q, r

    combat.withDeferredDeaths(function()
        -- Infest's own 1 damage; if it kills the enemy, spawn an Infested ally on its cell
        local lineAtk = combat.Attack.new("Infest", "Infest", math.huge, 1)
        local wasDestroyed = lineAtk:dealDamageToTarget(target, _G.hero, 1, state.entities, sounds, nil)
        if wasDestroyed then
            -- Drop the dying corpse so the summoned ally takes the cell cleanly.
            for i = #state.entities, 1, -1 do
                local o = state.entities[i]
                if o.q == targetQ and o.r == targetR then
                    table.remove(state.entities, i)
                end
            end
            local sprite = environment.unitSpriteCache and environment.unitSpriteCache[42]
            local shot = InfestedShotAttack.new()
            local victim = Entity.new("Infested", Entity.TYPES.CHARACTER, targetQ, targetR,
                1, true, 2, sprite, nil, {
                { attack = shot, name = shot.name, description = shot.description },
            })
            victim.maxAttacks = 1
            victim.maxMoves = 2
            victim.diesAtEndOfTurn = true
            table.insert(state.entities, victim)
        end
    end)

    global_abilities.spendAbility(self)
    undo.snapshot()

    if visual then
        local x, y = getDrawCoords(targetQ, targetR)
        visual.addMagicExplosion(x, y, 0.8, 0.5, 0.1)
    end
    sounds.play("summon_attack")
    if _G.rebuildEntityIndex then _G.rebuildEntityIndex() end
    if _G.checkGameEnd then _G.checkGameEnd() end
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function InfestAbility:collectOverlays(hex, cellOverlays, state)
    -- Highlight every clickable enemy.
    for _, e in ipairs(state.entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            local key = e.q .. "," .. e.r
            local hovered = (hex.hoverQ == e.q and hex.hoverR == e.r)
            cellOverlays[key] = hovered
                and { fill = {1, 0.3, 0.2, 0.55}, line = {1, 0.3, 0.2, 1.0} }
                or { fill = {0.8, 0.3, 0.1, 0.4}, line = {1, 0.4, 0.2, 0.8} }
        end
    end
end

function InfestAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.8, 0.3, 0.1},
        label = "Infest",
        activeLabel = "Select enemy",
        tooltipH = 96,
        tooltipTitle = "Infest",
        tooltipLines = {
            "Deal 1 damage to a specific",
            "enemy. If lethal, an Infested",
            "ally (1 HP) spawns on its cell.",
            "Its shot pushes the first unit,",
            "then it dies (also at end of turn).",
        },
    })
end

-- Register all abilities
global_abilities.register(HealAbility.new())
global_abilities.register(FlashHealAbility.new())
global_abilities.register(StimPackAbility.new())
global_abilities.register(ArmorPackAbility.new())
global_abilities.register(ExtraMoveAbility.new())
global_abilities.register(WindTorrent.new())
global_abilities.register(UnearthAbility.new())
global_abilities.register(MindControlAbility.new())
global_abilities.register(AccelerateDecayAbility.new())
global_abilities.register(ForceAttackAbility.new())
global_abilities.register(RageAbility.new())
global_abilities.register(TheBigOneAbility.new())
global_abilities.register(AirStrikeAbility.new())
global_abilities.register(JumpingStrikeAbility.new())
global_abilities.register(OverloadAbility.new())
global_abilities.register(ChainLightningAbility.new())
global_abilities.register(InvulnerabilityAbility.new())
global_abilities.register(VortexAbility.new())
global_abilities.register(HexAbility.new())
global_abilities.register(UpsideDownAbility.new())
global_abilities.register(TeleportAbility.new())
global_abilities.register(SpeedBoostAbility.new())
global_abilities.register(VoidAbility.new())
global_abilities.register(InfestAbility.new())

return global_abilities
