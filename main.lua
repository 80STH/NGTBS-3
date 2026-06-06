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
require("game")

pushAnimations = state.pushAnimations

windTorrent = nil

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
    attackButtons = state.attackButtons
    sounds = state.sounds
    actionHistory = state.actionHistory
    maxUndoCount = state.maxUndoCount
    windTorrent = state.windTorrent
    windTorrentUI = state.windTorrentUI
    restartButton = state.restartButton
    endTurnButton = state.endTurnButton
    undoButton = state.undoButton
    decayAppliedForTurnLimit = state.decayAppliedForTurnLimit
    decayMessageTimer = state.decayMessageTimer
    fireAppliedForTurnLimit = state.fireAppliedForTurnLimit
    pushAnimations = state.pushAnimations
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
    state.attackButtons = attackButtons
    state.sounds = sounds
    state.actionHistory = actionHistory
    state.maxUndoCount = maxUndoCount
    state.windTorrent = windTorrent
    state.windTorrentUI = windTorrentUI
    state.restartButton = restartButton
    state.endTurnButton = endTurnButton
    state.undoButton = undoButton
    state.decayAppliedForTurnLimit = decayAppliedForTurnLimit
    state.decayMessageTimer = decayMessageTimer
    state.fireAppliedForTurnLimit = fireAppliedForTurnLimit
    state.pushAnimations = pushAnimations
end

function love.load()
    selectedAttack = nil
    attackMode = false
    attackButtons = {}
    restartButton = {
        x = 10, y = 320, width = 120, height = 30,
        text = "Restart Game", isHovered = false
    }
    sti = require 'libraries/sti'
    local hexStatuses
    terrainMap, entities, width, height, hexStatuses = environment.loadMapFromTiled('maps/map1.lua')
    hex = require("hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        config.ACTIVE_RADIUS,
        config.CENTER_Q,
        config.CENTER_R
    )

    turnCount = 0
    maxTurns = 1
    decayAppliedForTurnLimit = false
    decayMessageTimer = 0
    gameActive = true
    win = false
    loss = false
    fireAppliedForTurnLimit = false

    windTorrentUI = {
        active = false,
        button = { x = 10, y = 240, width = 120, height = 30 }
    }
    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())

    status.initHexStatuses(hexStatuses)

    globalHealth = { current = 5, max = 5, initial = 5 }
    combat.globalHealth = globalHealth

    turnState = {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false
    }

    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.hasPreparedAttack = false
            e.preparePos = nil
            e.preparedTarget = nil
            e.movementFinished = false
        end
    end

    selectedActor = nil
    for _, a in ipairs(entities) do
        if a.isPlayable and a.health > 0 then
            selectedActor = a
            hex.selectedQ, hex.selectedR = a.q, a.r
            break
        end
    end

    for _, a in ipairs(entities) do
        if a.isPlayable then
            a.hasActedThisTurn = false
            a.hasMovedThisTurn = false
        end
    end

    turnManager.startGame()

    hex:centerOnScreen(love.graphics.getWidth(), love.graphics.getHeight())

    sounds = {}
    sounds.undo = love.audio.newSource("sounds/hover.wav", "static")
    sounds.undo:setVolume(0.4)
    sounds.turn = love.audio.newSource("sounds/hover.wav", "static")
    sounds.turn:setVolume(0.3)
    sounds.attack = love.audio.newSource("sounds/blip.wav", "static")
    sounds.attack:setVolume(0.5)
    sounds.collision = love.audio.newSource("sounds/blip.wav", "static")
    sounds.collision:setVolume(0.6)

    maxUndoCount = countPlayableActors()
    actionHistory = {}

    endTurnButton = {
        x = 10, y = 280, width = 120, height = 30,
        text = "End Turn", isHovered = false
    }

    windTorrent = combat.WindTorrentAttack.new()

    windTorrentUI.button = { x = 10, y = 240, width = 120, height = 30, isHovered = false }

    syncGlobalsToState()
end

function getDrawCoords(q, r)
    local x, y = hex:hexToPixel(q, r)
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
        y = y + config.WATER_Y_OFFSET
    end
    return x, y
end

function getWindDirectionFromHex(q, r, centerQ, centerR, hex)
    local cx, cy, cz = hex_utils.axialToCube(centerQ, centerR)
    local x, y, z = hex_utils.axialToCube(q, r)
    local dx, dy, dz = x - cx, y - cy, z - cz

    if dx == 0 and dy == 0 and dz == 0 then
        return nil
    end

    local absDx, absDy, absDz = math.abs(dx), math.abs(dy), math.abs(dz)
    local maxVal = math.max(absDx, absDy, absDz)

    local ndx = math.floor(dx / maxVal + 0.5)
    local ndy = math.floor(dy / maxVal + 0.5)
    local ndz = math.floor(dz / maxVal + 0.5)

    if ndx + ndy + ndz ~= 0 then
        return nil
    end

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

function love.mousepressed(x, y, button)
    input.mousepressed(x, y, button)
end

function isPositionOccupied(q, r, movingEntity)
    if not hex:isActiveHex(q, r) then
        return true
    end
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then
        return true
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

    turnManager.update(dt)

    local mx, my = love.mouse.getPosition()
    local hq, hr = hex:pixelToHex(mx, my)
    if hex:isActiveHex(hq, hr) then
        hex.hoverQ, hex.hoverR = hq, hr
    else
        hex.hoverQ, hex.hoverR = -1, -1
    end

    undoButton = undoButton or {}
    undoButton.isHovered = (mx >= 10 and mx <= 130 and my >= 200 and my <= 230)
    endTurnButton.isHovered = (mx >= endTurnButton.x and mx <= endTurnButton.x + endTurnButton.width and
                               my >= endTurnButton.y and my <= endTurnButton.y + endTurnButton.height)
    windTorrentUI.button.isHovered = (mx >= windTorrentUI.button.x and mx <= windTorrentUI.button.x + windTorrentUI.button.width and
                                      my >= windTorrentUI.button.y and my <= windTorrentUI.button.y + windTorrentUI.button.height)
end

function love.draw()
    syncGlobalsToState()
    renderer.draw(state)
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
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "water" then return false end
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
    input.keypressed(key)
end
