local enemy_generator = {}

local HEALTH_COST = {1, 2, 4}
local SPEED_COST = {1, 2, 3}
local MOBILITY_COST = {walking = 0, hovering = 2}
local AURA_COST = {none = 0, slow = 3}

local ATTACKS = {
    {name = "Ghost Bolt", set = "ghost", cost = 3, color = {0.7, 0.3, 1}},
    {name = "Bite", set = "zombie", cost = 2, color = {0.3, 0.7, 0.2}},
    {name = "Magic Bolt", set = "lich", cost = 3, color = {0.8, 0.2, 0.8}},
    {name = "Bash", set = "brute", cost = 2, color = {0.6, 0.4, 0.2}},
    {name = "Lunge", set = "lancer", cost = 2, color = {0.5, 0.5, 0.7}},
    {name = "Cleave", set = "dervish", cost = 3, color = {0.8, 0.4, 0.3}},
}

local AI_MODELS = {
    {id = "buildings", name = "Siege", cost = 1},
    {id = "units", name = "Hunter", cost = 1},
    {id = "indiscriminate", name = "Chaos", cost = 0},
}

function enemy_generator.calculateCost(params)
    local cost = 0
    cost = cost + HEALTH_COST[params.health]
    cost = cost + SPEED_COST[params.moveRange - 1]
    cost = cost + MOBILITY_COST[params.mobility]
    cost = cost + params.attack.cost
    cost = cost + AURA_COST[params.aura]
    for _, model in ipairs(AI_MODELS) do
        if model.id == params.aiModel then
            cost = cost + model.cost
            break
        end
    end
    return cost
end

function enemy_generator.generate(budget)
    local params = {}
    
    params.health = love.math.random(1, 3)
    params.moveRange = love.math.random(2, 4)
    params.mobility = love.math.random() < 0.3 and "hovering" or "walking"
    params.attack = ATTACKS[love.math.random(#ATTACKS)]
    params.aura = love.math.random() < 0.2 and "slow" or "none"
    local aiModel = AI_MODELS[love.math.random(#AI_MODELS)]
    params.aiModel = aiModel.id
    
    local cost = enemy_generator.calculateCost(params)
    params.cost = cost
    params.budget = budget
    
    params.name = enemy_generator.generateName(params)
    params.color = params.attack.color
    
    return params
end

function enemy_generator.generateName(params)
    local prefix = ""
    if params.mobility == "hovering" then
        prefix = "Hovering "
    elseif params.health == 3 then
        prefix = "Tank "
    elseif params.moveRange == 4 then
        prefix = "Swift "
    end
    
    local baseName = params.attack.set:gsub("^%l", string.upper)
    if params.aiModel == "buildings" then
        baseName = baseName .. " Siege"
    elseif params.aiModel == "units" then
        baseName = baseName .. " Hunter"
    end
    
    return prefix .. baseName
end

function enemy_generator.getAttacks()
    return ATTACKS
end

function enemy_generator.getAIModels()
    return AI_MODELS
end

return enemy_generator
