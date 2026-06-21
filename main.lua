-- main.lua
-- Точка входа. Инициализация, обновление, диспетчеризация ввода.
-- Состояние игры хранится в `state` (gamestate).
-- Отрисовка делегирована renderer-у.

state = require("gamestate").new()

combat = require("combat")
ai = require("ai")
require("hexgrid")
environment = require("environment")
status = require("status")
ui = require("ui")
pathfinding = require("pathfinding")
effects = require("effects")
visual = require("visual_effects")
config = require("config")
local hex_utils = require("hex_utils")
local renderer = require("renderer")
local input = require("input")
local turnManager = require("turn_manager")
local cell_rules = require("cell_rules")
menu = require("menu")
local objectives = require("objectives")
global_abilities = require("global_abilities")
shop = require("shop")
require("game")

-- Логирование: включить здесь (или через _G.LOG_ENABLED).
-- Категории: ai, combat, effects, entity, env, game, input, objectives,
--            status, trains, turn, ui, main, map.
_G.log = require("log")
log.enabled = false
log.level = "debug"

-- Включить запись в файл через переменную окружения NGTBS_LOG_FILE.
-- Это позволяет проверить загрузку игры без окна: задаём путь, запускаем
-- love, читаем файл. Не влияет на обычный запуск.
do
    local logFile = os.getenv("NGTBS_LOG_FILE")
    if logFile and logFile ~= "" then
        log.enabled = true
        log.file = logFile
        -- очищаем файл при старте
        local f = io.open(logFile, "w")
        if f then f:close() end
    end
end

pushAnimations = state.pushAnimations
dpiScale = 1
logicalW = 0
logicalH = 0
screenShake = { timer = 0, intensity = 6, duration = 0.3 }
testViewActive = false
testViewOffsetY = 0

gamePhase = "menu"
selectedMapPath = nil
selectedSquad = nil
difficultyModifier = 1
disableEnemySpawn = false
chaos = 0
chaosMax = 5
unplacedAllies = {}
isProgressionRun = false
currentMapIndex = 1
showAbilityMenu = false
abilityMenu = nil
progressionOverlay = nil
mapProgression = {"maps/map1.lua", "maps/map2.lua", "maps/map3.lua", "maps/map4.lua"}
unitUpgrades = {}  -- "Warrior" → { choices = {"dashToFlipChain"} }
artifacts = {}  -- list of unlocked artifact IDs
placedAllies = {}
deploySelectedIdx = nil
allyPanelButtons = {}

