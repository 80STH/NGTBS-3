-- global_abilities.lua
-- Модульная система одноразовых способностей.
-- Каждая способность — независимый объект со своим hasBeenUsed, кнопкой, хоткеем.
-- Все способности доступны одновременно (не mutually exclusive в плане использования,
-- но только одна может быть в режиме выбора цели).

local ui = require("ui")
local combat = require("combat")
local hex_utils = require("hex_utils")
local status = require("status")
local environment = require("environment")

local global_abilities = {}

global_abilities.registry = {}
global_abilities.activeAbility = nil
global_abilities.dropdownOpen = false
global_abilities.abilityOrder = {"Heal", "Extra Move", "Wind Torrent", "Unearth", "Mind Control", "Accelerate Decay"}

local function getDropdownHeader()
    local screenW = love.graphics.getWidth()
    local w = 145
    local x = screenW - w - 200
    return { x = x, y = 10, w = w, h = 26 }
end

function global_abilities.register(obj)
    global_abilities.registry[obj.name] = obj
end

function global_abilities.reset()
    global_abilities.activeAbility = nil
    for _, ab in pairs(global_abilities.registry) do
        if ab.reset then ab:reset() end
        ab.hasBeenUsed = false
    end
end

local itemH = 28

local function getAbilityItemRect(index)
    local h = getDropdownHeader()
    local itemY = h.y + h.h + (index - 1) * itemH
    return h.x, itemY, h.w, itemH
end

function global_abilities.handleButtonClick(x, y, state)
    local h = getDropdownHeader()
    if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then
        global_abilities.dropdownOpen = not global_abilities.dropdownOpen
        return true
    end
    if not global_abilities.dropdownOpen then return false end
    for i, name in ipairs(global_abilities.abilityOrder) do
        local ab = global_abilities.registry[name]
        if ab then
            local ix, iy, iw, ih = getAbilityItemRect(i)
            if x >= ix and x <= ix + iw and y >= iy and y <= iy + ih then
                if state.turnState.phase == "player" and not ab.hasBeenUsed then
                    if global_abilities.activeAbility then
                        global_abilities.activeAbility:onDeactivate(state)
                    end
                    global_abilities.activeAbility = ab
                    ab:onActivate(state)
                    global_abilities.dropdownOpen = false
                elseif ab.hasBeenUsed then
                    print(ab.name .. " has already been used this game!")
                elseif state.turnState.phase ~= "player" then
                    print("Can only use abilities during your turn!")
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
        print(ab.name .. " cancelled")
        return true
    end
end

function global_abilities.handleKey(key, state)
    for _, ab in pairs(global_abilities.registry) do
        if key == ab.key then
            if state.turnState.phase == "player" and not ab.hasBeenUsed then
                if global_abilities.activeAbility then
                    global_abilities.activeAbility:onDeactivate(state)
                end
                global_abilities.activeAbility = ab
                ab:onActivate(state)
            elseif ab.hasBeenUsed then
                print(ab.name .. " has already been used this game!")
            elseif state.turnState.phase ~= "player" then
                print("Can only use abilities during your turn!")
            end
            return true
        end
    end
    if key == "escape" and global_abilities.activeAbility then
        global_abilities.activeAbility:onDeactivate(state)
        global_abilities.activeAbility = nil
        return true
    end
    return false
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
    local buttonFont = love.graphics.newFont(11)

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
    love.graphics.printf("Abilities " .. icon, h.x, h.y + 7, h.w, "center")
    love.graphics.setFont(oldFont)

    if not global_abilities.dropdownOpen then return end

    -- Items
    for i, name in ipairs(global_abilities.abilityOrder) do
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
    love.graphics.setColor(1, 1, 1, 1)
end

-- Начисление previewDamage только для зданий (для глобальных воздействий)
function global_abilities.previewBuildingDamage(globalHealth, damagedEntities)
    if not globalHealth then return end
    for _, dmg in ipairs(damagedEntities) do
        if dmg.entity and dmg.entity:isBuilding() and dmg.entity.health > 0 then
            local actual = math.min(dmg.damage or 1, dmg.entity.health)
            globalHealth.previewDamage = (globalHealth.previewDamage or 0) + actual
        end
    end
