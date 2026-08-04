-- tests/turn_order_test.lua
-- Verifies buildEnemyAttackQueue: all enemies attack one at a time (single
-- sequential group), units before buildings, leaders before regulars,
-- attacksFirst first, trains appended last.

local turnManager

local function entity(name, props)
    props = props or {}
    return {
        name = name,
        health = 1,
        isDying = false,
        isPlayable = false,
        isTrainAttack = false,
        hasPreparedAttack = true,
        _preparedTargetType = props.targetType or "unit",
        isLeader = props.isLeader or false,
        attacksFirst = props.attacksFirst or false,
        isCharacter = function() return true end,
    }
end

local function setup()
    package.loaded["system.trains"] = {
        prepareTrainAttacks = function() end,
        getTrainGroups = function() return {} end,
    }
    turnManager = require("core.turn_manager")
end

return {
    name = "turn_order",
    tests = {
        { name = "all prepared enemies land in one sequential group", fn = function()
            setup()
            entities = {
                entity("zombie", { targetType = "unit" }),
                entity("lich", { targetType = "building" }),
            }
            local queue = turnManager.buildEnemyAttackQueue()
            return #queue == 1 and queue[1].type == "sequential" and #queue[1].enemies == 2
        end },
        { name = "units attack before buildings", fn = function()
            setup()
            entities = {
                entity("lich", { targetType = "building" }),
                entity("zombie", { targetType = "unit" }),
            }
            local enemies = turnManager.buildEnemyAttackQueue()[1].enemies
            return enemies[1].name == "zombie" and enemies[2].name == "lich"
        end },
        { name = "leaders before regulars within tier", fn = function()
            setup()
            entities = {
                entity("regular", { targetType = "unit" }),
                entity("leader", { targetType = "unit", isLeader = true }),
            }
            local enemies = turnManager.buildEnemyAttackQueue()[1].enemies
            return enemies[1].name == "leader" and enemies[2].name == "regular"
        end },
        { name = "attacksFirst before others", fn = function()
            setup()
            entities = {
                entity("normal", { targetType = "unit" }),
                entity("first", { targetType = "unit", attacksFirst = true }),
            }
            local enemies = turnManager.buildEnemyAttackQueue()[1].enemies
            return enemies[1].name == "first" and enemies[2].name == "normal"
        end },
        { name = "dead and unprepared enemies excluded", fn = function()
            setup()
            local dead = entity("dead", { targetType = "unit" })
            dead.health = 0
            local noPrep = entity("noprep", { targetType = "unit" })
            noPrep.hasPreparedAttack = false
            entities = { dead, noPrep, entity("alive", { targetType = "unit" }) }
            local enemies = turnManager.buildEnemyAttackQueue()[1].enemies
            return #enemies == 1 and enemies[1].name == "alive"
        end },
        { name = "empty queue when nobody prepared", fn = function()
            setup()
            entities = {}
            return #turnManager.buildEnemyAttackQueue() == 0
        end },
    },
}
