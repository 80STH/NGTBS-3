-- game.lua
-- Game lifecycle: restart, end check, global effects.
-- Functions are global (used by other modules via _G).

local turnManager = require("core.turn_manager")
local objectives = require("system.objectives")
local trains = require("system.trains")
local Entity = require("entity.entity")
local log = require("util.log")
local cell_rules = require("grid.cell_rules")
local hex_utils = require("grid.hex_utils")
local visual = require("system.visual_effects")
local environment = require("entity.environment")
local status = require("system.status")

_G.graveyard = {}

local function newTurnState()
    return {
        phase = "enemy_prepare",
        enemyPrepareQueue = {},
        _batchMovePlanning = false,
        _waitingForMoves = false,
        enemyAttackQueue = {},
        enemyAttackTimer = 0,
        delayBetweenAttacks = 0.4,
        pendingDigProcessing = false,
        caravansMoving = false,
    }
end

local function resetEnemyPrepareFlags()
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable then
            e.hasPreparedAttack = false
            e.preparePos = nil
            e.preparedTarget = nil
            e.movementFinished = false
            e.isMoving = false
            e.path = {}
            e.currentPathIndex = 0
            e._reservedCell = nil
        end
        if e.rootedTarget then
            status.removeFromEntity(e.rootedTarget, "rooted")
            e.rootedTarget = nil
        end
    end
end

local function placeRubble(e)
    if e:isObstacle() and not e.indestructible then
        if not upperTerrainMap[e.q] then upperTerrainMap[e.q] = {} end
        upperTerrainMap[e.q][e.r] = "mountain_rubble"
    elseif e:isBuilding() and not e.isTrainCar
        and e.name ~= "TunnelEntrance" and e.name ~= "TunnelExit" and e.name ~= "OccupiedTunnel" then
        if not upperTerrainMap[e.q] then upperTerrainMap[e.q] = {} end
        upperTerrainMap[e.q][e.r] = "building_rubble"
    end
end

-- ============================================================
-- STONE PILLAR: collapses onto an adjacent cell when destroyed,
-- crushing everything there and re-forming as a new 1 HP pillar.
-- ============================================================
local pendingPillarSpawns = {}

-- First living (non-dying) entity occupying a cell
local function livingEntityAt(q, r)
    for _, v in ipairs(entities) do
        if not v.isDying then
            if v.q == q and v.r == r then return v end
            if v.cells then
                for _, c in ipairs(v.cells) do
                    if c.q == q and c.r == r then return v end
                end
            end
        end
    end
    return nil
end

-- All valid collapse targets for a pillar at (q,r): faced cell first, then
-- other adjacent active non-water hexes. Skips cells that can't be crushed
-- (indestructible occupants or another StonePillar — prevents infinite
-- collapse ping-pong).
local function pillarCollapseTargets(q, r, dir)
    local faced, others = nil, {}
    for _, d in ipairs(hex_utils.CUBE_DIRECTIONS) do
        local nq, nr = hex_utils.applyCubeStep(q, r, d.dx, d.dy, d.dz)
        if hex and hex:isActiveHex(nq, nr) then
            local t = terrainMap and terrainMap[nq] and terrainMap[nq][nr]
            if not cell_rules.isHoleTerrain(t) then
                local occ = livingEntityAt(nq, nr)
                if not occ or (not occ.indestructible and occ.name ~= "StonePillar") then
                    if dir and d.dx == dir.dx and d.dy == dir.dy and d.dz == dir.dz then
                        faced = { q = nq, r = nr }
                    else
                        table.insert(others, { q = nq, r = nr })
                    end
                end
            end
        end
    end
    return faced, others
end

