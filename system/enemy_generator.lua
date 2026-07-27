local enemy_generator = {}

local HEALTH_COST = {0, 4, 8}
local SPEED_COST = {0, 1, 2}
local MOBILITY_COST = {walking = 0, hovering = 1, teleport = 4}
local AURA_COST = {none = 0, slow = 3}

local ATTACKS = {
    {name = "Ghost Bolt", set = "ghost", cost = 2, color = {0.7, 0.3, 1}, melee = false},
    {name = "Bite", set = "zombie", cost = 2, color = {0.3, 0.7, 0.2}, melee = true},
    {name = "Magic Bolt", set = "lich", cost = 2, color = {0.8, 0.2, 0.8}, melee = false},
    {name = "Bash", set = "brute", cost = 4, color = {0.6, 0.4, 0.2}, melee = true},
    {name = "Lunge", set = "lancer", cost = 4, color = {0.5, 0.5, 0.7}, melee = true},
    {name = "Cleave", set = "dervish", cost = 5, color = {0.8, 0.4, 0.3}, melee = true},
}

local AI_MODELS = {
    {id = "buildings", name = "Siege", cost = 0},
    {id = "units", name = "Hunter", cost = 0},
    {id = "indiscriminate", name = "Chaos", cost = 0},
}

function enemy_generator.calculateCost(params)
    local cost = 0
    cost = cost + HEALTH_COST[params.health]
    
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

function enemy_generator.generate(budget)
    local params = {}
    
    params.health = love.math.random(1, 3)
    
    local mobilityRoll = love.math.random()
    if mobilityRoll < 0.15 then
        params.mobility = "teleport"
        params.moveRange = "infinite"
    else
        params.mobility = mobilityRoll < 0.35 and "hovering" or "walking"
        params.moveRange = love.math.random(2, 4)
    end
    
    params.aura = love.math.random() < 0.2 and "slow" or "none"
    if params.aura == "slow" then
        local melee = {}
        for _, a in ipairs(ATTACKS) do if a.melee then table.insert(melee, a) end end
        params.attack = melee[love.math.random(#melee)]
    else
        params.attack = ATTACKS[love.math.random(#ATTACKS)]
    end
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
    if params.mobility == "teleport" then
        prefix = "Phase "
    elseif params.mobility == "hovering" then
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
