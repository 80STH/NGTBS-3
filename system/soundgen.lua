-- soundgen.lua
-- Procedural 8-bit / chip-style sound generator
-- Uses Love2D SoundData to generate sounds without .wav files
-- All sounds are cached so they're generated once and reused

local soundgen = {}

local sampleRate = 44100
local cache = {}

local function makeSoundData(samples)
    local sd = love.sound.newSoundData(#samples, sampleRate, 16, 1)
    for i = 1, #samples do
        local v = math.floor(samples[i] * 32767)
        if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
        sd:setSample(i - 1, v / 32767)
    end
    return sd
end

local function cached(name, fn)
    if cache[name] then return cache[name] end
    local sd = fn()
    local src = love.audio.newSource(sd)
    src:setVolume(0.4)
    cache[name] = src
    return src
end

-- ============================================================
-- SOUND GENERATORS
-- ============================================================

function soundgen.move()
    return cached("move", function()
        local dur = 0.04
        local n = math.floor(sampleRate * dur)
        local s = {}
        local freq = 400
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * freq * t) * envelope * 0.3
            table.insert(s, v)
            freq = freq + 800 * (i / n)
        end
        return makeSoundData(s)
    end)
end

function soundgen.attack()
    return cached("attack", function()
        local dur = 0.15
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local freq = 800 - 600 * (i / n)
            local v = math.sin(2 * math.pi * freq * t) * envelope * 0.4
            -- Add noise burst at the start
            local noise = (math.random() * 2 - 1) * envelope * 0.3
            table.insert(s, v + noise)
        end
        return makeSoundData(s)
    end)
end

function soundgen.hit()
    return cached("hit", function()
        local dur = 0.08
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local envelope = 1 - (i / n)
            local v = (math.random() * 2 - 1) * envelope * 0.5
            table.insert(s, v)
        end
        return makeSoundData(s)
    end)
end

function soundgen.death()
    return cached("death", function()
        local dur = 0.3
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local freq = 300 - 250 * (i / n)
            local v = math.sin(2 * math.pi * freq * t) * envelope * 0.4
            local noise = (math.random() * 2 - 1) * envelope * 0.2
            table.insert(s, v + noise)
        end
        return makeSoundData(s)
    end)
end

function soundgen.ui_click()
    return cached("ui_click", function()
        local dur = 0.03
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * 800 * t) * envelope * 0.25
            table.insert(s, v)
        end
        return makeSoundData(s)
    end)
end

function soundgen.ui_hover()
    return cached("ui_hover", function()
        local dur = 0.015
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * 1200 * t) * envelope * 0.12
            table.insert(s, v)
        end
        return makeSoundData(s)
    end)
end

function soundgen.turn_start()
    return cached("turn_start", function()
        local dur = 0.2
        local n = math.floor(sampleRate * dur)
        local s = {}
        local notes = {523, 659, 784} -- C5, E5, G5 arpeggio
        for ni = 1, #notes do
            local start = math.floor((ni - 1) * n / 3)
            local finish = math.floor(ni * n / 3)
            for i = start + 1, finish do
                local t = (i - 1) / sampleRate
                local localT = t - (ni - 1) * dur / 3
                local envelope = math.max(0, 1 - localT * 8)
                local v = math.sin(2 * math.pi * notes[ni] * t) * envelope * 0.2
                table.insert(s, v)
            end
        end
        return makeSoundData(s)
    end)
end

function soundgen.dig()
    return cached("dig", function()
        local dur = 0.25
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local freq = 60 + 20 * math.sin(t * 30)
            local v = math.sin(2 * math.pi * freq * t) * envelope * 0.5
            local noise = (math.random() * 2 - 1) * envelope * 0.4
            table.insert(s, v + noise)
        end
        return makeSoundData(s)
    end)
end

function soundgen.lightning()
    return cached("lightning", function()
        local dur = 0.4
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local envelope = 1 - (i / n)
            local v = (math.random() * 2 - 1) * envelope * 0.6
            local crackle = math.sin(2 * math.pi * 80 * (i - 1) / sampleRate) * envelope * 0.5
            table.insert(s, math.max(-1, math.min(1, v + crackle)))
        end
        return makeSoundData(s)
    end)
end

