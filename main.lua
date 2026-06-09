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
menu = require("menu")
local objectives = require("objectives")
global_abilities = require("global_abilities")
require("game")

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
unplacedAllies = {}
placedAllies = {}
deploySelectedIdx = nil
allyPanelButtons = {}

function syncStateToGlobals()
    entities = state.entities
    hex = state.hex
    terrainMap = state.terrainMap
    globalHealth = state.globalHealth
    turnState = state.turnState
    turnCount = state.turnCount
    maxTurns = state.maxTurns
    gameActive = state.gameActive
    win = state.win
    loss = state.loss
    selectedActor = state.selectedActor
    selectedAttack = state.selectedAttack
    attackMode = state.attackMode
    flipTargetActor = state.flipTargetActor
    vortexTargetCell = state.vortexTargetCell
    attackButtons = state.attackButtons
    sounds = state.sounds
    actionHistory = state.actionHistory
    maxUndoCount = state.maxUndoCount
    restartButton = state.restartButton
    endTurnButton = state.endTurnButton
    undoButton = state.undoButton
    decayAppliedForTurnLimit = state.decayAppliedForTurnLimit
    decayMessageTimer = state.decayMessageTimer
    fireAppliedForTurnLimit = state.fireAppliedForTurnLimit
    pushAnimations = state.pushAnimations
    showEnemyOrder = state.showEnemyOrder
    dpiScale = state.dpiScale
    DEBUG_COMBAT = state.DEBUG_COMBAT
end

function syncGlobalsToState()
    state.entities = entities
    state.hex = hex
    state.terrainMap = terrainMap
    state.globalHealth = globalHealth
    state.turnState = turnState
    state.turnCount = turnCount
    state.maxTurns = maxTurns
    state.gameActive = gameActive
    state.win = win
    state.loss = loss
    state.selectedActor = selectedActor
    state.selectedAttack = selectedAttack
    state.attackMode = attackMode
    state.flipTargetActor = flipTargetActor
    state.vortexTargetCell = vortexTargetCell
    state.attackButtons = attackButtons
    state.sounds = sounds
    state.actionHistory = actionHistory
    state.maxUndoCount = maxUndoCount
    state.restartButton = restartButton
    state.endTurnButton = endTurnButton
    state.undoButton = undoButton
    state.decayAppliedForTurnLimit = decayAppliedForTurnLimit
    state.decayMessageTimer = decayMessageTimer
    state.fireAppliedForTurnLimit = fireAppliedForTurnLimit
    state.pushAnimations = pushAnimations
    state.dpiScale = dpiScale
    state.showEnemyOrder = showEnemyOrder
end

function love.load()
    dpiScale = love.window.getDPIScale()
    sti = require 'libraries/sti'
    maxTurns = 5
    environment.loadUnitSprites()

    restartButton = {
        x = 10, y = 295, width = 120, height = 30,
        text = "Restart Game", isHovered = false
    }
    endTurnButton = {
        x = 10, y = 260, width = 120, height = 30,
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
end

function getDrawCoords(q, r)
    local x, y = hex:hexToPixel(q, r)
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
        y = y + config.WATER_Y_OFFSET
    end
    return x, y
end



function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    local lx, ly = x / dpiScale, y / dpiScale
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
    if not hex:isActiveHex(q, r) then
        return true
    end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
        if movingEntity and movingEntity.waterWalker then
            -- ok
        else
            return true
        end
    end
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            return true
        end
    end
    return false
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
    if globalHealth.flashTimer and globalHealth.flashTimer > 0 then
        globalHealth.flashTimer = globalHealth.flashTimer - dt
    end
    if decayMessageTimer > 0 then
        decayMessageTimer = decayMessageTimer - dt
    end

    if endTurnButton.isHeld then
        endTurnButton.holdTimer = endTurnButton.holdTimer + dt
        if endTurnButton.holdTimer >= 0.7 then
            endTurnButton.isHeld = false
            endTurnButton.holdTimer = 0
            endTurn()
        end
    end

    if testViewActive then
        testViewOffsetY = math.sin(love.timer.getTime() * 1.5) * 60
    end

    if screenShake.timer > 0 then
        screenShake.timer = math.max(0, screenShake.timer - dt)
    end

    turnManager.update(dt)
    objectives.update(entities)

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
    undoButton.isHovered = (mx >= 10 and mx <= 130 and my >= 190 and my <= 220)
    endTurnButton.isHovered = (mx >= endTurnButton.x and mx <= endTurnButton.x + endTurnButton.width and
                               my >= endTurnButton.y and my <= endTurnButton.y + endTurnButton.height)
end

function love.resize(w, h)
    dpiScale = love.window.getDPIScale()
    if hex then
        hex:centerOnScreen(w / dpiScale, h / dpiScale)
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(dpiScale)
    logicalW = love.graphics.getWidth() / dpiScale
    logicalH = love.graphics.getHeight() / dpiScale

    if gamePhase == "menu" then
        menu.draw()
    elseif gamePhase == "deploy" then
        syncGlobalsToState()
        renderer.drawDeployPhase(state, unplacedAllies, placedAllies, deploySelectedIdx)
    else
        if screenShake.timer > 0 then
            local t = screenShake.timer / screenShake.duration
            local ease = (1 - t) * (1 - t)
            local offsetY = screenShake.intensity * ease * math.sin(t * math.pi * 12)
            love.graphics.translate(0, offsetY)
        end
        syncGlobalsToState()
        renderer.draw(state)
    end

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
    end

    for i, enemy in ipairs(queue) do
        order[enemy] = i
    end
    return order
end

function isCellPassable(q, r, movingEntity)
    if not hex:isActiveHex(q, r) then return false end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
        if movingEntity and movingEntity.waterWalker then
            -- ok
        else
            return false
        end
    end
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            if not e.isPlayable then
                return false
            end
        end
    end
    return true
end

function isCellOccupiedForStop(q, r, movingEntity)
    if not hex:isActiveHex(q, r) then return true end
    for _, e in ipairs(entities) do
        if e ~= movingEntity and e.q == q and e.r == r then
            return true
        end
    end
    return false
end

function love.keypressed(key)
    if gamePhase == "menu" then
        menu.keypressed(key)
    else
        input.keypressed(key)
    end
end
