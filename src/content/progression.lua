-- src/content/progression.lua
-- Meta-progression: per-unit upgrade choices and global artifacts.
-- Adding new upgrades/artifacts: add an entry with an `apply(entity)` callback.
-- The progression menu (render/ui) reads `progression.upgrades` and `progression.artifacts`.

local progression = {}

-- per-unit upgrade choices (player picks one per unlocked unit per map clear)
progression.upgrades = {
    Warrior = {
        { id = "dash_flip_chain", name = "Dash→Flip", desc = "After Dash, may Flip the same target",
          apply = function(e) e.dashFlipChain = true end },
        { id = "flip_dash_chain", name = "Flip→Dash", desc = "After Flip, may Dash the same target",
          apply = function(e) e.flipDashChain = true end },
    },
    Puncher = {
        { id = "empower_start", name = "Empowered Start", desc = "Begin each map empowered",
          apply = function(e) e:applyStatus("empowered") end },
        { id = "choose_push_dir", name = "Windup", desc = "Choose push direction on Heavy Punch",
          apply = function(e) e.choosePushDir = true end },
    },
    Rogue = {
        { id = "redirect_shot", name = "Ricochet", desc = "Shoot may redirect to a second target",
          apply = function(e) e.redirectShot = true end },
        { id = "point_blank_lethal", name = "Close Quarters", desc = "Point-blank shot is lethal",
          apply = function(e) e.pointBlankLethal = true end },
    },
}

progression.artifacts = {
    { id = "root_immune", name = "Iron Will", desc = "Allies immune to root/slow auras",
      apply = function(e) e.rootImmune = true end },
    { id = "armor", name = "Fortress", desc = "Allies take -1 damage",
      apply = function(e) e.armor = (e.armor or 0) + 1 end },
    { id = "move_speed", name = "Swift Boots", desc = "Allies +1 move range",
      apply = function(e) e.moveRange = e.moveRange + 1 end },
    { id = "move_after_attack", name = "Hit & Run", desc = "Allies may move after attacking",
      apply = function(e) e.canMoveAfterAttack = true end },
    { id = "phase_through", name = "Ghost Cloak", desc = "Allies phase through enemies",
      apply = function(e) e.phaseThroughEnemies = true end },
    { id = "deploy_anywhere", name = "Scout", desc = "Allies deploy on any terrain",
      apply = function(e) e.deployAnywhere = true end },
}

-- state (persisted across maps within a run)
progression.chosenUpgrades = {}  -- unitName -> list of choice ids
progression.chosenArtifacts = {} -- list of artifact ids

function progression.reset()
    progression.chosenUpgrades = {}
    progression.chosenArtifacts = {}
end

function progression.addUpgrade(unitName, choiceId)
    progression.chosenUpgrades[unitName] = progression.chosenUpgrades[unitName] or {}
    table.insert(progression.chosenUpgrades[unitName], choiceId)
end

function progression.addArtifact(artId)
    table.insert(progression.chosenArtifacts, artId)
end

-- Apply all chosen upgrades + artifacts to a freshly created ally entity.
function progression.applyToEntity(e)
    local ups = progression.chosenUpgrades[e.defId]
    if ups then
        for _, cid in ipairs(ups) do
            for _, choice in ipairs(progression.upgrades[e.defId] or {}) do
                if choice.id == cid then choice.apply(e) end
            end
        end
    end
    for _, aid in ipairs(progression.chosenArtifacts) do
        for _, art in ipairs(progression.artifacts) do
            if art.id == aid then art.apply(e) end
        end
    end
end

-- Build the list of available picks after a map clear (units without an upgrade + unused artifacts)
function progression.availablePicks(squadUnitNames)
    local out = {}
    for _, name in ipairs(squadUnitNames) do
        local ups = progression.chosenUpgrades[name] or {}
        if #ups < #(progression.upgrades[name] or {}) then
            table.insert(out, { type = "unit", name = name })
        end
    end
    for _, art in ipairs(progression.artifacts) do
        local taken = false
        for _, aid in ipairs(progression.chosenArtifacts) do if aid == art.id then taken = true break end end
        if not taken then table.insert(out, { type = "artifact", id = art.id, name = art.name, desc = art.desc }) end
    end
    return out
end

return progression
