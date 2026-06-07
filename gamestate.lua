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
    self.maxTurns = 5
    self.gameActive = true
    self.win = false
    self.loss = false

    self.selectedActor = nil
    self.selectedAttack = nil
    self.attackMode = false
    self.flipTargetActor = nil
    self.attackButtons = {}
    self.sounds = {}

    self.actionHistory = {}
    self.maxUndoCount = 0


    self.restartButton = {
        x = 10, y = 295, width = 120, height = 30,
        text = "Restart Game", isHovered = false,
    }
    self.endTurnButton = {
        x = 10, y = 260, width = 120, height = 30,
        text = "End Turn", isHovered = false,
        holdTimer = 0, isHeld = false,
    }
    self.undoButton = { isHovered = false }

    self.decayAppliedForTurnLimit = false
    self.decayMessageTimer = 0
    self.fireAppliedForTurnLimit = false

    self.pushAnimations = { queue = {}, active = false }

    self.showEnemyOrder = false

    self.dpiScale = 1

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
