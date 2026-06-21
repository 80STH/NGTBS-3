-- ai.lua
-- AI: enemies move toward the target, then prepare an attack
-- Fixed: ranged attacks (Lich, Ghost) and Bite work correctly

local ai = {}
local pathfinding = require("grid.pathfinding")
local hex_utils = require("grid.hex_utils")
local visual = require("system.visual_effects")
local attack_effects = require("combat.attack_effects")
local status = require("system.status")
local log = require("util.log")

-- Check if the target lies on one of six straight lines from the source (including any distance)
local function isOnStraightLine(fromQ, fromR, toQ, toR, hex)
    local fx, fy, fz = hex_utils.axialToCube(fromQ, fromR)
    local tx, ty, tz = hex_utils.axialToCube(toQ, toR)
    local dx, dy, dz = tx - fx, ty - fy, tz - fz

    local function gcd(a, b)
        a = math.abs(a); b = math.abs(b)
        while b ~= 0 do a, b = b, a % b end
        return a
    end
    local g = gcd(gcd(dx, dy), dz)
    if g == 0 then return false end
    local stepX, stepY, stepZ = dx / g, dy / g, dz / g

    local validDirections = {
        {1, -1, 0}, {1, 0, -1}, {0, 1, -1},
        {-1, 1, 0}, {-1, 0, 1}, {0, -1, 1}
    }
    for _, dir in ipairs(validDirections) do
        if stepX == dir[1] and stepY == dir[2] and stepZ == dir[3] then
            return true
        end
    end
    return false
end

local function debugPrint(...)
    log.debug("ai", ...)
end

-- Whether the attack requires a straight line (for Bite and Magic Bolt — no)
local function attackRequiresLine(attack)
    return true
end

-- Whether the attack should hit the first target on the line (Ghost, Dash, Shoot, Piercing)
local function attackHitsFirstTarget(attack)
    return attack.name == "Ghost Bolt" or attack.name == "Dash" or attack.name == "Shoot" or attack.name == "Piercing Shot"
end

-- Get the current enemy attack (the first one)
local function getEnemyAttack(enemy)
    if not enemy.attacks or #enemy.attacks == 0 then return nil end
    return enemy.attacks[1].attack
end

-- Get all attackable targets (players + buildings)
function ai.getAttackableTargets(entities)
    local targets = {}
    for _, e in ipairs(entities) do
        if (e:isCharacter() and e.isPlayable and e.health > 0) or
           (e:isBuilding() and e.health > 0) then
            local priority = e.isPlayable and 10 or 8
            table.insert(targets, {entity = e, type = e.isPlayable and "player" or "building", priority = priority, health = e.health})
        end
    end
    return targets
end

-- Check if the enemy can prepare an attack right now
function ai.canPrepareAttack(enemy, entities)
    local attack = getEnemyAttack(enemy)
    if not attack then return false end
    local targets = ai.getAttackableTargets(entities)
    for _, t in ipairs(targets) do
        local dist = hex:getDistance(enemy.q, enemy.r, t.entity.q, t.entity.r)
        if dist <= attack.range then
            if not attackRequiresLine(attack) then
                return true
            elseif isOnStraightLine(enemy.q, enemy.r, t.entity.q, t.entity.r, hex) then
                if attackHitsFirstTarget(attack) then
                    local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, t.entity.q, t.entity.r, hex)
                    if stepX then
                        local firstTarget, _ = attack:findFirstTargetOnLine(enemy.q, enemy.r, stepX, stepY, stepZ, hex, entities)
                        if firstTarget == t.entity then
                            return true
                        end
                    end
                else
                    return true
                end
            end
        end
    end
    return false
end