UPGRADE_CHOICES = {
    Warrior = {
        { id = "dashToFlipChain", name = "Dash→Flip", desc = "After Dash, can Flip the same target" },
        { id = "flipToDashChain", name = "Flip→Dash", desc = "After Flip, can Dash the same target" },
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

-- Синхронизация глобалов -> state (renderer и gamestate-методы читают из state).
-- Реализация вынесена в gamestate.lua:GameState:syncFromGlobals().
-- Цель будущей миграции — убрать эту функцию, обращаясь к state.* напрямую.
-- Синхронизация глобалов -> state (renderer и gamestate-методы читают из state).
-- Реализация вынесена в gamestate.lua:GameState:syncFromGlobals().
-- Цель будущей миграции — убрать эту функцию, обращаясь к state.* напрямую.
function syncState()
    state:syncFromGlobals()
end

function handleAbilityMenuClick(x, y)
    local w, h = logicalW, logicalH
    local menuW, menuH = 340, 340
    local menuX = w/2 - menuW/2
    local menuY = h/2 - menuH/2 + 30

    if abilityMenu.mode == "upgrade" then
        local itemH = 60
        local itemStartY = menuY + 90

        if not abilityMenu.selectedItem then
            -- Stage 1: pick a unit to upgrade or an artifact
            for i, entry in ipairs(abilityMenu.available) do
                local ix = menuX + 20
                local iy = itemStartY + (i - 1) * (itemH + 6)
                local iw = menuW - 40
                if x >= ix and x <= ix + iw and y >= iy and y <= iy + itemH then
                    abilityMenu.selectedItem = entry
                    if entry.type == "unit" then
                        abilityMenu.availableChoices = UPGRADE_CHOICES[entry.name]
                        abilityMenu.selectedChoice = nil
                    else
                        abilityMenu.selectedChoice = entry.id
                        abilityMenu.availableChoices = nil
                    end
                    return
                end
            end
        else
            local entry = abilityMenu.selectedItem
            if entry.type == "unit" then
                -- Stage 2: pick a choice for the unit
                local choiceH = 50
                for i, choice in ipairs(abilityMenu.availableChoices) do
                    local ix = menuX + 20
                    local iy = itemStartY + (i - 1) * (choiceH + 6)
                    local iw = menuW - 40
                    if x >= ix and x <= ix + iw and y >= iy and y <= iy + choiceH then
                        abilityMenu.selectedChoice = choice.id
                        return
                    end
                end

                -- Back button
                local backBtnY = itemStartY + #abilityMenu.availableChoices * (choiceH + 6) + 10
                if x >= menuX + 20 and x <= menuX + 20 + 100 and y >= backBtnY and y <= backBtnY + 30 then
                    abilityMenu.selectedItem = nil
                    abilityMenu.selectedChoice = nil
                    abilityMenu.availableChoices = nil
                    return
                end
            end

            -- Confirm button (unit upgrade or artifact)
            if abilityMenu.selectedChoice then
                local btnW, btnH = 200, 40
                local btnX = w/2 - btnW/2
                local btnY = menuY + menuH - 60
                if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
                    if abilityMenu.selectedItem.type == "unit" then
                        local data = unitUpgrades[abilityMenu.selectedItem.name] or { choices = {} }
                        table.insert(data.choices, abilityMenu.selectedChoice)
                        unitUpgrades[abilityMenu.selectedItem.name] = data
                    else
                        table.insert(artifacts, abilityMenu.selectedChoice)
                    end
                    showAbilityMenu = false
                    abilityMenu = nil
                    local nextMap = currentMapIndex + 1
                    if nextMap <= #mapProgression then
                        currentMapIndex = nextMap
                        restartGame(mapProgression[nextMap])
                    else
                        progressionOverlay = "complete"
                    end
                end
            end
        end
        return
    end

    -- Ability item rects
    local itemH = 36
    local itemStartY = menuY + 90
    for i, name in ipairs(abilityMenu.available) do
        local ix = menuX + 20
        local iy = itemStartY + (i - 1) * (itemH + 6)
        local iw = menuW - 40
        if x >= ix and x <= ix + iw and y >= iy and y <= iy + itemH then
            local already = false
            for _, s in ipairs(abilityMenu.selected) do
                if s == name then already = true; break end
            end
            if already then
                for j = #abilityMenu.selected, 1, -1 do
                    if abilityMenu.selected[j] == name then
                        table.remove(abilityMenu.selected, j)
                        break
                    end
                end
            elseif #abilityMenu.selected < abilityMenu.maxSelect then
                table.insert(abilityMenu.selected, name)
            end
            return
        end
    end

    -- Confirm button
    if #abilityMenu.selected == abilityMenu.maxSelect then
        local btnW, btnH = 200, 40
        local btnX = w/2 - btnW/2
        local btnY = menuY + menuH - 60
        if x >= btnX and x <= btnX + btnW and y >= btnY and y <= btnY + btnH then
            global_abilities.unlockAll(abilityMenu.selected)
            global_abilities.maxMana = global_abilities.maxMana + 1
            showAbilityMenu = false
            abilityMenu = nil
            local nextMap = currentMapIndex + 1
            if nextMap <= #mapProgression then
                currentMapIndex = nextMap
                restartGame(mapProgression[nextMap])
            else
                progressionOverlay = "complete"
            end
        end
    end
end

function handleProgressionOverlayClick(x, y)
    local w = logicalW
    local btnW, btnH = 240, 50
    local btnX = w/2 - btnW/2
    local btnY = logicalH/2 + 60

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
    sti = require 'libraries/sti'
    maxTurns = 5
    environment.loadUnitSprites()

    restartButton = {
        x = 270, y = 0, width = 110, height = 30,
        text = "Restart Game", isHovered = false,
        isHeld = false, holdTimer = 0,
    }
    endTurnButton = {
        x = 140, y = 0, width = 110, height = 30,
        text = "End Turn", isHovered = false,
        holdTimer = 0, isHeld = false,
    }

    sounds = {}
    sounds.undo = love.audio.newSource("sounds/hover.wav", "static")
    sounds.undo:setVolume(0.4)
    sounds.turn = love.audio.newSource("sounds/hover.wav", "static")
    sounds.turn:setVolume(0.3)
    sounds.attack = love.audio.newSource("sounds/blip.wav", "static")
    sounds.attack:setVolume(0.5)
    sounds.collision = love.audio.newSource("sounds/blip.wav", "static")
    sounds.collision:setVolume(0.6)

    showEnemyOrder = false
    gamePhase = "menu"

    -- Инициализация глобального turnState (раньше полагался на confirmDeploy/
    -- skipDeploy-блок restartGame, что приводило к падению при autostart).
    turnState = state.turnState
end

function getDrawCoords(q, r)
    local x, y = hex:hexToPixel(q, r)
    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r]
    if terrain == "water" or terrain == "underwater_mines" then
        y = y + config.WATER_Y_OFFSET
    end
    return x, y
end



function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    local lx, ly = x / dpiScale, y / dpiScale
    if shop.isOpen then
        shop.mousepressed(lx, ly)
        return
    end
    if showAbilityMenu then
        handleAbilityMenuClick(lx, ly)
        return
    end
    if progressionOverlay then
        handleProgressionOverlayClick(lx, ly)
        return
    end
    if gamePhase == "menu" then
        menu.mousepressed(lx, ly)
    else
        input.mousepressed(lx, ly, button)
    end
end

function love.mousereleased(x, y, button)
    input.mousereleased(x / dpiScale, y / dpiScale, button)
end

function isPositionOccupied(q, r, movingEntity)
    -- Делегирует в cell_rules.isOccupied (с водой и phaseThroughEnemies).
    return cell_rules.isOccupied(q, r, movingEntity)
end

-- Returns 3 push direction choices for choosePushDir (Puncher lvl3)
-- Uses cube coordinate rotation (±60°)
function getPushDirChoices(stepX, stepY, stepZ)
    -- Rotate +60° clockwise: (x,y,z) → (-z, -x, -y)
    local cw = {x = -stepZ, y = -stepX, z = -stepY}
    -- Rotate -60° counter-clockwise: (x,y,z) → (-y, -z, -x)
    local ccw = {x = -stepY, y = -stepZ, z = -stepX}
    return {ccw, {x = stepX, y = stepY, z = stepZ}, cw}
end

function getEntityAtHex(q, r)
    for _, e in ipairs(entities) do
        if e.q == q and e.r == r then
            return e
        end
    end
    return nil
end

function love.update(dt)
    shop.update(dt)
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
    if decayMessageTimer > 0 then
        decayMessageTimer = decayMessageTimer - dt
    end

    -- Hold-to-confirm для кнопок (общая логика)
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
    updateHoldButton(endTurnButton, endTurn)
    updateHoldButton(restartButton, restartGame)

    if testViewActive then
        testViewOffsetY = math.sin(love.timer.getTime() * 1.5) * 60
    end

    if screenShake.timer > 0 then
        screenShake.timer = math.max(0, screenShake.timer - dt)
    end

    turnManager.update(dt)
    objectives.update(entities)

    if isProgressionRun and win and gameActive == false and not showAbilityMenu and not progressionOverlay then
        local squad = menu.getSquads()[selectedSquad]
        local available = {}
        if squad then
            for _, unitDef in ipairs(squad.units) do
                local name = unitDef.name
                if name == "Warrior" or name == "Puncher" or name == "Rogue" then
                    local data = unitUpgrades[name]
                    local hasUpgrade = data and #data.choices > 0
                    if not hasUpgrade then
                        table.insert(available, { type = "unit", name = name })
                    end
                end
            end
            for _, art in ipairs(ARTIFACT_CHOICES) do
                local already = false
                for _, a in ipairs(artifacts) do
                    if a == art.id then already = true; break end
                end
                if not already then
                    table.insert(available, { type = "artifact", id = art.id, name = art.name, desc = art.desc })
                end
            end
        end
        if #available > 0 then
            showAbilityMenu = true
            abilityMenu = {
                available = available,
                mode = "upgrade",
                selectedItem = nil,
                selectedChoice = nil,
                availableChoices = nil,
            }
        else
            progressionOverlay = "complete"
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
    local bottomY = logicalH - 65
    undoButton.isHovered = (mx >= 10 and mx <= 120 and my >= bottomY and my <= bottomY + 30)
    endTurnButton.isHovered = (mx >= endTurnButton.x and mx <= endTurnButton.x + endTurnButton.width and
                               my >= endTurnButton.y and my <= endTurnButton.y + endTurnButton.height)
end

function love.resize(w, h)
    dpiScale = love.window.getDPIScale()
    logicalW = w / dpiScale
    logicalH = h / dpiScale
    if hex then
        hex:centerOnScreen(logicalW, logicalH)
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(dpiScale)
    logicalW = love.graphics.getWidth() / dpiScale
    logicalH = love.graphics.getHeight() / dpiScale
    local bottomY = logicalH - 65
    restartButton.y = bottomY
    endTurnButton.y = bottomY

    if gamePhase == "menu" then
        menu.draw()
    elseif gamePhase == "deploy" then
        syncState()
        renderer.drawDeployPhase(state, unplacedAllies, placedAllies, deploySelectedIdx)
    else
        if screenShake.timer > 0 then
            local t = screenShake.timer / screenShake.duration
            local ease = (1 - t) * (1 - t)
            local offsetY = screenShake.intensity * ease * math.sin(t * math.pi * 12)
            love.graphics.translate(0, offsetY)
        end
        syncState()
        renderer.draw(state)
    end

    shop.draw()

    love.graphics.pop()
end

function getEnemyAttackOrder(entities, turnState)
    local order = {}
    local queue = {}

    if turnState.phase == "enemy_attack" then
        queue = turnState.enemyAttackQueue or {}
    else
        for _, e in ipairs(entities) do
            if e:isCharacter() and not e.isPlayable and e.hasPreparedAttack and e.health > 0 then
                table.insert(queue, e)
            end
        end
        local trains_mod = require("trains")
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

function isCellPassable(q, r, movingEntity)
    return cell_rules.isPassable(q, r, movingEntity)
end

function isCellOccupiedForStop(q, r, movingEntity)
    return cell_rules.isOccupiedForStop(q, r, movingEntity)
end

function love.keypressed(key)
    if key == "f5" and gameActive then
        win = true
        gameActive = false
        log.warn("main", "AUTO WIN (debug)")
        syncState()
        return
    end
    if gamePhase == "menu" then
        menu.keypressed(key)
    else
        input.keypressed(key)
    end
end

function love.keyreleased(key)
    input.keyreleased(key)
end
