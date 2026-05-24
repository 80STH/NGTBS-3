function love.conf(t)
    t.title = "Hex Grid Tactics Game"
    t.author = "Your Name"
    t.version = "11.4"
    
    t.window.width = 1600
    t.window.height = 1200
    t.window.resizable = true
    
    -- Включаем доступ к файловой системе
    t.identity = "HexTacticsGame"  -- Создает папку для сохранений
    
    -- Модули
    t.modules.audio = true
    t.modules.graphics = true
    t.modules.keyboard = true
    t.modules.mouse = true
    t.modules.timer = true
    t.modules.filesystem = true  -- Обязательно для сохранений



    t.console = true  -- Включает консоль Windows
end