-- Get the best target for an enemy considering distribution
function ai.getBestTargetForEnemy(enemy, entities, hex, selectedTargets)
    selectedTargets = selectedTargets or {}
    local attack = getEnemyAttack(enemy)
    if not attack then return nil, -math.huge end

    local bestTarget = nil
    local bestScore = -math.huge
    local targets = ai.getAttackableTargets(entities)

    for _, t in ipairs(targets) do
        local target = t.entity
        local dist = hex:getDistance(enemy.q, enemy.r, target.q, target.r)
        if dist > attack.range then goto continue end
        if attack.minRange and dist < attack.minRange then goto continue end

        local valid = false
        if attackRequiresLine(attack) then
            if isOnStraightLine(enemy.q, enemy.r, target.q, target.r, hex) then
                if attackHitsFirstTarget(attack) then
                    local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, target.q, target.r, hex)
                    if stepX then
                        local firstTarget, _ = attack:findFirstTargetOnLine(enemy.q, enemy.r, stepX, stepY, stepZ, hex, entities)
                        if firstTarget == target then
                            valid = true
                        end
                    end
                else
                    valid = true
                end
            end
        elseif attack.name == "Bite" then
            valid = (dist <= attack.range)
        elseif attack.name == "Magic Bolt" or attack.name == "Power Bolt" then
            valid = (dist <= attack.range) and isOnStraightLine(enemy.q, enemy.r, target.q, target.r, hex)
        end

        if not valid then goto continue end

        local score = -dist * 2 + t.priority - (selectedTargets[target] or 0) * 3
        if t.health <= 2 then score = score + 15
        elseif t.health <= 3 then score = score + 5 end
        if t.type == "building" and t.health < t.entity.maxHealth then score = score + 8 end

        if score > bestScore then
            bestScore = score
            bestTarget = target
        end
        ::continue::
    end
    return bestTarget, bestScore
end

-- Prepare attack for enemy (without movement)
function ai.prepareAttackForEnemy(enemy, entities, hex, selectedTargets)
    if not enemy:isCharacter() or enemy.isPlayable or enemy.health <= 0 then return false end
    if not ai.canPrepareAttack(enemy, entities) then return false end

    -- Clear previous rooted target if any
    if enemy.rootedTarget then
        status.removeFromEntity(enemy.rootedTarget, "rooted")
        enemy.rootedTarget = nil
    end

    local attack = getEnemyAttack(enemy)
    if not attack then return false end

    local bestTarget = ai.getBestTargetForEnemy(enemy, entities, hex, selectedTargets)
    if not bestTarget then
        debugPrint(string.format("%s cannot prepare: no valid target", enemy.name))
        return false
    end

    if attackRequiresLine(attack) then
        local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, bestTarget.q, bestTarget.r, hex)
        if not stepX then return false end
        enemy.attackDirection = { dx = stepX, dy = stepY, dz = stepZ }
    else
        enemy.attackDirection = nil
    end

    enemy.hasPreparedAttack = true
    local dx, dy, dz = hex_utils.getCubeDiff(enemy.q, enemy.r, bestTarget.q, bestTarget.r)
    enemy.preparedTargetOffset = { dx = dx, dy = dy, dz = dz }
    enemy.preparedAttack = attack
    enemy.preparedTargetQ = nil
    enemy.preparedTargetR = nil

    -- Zombie: immobilise target
    if (enemy.name == "Zombie" or enemy.name == "PoisonousZombie") and bestTarget:isCharacter() then
        status.applyToEntity(bestTarget, "rooted")
        enemy.rootedTarget = bestTarget
    end

    debugPrint(string.format("%s prepared attack targeting %s (%s)", 
               enemy.name, bestTarget.name, bestTarget:isBuilding() and "building" or "player"))
    return true
end

