function love.conf(t)
    t.title = "Hex Tactics"
    t.author = "80STH"
    t.version = "11.4"
    t.identity = "HexTactics"

    t.window.highdpi = true
    t.window.width = 720
    t.window.height = 1280
    t.window.resizable = true
    t.window.minwidth = 360
    t.window.minheight = 640

    t.modules.audio = true
    t.modules.graphics = true
    t.modules.keyboard = true
    t.modules.mouse = true
    t.modules.touch = true
    t.modules.timer = true
    t.modules.filesystem = true
    t.modules.math = true

    t.console = true
end
