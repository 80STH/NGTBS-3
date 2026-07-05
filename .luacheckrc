-- luacheck config for NGTBS-2 (LÖVE2D hex tactics)
-- Run: luacheck . --codes
--
-- Стратегия: временно разрешаем известные глобалы (пока идёт миграция в gamestate).
-- Цель — постепенно выкинуть всё из `globals` по мере перевода в `state.*` / локали.

std = "luajit"

-- Игнорируем самопальный love-defs и сторонние либы
exclude_files = { "libraries/*" }

-- Кодировка комментариев RU/EN — luacheckwarns на длинных строках, приглушим
max_line_length = 140

-- Чувствительность: предупреждать о неиспользуемых и о глобалах
unused = true
global = true
redefined = false

globals = {
  -- LÖVE2D колбэки и хост
  "love", "_G",

  -- Модули, экспортированные как глобалы (main.lua)
  "state", "combat", "ai", "environment", "status", "ui", "pathfinding",
  "effects", "visual", "config", "menu", "global_abilities", "shop",
  "hex", "sti", "pause_menu",

  -- Игровое состояние (мигрирует в gamestate)
  "entities", "terrainMap", "turnState", "turnCount", "maxTurns",
  "gameActive", "win", "loss", "selectedActor", "selectedAttack",
  "attackMode", "flipTargetActor", "vortexTargetCell", "pushDirTargetCell",
  "pullHookTargetCell", "attackButtons", "sounds", "actionHistory",
  "maxUndoCount", "decayAppliedForTurnLimit", "decayMessageTimer",
  "fireAppliedForTurnLimit", "pushAnimations", "dpiScale", "screenShake",
  "testViewActive", "testViewOffsetY", "gamePhase", "selectedMapPath",
  "selectedSquad", "difficultyModifier", "disableEnemySpawn", "chaos",
  "chaosMax", "unplacedAllies", "isProgressionRun", "currentMapIndex",
  "showAbilityMenu", "abilityMenu", "progressionOverlay", "mapProgression",
  "unitUpgrades", "artifacts", "placedAllies", "deploySelectedIdx",
  "allyPanelButtons", "showEnemyOrder",
  "width", "height", "orientation", "hexStatuses", "deployableAllies",
  "endTurnButton", "undoButton",

  -- Глобальные функции (game.lua / main.lua)
  "syncState", "handleAbilityMenuClick", "handleProgressionOverlayClick",
  "getDrawCoords", "isPositionOccupied", "getPushDirChoices",
  "getEntityAtHex", "isCellPassable", "isCellOccupiedForStop",
  "getEnemyAttackOrder", "restartGame", "endTurn",
  "updateActorMovement", "updateDeathAnimations", "turnManager",
}

-- Разрешаем читать глобалы, объявленные в других файлах (пока)
allow_defined = true
allow_defined_top = false

-- Не считаем ошибкой обращение к полям love
ignore = { "212/self", "212", "542", "113" }