end

function global_abilities.drawAbilityButton(self, mx, my, state, cfg)
    local isActive = (global_abilities.activeAbility == self)
    local available = (state.turnState.phase == "player" and not self.hasBeenUsed)
    local x, y, w, h = self.button.x, self.button.y, self.button.width, self.button.height
    local buttonFont = love.graphics.newFont(11)
    local logicalW = love.graphics.getWidth()

    local cr, cg, cb = cfg.color[1], cfg.color[2], cfg.color[3]
    love.graphics.setColor(available and cr or 0.5, available and cg or 0.5, available and cb or 0.5, isActive and 0.5 or 0.8)
    love.graphics.rectangle("fill", x, y, w, h, 5)
    love.graphics.setColor(1, 1, 1, 1)
    local old = love.graphics.getFont()
    love.graphics.setFont(buttonFont)
    love.graphics.printf(isActive and cfg.activeLabel or cfg.label, x, y + 9, w, "center")
    love.graphics.setFont(old)

    local isHover = mx and my and mx >= x and mx <= x + w and my >= y and my <= y + h
    if isHover then
        local usedText = self.hasBeenUsed and " (used)" or ""
        local tooltipW = 260
        local tx, ty = x + w + 6, y
        if tx + tooltipW > logicalW - 10 then tx = x - tooltipW - 6 end
        if ty + cfg.tooltipH > logicalH - 10 then ty = logicalH - cfg.tooltipH - 10 end
        love.graphics.setColor(0.1, 0.1, 0.2, 0.95)
        love.graphics.rectangle("fill", tx, ty, tooltipW, cfg.tooltipH, 6)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.rectangle("line", tx, ty, tooltipW, cfg.tooltipH, 6)
        love.graphics.setColor(1, 1, 0.6, 1)
        love.graphics.print(cfg.tooltipTitle .. usedText, tx + 8, ty + 6)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        for i, line in ipairs(cfg.tooltipLines) do
            love.graphics.print(line, tx + 8, ty + 20 + (i - 1) * 16)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- ============================================================
-- UNEARTH: все выкопки немедленно срабатывают
-- ============================================================
local UnearthAbility = {}
UnearthAbility.__index = UnearthAbility

function UnearthAbility.new()
    local self = {
        name = "Unearth",
        key = "u",
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, UnearthAbility)
end

function UnearthAbility:reset()
    self.hasBeenUsed = false
end

function UnearthAbility:onActivate(state)
    local spawned = 0
    local digSites = status.getAllDigSites()
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
            if terrain ~= "water" and not status.hasNegativeHexStatus(site.q, site.r) then
                local newEnemy = environment.createRandomEnemy(site.q, site.r)
                table.insert(state.entities, newEnemy)
                spawned = spawned + 1
            end
        end
        status.removeDigSite(site.q, site.r)
    end
    self.hasBeenUsed = true
    state.actionHistory = {}
    global_abilities.activeAbility = nil
    print("Unearth: " .. spawned .. " enemies emerged!")
    if _G.checkGameEnd then _G.checkGameEnd() end
end

function UnearthAbility:onDeactivate(state)
end

function UnearthAbility:onClickHex(q, r, hex, state)
    return false
end

function UnearthAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.7, 0.5, 0.2},
        label = "Unearth (U)",
        activeLabel = "Unearth (U)",
        tooltipH = 64,
        tooltipTitle = "Unearth",
        tooltipLines = {
            "All enemies in dig sites",
            "immediately emerge.",
        },
    })
end

-- ============================================================
-- MIND CONTROL: переместить врага на 1 клетку
-- ============================================================
local MindControlAbility = {}
MindControlAbility.__index = MindControlAbility

