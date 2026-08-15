-- commanders.lua
-- Commander definitions: starting abilities, exclusive artifacts, upgrades
-- Commanders are the ones who use global_abilities
-- Selected in menu before squad selection, forming a commander+squad pair

local commanders = {}

commanders.list = {}

-- ============================================================
-- HEALER
-- ============================================================
commanders.list.Healer = {
    name = "Healer",
    desc = "Support specialist. Starts with Heal. Excels at keeping allies alive and cleansing debuffs.",
    startAbilities = { "Heal" },
    startMana = 3,
    startMaxMana = 3,
    color = { 0.2, 0.7, 0.3 },
    -- Exclusive artifacts offered during progression (after unit upgrades)
    exclusiveArtifacts = {
        {
            id = "healer_mana",
            name = "Divine Favor",
            desc = "+1 max mana for the commander.",
            apply = function() global_abilities.maxMana = (global_abilities.maxMana or 3) + 1; global_abilities.mana = global_abilities.maxMana end,
        },
    },
}

-- ============================================================
-- ENFORCER
-- ============================================================
commanders.list.Enforcer = {
    name = "Enforcer",
    desc = "Tactical specialist. Starts with Extra Move. Excels at repositioning allies and enemy disruption.",
    startAbilities = { "Extra Move", "Void" },
    startMana = 3,
    startMaxMana = 3,
    color = { 0.2, 0.4, 0.9 },
    exclusiveArtifacts = {
        {
            id = "enforcer_mana",
            name = "Tactical Genius",
            desc = "+1 max mana for the commander.",
            apply = function() global_abilities.maxMana = (global_abilities.maxMana or 3) + 1; global_abilities.mana = global_abilities.maxMana end,
        },
    },
}

-- ============================================================
-- API
-- ============================================================

function commanders.get(name)
    return commanders.list[name]
end

return commanders
