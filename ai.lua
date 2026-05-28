-- ai.lua
-- Simple AI for enemies (with debug messages)

local ai = {}

-- Flag to enable/disable debug output
ai.DEBUG = true

-- Debug print function
local function debugPrint(...)
    if ai.DEBUG then
        print("[AI DEBUG]", ...)
    end
end

-- Maximum primitive AI: just goes to the nearest ally and attacks
function ai.performEnemyTurn(enemy, entities, hex, sounds)
    debugPrint("=== Starting turn for enemy:", enemy.name, "===")
    debugPrint("Enemy position: q=" .. enemy.q .. ", r=" .. enemy.r)
    
    -- Проверяем, что это действительно враг (персонаж, не игрок)
    if not enemy:isCharacter() or enemy.isPlayable then
        debugPrint("ERROR: " .. (enemy.name or "Unknown") .. " is not an enemy character!")
        return false, "Not an enemy"
    end
    
    if enemy.hasActedThisTurn then
        debugPrint(enemy.name .. " has already acted this turn")
        return false, "Already acted"
    end
    
    if enemy.isMoving then
        debugPrint(enemy.name .. " is still moving")
        return false, "Is moving"
    end
    
    -- Find the nearest allied player (только персонажи-игроки)
    local nearestAlly = nil
    local nearestDistance = math.huge
    
    debugPrint("Searching for targets among", #entities, "actors")
    for _, e in ipairs(entities) do
        -- Атакуем только играбельных персонажей (союзников)
        if e:isCharacter() and e.isPlayable and e.health > 0 then
            local dist = hex:getDistance(enemy.q, enemy.r, e.q, e.r)
            if dist < nearestDistance then
                nearestDistance = dist
                nearestAlly = e
            end
        end
    end
    
    if not nearestAlly then
        debugPrint(enemy.name .. " has no targets! Ending turn.")
        enemy.hasActedThisTurn = true
        return false, "No target"
    end
    
    debugPrint("Nearest target:", nearestAlly.name, "at distance", nearestDistance)
    
    -- If enemy is adjacent to target (distance 1), attack
    if nearestDistance == 1 then
        debugPrint("Target is adjacent - attacking!")
        return ai.performAttack(enemy, nearestAlly, entities, hex, sounds)
    else
        -- Otherwise move towards target (to distance 1 from it)
        debugPrint("Moving towards target (distance", nearestDistance .. ")")
        local moveResult = ai.performMove(enemy, nearestAlly, entities, hex)
        if not moveResult then
            debugPrint(enemy.name .. " cannot move to target! Ending turn.")
            enemy.hasActedThisTurn = true
        end
        return moveResult
    end
end

-- Primitive movement towards target
function ai.performMove(enemy, target, entities, hex)
    debugPrint("--- Planning movement for", enemy.name, "---")
    debugPrint("Target:", target.name, "position: q=" .. target.q .. ", r=" .. target.r)
    
    -- Проверяем, что цель - персонаж
    if not target:isCharacter() then
        debugPrint("Target is not a character, cannot move towards it!")
        return false
    end
    
    -- Find all cells at distance 1 from target
    local targetNeighbors = hex:getNeighbors(target.q, target.r)
    local bestCell = nil
    local bestDistance = math.huge
    
    debugPrint("Checking", #targetNeighbors, "neighbor cells around target")
    
    -- Check each cell around the target
    for i, neighbor in ipairs(targetNeighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            -- Check if cell is occupied (by any entity - character, obstacle, or building)
            local isOccupied = false
            local occupiedBy = ""
            
            for _, actor in ipairs(entities) do
                if actor ~= enemy and actor.q == neighbor.q and actor.r == neighbor.r then
                    isOccupied = true
                    occupiedBy = actor.name
                    break
                end
            end
            
            if not isOccupied then
                local distToEnemy = hex:getDistance(enemy.q, enemy.r, neighbor.q, neighbor.r)
                debugPrint("  Cell", i .. ": q=" .. neighbor.q .. ", r=" .. neighbor.r .. 
                          ", distance to enemy:", distToEnemy, "/" .. enemy.moveRange)
                
                if distToEnemy < bestDistance and distToEnemy <= enemy.moveRange then
                    bestDistance = distToEnemy
                    bestCell = neighbor
                end
            else
                debugPrint("  Cell", i .. ": q=" .. neighbor.q .. ", r=" .. neighbor.r .. " occupied by:", occupiedBy)
            end
        end
    end
    
    -- If we found a cell, move to it
    if bestCell and bestDistance <= enemy.moveRange then
        debugPrint("Found optimal cell: q=" .. bestCell.q .. ", r=" .. bestCell.r .. 
                  ", distance:", bestDistance)
        local moveResult = ai.moveToCell(enemy, bestCell.q, bestCell.r, hex, entities)
        if not moveResult then
            debugPrint("Failed to move to optimal cell")
        end
        return moveResult
    end
    
    -- If no cell found near target, move towards target
    debugPrint("No free cells found near target, moving in direction of target")
    local moveResult = ai.moveTowards(enemy, target.q, target.r, entities, hex)
    if not moveResult then
        debugPrint("Failed to move towards target")
    end
    return moveResult
end

-- Movement to specific cell
function ai.moveToCell(enemy, targetQ, targetR, hex, entities)
    debugPrint("--- Attempting to move to cell:", targetQ, targetR, "---")
    
    if enemy.isMoving then
        debugPrint("Enemy is already moving")
        return false
    end
    
    local distance = hex:getDistance(enemy.q, enemy.r, targetQ, targetR)
    debugPrint("Distance to target cell:", distance, "move range:", enemy.moveRange)
    
    if distance > enemy.moveRange then
        debugPrint("Target cell is too far (distance", distance .. "> move range", enemy.moveRange .. ")")
        return false
    end
    
    -- Check if cell is occupied
    debugPrint("Checking if target cell is occupied...")
    for _, actor in ipairs(entities) do
        if actor ~= enemy and actor.q == targetQ and actor.r == targetR then
            debugPrint("Cell occupied by actor:", actor.name)
            return false
        end
    end
    
    for _, obstacle in ipairs(entities) do
        if obstacle.q == targetQ and obstacle.r == targetR then
            debugPrint("Cell occupied by obstacle")
            return false
        end
    end
    
    debugPrint("Target cell is free, finding path...")
    
    -- Find path
    local path = ai.findSimplePath(enemy.q, enemy.r, targetQ, targetR, enemy, entities, hex)
    
    if path then
        debugPrint("Path found, length:", #path, "steps")
        if #path > 0 and #path <= enemy.moveRange then
            debugPrint("Path is within move range, starting movement")
            enemy.path = path
            enemy.currentPathIndex = 1
            ai.startEnemyMove(enemy, hex)
            return true
        else
            debugPrint("Path too long (", #path, "steps) for move range (", enemy.moveRange, ")")
            debugPrint(enemy.name .. " cannot reach target, ending turn")
            return false
        end
    else
        debugPrint("No path found to target cell! " .. enemy.name .. " is blocked, ending turn")
        return false
    end
end

-- Simple BFS pathfinding
function ai.findSimplePath(startQ, startR, targetQ, targetR, enemy, entities, hex)
    debugPrint("--- BFS Pathfinding ---")
    debugPrint("From: q=" .. startQ .. ", r=" .. startR)
    debugPrint("To: q=" .. targetQ .. ", r=" .. targetR)
    
    local queue = {{q = startQ, r = startR, path = {}}}
    local visited = {}
    local startKey = startQ .. "," .. startR
    visited[startKey] = true
    
    local iterations = 0
    while #queue > 0 do
        iterations = iterations + 1
        local current = table.remove(queue, 1)
        
        if current.q == targetQ and current.r == targetR then
            debugPrint("Path found after", iterations, "iterations, length:", #current.path)
            return current.path
        end
        
        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, neighbor in ipairs(neighbors) do
            local key = neighbor.q .. "," .. neighbor.r
            
            if not visited[key] and hex:isValidHex(neighbor.q, neighbor.r) then
                -- Check if cell is occupied
                local isOccupied = false
                
                for _, entity in ipairs(entities) do
                    if entity ~= enemy and entity.q == neighbor.q and entity.r == neighbor.r then
                        isOccupied = true
                        break
                    end
                end
                
                if not isOccupied then
                    visited[key] = true
                    local newPath = {}
                    for _, step in ipairs(current.path) do
                        table.insert(newPath, step)
                    end
                    table.insert(newPath, {q = neighbor.q, r = neighbor.r})
                    table.insert(queue, {q = neighbor.q, r = neighbor.r, path = newPath})
                end
            end
        end
    end
    
    debugPrint("No path found after", iterations, "iterations")
    return nil
end

-- Move towards target (straight line)
function ai.moveTowards(enemy, targetQ, targetR, entities, hex)
    debugPrint("--- Moving towards target:", targetQ, targetR, "---")
    
    -- Find all neighbors of enemy
    local neighbors = hex:getNeighbors(enemy.q, enemy.r)
    
    debugPrint("Checking", #neighbors, "neighbor cells from current position")
    
    -- Choose the neighbor closest to target
    local bestNeighbor = nil
    local bestDistance = math.huge
    
    for i, neighbor in ipairs(neighbors) do
        if hex:isValidHex(neighbor.q, neighbor.r) then
            -- Check if cell is occupied
            local isOccupied = false
            local occupiedBy = ""
            
            for _, entity in ipairs(entities) do
                if entity ~= enemy and entity.q == neighbor.q and entity.r == neighbor.r then
                    isOccupied = true
                    occupiedBy = entity.name
                    break
                end
            end
            
            if not isOccupied then
                local distToTarget = hex:getDistance(neighbor.q, neighbor.r, targetQ, targetR)
                debugPrint("  Neighbor", i .. ": q=" .. neighbor.q .. ", r=" .. neighbor.r .. 
                          ", distance to target:", distToTarget)
                
                if distToTarget < bestDistance then
                    bestDistance = distToTarget
                    bestNeighbor = neighbor
                end
            else
                debugPrint("  Neighbor", i .. ": q=" .. neighbor.q .. ", r=" .. neighbor.r .. 
                          " occupied by:", occupiedBy)
            end
        end
    end
    
    if bestNeighbor then
        debugPrint("Moving to best neighbor: q=" .. bestNeighbor.q .. ", r=" .. bestNeighbor.r)
        -- ИСПРАВЛЕНО: правильный порядок аргументов: enemy, q, r, hex, entities
        local moveResult = ai.moveToCell(enemy, bestNeighbor.q, bestNeighbor.r, hex, entities)
        if not moveResult then
            debugPrint("Failed to move to neighbor cell, ending turn")
        end
        return moveResult
    end
    
    debugPrint("No valid neighbors found to move to! " .. enemy.name .. " is completely surrounded, ending turn")
    return false
end

-- Start enemy movement
function ai.startEnemyMove(enemy, hex)
    if enemy.currentPathIndex and enemy.currentPathIndex <= #enemy.path then
        local nextStep = enemy.path[enemy.currentPathIndex]
        debugPrint("Starting movement to step", enemy.currentPathIndex .. "/" .. #enemy.path .. 
                  ": q=" .. nextStep.q .. ", r=" .. nextStep.r)
        
        enemy.isMoving = true
        enemy.timer = 0
        enemy.targetQ = nextStep.q
        enemy.targetR = nextStep.r
        
        enemy.startX, enemy.startY = hex:hexToPixel(enemy.q, enemy.r)
        enemy.endX, enemy.endY = hex:hexToPixel(enemy.targetQ, enemy.targetR)
        
        debugPrint("Movement animation started: from pixel (" .. 
                  enemy.startX .. ", " .. enemy.startY .. ") to (" .. 
                  enemy.endX .. ", " .. enemy.endY .. ")")
    else
        enemy.isMoving = false
        enemy.path = {}
        enemy.currentPathIndex = 0
        
        enemy.hasActedThisTurn = true
        debugPrint(enemy.name .. " finished moving! Turn complete.")
    end
end

-- Update enemy movement
function ai.updateEnemyMovement(enemy, dt, hex)
    if enemy.isMoving then
        enemy.timer = enemy.timer + dt
        local t = enemy.timer / enemy.speed
        
        if t >= 1 then
            debugPrint(enemy.name .. " reached cell: q=" .. enemy.targetQ .. ", r=" .. enemy.targetR)
            enemy.q = enemy.targetQ
            enemy.r = enemy.targetR
            enemy.isMoving = false
            
            if enemy.currentPathIndex then
                enemy.currentPathIndex = enemy.currentPathIndex + 1
                if enemy.currentPathIndex <= #enemy.path then
                    debugPrint(enemy.name .. " continuing to next path step:", enemy.currentPathIndex)
                    ai.startEnemyMove(enemy, hex)
                else
                    enemy.path = {}
                    enemy.currentPathIndex = 0
                    enemy.hasActedThisTurn = true
                    debugPrint(enemy.name .. " finished entire movement! Turn complete.")
                end
            end
        end
    end
end

-- Enemy attack
function ai.performAttack(enemy, target, entities, hex, sounds)
    debugPrint("---", enemy.name, "attacking", target.name, "---")
    
    -- Проверяем, что цель - персонаж
    if not target:isCharacter() then
        debugPrint("Target is not a character, cannot attack!")
        return false, "Target is not a character"
    end
    
    -- Simple attack with damage 1
    local damage = 1
    
    -- Check distance
    local distance = hex:getDistance(enemy.q, enemy.r, target.q, target.r)
    debugPrint("Distance to target:", distance)
    
    if distance ~= 1 then
        debugPrint("Target not adjacent (distance", distance .. "), cannot attack")
        return false, "Target not adjacent"
    end
    
    debugPrint("Dealing", damage, "damage to", target.name)
    
    -- Deal damage
    local healthBefore = target.health
    target.health = target.health - damage
    
    print(string.format("%s attacks %s for %d damage!", enemy.name, target.name, damage))
    debugPrint(target.name .. " health:", healthBefore, "->", target.health)
    
    if sounds and sounds.attack then
        sounds.attack:play()
    end
    
    if target.health <= 0 then
        debugPrint(target.name .. " has been defeated!")
        print(target.name .. " has been defeated!")
        for i, a in ipairs(entities) do
            if a == target then
                table.remove(entities, i)
                debugPrint(target.name .. " removed from actors list")
                break
            end
        end
    end
    
    enemy.hasActedThisTurn = true
    debugPrint(enemy.name .. " attack complete, turn finished")
    return true, nil
end

-- Get list of all enemies (non-playable characters only, not obstacles/buildings)
function ai.getEnemies(actors)
    local enemies = {}
    for _, actor in ipairs(actors) do
        -- Только персонажи, которые НЕ играбельные (враги)
        -- Исключаем препятствия и здания
        if actor:isCharacter() and not actor.isPlayable then
            table.insert(enemies, actor)
        end
    end
    debugPrint("Found", #enemies, "enemies in actors list")
    return enemies
end

-- Check if there are enemies that haven't acted yet
function ai.hasEnemiesToAct(actors)
    local count = 0
    for _, actor in ipairs(actors) do
        -- Только персонажи-враги, которые не ходили и не двигаются
        if actor:isCharacter() and not actor.isPlayable and not actor.hasActedThisTurn and not actor.isMoving then
            count = count + 1
        end
    end
    debugPrint("Enemies remaining to act:", count)
    return count > 0
end

-- Execute turn for all enemies
function ai.performAllEnemiesTurn(entities, hex, sounds)
    debugPrint("=== Performing enemies turn ===")
    local anyActed = false
    
    for _, enemy in ipairs(entities) do
        -- Только персонажи-враги, которые не ходили и не двигаются
        if enemy:isCharacter() and not enemy.isPlayable and not enemy.hasActedThisTurn and not enemy.isMoving then
            debugPrint("Processing enemy:", enemy.name)
            ai.performEnemyTurn(enemy, entities, hex, sounds)
            anyActed = true
            break -- Process one enemy at a time
        end
    end
    
    if not anyActed then
        debugPrint("No enemies to process this turn")
    end
    
    return anyActed
end

return ai