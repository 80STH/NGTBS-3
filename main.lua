-- main.lua
-- Entry point. Initialization, update, input dispatching.
-- Game state lives in globals; renderer reads from the state table.
state = _G

-- Устанавливаем linear-фильтрацию по умолчанию для всех текстур
love.graphics.setDefaultFilter("linear", "linear")

undo = require("system.undo")
combat = require("combat.combat")
ai = require("combat.ai")
require("grid.hexgrid")
environment = require("entity.environment")
status = require("system.status")
ui = require("ui.ui")
pathfinding = require("grid.pathfinding")
effects = require("system.effects")
visual = require("system.visual_effects")
config = require("core.config")
local hex_utils = require("grid.hex_utils")
local renderer = require("ui.renderer")
local input = require("ui.input")
local turnManager = require("core.turn_manager")
local cell_rules = require("grid.cell_rules")
menu = require("ui.menu")
local objectives = require("system.objectives")
global_abilities = require("system.global_abilities")
shop = require("ui.shop")
map_editor = require("editor.map_editor")
pause_menu = require("ui.pause_menu")
enemy_lab = require("ui.enemy_lab")
require("core.game")
local commanders = require("system.commanders")
local trains_mod = require("system.trains")

-- Logging: enable here (or via _G.LOG_ENABLED).
-- Categories: ai, combat, effects, entity, env, game, input, objectives,
--            status, trains, turn, ui, main, map.
_G.log = require("util.log")
log.enabled = true
log.level = "debug"

-- Enable file logging via the NGTBS_LOG_FILE environment variable.
-- This allows checking game loading without a window: set the path, run
-- love, read the file. Does not affect normal launch.
do
    local logFile = os.getenv("NGTBS_LOG_FILE")
    if logFile and logFile ~= "" then
        log.enabled = true
        log.file = logFile
        -- clear file on start
        local f = io.open(logFile, "w")
        if f then f:close() end
    end
end

pushAnimations = require("combat.push_animator")
dpiScale = 1
logicalW = 0
logicalH = 0
screenShake = { timer = 0, intensity = 6, duration = 0.3 }
testViewActive = false
testViewOffsetY = 0

gamePhase = "menu"
selectedMapPath = nil
selectedSquad = nil
selectedCommander = nil
difficultyModifier = 1
squadHpBonus = 0
squadMoveBonus = 0
squadArmorBonus = 0
spawnAllUnits = false
unlimitedAbilities = false
chaos = 0
chaosMax = 4
chaosSurplus = 0
chaosScaleBonus = 0
entityAt = {}
unplacedAllies = {}
isProgressionRun = false
currentMapIndex = 1
progressionShopOpened = false
progressionOverlay = nil
mapProgression = {"maps/map1.lua", "maps/map2.lua", "maps/map3.lua", "maps/map4.lua"}
progressionChoices = {}
unitUpgrades = {}  -- "Warrior" > { choices = {"dashToFlipChain"} }
artifacts = {}  -- list of unlocked artifact IDs
commanderArtifacts = {}  -- commander-specific artifact IDs
placedAllies = {}
deploySelectedIdx = nil
allyPanelButtons = {}

UPGRADE_CHOICES = {
    Warrior = {
        { id = "dashToFlipChain", name = "Dash>Flip", desc = "After Dash, can Flip the same target" },
        { id = "flipToDashChain", name = "Flip>Dash", desc = "After Flip, can Dash the same target" },
    },
    Puncher = {
        { id = "empowerAtStart", name = "Empowered Start", desc = "Start each map empowered" },
        { id = "choosePushDir", name = "Windup", desc = "Choose push direction" },
    },
    Rogue = {
        { id = "redirectShot", name = "Ricochet", desc = "Redirect shot to second target" },
        { id = "pointBlankLethal", name = "Close Quarters", desc = "Point-blank shot is lethal" },
    },
}