local function planPillarCollapse(q, r, dir)
    local faced, others = pillarCollapseTargets(q, r, dir)
    if faced then return faced end
    if #others == 0 then return nil end
    return others[love.math.random(#others)]
end

-- Hover preview: where would this pillar fall, who gets crushed?
-- Deterministic when the faced cell is valid or only one option exists.
function previewPillarFall(pillar)
    local faced, others = pillarCollapseTargets(pillar.q, pillar.r, pillar.direction)
    local result = { target = faced, fallbacks = others, victims = {} }
    local cell = faced or (#others == 1 and others[1] or nil)
    if cell then
        for _, v in ipairs(entities) do
            if not v.isDying and v.health > 0 and not v.indestructible then
                local onCell = v.q == cell.q and v.r == cell.r
                if not onCell and v.cells then
                    for _, c in ipairs(v.cells) do
                        if c.q == cell.q and c.r == cell.r then onCell = true break end
                    end
                end
                if onCell then table.insert(result.victims, v) end
            end
        end
    end
    return result
end

local function crushCell(target)
    -- Kill every living occupant, then queue the new pillar until corpses clear
    local crushed = false
    for _, v in ipairs(entities) do
        if not v.isDying and v.health > 0 and not v.indestructible then
            local onCell = v.q == target.q and v.r == target.r
            if not onCell and v.cells then
                for _, c in ipairs(v.cells) do
                    if c.q == target.q and c.r == target.r then onCell = true break end
                end
            end
            if onCell then
                v:startDeath()
                crushed = true
            end
        end
    end
    table.insert(pendingPillarSpawns, target)
    if crushed then
        local cx, cy = hex:hexToPixel(target.q, target.r)
        visual.addEffect(cx, cy, "slam", 0.4)
        log.infof("game", "StonePillar collapses onto (%d,%d), crushing occupants!", target.q, target.r)
    end
end

-- Spawn queued pillars once their cell is free of dying corpses
local function processPillarSpawns()
    for i = #pendingPillarSpawns, 1, -1 do
        local p = pendingPillarSpawns[i]
        if not livingEntityAt(p.q, p.r) then
            local pillar = Entity.new("StonePillar", Entity.TYPES.OBSTACLE, p.q, p.r, 1, false, 0, nil, nil, {})
            pillar.sprite = environment.generateBuildingSprite("StonePillar", 12, 16)
            pillar.noSidedPush = true
            if p.dir then
                pillar.direction = { dx = p.dir.dx, dy = p.dir.dy, dz = p.dir.dz }
            end
            table.insert(entities, pillar)
            table.remove(pendingPillarSpawns, i)
        end
    end
end

function restartGame(mapPath)
    mapPath = mapPath or selectedMapPath or 'maps/map1.lua'
    selectedMapPath = mapPath
    log.infof("game", "=== RESTARTING GAME: %s ===", mapPath)

    -- Guarantee a clean turnState on every restart.
    turnState = newTurnState()
    boundarySelected = nil
    pendingPillarSpawns = {}

    local hexStatuses
    local deployableAllies

    -- Load native format map
    local mapData = love.filesystem.load(mapPath)()
    local mapActiveRadius, mapCenterQ, mapCenterR
    terrainMap, entities, width, height, hexStatuses, _, deployableAllies, orientation, upperTerrainMap = environment.loadNativeMap(mapData)
    elevationMap = {}
    if mapData and mapData.elevation then
        for key, elv in pairs(mapData.elevation) do
            local q, r = key:match("^(%d+),(%d+)$")
            if q and r then
                q, r = tonumber(q), tonumber(r)
                if not elevationMap[q] then elevationMap[q] = {} end
                elevationMap[q][r] = (elv == true or elv == "high")
            end
        end
    end

    -- Retractable highground: cells toggleable via the Mechanism button
    retractableCells = {}
    if mapData and mapData.retractable then
        for key in pairs(mapData.retractable) do
            local q, r = key:match("^(%d+),(%d+)$")
            if q and r then
                q, r = tonumber(q), tonumber(r)
                table.insert(retractableCells, { q = q, r = r })
            end
        end
    end
    -- Unique lift texture for retractable cells (upper terrain follows the
    -- raise/lower animation and is already covered by undo snapshots)
    for _, c in ipairs(retractableCells) do
        if not upperTerrainMap[c.q] then upperTerrainMap[c.q] = {} end
        upperTerrainMap[c.q][c.r] = "lift"
    end
    highgroundRaised = false
    mechanismUsedThisTurn = false
    highgroundAnim = nil

    -- Conveyor belt cells (upper terrain "conveyor:<dir>"), driven by the Mechanism button
    local HexGrid = require("grid.hexgrid")
    conveyorCells = {}
    for q, row in pairs(upperTerrainMap or {}) do
        for r, val in pairs(row) do
            local dirName = val and val:match("^conveyor:(%a+)$")
            if dirName and HexGrid.CONVEYOR_DIRS[dirName] then
                conveyorCells[q .. "," .. r] = HexGrid.CONVEYOR_DIRS[dirName]
            end
        end
    end
    -- Button-activated hazard plates: "spikes", "burner", "oxidizer" markers.
    -- Stored as an ordered list so the Mechanism press ticks each occupied cell once.
    mechanismTrapCells = {}
    for q, row in pairs(upperTerrainMap or {}) do
        for r, val in pairs(row) do
            if val == "spikes" or val == "burner" or val == "oxidizer" then
                table.insert(mechanismTrapCells, { q = q, r = r, type = val })
            end
        end
    end
    mapActiveRadius = mapData and mapData.activeRadius or config.ACTIVE_RADIUS
    mapCenterQ = mapData and mapData.centerQ or config.CENTER_Q or math.floor(width / 2)
    mapCenterR = mapData and mapData.centerR or config.CENTER_R or math.floor(height / 2)
    orientation = orientation or "pointy"

    hex = require("grid.hexgrid").new(
        config.HEX_RADIUS,
        width, height,
        mapActiveRadius,
        mapCenterQ,
        mapCenterR,
        orientation,
        mapData and mapData.activeRows or nil
    )
    hex:centerOnScreen(love.graphics.getWidth() / dpiScale, love.graphics.getHeight() / dpiScale)
    hex.rotation = (orientation == "flat") and 0 or config.GRID_ROTATION_ANGLE

    status.initHexStatuses(hexStatuses)



    resetEnemyPrepareFlags()

    -- Map4: Power Lich boss
    if mapPath:match("map4") then
        local spots = findRandomEmptyCells(1, function(q, r)
            return status.hasNegativeHexStatus(q, r)
        end)
        if #spots >= 1 then
            local cell = spots[1]
            local lich = environment.createEnemyByType("PowerLich", cell.q, cell.r)
            lich.isLeader = true
            table.insert(entities, lich)
            log.debugf("game", "Power Lich placed at (%d,%d)", cell.q, cell.r)
        end
    end

    -- Spawn random enemies at game start
    local initialAlive = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isSummoningRod then
            initialAlive = initialAlive + 1
        end
    end
    local enemyTarget = soloMode and 3 or 5
    if initialAlive < enemyTarget then
        local needed = enemyTarget - initialAlive
        local spots = findRandomEmptyCells(needed, function(q, r)
            return status.hasNegativeHexStatus(q, r)
        end)
        for _, cell in ipairs(spots) do
            local enemy = environment.createRandomEnemy(cell.q, cell.r)
            table.insert(entities, enemy)
            log.debugf("game", "Initial spawn: %s at (%d,%d)", enemy.name, cell.q, cell.r)
        end
        log.infof("game", "Initial spawn complete: %d enemies added (total %d)", #spots, initialAlive + #spots)
    end

    -- Setup deploy phase
    local skipDeploy = mapPath:match("test_polygon_[12]")
    -- Soul Power resource: fresh runs get a full budget; subsequent level
    -- restarts keep whatever survived (progress carries between missions).
    if soulPower == nil then soulPower = soulPowerMax or 5 end
    hero = nil
    heroRevivePending = false
    heroDeathPos = nil
    if soloMode and selectedSoloHero then
        hero = environment.createSoloHero(selectedSoloHero, -1, -1)
        unplacedAllies = { hero }
    else
        unplacedAllies = deployableAllies or {}
    end
    placedAllies = {}
    deploySelectedIdx = nil

    if not skipDeploy then
        for _, ally in ipairs(unplacedAllies) do
            ally.q = -1
            ally.r = -1
        end
    end

    selectedActor = nil
    hex.selectedQ = -1
    hex.selectedR = -1
    hex.hoverQ = -1
    hex.hoverR = -1

    if not isProgressionRun then
        global_abilities.initWithCommander(selectedCommander)
    end
    global_abilities.reset()
    _G.graveyard = {}
    if not isProgressionRun then
        _G.genericUpgrades = {}
    end
    dpiScale = love.window.getDPIScale()

    flipTargetActor = nil
    mightyThrowTarget = nil
    vortexTargetCell = nil
    cleaveTargetCell = nil
    pushDirTargetCell = nil
    attackMode = false
    selectedAttack = nil
    attackButtons = {}
    undo.clear()
    if pushAnimations and pushAnimations.clear then pushAnimations.clear() end
    if combat and combat.clearPendingDeaths then combat.clearPendingDeaths() end
    visual.effects = {}
    decayMessageTimer = 0

    maxUndoCount = 0

    turnCount = 0
    gameActive = true
    win = false
    loss = false
    _G.slowMode = false
    fireAppliedForTurnLimit = false
    decayAppliedForTurnLimit = false
    chaos = 0
    lichKilledPlayer = false
    status.clearAllDigSites()

    -- map3 train setup: inject tunnels and railway if needed
    if mapPath:match("map3") then
        local hasTunnels = false
        for _, e in ipairs(entities) do
            if e.name == "TunnelEntrance" or e.name == "TunnelExit" then hasTunnels = true; break end
        end
        if not hasTunnels then
            local envMod = require("entity.environment")
            local loadedMap = envMod.loadedMap
            local tileW = (loadedMap and loadedMap.tilewidth) or 14
            local tileH = (loadedMap and loadedMap.tileheight) or 12
            local entranceData = {{2,2},{2,6}}
            local exitData = {{6,2},{6,6}}
            local railCells = {{2,2},{3,2},{4,2},{5,2},{6,2},{2,6},{3,6},{4,6},{5,6},{6,6}}
            local railDirs = {1,2,1,2,2, 1,2,1,2,2}

            for i, cell in ipairs(railCells) do
                local q, r = cell[1], cell[2]
                if not upperTerrainMap[q] then upperTerrainMap[q] = {} end
                upperTerrainMap[q][r] = "railway:" .. railDirs[i]
            end

            for _, td in ipairs(entranceData) do
                local tunnel = Entity.new("TunnelEntrance", Entity.TYPES.BUILDING, td[1], td[2], 2, false, 0, nil, nil, {})
                tunnel.isObjective = true
                tunnel.indestructible = true
                tunnel.sprite = envMod.generateBuildingSprite("TunnelEntrance", tileW, tileH)
                table.insert(entities, tunnel)
                log.debugf("game", "Placed TunnelEntrance at (%d,%d)", td[1], td[2])
            end
            for _, td in ipairs(exitData) do
                local tunnel = Entity.new("TunnelExit", Entity.TYPES.BUILDING, td[1], td[2], 2, false, 0, nil, nil, {})
                tunnel.isObjective = true
                tunnel.indestructible = true
                tunnel.sprite = envMod.generateBuildingSprite("TunnelExit", tileW, tileH)
                table.insert(entities, tunnel)
                log.debugf("game", "Placed TunnelExit at (%d,%d)", td[1], td[2])
            end
        end
    end

    trains.init(entities, terrainMap, hex)
    require("system.teleporters").scan(upperTerrainMap)
    objectives.reset()
    objectives.generate(entities, hex, mapData and mapData.objectives)
    objectives.update(entities)

    if skipDeploy then
        for _, ally in ipairs(unplacedAllies) do
            table.insert(entities, ally)
        end
        unplacedAllies = {}
        placedAllies = {}
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
        turnState = newTurnState()
        resetEnemyPrepareFlags()
        updateAttackButtons(selectedActor)
        maxUndoCount = countPlayableActors()
        turnManager.startGame()
        gamePhase = "playing"
    else
        gamePhase = "deploy"
    end
    clearCellDuplicateWarnings()
    rebuildEntityIndex()
    log.infof("game", "=== MAP LOADED — %s ===", (skipDeploy and "GAME STARTED" or "DEPLOY YOUR ALLIES"))
end

function confirmDeploy()
    -- Hero redeploy after a death-save: simple landing, no deploy effects,
    -- no turn restart — the player turn is already running.
    if soloMode and heroRevivePending and hero and #placedAllies == 1 and placedAllies[1] == hero then
        table.insert(entities, hero)
        heroRevivePending = false
        -- Coming back from a death-save costs 1 move point (not an attack).
        heroDeathPos = nil
        hero.hasActedThisTurn = false
        hero.hasMovedThisTurn = false
        hero.canMoveAfterAttack = false
        hero.attacksLeft = 2
        hero.movesLeft = math.max(1, (hero.movesLeft or 2) - 1)
        selectedActor = hero
        hex.selectedQ, hex.selectedR = hero.q, hero.r
        unplacedAllies = {}
        placedAllies = {}
        deploySelectedIdx = nil
        updateAttackButtons(hero)
        rebuildEntityIndex()
        gamePhase = "playing"
        log.info("game", "=== HERO REDEPLOYED — TURN CONTINUES ===")
        return
    end

    local deploy_effects = require("system.deploy_effects")
    for _, ally in ipairs(placedAllies) do
        table.insert(entities, ally)
    end

    -- Landing effects: each ally triggers its deploy effect at its cell
    for _, ally in ipairs(placedAllies) do
        deploy_effects.apply(ally, ally.q, ally.r)
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

    turnState = newTurnState()
    resetEnemyPrepareFlags()

    updateAttackButtons(selectedActor)
    maxUndoCount = countPlayableActors()
    gameActive = true
    rebuildEntityIndex()

    turnManager.startGame()
    gamePhase = "playing"

    unplacedAllies = {}
    placedAllies = {}
    deploySelectedIdx = nil

    log.info("game", "=== DEPLOY CONFIRMED — GAME STARTED ===")
end

-- Solo losses (building damage, objectives, train cars) drain Soul Power
-- instead of the chaos meter (non-solo keeps the chaos meter). Hitting zero
-- ends the run unless the hero can still fight on borrowed time — see loss rules.
function spendSoul(amount)
    if _G.soloMode and soulPower ~= nil then
        soulPower = math.max(0, soulPower - amount)
        log.infof("game", "Soul Power -%d (now %d/%d)", amount, soulPower, soulPowerMax)
        if soulPower <= 0 then
            loss = true
            gameActive = false
            log.warn("game", "DEFEAT: Soul Power is spent! The realm has nothing left.")
        end
    end
end

-- Kept name so older call sites (Entity damage on buildings/trains and the
-- objective failures) still work: those losses are now soul-power drains.
function damageHero(amount)
    spendSoul(amount)
end

-- Solo hero respawn (called from Entity.takeDamage/startDeath on a lethal
-- hit). Costs 1 Soul Power; the hero comes back next player turn with only
-- 1 HP. Without soul power the hero truly dies (run over).
-- Returns true when the hero is truly destroyed, false when revived.
function heroDeathSave(h)
    if (soulPower or 0) > 0 and h._trueDeath ~= true then
        soulPower = soulPower - 1
        h.health = 1                   -- revived hero appears with 1 HP
        log.infof("game", "%s falls! A soul is spent (%d/%d left), he returns with 1 HP.",
            h.name, soulPower, soulPowerMax)

        -- Vanish from the field; mandatory simple redeploy next player turn
        heroDeathPos = { q = h.q, r = h.r }
        for i, e in ipairs(entities) do
            if e == h then table.remove(entities, i) break end
        end
        if status.getEntityStatuses then
            for _, s in ipairs(status.getEntityStatuses(h)) do
                status.removeFromEntity(h, s)
            end
        end
        h.isDying = false
        heroRevivePending = true
        selectedActor = nil
        if hex then hex.selectedQ, hex.selectedR = -1, -1 end
        if updateAttackButtons then updateAttackButtons(nil) end
        if hex and hex.hexToPixel then
            local cx, cy = hex:hexToPixel(h.q, h.r)
            visual.addEffect(cx, cy, "slam", 0.5)
        end
        rebuildEntityIndex()
        log.info("game", "The hero drops — redeploy him next turn!")
        return false
    end

    h._trueDeath = true
    h.health = 0
    h:startDeath()
    checkGameEnd()
    log.info("game", "DEFEAT: the hero has no soul power left to return!")
    return true
end

-- The Mechanism button: one press drives every environment mechanism on
-- the map at once — toggles the retractable highground, activates the
-- teleporters and runs the conveyor belts. 1-turn cooldown.
function activateMechanisms()
    local teleporters = require("system.teleporters")
    local anyMechanism = (#retractableCells > 0) or teleporters.hasActivePair()
        or next(conveyorCells or {}) ~= nil or (mechanismTrapCells and #mechanismTrapCells > 0)
    if not anyMechanism then return false end
    if mechanismUsedThisTurn then return false end

    -- 1. Retractable highground: flip elevation (logic instantly, visuals animate)
    if #retractableCells > 0 then
        highgroundRaised = not highgroundRaised
        for _, c in ipairs(retractableCells) do
            if highgroundRaised then
                if not elevationMap[c.q] then elevationMap[c.q] = {} end
                elevationMap[c.q][c.r] = true
            else
                if elevationMap[c.q] then elevationMap[c.q][c.r] = nil end
            end
        end
        highgroundAnim = {
            start = love.timer.getTime(),
            duration = 0.5,
            raising = highgroundRaised,
        }
        log.infof("game", "Highground %s", highgroundRaised and "raised" or "lowered")
    end

    -- 2. Teleporters: everyone standing on a portal is teleported (or swapped)
    if teleporters.hasActivePair() then
        for _, e in ipairs(entities) do
            if e:isCharacter() and e.health > 0 and not e.isDying and not e.isMoving then
                combat.triggerTeleporter(e)
            end
        end
    end

    -- 3. Conveyor belts: every character on a belt cell is pushed one step;
    -- being pushed into an occupied cell counts as a collision.
    if next(conveyorCells or {}) ~= nil then
        local hex_utils = require("grid.hex_utils")
        for _, e in ipairs(entities) do
            if e:isCharacter() and e.health > 0 and not e.isDying and not e.isMoving then
                local dir = conveyorCells[e.q .. "," .. e.r]
                if dir then
                    local nq, nr = hex_utils.applyCubeStep(e.q, e.r, dir[1], dir[2], dir[3])
                    if hex:isActiveHex(nq, nr) then
                        local occupant = getEntityAtHex(nq, nr)
                        if occupant then
                            -- Collision: both take 1 damage, pushed unit bounces back
                            combat.applyCollisionDamage(e, occupant, sounds)
                            combat.addCollisionBounceAnimation(e, e.q, e.r, nq, nr, hex, entities, sounds, occupant)
                            log.infof("game", "Conveyor slams %s into %s at (%d,%d)!", e.name, occupant.name, nq, nr)
                        else
                            local terrain = terrainMap and terrainMap[nq] and terrainMap[nq][nr] or "grass"
                            if not cell_rules.isHoleTerrain(terrain) or e.waterWalker or e.hovering then
                                combat.moveEntityWithAnimation(e, e.q, e.r, nq, nr)
                                log.infof("game", "Conveyor moves %s to (%d,%d)", e.name, nq, nr)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 4. Hazard plates: spikes deal 1 damage, burners ignite, oxidizers
    --    coat in acid — to every living character standing on a marked cell.
    if mechanismTrapCells and #mechanismTrapCells > 0 then
        for _, cell in ipairs(mechanismTrapCells) do
            for _, e in ipairs(entities) do
                if e:isCharacter() and e.health > 0 and not e.isDying and not e.isMoving
                    and e.q == cell.q and e.r == cell.r then
                    if cell.type == "spikes" then
                        local x, y = hex:hexToPixel(cell.q, cell.r)
                        local wasDestroyed = e:takeDamage(1)
                        visual.addEffect(x, y, "slam", 0.35)
                        sounds.play("collision")
                        log.infof("game", "Spikes hit %s for 1 damage!", e.name)
                        if wasDestroyed then e:startDeath() end
                    elseif cell.type == "burner" then
                        if not status.hasEntityStatus(e, "fire") then
                            status.applyToEntity(e, "fire")
                            sounds.play("fire")
                            log.infof("game", "Burner ignites %s!", e.name)
                        end
                    elseif cell.type == "oxidizer" then
                        if not status.hasEntityStatus(e, "acid") then
                            status.applyToEntity(e, "acid")
                            log.infof("game", "Oxidizer coats %s in acid!", e.name)
                        end
                    end
                end
            end
        end
    end

    mechanismUsedThisTurn = true
    undo.snapshot()
    if sounds then sounds.play("click") end
    return true
end

function checkGameEnd()
    if not gameActive then return end

    if soloMode then
        if not (hero and hero.health > 0 and not hero.isDying) then
            loss = true
            gameActive = false
            log.warn("game", "DEFEAT: The hero has fallen!")
            return
        end
    end

    if (chaos or 0) >= chaosMax then
        loss = true
        gameActive = false
        log.warn("game", "DEFEAT: Chaos has consumed the realm!")
        return
    end

    local anyEnemy = false
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isDying then
            anyEnemy = true
            break
        end
    end
    if not anyEnemy and decayAppliedForTurnLimit then
        win = true
        gameActive = false
        objectives.checkOnVictory(entities)
        log.info("game", "VICTORY: All enemies defeated after turn limit!")
        return
    end
end

function applyDecayToAllEnemies()
    log.debugf("game", "applyDecayToAllEnemies called, turnCount=%s maxTurns=%s", turnCount, maxTurns)
    local count = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            count = count + 1
            if not status.hasEntityStatus(e, "decay") then
                status.applyToEntity(e, "decay")
                log.debugf("game", "Decay afflicts %s", e.name)
            end
        end
    end
    log.debugf("game", "Total living enemies found: %d", count)
end

function updateDeathAnimations(dt)
    for i = #entities, 1, -1 do
        local e = entities[i]
        if e.isDying then
            e.deathTimer = e.deathTimer + dt
            if e.deathTimer >= e.deathDuration then
                if e.isTrainCar then
                    local trains_mod = require("system.trains")
                    local group = trains_mod.getCarGroup(e)
                    if group then
                        group.active = false
                        local loco = group.cars[1]
                        if loco then
                            loco.hasPreparedAttack = false
                            loco.isTrainAttack = nil
                        end
                    end
                end
                if e.name == "TunnelEntrance" or e.name == "TunnelExit" or e.name == "OccupiedTunnel" then
                    local dtunnel = Entity.new("DestroyedTunnel", Entity.TYPES.BUILDING, e.q, e.r, 1, false, 0, nil, nil, {})
                    dtunnel.indestructible = true
                    dtunnel.sprite = environment.generateBuildingSprite("DestroyedTunnel", 12, 12)
                    table.insert(entities, dtunnel)
                end
                if e.name == "MountainHouse" or e.name == "SmallMountainHouse" then
                    local ruined = Entity.new("RuinedMountainHouse", Entity.TYPES.BUILDING, e.q, e.r, 1, false, 0, nil, nil, {})
                    ruined.indestructible = true
                    ruined.sprite = environment.generateBuildingSprite("RuinedMountainHouse", 12, 12)
                    table.insert(entities, ruined)
                end

                -- StonePillar: collapse onto an adjacent cell (faced if possible)
                if e.name == "StonePillar" then
                    local target = planPillarCollapse(e.q, e.r, e.direction)
                    if target then
                        target.dir = e.direction and { dx = e.direction.dx, dy = e.direction.dy, dz = e.direction.dz }
                        crushCell(target)
                    end
                end

                -- Place upper_terrain rubble for destroyed buildings/obstacles
                placeRubble(e)

                if e.isPlayable and e:isCharacter() and e.health <= 0 then
                    _G.graveyard = _G.graveyard or {}
                    table.insert(_G.graveyard, {
                        name = e.name, q = e.q, r = e.r,
                        maxHealth = e.maxHealth, moveRange = e.moveRange,
                        hovering = e.hovering,
                        teleporting = e.teleporting, waterWalker = e.waterWalker,
                        sprite = e.sprite, color = e.color,
                        attacks = e.attacks, upgradeLevel = e.upgradeLevel,
                    })
                    log.infof("game", "Ally %s added to graveyard at (%d,%d)", e.name, e.q, e.r)
                end

                table.remove(entities, i)
            end
        end
    end

    processPillarSpawns()
end

function countPlayableActors()
    local count = 0
    for _, actor in ipairs(entities) do
        if actor.isPlayable then
            count = count + 1
        end
    end
    return count
end

-- ============================================================
-- GENERAL EVENT GENERATION (dig sites, lightning)
-- ============================================================

-- Finds N random empty (unoccupied, non-water) cells
function findRandomEmptyCells(count, excludeFn, qMin)
    qMin = qMin or 0
    local candidates = {}
    local candidatesBias = {}
    for q = 0, hex.gridWidth - 1 do
        for r = 0, hex.gridHeight - 1 do
            if hex:isActiveHex(q, r) then
                local occupied = false
                for _, e in ipairs(entities) do
                    if e.q == q and e.r == r then occupied = true; break end
                    if e.cells then
                        for _, c in ipairs(e.cells) do
                            if c.q == q and c.r == r then
                                occupied = true
                                break
                            end
                        end
                    end
                end
                if not occupied then
                    local terrain = terrainMap and terrainMap[q] and terrainMap[q][r] or "grass"
                    if not cell_rules.isHoleTerrain(terrain) and not cell_rules.isRailway(q, r) then
                        if not excludeFn or not excludeFn(q, r) then
                            if q >= qMin then
                                table.insert(candidatesBias, {q = q, r = r})
                            else
                                table.insert(candidates, {q = q, r = r})
                            end
                        end
                    end
                end
            end
        end
    end
    -- Prefer biased cells, fill remainder from any cells
    local function shuffle(t)
        for i = #t, 2, -1 do local j = love.math.random(i); t[i], t[j] = t[j], t[i] end
        return t
    end
    shuffle(candidatesBias)
    shuffle(candidates)
    for _, c in ipairs(candidates) do table.insert(candidatesBias, c) end
    local result = {}
    for i = 1, math.min(count, #candidatesBias) do
        table.insert(result, candidatesBias[i])
    end
    return result
end

function processDigSites()
    for _, entity in ipairs(entities) do
        if entity.health > 0 and status.hasDigSite(entity.q, entity.r) then
            local wasDestroyed = entity:takeDamage(1)
            log.infof("game", "Dig site damage: %s takes 1 damage!", entity.name)
            sounds.play("collision")
            if wasDestroyed then
                entity:startDeath()
            end
            status.stepOnDigSite(entity.q, entity.r)
        end
    end

    for i = #entities, 1, -1 do
        if entities[i].health <= 0 then
            local e = entities[i]
            placeRubble(e)
            table.remove(entities, i)
        end
    end

    local readyDigs = status.decrementDigTimers()
    for _, dig in ipairs(readyDigs) do
        local occupied = false
        for _, e in ipairs(entities) do
            if e.q == dig.q and e.r == dig.r then
                occupied = true
                break
            end
        end
        local terrain = terrainMap and terrainMap[dig.q] and terrainMap[dig.q][dig.r] or "grass"
        if not occupied and not cell_rules.isHoleTerrain(terrain) and not cell_rules.isRailway(dig.q, dig.r) and not status.hasNegativeHexStatus(dig.q, dig.r) then
            local newEnemy = environment.createRandomEnemy(dig.q, dig.r)
            table.insert(entities, newEnemy)
            local x, y = hex:hexToPixel(dig.q, dig.r)
            visual.addEffect(x, y, "dig", 0.5)
            sounds.play("dig")
            log.infof("game", "A %s digs out at (%d,%d)!", newEnemy.name, dig.q, dig.r)
        else
            log.debugf("game", "Dig site at (%d,%d) blocked, no spawn", dig.q, dig.r)
            _G.objective_digBlocks = (_G.objective_digBlocks or 0) + 1
        end
        status.removeDigSite(dig.q, dig.r)
    end

    status.ageDigSites()

    if decayAppliedForTurnLimit then return end

    local aliveEnemies = 0
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 and not e.isSummoningRod then
            aliveEnemies = aliveEnemies + 1
        end
    end
    local spawnLimit = 6
    local needed = spawnLimit - aliveEnemies
    if needed > 0 then
        local spots = findRandomEmptyCells(needed, function(q, r)
            return status.hasDigSite(q, r) or status.hasNegativeHexStatus(q, r)
        end, 4)
        local digTypes = { "Ghost", "Zombie", "Lich" }
        for _, spot in ipairs(spots) do
            local spawnType = digTypes[love.math.random(1, #digTypes)]
            status.setDigSite(spot.q, spot.r, 1, spawnType)
            log.debugf("game", "New dig site at (%d,%d) -> %s", spot.q, spot.r, spawnType)
        end
    end
end

-- ============================================================
-- LIGHTNING
-- ============================================================
lightningTargetQ = -1
lightningTargetR = -1
lightningWarning = false

function selectLightningTarget()
    lightningTargetQ = -1
    lightningTargetR = -1
    lightningWarning = false
    if not hex then return end

    local spots = findRandomEmptyCells(1)
    if #spots == 0 then return end

    local spot = spots[1]
    lightningTargetQ = spot.q
    lightningTargetR = spot.r
    lightningWarning = true
    log.debugf("game", "Lightning warning at (%d,%d)", spot.q, spot.r)
end

function strikeLightning()
    if lightningTargetQ < 0 or lightningTargetR < 0 then
        lightningWarning = false
        return
    end
    if not hex or not getDrawCoords then
        lightningWarning = false
        return
    end

    local tq, tr = lightningTargetQ, lightningTargetR
    local fx, fy = getDrawCoords(tq, tr)
    if visual and visual.addLightning then
        visual.addLightning(fx, fy, 0.3)
    end
    sounds.play("lightning")

    local target = getEntityAtHex(tq, tr)
    if target and target.health > 0 then
        local wasDestroyed = target:takeDamage(1)
        sounds.play("collision")
        if not wasDestroyed then
            status.applyToEntity(target, "empowered")
            log.infof("game", "Lightning strikes %s! 1 damage, Empowered applied", target.name)
        else
            target:startDeath()
            log.infof("game", "Lightning destroys %s!", target.name)
        end
    end

    lightningTargetQ = -1
    lightningTargetR = -1
    lightningWarning = false
end
