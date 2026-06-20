-- main.lua
-- Entry point. Owns the Game state, camera, sound, and Love callbacks.
-- Mobile-friendly: a single design resolution (720x1280) scaled to the window.

local Game = require("src.game.game")
local camera = require("src.render.camera")
local renderer = require("src.render.renderer")
local ui = require("src.render.ui")
local input = require("src.game.input")
local sound = require("src.assets.sound")
local mapmod = require("src.core.map")
local progression = require("src.content.progression")
local abilities = require("src.content.abilities")

local game
local cam

local function listMaps()
    local items = love.filesystem.getDirectoryItems("maps")
    local list = {}
    for _, f in ipairs(items) do
        if f:match("%.lua$") then table.insert(list, "maps/" .. f) end
    end
    table.sort(list)
    return list
end

local SQUADS = {
    { name = "Old Guard",  units = { "Warrior", "Puncher", "Rogue" } },
    { name = "Wild Magic", units = { "Summoner", "Rogue" } },
    { name = "Vanguard",   units = { "Warrior", "Rogue" } },
}

local function soundShim()
    return setmetatable({}, { __index = function(_, k)
        return { play = function() sound.play(k) end, setVolume = function() end, clone = function() return nil end }
    end })
end

local function startMap(path)
    local data = mapmod.load(path)
    local squad = SQUADS[game.selectedSquad or 1] or SQUADS[1]
    game:loadMap(data, squad.units)
    if game.grid then game.grid:centerOnScreen(cam.designW, cam.designH) end
end

function love.load()
    love.window.setTitle("Hex Tactics")
    sound.init()
    cam = camera.new()
    cam:resize(love.graphics.getDimensions())

    game = Game.new({ sounds = soundShim(), mapList = listMaps(), squads = SQUADS })
    game.selectedSquad = 1

    -- callbacks
    game.onStartMap = function(path)
        game.selectedMap = path
        startMap(path)
    end
    game.onRestart = function()
        if game.selectedMap then startMap(game.selectedMap) end
    end
    game.onNextMap = function()
        game.mapIndex = game.mapIndex + 1
        if game.mapIndex <= #game.mapList then
            game.selectedMap = game.mapList[game.mapIndex]
            startMap(game.selectedMap)
        else
            game.phase = "menu"
        end
    end
    game.onMenu = function()
        game.phase = "menu"
        game.progressionRun = false
        progression.reset()
        abilities.resetUnlocks()
    end
    game.onProgressionConfirmed = function()
        local next = game.mapIndex + 1
        if next <= #game.mapList then
            game.mapIndex = next
            game.selectedMap = game.mapList[next]
            startMap(game.selectedMap)
        else
            game.phase = "menu"
            game.progressionRun = false
        end
    end
    game.onMapCleared = function()
        if not game.progressionRun then return end
        local squad = SQUADS[game.selectedSquad or 1]
        local picks = progression.availablePicks(squad.units)
        if #picks > 0 then
            game.abilityMenu = { available = picks, selectedItem = nil, selectedChoice = nil }
        end
    end
end

function love.resize(w, h)
    cam:resize(love.graphics.getDimensions())
    if game and game.grid then game.grid:centerOnScreen(cam.designW, cam.designH) end
end

local function updateHover()
    if not game or not game.grid then return end
    local mx, my = love.mouse.getPosition()
    local dx, dy = cam:toDesign(mx, my)
    local hq, hr = game.grid:pixelToHex(dx, dy)
    if game.grid:isActiveHex(hq, hr) then
        game.grid.hoverQ, game.grid.hoverR = hq, hr
    else
        game.grid.hoverQ, game.grid.hoverR = nil, nil
    end
end

function love.update(dt)
    if game then
        game:update(dt)
        updateHover()
    end
end

function love.draw()
    cam:apply()
    if game then
        -- screen shake
        if game.screenShake.t > 0 then
            local p = game.screenShake.t / game.screenShake.dur
            local oy = game.screenShake.mag * (1 - p) * math.sin(p * math.pi * 10)
            love.graphics.translate(0, oy)
        end
        if game.phase == "menu" then
            ui.draw(game)
        else
            renderer.draw(game)
            ui.draw(game)
        end
        -- message
        if game.message and game.messageTimer > 0 then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", 60, 1080, 600, 40, 8)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setFont(love.graphics.newFont(14))
            love.graphics.printf(game.message, 70, 1088, 580, "center")
        end
    end
    cam:release()
end

local function handlePress(x, y)
    local dx, dy = cam:toDesign(x, y)
    if ui.handlePress(game, dx, dy) then return end
    if game.phase == "deploy" then
        input.handleDeployPress(game, dx, dy)
    elseif game.phase == "playing" then
        input.handlePress(game, dx, dy)
    end
end

function love.mousepressed(x, y, button)
    if button ~= 1 then return end
    handlePress(x, y)
end

-- touch: treat first touch as a press
function love.touchpressed(id, x, y)
    handlePress(x, y)
end

function love.keypressed(key)
    if not game then return end
    if key == "escape" then
        if abilities.activeAbility then
            abilities.activeAbility:onDeactivate(game)
            abilities.activeAbility = nil
        elseif game.phase ~= "menu" then
            game.phase = "menu"
        end
        return
    end
    if game.phase == "playing" and game.turn.phase == "player" then
        if abilities.handleKey(key, game) then return end
        if key == "r" then if game.onRestart then game.onRestart() end return end
        if key == "tab" or key == "q" then
            if game.selectedActor then
                game:switchAttack()
                if not game.attackMode then game:selectAttack(game.selectedActor:getCurrentAttackId()) end
            end
            return
        end
        if key == "f5" then  -- debug auto-win
            game.win = true; game.phase = "gameover"
            if game.progressionRun then game:onMapCleared() end
            return
        end
    end
end
