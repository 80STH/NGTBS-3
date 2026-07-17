local icon_cache = {}
local ICON_SIZE = 48

local icon_names = {
    "wound", "heavy_wound", "fatal_wound", "fatal_wound_acid",
    "building_damage", "heavy_building_damage", "building_destruction",
    "collision_damage", "collision_no_damage",
    "health", "move",
    "trait_flying", "trait_hovering", "trait_teleporting",
    "trait_water_walker", "trait_indestructible", "trait_move_after_attack",
    "atk_dash", "atk_flip", "atk_shoot", "atk_push", "atk_piercing_shot",
    "atk_stone_throw", "atk_cone_blast", "atk_magic_bolt", "atk_power_bolt",
    "atk_ghost_bolt", "atk_bite", "atk_summon", "atk_split",
    "atk_vortex_strike", "atk_wide_vortex", "atk_pull_hook", "atk_electric_hook",
    "atk_bash", "atk_cleave", "atk_lunge", "atk_heavy_punch",
    "atk_empower_punch", "atk_rampage", "atk_mend", "atk_phase_shift",
    "atk_frenzy", "atk_hunt", "atk_mighty_throw",
    "btn_order", "btn_undo", "btn_end_turn",
    "abil_heal", "abil_extra_move", "abil_wind_torrent", "abil_unearth",
    "abil_mind_control", "abil_accelerate_decay", "abil_force_attack",
    "abil_rage", "abil_the_big_one", "abil_air_strike",
    "abil_jumping_strike", "abil_stasis_overload", "abil_chain_lightning",
    "abil_invulnerability", "abil_vortex", "abil_hex",
    "abil_upside_down", "abil_teleport", "abil_speed_boost",
}

function icon_cache.loadAll()
    for _, name in ipairs(icon_names) do
        local path = "icons/" .. name .. ".png"
        local info = love.filesystem.getInfo(path)
        if info then
            local img = love.graphics.newImage(path)
            img:setFilter("nearest", "nearest")
            icon_cache[name] = img
        end
    end
end

function icon_cache.get(name)
    return icon_cache[name]
end

function icon_cache.draw(name, x, y, alpha)
    local img = icon_cache[name]
    if not img then return end
    local w, h = img:getDimensions()
    local scale = ICON_SIZE / math.max(w, h)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, x, y, 0, scale, scale, w/2, h/2)
    love.graphics.setColor(1, 1, 1, 1)
end

function icon_cache.drawSmall(name, x, y, size, alpha)
    local img = icon_cache[name]
    if not img then return end
    local w, h = img:getDimensions()
    local scale = (size or 28) / math.max(w, h)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, x, y, 0, scale, scale, w/2, h/2)
    love.graphics.setColor(1, 1, 1, 1)
end

function icon_cache.keyForAttack(attackName)
    if not attackName then return nil end
    local key = "atk_" .. attackName:lower():gsub(" ", "_")
    return icon_cache[key] and key or nil
end

function icon_cache.keyForAbility(abilityName)
    if not abilityName then return nil end
    local key = "abil_" .. abilityName:lower():gsub(" ", "_")
    return icon_cache[key] and key or nil
end

return icon_cache