function ai.executePreparedAttack(enemy, entities, hex, sounds)
    if not enemy.hasPreparedAttack or enemy.health <= 0 then return false end
    local attack = enemy.preparedAttack
    if not attack then return false end

    -- Summoning rod: call execute directly
    if enemy.isSummoningRod then
        if attack and attack.execute then
            attack:execute(enemy, nil, nil, hex, entities, sounds)
        end
        enemy.hasPreparedAttack = false
        enemy.summonTargetQ = nil
        enemy.summonTargetR = nil
        enemy.preparedAttack = nil
        return true
    end

    local target = nil
    local targetQ, targetR = nil, nil  -- target cell (will always be determined)

    -- ===== 1. Determine the target cell and, possibly, the target =====
    if attackHitsFirstTarget(attack) then
        -- Ghost Bolt, Shoot, Dash, Piercing – follow the line to the first target or to the edge
        local dir = enemy.attackDirection
        if dir then
            local curQ, curR = enemy.q, enemy.r
            local lastValidQ, lastValidR = curQ, curR
            while true do
                local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, dir.dx, dir.dy, dir.dz)
                if not hex:isValidHex(nextQ, nextR) then break end
                local e = combat.getEntityAtHex(nextQ, nextR, entities)
                if e and e.health > 0 and e ~= enemy then
                    target = e
                    targetQ, targetR = nextQ, nextR
                    break
                end
                lastValidQ, lastValidR = nextQ, nextR
                curQ, curR = nextQ, nextR
            end
            if not target then
                -- No target — take the last traversed cell (end of line or edge)
                targetQ, targetR = lastValidQ, lastValidR
            end
        end
    else
        -- Bite and Magic Bolt: use the saved offset
        if enemy.preparedTargetOffset then
            targetQ, targetR = hex_utils.applyCubeDiff(
                enemy.q, enemy.r,
                enemy.preparedTargetOffset.dx,
                enemy.preparedTargetOffset.dy,
                enemy.preparedTargetOffset.dz
            )
            -- Check if there is a living target there
            local e = combat.getEntityAtHex(targetQ, targetR, entities)
            if e and e.health > 0 and e ~= enemy then
                if attack.name == "Magic Bolt" or attack.name == "Power Bolt" then
                    if isOnStraightLine(enemy.q, enemy.r, targetQ, targetR, hex) then
                        target = e
                    end
                else -- Bite
                    if hex:getDistance(enemy.q, enemy.r, targetQ, targetR) <= attack.range then
                        target = e
                    end
                end
            end
        end
    end

    -- ===== 2. ALWAYS draw the animation (even if there is no target) =====
    if attack.name == "Ghost Bolt" then
        if target then
            attack_effects.ghostBolt(enemy, target, hex)
        elseif targetQ and targetR then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            visual.addLineEffect(fromX, fromY, toX, toY, 0.7, 0.3, 1.0, 3, 0.6)
        end
    elseif attack.name == "Bite" then
        if target then
            attack_effects.bite(enemy, target, hex)
        elseif targetQ and targetR then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            visual.addLineEffect(fromX, fromY, toX, toY, 0.9, 0.2, 0.2, 4, 0.8)
            visual.addEffect(toX, toY, "hit", 0.25)
        end
    elseif attack.name == "Magic Bolt" then
        if target then
            attack_effects.magicBolt(enemy, target, hex)
        elseif targetQ and targetR then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            local midX = (fromX + toX) / 2
            local midY = (fromY + toY) / 2
            visual.addArcEffect(fromX, fromY, toX, toY, 0.6, 0.2, 1.0, 0.3, midX, midY - 60)
            visual.addEffect(toX, toY, "hit", 0.4)
        end
    elseif attack.name == "Power Bolt" then
        if target then
            attack_effects.magicBolt(enemy, target, hex)
        end
    elseif attack.name == "Dash" then
        -- For dash, a line can be drawn to the target cell (if present)
        if targetQ and targetR then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            visual.addDashEffect(fromX, fromY, toX, toY)
        end
    elseif attack.name == "Shoot" then
        if target then
            local dir = enemy.attackDirection
            local pushQ, pushR
            if dir and target.isPushable ~= false then
                pushQ, pushR = hex_utils.applyCubeStep(target.q, target.r, dir.dx, dir.dy, dir.dz)
            end
            attack_effects.shoot(enemy, target, pushQ, pushR, hex)
        elseif targetQ and targetR then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            visual.addLineEffect(fromX, fromY, toX, toY, 0.9, 0.7, 0.2, 3, 1.0)
        end
    elseif attack.name == "Bash" or attack.name == "Lunge" then
        if target then
            local tx, ty = getDrawCoords(target.q, target.r)
            visual.addLineEffect(getDrawCoords(enemy.q, enemy.r), tx, ty, 0.9, 0.5, 0.2, 4, 0.6)
            visual.addEffect(tx, ty, "hit", 0.3)
            -- Extra target for Bash (behind attacker) and Lunge (behind target)
            local extraQ, extraR, extraTarget = nil, nil, nil
            if attack.name == "Bash" then
                local stepX, stepY, stepZ = attack:getLineDirection(target.q, target.r, enemy.q, enemy.r, hex)
                if stepX then
                    extraQ, extraR = hex_utils.applyCubeStep(enemy.q, enemy.r, stepX, stepY, stepZ)
                end
            else -- Lunge
                local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, target.q, target.r, hex)
                if stepX then
                    extraQ, extraR = hex_utils.applyCubeStep(target.q, target.r, stepX, stepY, stepZ)
                end
            end
            if extraQ and extraR then
                local e = combat.getEntityAtHex(extraQ, extraR, entities)
                if e and e.health > 0 then
                    extraTarget = e
                    local ex, ey = getDrawCoords(extraQ, extraR)
                    visual.addEffect(ex, ey, "hit", 0.3)
                end
            end
            -- Defer the extra target for dealing damage
            enemy._extraAttackTarget = extraTarget
        end
    elseif attack.name == "Cleave" then
        if targetQ and targetR then
            local fromX, fromY = getDrawCoords(enemy.q, enemy.r)
            local toX, toY = getDrawCoords(targetQ, targetR)
            visual.addLineEffect(fromX, fromY, toX, toY, 0.9, 0.5, 0.2, 3, 0.6)
        end
        -- Two side targets (the main target will already be hit)
        local frontTargets = {}
        local stepX, stepY, stepZ = attack:getLineDirection(enemy.q, enemy.r, targetQ, targetR, hex)
        if stepX then
            local sx1, sy1, sz1 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, true)
            local sx2, sy2, sz2 = hex_utils.rotateCubeDir(stepX, stepY, stepZ, false)
            local side1Q, side1R = hex_utils.applyCubeStep(enemy.q, enemy.r, sx1, sy1, sz1)
            local side2Q, side2R = hex_utils.applyCubeStep(enemy.q, enemy.r, sx2, sy2, sz2)
            local sideCells = {{q = side1Q, r = side1R}, {q = side2Q, r = side2R}}
            for _, cell in ipairs(sideCells) do
                local e = combat.getEntityAtHex(cell.q, cell.r, entities)
                if e and e.health > 0 then
                    table.insert(frontTargets, e)
                end
                local cx, cy = getDrawCoords(cell.q, cell.r)
                visual.addEffect(cx, cy, "hit", 0.2)
            end
        end
        enemy._cleaveTargets = frontTargets
    end

    -- ===== 3. PowerLichBoltAttack uses its own execute =====
    if attack.name == "Power Bolt" then
        if target or (targetQ and targetR) then
            attack:execute(enemy, targetQ, targetR, hex, entities, sounds)
        end
    elseif target then
        local damage = attack.damage
        local wasDestroyed = target:takeDamage(damage)
        log.infof("ai", "%s attacks %s for %d damage!", enemy.name, target.name, damage)
        if sounds and sounds.attack then sounds.attack:play() end
        if wasDestroyed then
            target:startDeath()
        end
    else
        debugPrint(string.format("%s attacks cell (%d,%d) but no valid target, animation only", 
                   enemy.name, targetQ or 0, targetR or 0))
    end

    -- Extra damage for Bash/Lunge (second target)
    if enemy._extraAttackTarget and enemy._extraAttackTarget.health > 0 then
        local extra = enemy._extraAttackTarget
        local wasDestroyed = extra:takeDamage(attack.damage)
        log.infof("ai", "%s also hits %s for %d damage!", enemy.name, extra.name, attack.damage)
        if sounds and sounds.attack then sounds.attack:play() end
        if wasDestroyed then
            extra:startDeath()
        end
        enemy._extraAttackTarget = nil
    end

    -- Multiple damage for Cleave
    if enemy._cleaveTargets then
        for _, ct in ipairs(enemy._cleaveTargets) do
            if ct.health > 0 then
                local wasDestroyed = ct:takeDamage(attack.damage)
                    log.infof("ai", "%s cleaves %s for %d damage!", enemy.name, ct.name, attack.damage)
                if wasDestroyed then
                    ct:startDeath()
                end
            end
        end
        enemy._cleaveTargets = nil
    end

    -- ===== 4. Reset attack state =====
    if enemy.rootedTarget then
        status.removeFromEntity(enemy.rootedTarget, "rooted")
        enemy.rootedTarget = nil
    end
    enemy.hasPreparedAttack = false
    enemy.attackDirection = nil
    enemy.preparedTargetOffset = nil
    enemy.preparedAttack = nil
    return true
