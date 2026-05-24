function love.conf(t)
    t.title = "NGTBS-2"
    t.author = "80STH"
    t.version = "11.4"
    
    t.window.width = 1400
    t.window.height = 1100
    t.window.resizable = true
    t.window.highdpi = false
    
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