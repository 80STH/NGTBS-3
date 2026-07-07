-- sounds.lua
-- Audio manager with .wav file priority and procedural fallback
-- Usage:
--   sounds.init()           -- call once in love.load()
--   sounds.play("attack")   -- triggers a one-shot sound
--   sounds.hover()          -- quiet tick on UI hover (rate-limited)
--
-- To replace with .wav files: just drop X.wav into sounds/ folder
-- (e.g. sounds/attack.wav, sounds/move.wav, etc.)

local sounds = {}
local soundgen = require("system.soundgen")
local log = require("util.log")

local enabled = true
local volume = 0.5
local hoverCooldown = 0
local hoverCooldownTime = 0.06
local loadedWav = {}

-- Map of sound names → generator function
local generators = {
    move = soundgen.move,
    attack = soundgen.attack,
    hit = soundgen.hit,
    death = soundgen.death,
    ui_click = soundgen.ui_click,
    ui_hover = soundgen.ui_hover,
    turn_start = soundgen.turn_start,
    dig = soundgen.dig,
    lightning = soundgen.lightning,
    train = soundgen.train,
    ability = soundgen.ability,
    undo = soundgen.undo,
    collision = soundgen.collision,
    cant = soundgen.cant,
    -- Aliases (map to existing sounds, replace with dedicated .wav later)
    fire = soundgen.hit,
    decay = soundgen.hit,
    wind = soundgen.wind_torrent,
    -- Attack-specific sounds
    dash = soundgen.dash,
    flip = soundgen.flip,
    bash_attack = soundgen.bash,
    cleave = soundgen.cleave,
    lunge = soundgen.lunge,
    heavy_punch = soundgen.heavy_punch,
    empower_punch = soundgen.empower_punch,
    bite_attack = soundgen.bite,
    shoot = soundgen.shoot,
    piercing_shot = soundgen.piercing_shot,
    ghost_bolt = soundgen.ghost_bolt,
    magic_bolt = soundgen.magic_bolt,
    power_bolt = soundgen.power_bolt,
    stone_throw = soundgen.stone_throw,
    vortex_strike = soundgen.vortex_strike,
    wide_vortex = soundgen.wide_vortex,
    pull_hook = soundgen.pull_hook,
    electric_hook = soundgen.electric_hook,
    cone_blast = soundgen.cone_blast,
    shockwave = soundgen.shockwave,
    summon_attack = soundgen.summon,
    split_attack = soundgen.split,
    summon_enemy = soundgen.summon_enemy,
    -- Ability-specific sounds
    heal_ability = soundgen.heal_ability,
    extra_move = soundgen.extra_move,
    wind_torrent = soundgen.wind_torrent,
    unearth = soundgen.unearth,
    mind_control = soundgen.mind_control,
    accelerate_decay = soundgen.accelerate_decay,
    vortex_ability = soundgen.vortex_ability,
}

-- Custom volume per sound type (multiplied by master volume)
local customVolumes = {
    ui_hover = 0.5,
    ui_click = 0.7,
    move = 0.6,
    turn_start = 0.8,
    ability = 0.7,
    cant = 0.8,
}

-- Try to load a .wav file; fall back to generator
local function loadSound(name)
    if loadedWav[name] ~= nil then
        return loadedWav[name] -- already tried
    end
    local wavPath = "sounds/" .. name .. ".wav"
    local info = love.filesystem.getInfo(wavPath)
    if info and info.type == "file" then
        local ok, src = pcall(love.audio.newSource, wavPath, "static")
        if ok and src then
            loadedWav[name] = src
            log.infof("sounds", "Loaded .wav: %s", wavPath)
            return src
        end
    end
    -- Fall back to procedural generation
    if generators[name] then
        local src = generators[name]()
        loadedWav[name] = src
        return src
    end
    loadedWav[name] = false
    return nil
end

function sounds.init()
    -- Pre-load the simple ones so first play doesn't lag
    loadSound("ui_click")
    loadSound("ui_hover")
    loadSound("move")
end

function sounds.setEnabled(on)
    enabled = on
end

function sounds.setVolume(v)
    volume = v
end

-- Play a one-shot sound by name
function sounds.play(name)
    if not enabled then return end
    local src = loadSound(name)
    if not src then return end
    src:stop()
    local v = (customVolumes[name] or 1.0) * volume
    src:setVolume(v)
    src:play()
end

-- Quiet UI hover tick with anti-spam cooldown
function sounds.hover(dt)
    if not enabled then return end
    hoverCooldown = hoverCooldown - dt
    if hoverCooldown > 0 then return end
    hoverCooldown = hoverCooldownTime
    local src = loadSound("ui_hover")
    if not src then return end
    src:stop()
    src:setVolume((customVolumes.ui_hover or 0.5) * volume)
    src:play()
end

return sounds