function MindControlAbility.new()
    local self = {
        name = "Mind Control",
        key = "m",
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
    print("Click on an enemy to mind control, or press ESC to cancel")
end

function MindControlAbility:onDeactivate(state)
    self.phase = nil
    self.target = nil
    restoreSelectedActor()
    print(self.name .. " cancelled")
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
            print("No valid enemy at this cell!")
            return true
        end
        self.target = target
        self.phase = "select_dest"
        print("Now click on an adjacent empty cell to move " .. tostring(target.name) .. " to")
        return true
    end

    if self.phase == "select_dest" then
        if not self.target then
            self:onDeactivate(state)
            return true
        end
        if q == self.target.q and r == self.target.r then
            print("Target is already at this cell!")
            return true
        end
        local dist = hex:getDistance(self.target.q, self.target.r, q, r)
        if dist ~= 1 then
            print("Destination must be adjacent!")
            return true
        end
        if not hex:isActiveHex(q, r) then
            print("Invalid destination!")
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
            print("Destination is occupied!")
            return true
        end
        self.target.q = q
        self.target.r = r
        self.hasBeenUsed = true
        state.actionHistory = {}
        print(tostring(self.target.name) .. " moved by mind control!")
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
        label = "Mind Control (M)",
        activeLabel = self.phase == "select_dest" and "Choose destination (M)" or "Select enemy (M)",
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
-- ACCELERATE DECAY: уменьшает макс. ходов до decay на 1
-- ============================================================
local AccelerateDecayAbility = {}
AccelerateDecayAbility.__index = AccelerateDecayAbility

function AccelerateDecayAbility.new()
    local self = {
        name = "Accelerate Decay",
        key = "d",
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
        print("Decay accelerated! Max turns reduced to " .. state.maxTurns)
    end
    self.hasBeenUsed = true
    state.actionHistory = {}
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
        label = "Accel. Decay (D)",
        activeLabel = "Accel. Decay (D)",
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
        key = "h",
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, HealAbility)
end

function HealAbility:reset()
    self.hasBeenUsed = false
end

function HealAbility:onActivate(state)
    print("Click on an ally to heal, or press ESC to cancel")
end

function HealAbility:onDeactivate(state)
    restoreSelectedActor()
    print(self.name .. " cancelled")
end

function HealAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r then
            target = e
            break
        end
    end

    if not target or target.health <= 0 or target:isBuilding() then
        print("No valid target!")
        return true
    end

    local hasDebuffs = #status.getEntityStatuses(target) > 0 or status.hasDigSite(target.q, target.r)
    if target.health >= target.maxHealth and not hasDebuffs then
        print(tostring(target.name) .. " is at full health with no debuffs to cure!")
        return true
    end

    target.health = target.maxHealth
    status.entityStatuses[target] = nil
    if status.hasAtHex(target.q, target.r, "fire") then
        status.removeFromHex(target.q, target.r, "fire")
        print("Fire on the ground extinguished!")
    end
    self.hasBeenUsed = true
    state.actionHistory = {}
    print(tostring(target.name) .. " fully healed and all negative effects removed!")
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function HealAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.8, 0.3},
        label = "Heal (H)",
        activeLabel = "Select target (H)",
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
        key = "x",
        button = { x = 0, y = 0, width = 120, height = 24 },
        hasBeenUsed = false,
    }
    return setmetatable(self, ExtraMoveAbility)
end

function ExtraMoveAbility:reset()
    self.hasBeenUsed = false
end

function ExtraMoveAbility:onActivate(state)
    print("Click on an ally that has already attacked, or press ESC to cancel")
end

function ExtraMoveAbility:onDeactivate(state)
    restoreSelectedActor()
    print(self.name .. " cancelled")
end

function ExtraMoveAbility:onClickHex(q, r, hex, state)
    local target = nil
    for _, e in ipairs(state.entities) do
        if e.q == q and e.r == r then
            target = e
            break
        end
    end

    if not target or not target.isPlayable or target.health <= 0 then
        print("No valid ally targeted!")
        return true
    end

    if not target.hasActedThisTurn then
        print(tostring(target.name) .. " hasn't attacked yet — cannot use Extra Move!")
        return true
    end

    target.canMoveAfterAttack = true
    self.hasBeenUsed = true
    state.actionHistory = {}
    print(tostring(target.name) .. " can now move after attacking!")
    restoreSelectedActor()
    global_abilities.activeAbility = nil
    return true
