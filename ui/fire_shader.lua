-- fire_shader.lua
-- Шейдерный эффект огня для гексов и сущностей
local fire_shader = {}

-- GLSL шейдер для процедурной генерации огня
local shaderCode = [[
    // Параметры, передаваемые из Lua
    extern number time;        // Время для анимации (секунды)
    extern vec2 hexCenter;     // Центр гекса в экранных координатах
    extern number hexRadius;   // Радиус гекса в пикселях
    extern number intensity;   // Общая интенсивность огня (0.0 - 1.0)

    // Функция хеширования для генерации псевдослучайных значений
    // Возвращает значение 0.0-1.0 для каждой точки
    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    // Функция шума (value noise)
    // Создаёт плавные переходы между случайными значениями
    float noise(vec2 p) {
        vec2 i = floor(p);           // Целая часть координат
        vec2 f = fract(p);           // Дробная часть координат
        f = f * f * (3.0 - 2.0 * f); // Сглаживание (smoothstep)
        
        // Получаем значения в четырёх углах ячейки
        float a = hash(i);
        float b = hash(i + vec2(1.0, 0.0));
        float c = hash(i + vec2(0.0, 1.0));
        float d = hash(i + vec2(1.0, 1.0));
        
        // Билинейная интерполяция
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    // Фрактальный шум (Fractal Brownian Motion)
    // Суммирует несколько октав шума для создания детализированной текстуры
    float fbm(vec2 p) {
        float value = 0.0;
        float amplitude = 0.5;  // Начальная амплитуда (вклад каждой октавы)
        float frequency = 1.0;  // Начальная частота
        
        for (int i = 0; i < 4; i++) {  // 4 октавы шума
            value += amplitude * noise(p * frequency);
            frequency *= 2.0;  // Удваиваем частоту (больше деталей)
            amplitude *= 0.5;  // Уменьшаем амплитуду (меньший вклад)
        }
        return value;
    }

    // Главная функция шейдера
    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        // Вычисляем позицию относительно центра гекса
        vec2 pos = screenCoord - hexCenter;
        float dist = length(pos) / hexRadius;  // Нормализованное расстояние от центра
        
        // Отсекаем пиксели за пределами гекса
        if (dist > 1.2) {
            return vec4(0.0);  // Прозрачный
        }
        
        // Вертикальная компонента (огонь поднимается вверх)
        float rise = -pos.y / hexRadius;  // Инвертируем Y (вверх = положительное)
        rise = clamp(rise * 0.7 + 0.4, 0.0, 1.0);  // Настраиваем диапазон
        
        // Горизонтальная компонента
        float horizontal = pos.x / hexRadius;
        
        // Координаты для шума (анимация через time)
        // horizontal * 2.5 - горизонтальная детализация
        // rise * 2.0 - time * 1.8 - вертикальное движение вверх
        vec2 noiseCoord = vec2(horizontal * 2.5, rise * 2.0 - time * 1.8);
        float n = fbm(noiseCoord);
        
        // Форма пламени: шум * вертикальная позиция
        float flame = n * rise;
        flame = pow(flame, 1.3) * intensity;  // Степень контролирует контраст
        
        // Цветовая палитра огня
        vec3 coreColor = vec3(1.0, 0.95, 0.4);   // Яркое жёлтое ядро
        vec3 midColor = vec3(1.0, 0.5, 0.1);     // Оранжевый средний слой
        vec3 outerColor = vec3(0.7, 0.15, 0.0);  // Тёмно-красные края
        
        // Смешиваем цвета на основе интенсивности пламени
        vec3 fireColor;
        if (flame > 0.5) {
            // Яркое ядро (flame 0.5-1.0)
            fireColor = mix(midColor, coreColor, (flame - 0.5) / 0.5);
        } else if (flame > 0.2) {
            // Средний слой (flame 0.2-0.5)
            fireColor = mix(outerColor, midColor, (flame - 0.2) / 0.3);
        } else {
            // Тусклые края (flame 0.0-0.2)
            fireColor = outerColor * (flame / 0.2);
        }
        
        // Затухание к краям гекса
        float edgeFade = 1.0 - smoothstep(0.5, 1.1, dist);
        float alpha = flame * edgeFade * 0.85;  // Финальная прозрачность
        
        return vec4(fireColor, alpha);
    }
]]

-- Создаём объект шейдера
fire_shader.shader = love.graphics.newShader(shaderCode)

-- Рисует огонь на гексе
-- x, y - центр гекса
-- radius - радиус гекса
-- time - текущее время для анимации
function fire_shader.drawFireOnHex(x, y, radius, time)
    love.graphics.setBlendMode("add")  -- Аддитивное смешивание для свечения
    fire_shader.shader:send("time", time)
    fire_shader.shader:send("hexCenter", {x, y})
    fire_shader.shader:send("hexRadius", radius)
    fire_shader.shader:send("intensity", 1.0)  -- Полная интенсивность для гекса
    
    love.graphics.setShader(fire_shader.shader)
    -- Рисуем прямоугольник с запасом (1.2x радиуса)
    love.graphics.rectangle("fill", x - radius * 1.2, y - radius * 1.2, radius * 2.4, radius * 2.4)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")  -- Возвращаем обычный режим
end

-- Рисует огонь на сущности
-- Параметры аналогичны drawFireOnHex, но intensity снижена
function fire_shader.drawFireOnEntity(x, y, radius, time)
    love.graphics.setBlendMode("add")
    fire_shader.shader:send("time", time)
    fire_shader.shader:send("hexCenter", {x, y})
    fire_shader.shader:send("hexRadius", radius)
    fire_shader.shader:send("intensity", 0.85)  -- Чуть менее интенсивный для сущностей
    
    love.graphics.setShader(fire_shader.shader)
    love.graphics.rectangle("fill", x - radius * 1.2, y - radius * 1.2, radius * 2.4, radius * 2.4)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

return fire_shader
