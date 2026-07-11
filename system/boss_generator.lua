local boss_generator = {}

local HEALTH_COST = {4, 6, 8, 10}
local SPEED_COST = {1, 2, 3}
local MOBILITY_COST = {walking = 0, hovering = 2, teleport = 10}
local AURA_COST = {none = 0, slow = 3}

local ATTACKS = {
    {name = "Magic Bolt", set = "lich", cost = 3, color = {0.8, 0.2, 0.8}},
}

local AI_MODELS = {
    {id = "buildings", name = "Siege", cost = 1},
    {id = "units", name = "Hunter", cost = 1},
    {id = "indiscriminate", name = "Chaos", cost = 0},
}

function boss_generator.calculateCost(params)
    local cost = 0
    cost = cost + HEALTH_COST[params.health - 3]
    
    if params.mobility == "teleport" then
        cost = cost + MOBILITY_COST.teleport
    else
        cost = cost + SPEED_COST[params.moveRange - 1]
        cost = cost + MOBILITY_COST[params.mobility]
    end
    
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

function boss_generator.generate(budget)
    local params = {}
    
    params.health = love.math.random(4, 6)
    
    local mobilityRoll = love.math.random()
    if mobilityRoll < 0.15 then
        params.mobility = "teleport"
        params.moveRange = "infinite"
    else
        params.mobility = mobilityRoll < 0.35 and "hovering" or "walking"
        params.moveRange = love.math.random(2, 3)
    end
    
    params.attack = ATTACKS[1]
    params.aura = love.math.random() < 0.25 and "slow" or "none"
    local aiModel = AI_MODELS[love.math.random(#AI_MODELS)]
    params.aiModel = aiModel.id
    
    local cost = boss_generator.calculateCost(params)
    params.cost = cost
    params.budget = budget
    
    params.name = boss_generator.generateName(params)
    params.color = params.attack.color
    
    return params
end

function boss_generator.generateName(params)
    local prefix = "Boss "
    if params.mobility == "teleport" then
        prefix = prefix .. "Phase "
    elseif params.mobility == "hovering" then
        prefix = prefix .. "Hovering "
    elseif params.health == 6 then
        prefix = prefix .. "Mighty "
    end
    
    local baseName = "Lich"
    if params.aiModel == "buildings" then
        baseName = baseName .. " Siege"
    elseif params.aiModel == "units" then
        baseName = baseName .. " Hunter"
    end
    
    return prefix .. baseName
end

function boss_generator.getAttacks()
    return ATTACKS
end

function boss_generator.getAIModels()
    return AI_MODELS
end

return boss_generator