end

function ExtraMoveAbility:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.4, 0.8},
        label = "Extra Move (X)",
        activeLabel = "Select target (X)",
        tooltipH = 64,
        tooltipTitle = "Extra Move",
        tooltipLines = {
            "Allow one ally who has already",
            "acted to move again.",
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
        key = "w",
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
    print("Click on any hex to choose wind direction, or press ESC to cancel")
end

function WindTorrent:onDeactivate(state)
    restoreSelectedActor()
    print(self.name .. " cancelled")
end

function WindTorrent:onClickHex(q, r, hex, state)
    local direction = self:_getDirectionFromHex(q, r, hex.centerQ, hex.centerR, hex)
    if not direction then
        print("Cannot determine direction from center")
        restoreSelectedActor()
        return true
    end

    self:executeGlobalWithAnimation(direction, hex, state.entities, state.sounds, state.terrainMap, state.globalHealth, function(success, message)
        if success then
            state.actionHistory = {}
            print("Wind Torrent used! History cleared.")
        else
            print("Wind Torrent failed: " .. (message or "unknown error"))
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
    for _, dmg in ipairs(damagedEntities) do
        if dmg.entity and dmg.entity.health > 0 then
            drawHealthBar(dmg.entity, dmg.x, dmg.y, dmg.damage)
        end
    end
    global_abilities.previewBuildingDamage(state.globalHealth, damagedEntities)
end

function WindTorrent:drawButton(mx, my, state)
    global_abilities.drawAbilityButton(self, mx, my, state, {
        color = {0.2, 0.6, 0.8},
        label = "Wind Torrent (W)",
        activeLabel = "Select direction (W)",
        tooltipH = 80,
        tooltipTitle = "Wind Torrent",
        tooltipLines = {
            "Click on any hex to push all",
            "units (friend and foe) away from",
            "that hex in a line.",
        },
    })
end

function WindTorrent:executeGlobalWithAnimation(direction, hex, entities, sounds, terrainMap, globalHealth, onComplete)
    if self.hasBeenUsed then
        if onComplete then onComplete(false, "Already used") end
        return false
    end

    local step = stepMap[direction]
    if not step then
        if onComplete then onComplete(false, "Invalid direction") end
        return false
    end

    print(string.format(" WIND TORRENT: Pushing everything %s!", direction))

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
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, obj.q, obj.r, hex, entities, sounds, globalHealth, occupied[fromKey])
            occupied[fromKey] = obj
            goto continue
        end

        local newQ, newR = hex_utils.applyCubeDiff(obj.q, obj.r, step.dx, step.dy, step.dz)
        if not hex:isActiveHex(newQ, newR) then
            combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, globalHealth, nil)
            occupied[fromKey] = obj
        else
            local immovableKey = newQ .. "," .. newR
            if immovableMap[immovableKey] then
                combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, globalHealth, immovableMap[immovableKey])
                occupied[fromKey] = obj
            else
                local targetOcc = occupied[newQ .. "," .. newR]
                if targetOcc then
                    combat.addCollisionBounceAnimation(obj, obj.q, obj.r, newQ, newR, hex, entities, sounds, globalHealth, targetOcc)
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
        self.hasBeenUsed = true
        if sounds and sounds.wind then sounds.wind:play() end
        if onComplete then onComplete(true, nil) end
        if _G.checkGameEnd then _G.checkGameEnd() end
    end)
    return true
end

-- Register all abilities
global_abilities.register(HealAbility.new())
global_abilities.register(ExtraMoveAbility.new())
global_abilities.register(WindTorrent.new())
global_abilities.register(UnearthAbility.new())
global_abilities.register(MindControlAbility.new())
global_abilities.register(AccelerateDecayAbility.new())

return global_abilities
