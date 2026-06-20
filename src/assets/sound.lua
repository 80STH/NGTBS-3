-- src/assets/sound.lua
-- Procedural sound effects. Generates simple waveforms at load time so the game
-- has audio with zero asset files. Replace any preset with a real .wav later by
-- loading it into the same `sources` table.

local sound = {}
sound.sources = {}
sound.enabled = true

local SR = 44100

local function envADSR(i, n, attack, release)
    local a = math.floor(n * attack)
    local r = math.floor(n * release)
    if i < a then return i / math.max(1, a) end
    if i > n - r then return math.max(0, (n - i) / math.max(1, r)) end
    return 1
end

local function makeTone(freq, dur, opts)
    opts = opts or {}
    local n = math.floor(SR * dur)
    -- mono, 16-bit; use setSample(index, value) 2-arg form (safe for mono)
    local sd = love.sound.newSoundData(n, SR, 16, 1)
    local vol = opts.volume or 0.5
    local ftype = opts.type or "sine"
    local f2 = opts.sweepTo or freq
    for i = 0, n - 1 do
        local t = i / SR
        local frac = i / n
        local f = freq + (f2 - freq) * frac
        local s = 0
        if ftype == "sine" then
            s = math.sin(2 * math.pi * f * t)
        elseif ftype == "square" then
            s = (math.sin(2 * math.pi * f * t) >= 0) and 1 or -1
        elseif ftype == "saw" then
            s = 2 * ((f * t) % 1) - 1
        elseif ftype == "noise" then
            s = (love.math.random() * 2 - 1)
        elseif ftype == "sweep" then
            s = math.sin(2 * math.pi * f * t)
        end
        if opts.harmonic then s = s * 0.6 + math.sin(2 * math.pi * f * 2 * t) * 0.3 end
        local e = envADSR(i, n, opts.attack or 0.02, opts.release or 0.3)
        sd:setSample(i, s * e * vol)
    end
    return love.audio.newSource(sd, "static")
end

function sound.init()
    sound.sources.hover    = makeTone(660, 0.05, { type = "sine", volume = 0.18, attack = 0.01, release = 0.9 })
    sound.sources.click    = makeTone(440, 0.06, { type = "square", volume = 0.22, attack = 0.01, release = 0.8 })
    sound.sources.attack   = makeTone(220, 0.12, { type = "noise", volume = 0.35, attack = 0.01, release = 0.6 })
    sound.sources.collision= makeTone(90,  0.18, { type = "saw", volume = 0.4, attack = 0.005, release = 0.7 })
    sound.sources.heal     = makeTone(440, 0.4,  { type = "sine", sweepTo = 880, volume = 0.3, attack = 0.05, release = 0.5 })
    sound.sources.wind     = makeTone(120, 0.5,  { type = "noise", sweepTo = 400, volume = 0.25, attack = 0.1, release = 0.6 })
    sound.sources.death    = makeTone(330, 0.35, { type = "saw", sweepTo = 80, volume = 0.3, attack = 0.01, release = 0.6 })
    sound.sources.summon   = makeTone(523, 0.35, { type = "sine", sweepTo = 1046, volume = 0.25, harmonic = true, attack = 0.05, release = 0.5 })
    sound.sources.undo     = makeTone(300, 0.1,  { type = "sine", volume = 0.2, attack = 0.01, release = 0.8 })
    sound.sources.turn     = makeTone(196, 0.15, { type = "sine", volume = 0.18, attack = 0.02, release = 0.7 })
    sound.sources.empower  = makeTone(660, 0.3,  { type = "sine", sweepTo = 1320, volume = 0.25, harmonic = true, attack = 0.05, release = 0.5 })
end

function sound.play(name)
    if not sound.enabled then return end
    local s = sound.sources[name]
    if not s then return end
    local c = s:clone()
    c:play()
end

return sound
