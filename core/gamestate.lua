-- gamestate.lua
-- Unified game state container.
-- Gradually replaces global variables.
--
-- MIGRATION STATUS: state is currently a "snapshot" — populated by syncState() in main.lua
-- every frame from _G. Full migration (accessing state.* instead of globals) —
-- next stage, requires running the game for verification.
-- To keep the migration localized, all fields are grouped by type below.
local GameState = {}
GameState.__index = GameState
local config = require("core.config")

function GameState.new()
    local self = setmetatable({}, GameState)

    self.config = config

    -- === Tables (passed by reference, syncState updates the pointer) ===
    self.entities = {}
    self.hex = nil
    self.terrainMap = {}
    self.upperTerrainMap = {}
    self.terrainTextures = {}
    self.turnState = {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        currentPreparingEnemy = nil,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false,
        caravansMoving = false,
    }
    self.attackButtons = {}
    self.sounds = {}
    self.pushAnimations = { queue = {}, active = false }
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

    -- === Primitives (syncState copies values every frame) ===
    self.turnCount = 0
    self.maxTurns = 5
    self.gameActive = true
    self.win = false
    self.loss = false
    self.attackMode = false
    self.maxUndoCount = 0
    self.decayAppliedForTurnLimit = false
    self.decayMessageTimer = 0
    self.fireAppliedForTurnLimit = false
    self.showEnemyOrder = false
    self.dpiScale = 1
    self.difficultyModifier = 1
    self.disableEnemySpawn = false

    -- === Entity/cell references (nil or table; syncState copies the reference) ===
    self.selectedActor = nil
    self.selectedAttack = nil
    self.flipTargetActor = nil
    self.vortexTargetCell = nil
    self.pullHookTargetCell = nil
    self.pushDirTargetCell = nil

    -- === UI/progression (fields added during review; not yet synchronized
    --     via syncState, because the renderer reads them from _G directly) ===
    self.gamePhase = "menu"
    self.selectedMapPath = nil
    self.selectedSquad = nil
    self.chaos = 0
    self.chaosMax = 5
    self.isProgressionRun = false
    self.currentMapIndex = 1
    self.showAbilityMenu = false
    self.abilityMenu = nil
    self.progressionOverlay = nil

    return self
end

-- Copies values from _G to self. Called from main.lua:syncState().
-- Tables — by reference (pointer is updated), primitives — by value.
function GameState:syncFromGlobals()
    self.entities = _G.entities or {}
    self.hex = _G.hex
    self.terrainMap = _G.terrainMap or {}
    self.upperTerrainMap = _G.upperTerrainMap or {}
    self.turnState = _G.turnState or self.turnState
    self.turnCount = _G.turnCount or 0
    self.maxTurns = _G.maxTurns or 5
    self.gameActive = _G.gameActive or false
    self.win = _G.win or false
    self.loss = _G.loss or false
    self.selectedActor = _G.selectedActor
    self.selectedAttack = _G.selectedAttack
    self.attackMode = _G.attackMode or false
    self.flipTargetActor = _G.flipTargetActor
    self.vortexTargetCell = _G.vortexTargetCell
    self.pushDirTargetCell = _G.pushDirTargetCell
    self.pullHookTargetCell = _G.pullHookTargetCell
    self.attackButtons = _G.attackButtons or {}
    self.sounds = _G.sounds or {}
    self.actionHistory = (_G.undo and _G.undo.history) or {}
    self.maxUndoCount = _G.maxUndoCount or 0
    self.restartButton = _G.restartButton or self.restartButton
    self.endTurnButton = _G.endTurnButton or self.endTurnButton
    self.undoButton = _G.undoButton or self.undoButton
    self.decayAppliedForTurnLimit = _G.decayAppliedForTurnLimit or false
    self.decayMessageTimer = _G.decayMessageTimer or 0
    self.fireAppliedForTurnLimit = _G.fireAppliedForTurnLimit or false
    self.pushAnimations = _G.pushAnimations or self.pushAnimations
    self.dpiScale = _G.dpiScale or 1
    self.difficultyModifier = _G.difficultyModifier or 1
    self.disableEnemySpawn = _G.disableEnemySpawn or false
    self.showEnemyOrder = _G.showEnemyOrder or false
    self.chaos = _G.chaos or 0
    self.chaosMax = _G.chaosMax or 5
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