function soundgen.train()
    return cached("train", function()
        local dur = 0.4
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = math.min(1, t * 10) * math.max(0, 1 - (i - n * 0.7) / (n * 0.3))
            local v = math.sin(2 * math.pi * 55 * t) * envelope * 0.4
            local noise = (math.random() * 2 - 1) * envelope * 0.3
            table.insert(s, v + noise)
        end
        return makeSoundData(s)
    end)
end

function soundgen.ability()
    return cached("ability", function()
        local dur = 0.25
        local n = math.floor(sampleRate * dur)
        local s = {}
        local notes = {440, 554, 659, 880} -- A4, C#5, E5, A5
        for ni = 1, #notes do
            local start = math.floor((ni - 1) * n / 4)
            local finish = math.floor(ni * n / 4)
            for i = start + 1, finish do
                local t = (i - 1) / sampleRate
                local localT = t - (ni - 1) * dur / 4
                local envelope = math.max(0, 1 - localT * 6)
                local v = math.sin(2 * math.pi * notes[ni] * t) * envelope * 0.25
                local v2 = math.sin(2 * math.pi * notes[ni] * 2 * t) * envelope * 0.08
                table.insert(s, v + v2)
            end
        end
        return makeSoundData(s)
    end)
end

function soundgen.undo()
    return cached("undo", function()
        local dur = 0.06
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local freq = 800 - 400 * (i / n)
            local v = math.sin(2 * math.pi * freq * t) * envelope * 0.3
            table.insert(s, v)
        end
        return makeSoundData(s)
    end)
end

function soundgen.collision()
    return cached("collision", function()
        local dur = 0.1
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * 100 * (i - 1) / sampleRate) * envelope * 0.5
            local noise = (math.random() * 2 - 1) * envelope * 0.5
            table.insert(s, v + noise)
        end
        return makeSoundData(s)
    end)
end

function soundgen.cant()
    return cached("cant", function()
        local dur = 0.12
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * 200 * t) * envelope * 0.2
            local v2 = math.sin(2 * math.pi * 205 * t) * envelope * 0.2
            table.insert(s, v + v2)
        end
        return makeSoundData(s)
    end)
end

-- ============================================================
-- ATTACK-SPECIFIC SOUNDS
-- ============================================================

-- Helper: quick impact + noise burst
local function impactSound(name, freq, dur, vol)
    local d = dur or 0.08
    local f = freq or 300
    local v = vol or 0.45
    return cached(name, function()
        local n = math.floor(sampleRate * d)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n) ^ 0.5
            local tone = math.sin(2 * math.pi * f * t) * envelope * v
            local noise = (math.random() * 2 - 1) * envelope * v * 0.7
            table.insert(s, tone + noise)
            f = f - f * 0.3 * (i / n)
        end
        return makeSoundData(s)
    end)
end

-- Helper: sweep sound
local function sweepSound(name, fStart, fEnd, dur, vol)
    return cached(name, function()
        local n = math.floor(sampleRate * (dur or 0.12))
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local freq = fStart + (fEnd - fStart) * (i / n)
            local v = math.sin(2 * math.pi * freq * t) * envelope * (vol or 0.4)
            table.insert(s, v)
        end
        return makeSoundData(s)
    end)
end