ARTIFACT_CHOICES = {
    { id = "rootImmune", name = "Iron Will", desc = "All units immune to roots/slowing auras" },
    { id = "deployAnywhere", name = "Scout", desc = "All units deploy on any terrain" },
    { id = "armor", name = "Fortress", desc = "All units take -1 damage" },
    { id = "moveSpeed", name = "Swift Boots", desc = "All units gain +1 move range" },
    { id = "canMoveAfterAttack", name = "Hit & Run", desc = "All units move after attacking" },
    { id = "phaseThroughEnemies", name = "Ghost Cloak", desc = "All units phase through enemies" },
}

function processLevelVictory()
    objectives.checkOnVictory(entities)
    
    local completedSecondary = 0
    local totalSecondary = #objectives.getList()
    log.infof("game", "processLevelVictory: totalSecondary=%d, chaos=%d", totalSecondary, chaos)
    for _, obj in ipairs(objectives.getList()) do
        local state = objectives.getState(obj.id)
        log.infof("game", "  objective %s: state=%s", obj.id, state)
        if state == "completed" then
            completedSecondary = completedSecondary + 1
        end
    end
    log.infof("game", "  completedSecondary=%d", completedSecondary)
    
    local totalReduction = completedSecondary + 1
    local actualReduction = math.min(chaos, totalReduction)
    chaos = chaos - actualReduction
    
    local surplusReduction = totalReduction - actualReduction
    if surplusReduction > 0 then
        chaosSurplus = chaosSurplus + surplusReduction
        local scaleIncrease = math.floor(chaosSurplus / 3)
        chaosScaleBonus = math.min(2, scaleIncrease)
    end
    
    log.infof("game", "  after: chaos=%d, chaosSurplus=%d, chaosScaleBonus=%d", chaos, chaosSurplus, chaosScaleBonus)
    
    if chaosSurplus >= 9 then
        progressionOverlay = "complete"
        return false
    end
    
    return completedSecondary == totalSecondary and totalSecondary > 0
end

function handleProgressionOverlayClick(x, y)
    local w = logicalW
    local btnW, btnH = 240, 50
    local btnX = w/2 - btnW/2
    local btnY = logicalH/2 + 100

    if progressionOverlay == "complete" then
        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            progressionOverlay = nil
            isProgressionRun = false
            currentMapIndex = 1
            gamePhase = "menu"
        end
    end
end

function love.load()
    dpiScale = love.window.getDPIScale()
    logicalW = love.graphics.getWidth() / dpiScale
    logicalH = love.graphics.getHeight() / dpiScale
    maxTurns = 5
    environment.loadUnitSprites()
    local icon_cache = require("ui.icon_cache")
    icon_cache.loadAll()

    endTurnButton = {
        isHovered = false,
        holdTimer = 0, isHeld = false,
    }
    undoButton = {
        x = 10, y = 0, width = 120, height = 30,
        isHeld = false, holdTimer = 0,
    }

    sounds = require("system.sounds")
    sounds.init()

    showEnemyOrder = false
    gamePhase = "menu"

    -- Initialize global turnState (previously relied on confirmDeploy/
    -- skipDeploy block in restartGame, which caused crashes on autostart).
end

function getDrawCoords(q, r)
    local x, y = hex:hexToPixel(q, r)
    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r]
    if terrain == "water" then
        y = y + config.WATER_Y_OFFSET
    end
    if testViewActive and q == hex.centerQ and r == hex.centerR then
        y = y + testViewOffsetY
    end
    return x, y
end



function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    local lx, ly = x / dpiScale, y / dpiScale
    if pause_menu.isOpen then
        pause_menu.mousepressed(lx, ly)
        return
    end
    if gamePhase == "playing" and gameActive then
        local pb = ui.getPauseBtnRect()
        if lx >= pb.x and lx <= pb.x + pb.w and ly >= pb.y and ly <= pb.y + pb.h then
            pause_menu.open()
            return
        end
    end
    if shop.isOpen then
        shop.mousepressed(lx, ly)
        return
    end
    if progressionOverlay then
        handleProgressionOverlayClick(lx, ly)
        return
    end
    if gamePhase == "menu" then
        menu.mousepressed(lx, ly)
    elseif gamePhase == "editor" then
        map_editor.mousepressed(lx, ly, button)
    elseif gamePhase == "creature_lab" then
        enemy_lab.mousepressed(lx, ly)
    else
        input.mousepressed(lx, ly, button)
    end
