-- objectives.lua
local objectives = {}

local objectiveList = {}
local objectiveStates = {}  -- id -> "pending" | "completed" | "failed"
local smallFont

-- Define objectives
local function initDefinitions()
    objectiveList = {
        {
            id = "protect_tower",
            name = "Protect the Tower",
            desc = "Keep the tower alive until victory",
            entityName = "Tower",
        },
        {
            id = "survive_poisonous_zombie",
            name = "Poisonous Zombie Survives",
            desc = "Poisonous zombie must not die before decay is applied",
            entityName = "PoisonousZombie",
        },
    }
end

function objectives.reset()
    initDefinitions()
    objectiveStates = {}
    for _, obj in ipairs(objectiveList) do
        objectiveStates[obj.id] = "pending"
    end
end

function objectives.getList()
    return objectiveList
end

function objectives.getState(id)
    return objectiveStates[id] or "pending"
end

function objectives.getCompletedCount()
    local count = 0
    for _, obj in ipairs(objectiveList) do
        if objectiveStates[obj.id] == "completed" then count = count + 1 end
    end
    return count
end

function objectives.getTotalCount()
    return #objectiveList
end

function objectives.getFailedCount()
    local count = 0
    for _, obj in ipairs(objectiveList) do
        if objectiveStates[obj.id] == "failed" then count = count + 1 end
    end
    return count
end

function objectives.update(entities)
    for _, obj in ipairs(objectiveList) do
        if objectiveStates[obj.id] == "pending" then
            if obj.id == "protect_tower" then
                local tower = nil
                for _, e in ipairs(entities) do
                    if e.name == obj.entityName and e.health > 0 then
                        tower = e
                        break
                    end
                end
                if not tower then
                    objectiveStates[obj.id] = "failed"
                end
            elseif obj.id == "survive_poisonous_zombie" then
                local zombie = nil
                for _, e in ipairs(entities) do
                    if e.name == obj.entityName and e.health and e.health > 0 then
                        zombie = e
                        break
                    end
                end
                if not zombie then
                    objectiveStates[obj.id] = decayAppliedForTurnLimit and "completed" or "failed"
                elseif decayAppliedForTurnLimit then
                    objectiveStates[obj.id] = "completed"
                end
            end
        end
    end
end

function objectives.checkOnVictory(entities)
    for _, obj in ipairs(objectiveList) do
        if objectiveStates[obj.id] == "pending" then
            if obj.id == "protect_tower" then
                local alive = false
                for _, e in ipairs(entities) do
                    if e.name == obj.entityName and e.health > 0 then
                        alive = true
                        break
                    end
                end
                objectiveStates[obj.id] = alive and "completed" or "failed"
            elseif obj.id == "survive_poisonous_zombie" then
                local alive = false
                for _, e in ipairs(entities) do
                    if e.name == obj.entityName and e.health and e.health > 0 then
                        alive = true
                        break
                    end
                end
                objectiveStates[obj.id] = (alive or decayAppliedForTurnLimit) and "completed" or "failed"
            end
        end
    end
end

function objectives.draw()
    local x = 10
    local y = 330
    local w = 180
    local lineH = 16
    local padding = 6
    local titleH = 20
    local totalH = titleH + #objectiveList * lineH + padding * 2

    love.graphics.setColor(0.1, 0.1, 0.2, 0.85)
    love.graphics.rectangle("fill", x, y, w, totalH, 5)
    love.graphics.setColor(0.4, 0.4, 0.6, 0.6)
    love.graphics.rectangle("line", x, y, w, totalH, 5)

    if not smallFont then smallFont = love.graphics.newFont(12) end
    love.graphics.setColor(0.9, 0.9, 0.6, 1)
    love.graphics.setFont(smallFont)
    love.graphics.print("Objectives", x + padding, y + padding)

    for i, obj in ipairs(objectiveList) do
        local sy = y + titleH + (i - 1) * lineH + padding
        local state = objectiveStates[obj.id] or "pending"
        local icon, color
        if state == "completed" then
            icon = "✓"
            color = {0.4, 1, 0.4, 1}
        elseif state == "failed" then
            icon = "✗"
            color = {1, 0.4, 0.4, 1}
        else
            icon = "○"
            color = {0.8, 0.8, 0.8, 1}
        end
        love.graphics.setColor(unpack(color))
        love.graphics.print(icon .. " " .. obj.name, x + padding, sy)
    end
end

initDefinitions()
return objectives
