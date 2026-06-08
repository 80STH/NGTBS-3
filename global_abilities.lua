-- global_abilities.lua
-- Модульная система одноразовых способностей.
-- Каждая способность — независимый объект со своим hasBeenUsed, кнопкой, хоткеем.
-- Все способности доступны одновременно (не mutually exclusive в плане использования,
-- но только одна может быть в режиме выбора цели).

local ui = require("ui")
local combat = require("combat")
local hex_utils = require("hex_utils")
local status = require("status")

local global_abilities = {}

global_abilities.registry = {}
global_abilities.activeAbility = nil

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

function global_abilities.handleButtonClick(x, y, state)
    for _, ab in pairs(global_abilities.registry) do
        local btn = ab.button
        if btn and x >= btn.x and x <= btn.x + btn.width and y >= btn.y and y <= btn.y + btn.height then
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
    for _, ab in pairs(global_abilities.registry) do
        ab:drawButton(mx, my, state)
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
-- HEAL
-- ============================================================
local HealAbility = {}
HealAbility.__index = HealAbility

function HealAbility.new()
    local self = {
        name = "Heal",
        key = "h",
        button = { x = 10, y = 120, width = 120, height = 30 },
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
        button = { x = 10, y = 155, width = 120, height = 30 },
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
        button = { x = 10, y = 225, width = 120, height = 30 },
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

return global_abilities
