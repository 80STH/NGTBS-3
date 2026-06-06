-- gamestate.lua
-- Единый контейнер состояния игры.
-- Постепенно заменяет глобальные переменные.
local GameState = {}
local config = require("config")

function GameState.new()
    local self = {}

    self.config = config
    self.entities = {}
    self.hex = nil
    self.terrainMap = {}
    self.terrainTextures = {}

    self.globalHealth = { current = 5, max = 5, initial = 5 }

    self.turnState = {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false,
    }
    self.turnCount = 0
    self.maxTurns = 1
    self.gameActive = true
    self.win = false
    self.loss = false

    self.selectedActor = nil
    self.selectedAttack = nil
    self.attackMode = false
    self.attackButtons = {}
    self.sounds = {}

    self.actionHistory = {}
    self.maxUndoCount = 0

    self.windTorrent = nil
    self.windTorrentUI = {
        active = false,
        button = { x = 10, y = 240, width = 120, height = 30, isHovered = false },
    }

    self.restartButton = {
        x = 10, y = 320, width = 120, height = 30,
        text = "Restart Game", isHovered = false,
    }
    self.endTurnButton = {
        x = 10, y = 280, width = 120, height = 30,
        text = "End Turn", isHovered = false,
    }
    self.undoButton = { isHovered = false }

    self.decayAppliedForTurnLimit = false
    self.decayMessageTimer = 0
    self.fireAppliedForTurnLimit = false

    self.pushAnimations = { queue = {}, active = false }

    self.showEnemyOrder = false

    self.DEBUG_COMBAT = true

    return self
end

function GameState:getPlayableActors()
    local actors = {}
    for _, e in ipairs(self.entities) do
        if e.isPlayable and e.health > 0 then
            table.insert(actors, e)
        end
    end
    return actors
end

function GameState:getLivingEnemies()
    local enemies = {}
    for _, e in ipairs(self.entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            table.insert(enemies, e)
        end
    end
    return enemies
end

function GameState:getEntityAtHex(q, r)
    for _, e in ipairs(self.entities) do
        if e.q == q and e.r == r then
            return e
        end
    end
    return nil
end

function GameState:countPlayableActors()
    local count = 0
    for _, e in ipairs(self.entities) do
        if e.isPlayable then
            count = count + 1
        end
    end
    return count
end

function GameState:getDrawCoords(q, r)
    local x, y = self.hex:hexToPixel(q, r)
    if self.terrainMap and self.terrainMap[q] and self.terrainMap[q][r] == "water" then
        y = y + config.WATER_Y_OFFSET
    end
    return x, y
end

function GameState:isPositionOccupied(q, r, movingEntity)
    if not self.hex:isActiveHex(q, r) then return true end
    if self.terrainMap and self.terrainMap[q] and self.terrainMap[q][r] == "water" then return true end
    for _, e in ipairs(self.entities) do
        if e ~= movingEntity and e.q == q and e.r == r then return true end
    end
    return false
end

function GameState:hasLivingEnemies()
    for _, e in ipairs(self.entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then return true end
    end
    return false
end

function GameState:hasLivingAllies()
    for _, e in ipairs(self.entities) do
        if e.isPlayable and e.health > 0 and not e.isDying then return true end
    end
    return false
end

return GameState
