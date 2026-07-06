function love.conf(t)
    t.title = "NGTBS-2"
    t.author = "80STH"
    t.version = "11.4"
    
    t.window.highdpi = true
    t.window.width = 800
    t.window.height = 1280
    t.window.resizable = true
    t.window.fullscreen = false
    t.window.borderless = false

    -- Android: use fullscreen, hide status bar via love.keyboard.setTextInput
    -- The 720x1280 resolution acts as logical canvas; dpiScale handles physical pixels
    
    -- Enable filesystem access
    t.identity = "HexTacticsGame"  -- Creates save folder

    -- Modules
    t.modules.audio = true
    t.modules.graphics = true
    t.modules.keyboard = true
    t.modules.mouse = true
    t.modules.timer = true
    t.modules.filesystem = true  -- Required for saves

    t.console = true  -- Enables Windows console
end