-- Helper: magical chime
local function magicSound(name, notes, dur, vol)
    return cached(name, function()
        local d = dur or 0.2
        local n = math.floor(sampleRate * d)
        local s = {}
        for ni = 1, #notes do
            local start = math.floor((ni - 1) * n / #notes)
            local finish = math.floor(ni * n / #notes)
            for i = start + 1, finish do
                local t = (i - 1) / sampleRate
                local localT = t - (ni - 1) * d / #notes
                local envelope = math.max(0, 1 - localT * 8)
                local v = math.sin(2 * math.pi * notes[ni] * t) * envelope * (vol or 0.3)
                local v2 = math.sin(2 * math.pi * notes[ni] * 1.5 * t) * envelope * (vol or 0.3) * 0.3
                table.insert(s, v + v2)
            end
        end
        return makeSoundData(s)
    end)
end

-- Helper: rumble
local function rumbleSound(name, freq, dur, vol)
    return cached(name, function()
        local n = math.floor(sampleRate * (dur or 0.25))
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * freq * t) * envelope * (vol or 0.45)
            local noise = (math.random() * 2 - 1) * envelope * (vol or 0.45) * 0.8
            table.insert(s, v + noise)
        end
        return makeSoundData(s)
    end)
end

-- MELEE ATTACKS
soundgen.dash = function() return sweepSound("dash", 600, 150, 0.1, 0.4) end
soundgen.flip = function() return sweepSound("flip", 400, 800, 0.12, 0.45) end
soundgen.bash = function() return impactSound("bash", 180, 0.1, 0.5) end
soundgen.cleave = function() return sweepSound("cleave", 500, 200, 0.15, 0.4) end
soundgen.lunge = function() return sweepSound("lunge", 300, 100, 0.1, 0.45) end
soundgen.heavy_punch = function() return impactSound("heavy_punch", 150, 0.12, 0.55) end
soundgen.empower_punch = function() return impactSound("empower_punch", 200, 0.14, 0.5) end
soundgen.bite = function() return impactSound("bite", 250, 0.07, 0.4) end

-- RANGED ATTACKS
soundgen.shoot = function() return sweepSound("shoot", 800, 400, 0.08, 0.35) end
soundgen.piercing_shot = function() return sweepSound("piercing_shot", 1000, 300, 0.1, 0.4) end
soundgen.ghost_bolt = function() return sweepSound("ghost_bolt", 1200, 200, 0.15, 0.25) end
soundgen.magic_bolt = function() return magicSound("magic_bolt", {600, 900, 1200}, 0.15, 0.35) end
soundgen.power_bolt = function() return rumbleSound("power_bolt", 80, 0.3, 0.55) end
soundgen.stone_throw = function() return rumbleSound("stone_throw", 100, 0.2, 0.5) end
soundgen.vortex_strike = function() return sweepSound("vortex_strike", 400, 800, 0.15, 0.35) end
soundgen.wide_vortex = function() return sweepSound("wide_vortex", 300, 700, 0.2, 0.3) end
soundgen.pull_hook = function() return sweepSound("pull_hook", 500, 150, 0.1, 0.4) end
soundgen.electric_hook = function() return magicSound("electric_hook", {880, 660, 440}, 0.12, 0.4) end

-- CONE / AOE
soundgen.cone_blast = function() return rumbleSound("cone_blast", 60, 0.25, 0.5) end
soundgen.shockwave = function() return rumbleSound("shockwave", 60, 0.25, 0.5) end

-- SUMMON
soundgen.summon = function() return magicSound("summon", {523, 659, 784, 1047}, 0.25, 0.35) end
soundgen.split = function() return magicSound("split", {784, 659, 523}, 0.2, 0.35) end
soundgen.summon_enemy = function() return magicSound("summon_enemy", {392, 311, 262}, 0.25, 0.4) end

-- ============================================================
-- ABILITY-SPECIFIC SOUNDS
-- ============================================================
soundgen.heal_ability = function() return magicSound("heal_ability", {523, 659, 784, 1047}, 0.3, 0.3) end
soundgen.extra_move = function() return sweepSound("extra_move", 600, 1200, 0.1, 0.35) end
soundgen.wind_torrent = function() return sweepSound("wind_torrent", 200, 600, 0.35, 0.4) end
soundgen.unearth = function() return rumbleSound("unearth", 50, 0.4, 0.5) end
soundgen.mind_control = function() return magicSound("mind_control", {440, 554, 440}, 0.2, 0.25) end
soundgen.accelerate_decay = function()
    return cached("accelerate_decay", function()
        local dur = 0.3
        local n = math.floor(sampleRate * dur)
        local s = {}
        for i = 1, n do
            local t = (i - 1) / sampleRate
            local envelope = 1 - (i / n)
            local v = math.sin(2 * math.pi * 150 * t) * envelope * 0.2
            -- Ticking effect
            local tick = (i % math.floor(sampleRate * 0.06) < 100) and 0.3 or 0
            table.insert(s, (v + tick) * envelope)
        end
        return makeSoundData(s)
    end)
end
soundgen.vortex_ability = function() return sweepSound("vortex_ability", 300, 900, 0.2, 0.35) end

return soundgen