end

function love.mousereleased(x, y, button)
    if gamePhase == "editor" then
        map_editor.mousereleased(x / dpiScale, y / dpiScale, button)
    else
        input.mousereleased(x / dpiScale, y / dpiScale, button)
    end
end

function love.mousemoved(x, y)
    if gamePhase == "editor" then
        map_editor.mousemoved(x / dpiScale, y / dpiScale)
    end
end

-- Returns 3 push direction choices for choosePushDir (Puncher lvl3)
-- Uses cube coordinate rotation (+-60)
function getPushDirChoices(stepX, stepY, stepZ)
    -- Rotate +60 clockwise: (x,y,z) -> (-z, -x, -y)
    local cw = {x = -stepZ, y = -stepX, z = -stepY}
    -- Rotate -60 counter-clockwise: (x,y,z) -> (-y, -z, -x)
    local ccw = {x = -stepY, y = -stepZ, z = -stepX}
    return {ccw, {x = stepX, y = stepY, z = stepZ}, cw}
end

local cellDuplicateWarnings = {}

function clearCellDuplicateWarnings()
    cellDuplicateWarnings = {}
end

function rebuildEntityIndex()
    entityAt = {}
    for _, e in ipairs(entities) do
        if e.q and e.r then
            local key = e.q .. "," .. e.r
            local existing = entityAt[key]
            if existing then
                local warnKey = key .. "|" .. tostring(existing.name or existing) .. "|" .. tostring(e.name or e)
                if not cellDuplicateWarnings[warnKey] then
                    cellDuplicateWarnings[warnKey] = true
                    log.errorf("debug", "CELL DUPLICATE: %s and %s both at (%d,%d)!", tostring(existing.name or existing), tostring(e.name or e), e.q, e.r)
                end
            end
            entityAt[key] = e
        end
    end
    if ui then ui._moveRangeCacheKey = nil end
end

function getEntityAtHex(q, r)
    return entityAt[q .. "," .. r]
end

function love.update(dt)
    if pause_menu.isOpen then return end
    shop.update(dt)
    if gamePhase == "editor" then
        map_editor.dpiScale = dpiScale
        map_editor.update(dt)
        return
    end
    if gamePhase == "deploy" then
        local mx, my = love.mouse.getPosition()
        mx = mx / dpiScale
        my = my / dpiScale
        local hq, hr = hex:pixelToHex(mx, my)
        if hex and hex:isActiveHex(hq, hr) then
            hex.hoverQ, hex.hoverR = hq, hr
        else
            hex.hoverQ, hex.hoverR = -1, -1
        end
        return
    end

    if gamePhase ~= "playing" then return end

    visual.update(dt)
    updateDeathAnimations(dt)
    for _, actor in ipairs(entities) do
        updateActorMovement(actor, dt)
        ai.updateEnemyMovement(actor, dt, hex)
        if actor.pulse then
            actor.pulse = actor.pulse + dt * (actor.pulseSpeed or 5)
        end
    end

    combat.updatePushAnimations(dt, hex)
    rebuildEntityIndex()
    if decayMessageTimer > 0 then
        decayMessageTimer = decayMessageTimer - dt
    end

    -- Hold-to-confirm for buttons (common logic)
    local function updateHoldButton(btn, onTrigger)
        if btn.isHeld then
            btn.holdTimer = (btn.holdTimer or 0) + dt
            if btn.holdTimer >= config.HOLD_TIME then
                btn.isHeld = false
                btn.holdTimer = 0
                onTrigger()
            end
        end
    end
    updateHoldButton(endTurnButton, turnManager.endPlayerTurn)
    updateHoldButton(undoButton, function() end)

    if testViewActive then
        testViewOffsetY = (1 - math.abs((love.timer.getTime() * 3) % 2 - 1)) * 30
    end

    if screenShake.timer > 0 then
        screenShake.timer = math.max(0, screenShake.timer - dt)
    end

    turnManager.update(dt)
    objectives.update(entities)

    if isProgressionRun and win and gameActive == false and not shop.isOpen and not progressionOverlay and not progressionShopOpened then
        progressionShopOpened = true
        local bothObjectivesCompleted = processLevelVictory()
        if progressionOverlay ~= "complete" then
            shop.openForProgression(bothObjectivesCompleted)
        end
    end

    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale
    my = my / dpiScale
    local hq, hr = hex:pixelToHex(mx, my)
    if hex:isActiveHex(hq, hr) then
        hex.hoverQ, hex.hoverR = hq, hr
    else
        hex.hoverQ, hex.hoverR = -1, -1
    end

    undoButton = undoButton or {}
    local ur = ui.getRightBtnRect(2) -- Undo
    undoButton.isHovered = (mx >= ur.x and mx <= ur.x + ur.w and my >= ur.y and my <= ur.y + ur.h)

    local er = ui.getRightBtnRect(1) -- End Turn
    endTurnButton.isHovered = (mx >= er.x and mx <= er.x + er.w and my >= er.y and my <= er.y + er.h)
    if undoButton.isHovered or endTurnButton.isHovered then
        sounds.hover(dt)
    end