end
-- Distance to the nearest target
function ai.getDistanceToNearestTarget(enemy, entities, hex)
    local best = math.huge
    local targets = ai.getAttackableTargets(entities)
    for _, t in ipairs(targets) do
        local d = hex:getDistance(enemy.q, enemy.r, t.entity.q, t.entity.r)
        if d < best then best = d end
    end
    return best
end

-- Find the first target on the line (for preview, but used in canPrepareAttack)
function findFirstTargetInDirection(startQ, startR, dx, dy, dz, hex, entities)
    local curQ, curR = startQ, startR
    while true do
        curQ, curR = hex_utils.applyCubeStep(curQ, curR, dx, dy, dz)
        if not hex:isValidHex(curQ, curR) then break end
        for _, e in ipairs(entities) do
            if e.q == curQ and e.r == curR and e.health > 0 then
                return e, curQ, curR
            end
        end
    end
    return nil, nil, nil
end

-- Movement + preparation (main method for the enemy preparation phase)
function ai.moveAndPrepare(enemy, entities, hex)
    if not enemy:isCharacter() or enemy.isPlayable or enemy.health <= 0 then
        return "failed"
    end
    if enemy.isMoving then
        return "moving"
    end

    -- Summoning rod: does not move, picks a random empty cell
    if enemy.isSummoningRod then
        if enemy.summonCooldown and enemy.summonCooldown > 0 then
            enemy.summonCooldown = enemy.summonCooldown - 1
            return "failed"
        end
        -- Collect free cells within radius 1 of the rod
        local freeCells = {}
        local neighbors = hex:getNeighbors(enemy.q, enemy.r)
        for _, nb in ipairs(neighbors) do
            if hex:isActiveHex(nb.q, nb.r) then
                local occupied = false
                for _, e in ipairs(entities) do
                    if e.q == nb.q and e.r == nb.r and e.health > 0 then
                        occupied = true
                        break
                    end
                end
                if not occupied then
                    local terrain = terrainMap and terrainMap[nb.q] and terrainMap[nb.q][nb.r] or "grass"
                    if terrain ~= "water" then
                        table.insert(freeCells, {q = nb.q, r = nb.r})
                    end
                end
            end
        end
        if #freeCells > 0 then
            local target = freeCells[love.math.random(1, #freeCells)]
            enemy.summonTargetQ = target.q
            enemy.summonTargetR = target.r
            local types = { "Ghost", "Zombie", "Lich", "Brute", "Lancer", "BogShaman", "Raider", "Dervish", "Crusher" }
            enemy.summonType = types[love.math.random(1, #types)]
            enemy.hasPreparedAttack = true
            if enemy.attacks and #enemy.attacks > 0 then
                enemy.preparedAttack = enemy.attacks[1].attack
            end
            debugPrint(string.format("SummoningRod prepares summon at (%d,%d): %s", target.q, target.r, enemy.summonType))
            return "prepared"
        end
        return "failed"
    end

    -- If already able to attack — prepare immediately
    if ai.canPrepareAttack(enemy, entities) then
        ai.prepareAttackForEnemy(enemy, entities, hex, {})
        return "prepared"
    end

    -- Find the nearest target
    local nearestTarget = nil
    local nearestDist = math.huge
    local targets = ai.getAttackableTargets(entities)
    
    for _, t in ipairs(targets) do
        local target = t.entity
        local dist = hex:getDistance(enemy.q, enemy.r, target.q, target.r)
        if dist < nearestDist then
            nearestDist = dist
            nearestTarget = target
        end
    end

    if not nearestTarget then
        return "failed"
    end

    -- Try to take a step toward the target
    local success = ai.performMoveTowards(enemy, nearestTarget, entities, hex)
    if success then
        return "moving"
    else
        debugPrint(enemy.name .. " cannot move towards target, skip")
        return "failed"
    end
end

function ai.performMoveTowards(enemy, target, entities, hex)
    local neighbors = hex:getNeighbors(target.q, target.r)
    local bestCell = nil
    local bestDist = math.huge
    local bestThreatenedCell = nil
    local bestThreatenedDist = math.huge

    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            local occupied = false
            for _, e in ipairs(entities) do
                if e ~= enemy and e.q == neighbor.q and e.r == neighbor.r and not e.isHazard then
                    occupied = true
                    break
                end
            end
            if not occupied then
                local distToEnemy = hex:getDistance(enemy.q, enemy.r, neighbor.q, neighbor.r)
                local effRange = ai.getEffectiveMoveRange(enemy, hex, entities)
                if distToEnemy <= effRange then
                    if not isCellDangerousForEntity(neighbor.q, neighbor.r, enemy) then
                        if isCellOnEnemyAttackLine(neighbor.q, neighbor.r, enemy, entities, hex) then
                            if distToEnemy < bestThreatenedDist then
                                bestThreatenedDist = distToEnemy
                                bestThreatenedCell = neighbor
                            end
                        elseif distToEnemy < bestDist then
                            bestDist = distToEnemy
                            bestCell = neighbor
                        end
                    end
                end
            end
        end
    end

    if bestCell then
        return ai.moveToCell(enemy, bestCell.q, bestCell.r, hex, entities)
    end
    if bestThreatenedCell then
        debugPrint(enemy.name .. " forced to move into threatened cell (enemy line)")
        return ai.moveToCell(enemy, bestThreatenedCell.q, bestThreatenedCell.r, hex, entities)
    end

    return ai.moveStepTowards(enemy, target.q, target.r, hex, entities)
end

function ai.moveStepTowards(enemy, targetQ, targetR, hex, entities)
    local neighbors = hex:getNeighbors(enemy.q, enemy.r)
    local bestNeighbor = nil
    local bestDist = math.huge
    local threatenedNeighbor = nil
    local threatenedDist = math.huge
    local dangerousNeighbor = nil
    local dangerousDist = math.huge

    for _, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) and hex:isActiveHex(neighbor.q, neighbor.r) then
            local occupied = false
            for _, e in ipairs(entities) do
                if e ~= enemy and e.q == neighbor.q and e.r == neighbor.r and not e.isHazard then
                    occupied = true
                    break
                end
            end
            if not occupied then
                local dist = hex:getDistance(neighbor.q, neighbor.r, targetQ, targetR)
                if dist < bestDist or dist < threatenedDist or dist < dangerousDist then
                    if not isCellDangerousForEntity(neighbor.q, neighbor.r, enemy) then
                        if isCellOnEnemyAttackLine(neighbor.q, neighbor.r, enemy, entities, hex) then
                            if dist < threatenedDist then
                                threatenedDist = dist
                                threatenedNeighbor = neighbor
                            end
                        elseif dist < bestDist then
                            bestDist = dist
                            bestNeighbor = neighbor
                        end
                    else
                        if dist < dangerousDist then
                            dangerousDist = dist
                            dangerousNeighbor = neighbor
                        end
                    end
                end
            end
        end
    end

    if bestNeighbor then
        return ai.moveToCell(enemy, bestNeighbor.q, bestNeighbor.r, hex, entities)
    end
    if threatenedNeighbor then
        debugPrint(enemy.name .. " forced to move into threatened cell (enemy line)")
        return ai.moveToCell(enemy, threatenedNeighbor.q, threatenedNeighbor.r, hex, entities)
    end
    if dangerousNeighbor then
        debugPrint(enemy.name .. " forced to move into dangerous cell (fire/acid)")
        return ai.moveToCell(enemy, dangerousNeighbor.q, dangerousNeighbor.r, hex, entities)
    end
    return false
end

function ai.getEffectiveMoveRange(enemy, hex, entities)
    if status.hasEntityStatus(enemy, "rooted") and not enemy.rootImmune then
        return 0
    end
    local base = enemy.moveRange + (status.hasEntityStatus(enemy, "empowered") and 1 or 0)
    if status.isWounded and status.isWounded(enemy) then
        base = base - 1
    end
    if hex and entities and combat and combat.isInSlowingAura then
        if combat.isInSlowingAura(enemy, entities, hex) then
            base = math.max(1, base - 2)
        end
    end
    return math.max(0, base)
end

function ai.moveToCell(enemy, targetQ, targetR, hex, entities)
    if enemy.isMoving then return false end
    -- Destination cell: occupied by any entity (except isHazard)
    for _, e in ipairs(entities) do
        if e ~= enemy and e.q == targetQ and e.r == targetR and not e.isHazard then
            return false
        end
    end
    local distance = hex:getDistance(enemy.q, enemy.r, targetQ, targetR)
    local effRange = ai.getEffectiveMoveRange(enemy, hex, entities)
    if distance > effRange then return false end

    local isBlockedFn
    if enemy.flying then
        isBlockedFn = function(q, r) return not hex:isActiveHex(q, r) end
    else
        isBlockedFn = function(q, r) return ai.isPositionOccupied(q, r, enemy, entities, hex) end
    end
    local path = pathfinding.findPath(enemy.q, enemy.r, targetQ, targetR, effRange,
        isBlockedFn, hex)

    if path and #path > 0 and #path <= effRange then
        enemy.path = path
        enemy.currentPathIndex = 1
        ai.startEnemyMove(enemy, hex)
        return true
    end
    return false
end

function ai.isPositionOccupied(q, r, movingEntity, entities, hex)
    -- Delegates to cell_rules.isOccupied. Enemies don't have phaseThroughEnemies,
    -- so we disable this check — behavior is equivalent to the old version.
    return require("grid.cell_rules").isOccupied(q, r, movingEntity, {
        entities = entities, hex = hex,
        allowPhaseThroughEnemies = false,
    })
end

function ai.startEnemyMove(enemy, hex)
    if enemy.currentPathIndex and enemy.currentPathIndex <= #enemy.path then
        local step = enemy.path[enemy.currentPathIndex]
        enemy.isMoving = true
        enemy.timer = 0
        enemy.targetQ = step.q
        enemy.targetR = step.r
        enemy.startX, enemy.startY = getDrawCoords(enemy.q, enemy.r)
        enemy.endX, enemy.endY = getDrawCoords(step.q, step.r)
    else
        enemy.isMoving = false
        enemy.path = {}
        enemy.currentPathIndex = 0
    end
end

function ai.updateEnemyMovement(enemy, dt, hex)
    if enemy.isMoving then
        enemy.timer = enemy.timer + dt
        local t = enemy.timer / enemy.speed
        if t >= 1 then
            enemy.q = enemy.targetQ
            enemy.r = enemy.targetR
            enemy.isMoving = false
            if enemy.currentPathIndex then
                enemy.currentPathIndex = enemy.currentPathIndex + 1
                if enemy.currentPathIndex <= #enemy.path then
                    ai.startEnemyMove(enemy, hex)
                else
                    -- Apply destination cell effects
                    if terrainMap then
                        local died = effects.applyAllCellEffects(enemy, enemy.q, enemy.r, terrainMap, entities)
                        if died then
                            checkGameEnd()
                        end
                    end
                    enemy.path = {}
                    enemy.currentPathIndex = 0
                    enemy.movementFinished = true
                end
            end
        end
    end
end

function ai.getLivingEnemies(entities)
    local enemies = {}
    for _, e in ipairs(entities) do
        if e:isCharacter() and not e.isPlayable and e.health > 0 then
            table.insert(enemies, e)
        end
    end
    return enemies
end

function isCellDangerousForEntity(q, r, entity)
    -- Underwater mines — lethal, never go there
    if terrainMap and terrainMap[q] and terrainMap[q][r] == "underwater_mines" then
        return true
    end
    local cellStatuses = status.getAtHex(q, r)
    if not cellStatuses or #cellStatuses == 0 then
        return false
    end
    for _, st in ipairs(cellStatuses) do
        if st == "dig_site" then
            return true
        end
        if st == "fire" or st == "acid" then
            if not status.hasEntityStatus(entity, st) then
                return true
            end
        end
    end
    return false
end

-- Check if a cell lies on another enemy's attack line (lower priority)
function isCellOnEnemyAttackLine(q, r, movingEnemy, entities, hex)
    for _, other in ipairs(entities) do
        if other ~= movingEnemy and other:isCharacter() and not other.isPlayable and other.health > 0 then
            local attack = getEnemyAttack(other)
            if attack and hex:getDistance(other.q, other.r, q, r) <= attack.range then
                if isOnStraightLine(other.q, other.r, q, r, hex) then
                    if attackHitsFirstTarget(attack) then
                        local stepX, stepY, stepZ = attack:getLineDirection(other.q, other.r, q, r, hex)
                        if stepX then
                            local curQ, curR = other.q, other.r
                            local found = false
                            while curQ ~= q or curR ~= r do
                                local nextQ, nextR = hex_utils.applyCubeStep(curQ, curR, stepX, stepY, stepZ)
                                if not hex:isValidHex(nextQ, nextR) then break end
                                local e = nil
                                for _, ent in ipairs(entities) do
                                    if ent.health > 0 and ent.q == nextQ and ent.r == nextR then
                                        e = ent
                                        break
                                    end
                                end
                                if e and e ~= other then
                                    if nextQ == q and nextR == r then
                                        found = true
                                    end
                                    break
                                end
                                if nextQ == q and nextR == r then found = true; break end
                                curQ, curR = nextQ, nextR
                            end
                            if found then return true end
                        end
                    else
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- Prepare all enemies with target distribution
function ai.prepareAllEnemiesWithTargetDistribution(entities, hex)
    local enemies = ai.getLivingEnemies(entities)
    local selectedTargets = {}
    
    for _, enemy in ipairs(enemies) do
        local bestTarget = ai.getBestTargetForEnemy(enemy, entities, hex, selectedTargets)
        if bestTarget then
            selectedTargets[bestTarget] = (selectedTargets[bestTarget] or 0) + 1
        end
    end
    
    for _, enemy in ipairs(enemies) do
        ai.prepareAttackForEnemy(enemy, entities, hex, selectedTargets)
    end
    
    return selectedTargets
end

return ai