end

function love.resize(w, h)
    dpiScale = love.window.getDPIScale()
    logicalW = w / dpiScale
    logicalH = h / dpiScale
    if gamePhase == "editor" and map_editor.hex then
        map_editor.hex:centerOnScreen(logicalW, logicalH)
        map_editor.hex.offsetX = map_editor.hex.offsetX - 200
    elseif hex then
        hex:centerOnScreen(logicalW, logicalH)
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(dpiScale)
    logicalW = love.graphics.getWidth() / dpiScale
    logicalH = love.graphics.getHeight() / dpiScale

    if gamePhase == "menu" then
        menu.draw()
    elseif gamePhase == "editor" then
        map_editor.draw()
    elseif gamePhase == "creature_lab" then
        enemy_lab.draw()
    elseif gamePhase == "deploy" then
        renderer.drawDeployPhase(state, unplacedAllies, placedAllies, deploySelectedIdx)
    else
        if screenShake.timer > 0 then
            local t = screenShake.timer / screenShake.duration
            local ease = (1 - t) * (1 - t)
            local offsetY = screenShake.intensity * ease * math.sin(t * math.pi * 12)
            love.graphics.translate(0, offsetY)
        end
        renderer.draw(state)
    end

    shop.draw()
    pause_menu.draw()

    love.graphics.pop()
end

function getEnemyAttackOrder(entities, turnState)
    local order = {}
    local queue = {}

    if turnState.phase == "enemy_attack" then
        queue = turnState.enemyAttackQueue or {}
    else
        local priority = {}
        local waterWalkers = {}
        local normal = {}
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 then
                local tbl = e.attacksFirst and priority or (e.waterWalker and waterWalkers or normal)
                table.insert(tbl, e)
            end
        end
        for _, e in ipairs(priority) do table.insert(queue, e) end
        for _, e in ipairs(waterWalkers) do table.insert(queue, e) end
        for _, e in ipairs(normal) do table.insert(queue, e) end

        local trainGroups = trains_mod.getTrainGroups()
        for _, group in pairs(trainGroups) do
            if group.active and group.cars and #group.cars > 0 then
                local loco = group.cars[1]
                if loco and loco.health and loco.health > 0 and not loco.isDying then
                    table.insert(queue, loco)
                end
            end
        end
    end

    for i, enemy in ipairs(queue) do
        order[enemy] = i
    end
    return order
end

function love.keypressed(key)
    if pause_menu.isOpen then
        pause_menu.keypressed(key)
        return
    end
    if key == "f5" and gameActive then
        win = true
        gameActive = false
        log.warn("main", "AUTO WIN (debug)")
        return
    end
    if gamePhase == "menu" then
        menu.keypressed(key)
    elseif gamePhase == "editor" then
        map_editor.keypressed(key)
    else
        input.keypressed(key)
    end
end

function love.keyreleased(key)
    input.keyreleased(key)
end

function love.wheelmoved(dx, dy)
    if gamePhase ~= "playing" then return end
end
