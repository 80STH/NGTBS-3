-- status_shaders.lua
-- Шейдеры для статус-эффектов (acid, decay, empowered, rooted)
local status_shaders = {}

-- ============================================================
-- ACID SHADER - кислота с пузырями
-- ============================================================
local acidShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус эффекта
    extern float time;         // Время для анимации
    extern float intensity;    // Общая интенсивность (0.0-1.0)

    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash(i);
        float b = hash(i + vec2(1.0, 0.0));
        float c = hash(i + vec2(0.0, 1.0));
        float d = hash(i + vec2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    float fbm(vec2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        float frequency = 1.0;
        for (int i = 0; i < 3; i++) {  // Количество октав шума
            value += amplitude * noise(p * frequency);
            frequency *= 2.0;
            amplitude *= 0.5;
        }
        return value;
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - center;
        float dist = length(pos);
        
        if (dist > radius * 1.2) {
            return vec4(0.0);
        }
        
        // Кислотная текстура с шумом (скорость движения)
        vec2 noiseCoord = pos * 0.05 + vec2(0.0, -time * 0.5);
        float n = fbm(noiseCoord);
        
        // Пузыри (количество = 4)
        float bubbles = 0.0;
        for (float i = 0.0; i < 4.0; i++) {
            float bubbleAngle = i * 1.5708 + time * 2.0;  // 1.5708 = 90°
            float bubbleDist = hash(vec2(i, 0.0)) * radius * 0.5;
            vec2 bubblePos = vec2(cos(bubbleAngle), sin(bubbleAngle)) * bubbleDist;
            float bubbleSize = 3.0 + hash(vec2(i, 1.0)) * 4.0;  // Размер пузыря
            float bubble = 1.0 - smoothstep(0.0, bubbleSize, length(pos - bubblePos));
            bubble *= 0.5 + 0.5 * sin(time * 3.0 + i);  // Пульсация
            bubbles += bubble;
        }
        
        // Основная кислота
        float acid = n * 0.7 + bubbles * 0.3;
        acid *= 1.0 - smoothstep(radius * 0.6, radius * 1.1, dist);
        
        float alpha = acid * intensity;
        vec3 col = mix(vec3(0.3, 0.8, 0.2), vec3(0.5, 0.9, 0.3), bubbles);
        col += vec3(0.2, 0.3, 0.1) * n;
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- DECAY SHADER - эффект разложения
-- ============================================================
local decayShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус эффекта
    extern float time;         // Время для анимации
    extern float intensity;    // Общая интенсивность (0.0-1.0)

    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash(i);
        float b = hash(i + vec2(1.0, 0.0));
        float c = hash(i + vec2(0.0, 1.0));
        float d = hash(i + vec2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - center;
        float dist = length(pos);
        float angle = atan(pos.y, pos.x);
        
        if (dist > radius) {
            return vec4(0.0);
        }
        
        // Тёмные частицы разложения (количество = 6)
        float particles = 0.0;
        for (float i = 0.0; i < 6.0; i++) {
            float particleAngle = i * 1.0472 + time * 1.5;  // 1.0472 = 60°
            float particleDist = hash(vec2(i, 0.0)) * radius * 0.6;
            vec2 particlePos = vec2(cos(particleAngle), sin(particleAngle)) * particleDist;
            float particleSize = 2.0 + hash(vec2(i, 1.0)) * 3.0;
            float particle = 1.0 - smoothstep(0.0, particleSize, length(pos - particlePos));
            particle *= 0.5 + 0.5 * sin(time * 4.0 + i * 3.0);  // Мерцание
            particles += particle;
        }
        
        // Гнилая текстура
        vec2 noiseCoord = vec2(angle * 2.0, dist * 0.1) + time * 0.5;
        float rot = noise(noiseCoord);
        
        // Основная масса
        float decay = (1.0 - smoothstep(0.0, radius * 0.7, dist)) * rot;
        decay += particles * 0.3;
        
        float alpha = decay * intensity;
        vec3 col = mix(vec3(0.2, 0.4, 0.1), vec3(0.1, 0.25, 0.05), rot);
        col = mix(col, vec3(0.3, 0.5, 0.2), particles * 0.3);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- EMPOWERED SHADER - эффект усиления
-- ============================================================
local empoweredShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус эффекта
    extern float time;         // Время для анимации
    extern float intensity;    // Общая интенсивность (0.0-1.0)

    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - center;
        float dist = length(pos);
        float angle = atan(pos.y, pos.x);
        
        if (dist > radius) {
            return vec4(0.0);
        }
        
        // Вращающиеся частицы энергии (количество = 6)
        float particles = 0.0;
        for (float i = 0.0; i < 6.0; i++) {
            float particleAngle = i * 1.0472 + time * 2.0;  // 1.0472 = 60°
            float particleDist = radius * 0.5 + radius * 0.3 * sin(time * 3.0 + i);  // Орбита
            vec2 particlePos = vec2(cos(particleAngle), sin(particleAngle)) * particleDist;
            float particleSize = 3.0 + 2.0 * sin(time * 5.0 + i * 2.0);  // Пульсация размера
            float particle = 1.0 - smoothstep(0.0, particleSize, length(pos - particlePos));
            particles += particle;
        }
        
        // Центральное свечение
        float glow = 1.0 - smoothstep(0.0, radius * 0.8, dist);
        glow *= 0.15 + 0.1 * sin(time * 4.0);
        
        // Кольцо энергии (радиус кольца)
        float ring = 1.0 - smoothstep(0.0, 3.0, abs(dist - radius * 0.8 - 2.0 * sin(time * 3.0)));
        ring *= 0.4;
        
        float alpha = (particles * 0.5 + glow + ring) * intensity;
        vec3 col = mix(vec3(1.0, 0.9, 0.2), vec3(1.0, 1.0, 0.5), particles * 0.3);
        col += ring * vec3(0.3, 0.3, 0.1);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- ROOTED SHADER - эффект опутывания корнями
-- ============================================================
local rootedShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус эффекта
    extern float time;         // Время для анимации
    extern float intensity;    // Общая интенсивность (0.0-1.0)

    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash(i);
        float b = hash(i + vec2(1.0, 0.0));
        float c = hash(i + vec2(0.0, 1.0));
        float d = hash(i + vec2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - center;
        float dist = length(pos);
        float angle = atan(pos.y, pos.x);
        
        if (dist > radius) {
            return vec4(0.0);
        }
        
        // Корни, растущие из центра (количество = 6)
        float roots = 0.0;
        for (float i = 0.0; i < 6.0; i++) {
            float rootAngle = i * 1.0472;  // 1.0472 = 60°
            float rootLen = radius * (0.4 + 0.2 * sin(time * 2.0 + i));  // Длина корня
            
            // Направление корня
            vec2 rootDir = vec2(cos(rootAngle), sin(rootAngle));
            vec2 toPixel = pos - rootDir * rootLen * 0.5;
            
            // Расстояние до линии корня
            float along = dot(toPixel, rootDir);
            float perp = length(toPixel - rootDir * along);
            
            // Толщина корня (уменьшается к концу)
            float thickness = 3.0 * (1.0 - along / rootLen);
            thickness = max(thickness, 1.0);
            
            float root = 1.0 - smoothstep(0.0, thickness, perp);
            root *= smoothstep(-rootLen * 0.5, 0.0, along) * smoothstep(rootLen * 0.5, 0.0, along);
            root *= 0.6 + 0.4 * sin(time * 3.0 + i);  // Пульсация
            roots += root;
        }
        
        // Центральное утолщение
        float centerGlow = 1.0 - smoothstep(0.0, radius * 0.3, dist);
        centerGlow *= 0.2 + 0.1 * sin(time * 3.0);
        
        float alpha = (roots + centerGlow) * intensity;
        vec3 col = mix(vec3(0.4, 0.7, 0.1), vec3(0.6, 0.8, 0.2), roots * 0.3);
        
        return vec4(col, alpha);
    }
]]

-- Инициализация шейдеров
function status_shaders.init()
    status_shaders.acid = love.graphics.newShader(acidShaderCode)
    status_shaders.decay = love.graphics.newShader(decayShaderCode)
    status_shaders.empowered = love.graphics.newShader(empoweredShaderCode)
    status_shaders.rooted = love.graphics.newShader(rootedShaderCode)
end

-- Функции отрисовки
function status_shaders.drawAcid(x, y, radius, time, intensity)
    love.graphics.setBlendMode("add")
    status_shaders.acid:send("center", {x, y})
    status_shaders.acid:send("radius", radius)
    status_shaders.acid:send("time", time)
    status_shaders.acid:send("intensity", intensity or 1.0)
    love.graphics.setShader(status_shaders.acid)
    love.graphics.rectangle("fill", x - radius * 1.2, y - radius * 1.2, radius * 2.4, radius * 2.4)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function status_shaders.drawDecay(x, y, radius, time, intensity)
    love.graphics.setBlendMode("add")
    status_shaders.decay:send("center", {x, y})
    status_shaders.decay:send("radius", radius)
    status_shaders.decay:send("time", time)
    status_shaders.decay:send("intensity", intensity or 1.0)
    love.graphics.setShader(status_shaders.decay)
    love.graphics.rectangle("fill", x - radius, y - radius, radius * 2, radius * 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function status_shaders.drawEmpowered(x, y, radius, time, intensity)
    love.graphics.setBlendMode("add")
    status_shaders.empowered:send("center", {x, y})
    status_shaders.empowered:send("radius", radius)
    status_shaders.empowered:send("time", time)
    status_shaders.empowered:send("intensity", intensity or 1.0)
    love.graphics.setShader(status_shaders.empowered)
    love.graphics.rectangle("fill", x - radius, y - radius, radius * 2, radius * 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function status_shaders.drawRooted(x, y, radius, time, intensity)
    love.graphics.setBlendMode("add")
    status_shaders.rooted:send("center", {x, y})
    status_shaders.rooted:send("radius", radius)
    status_shaders.rooted:send("time", time)
    status_shaders.rooted:send("intensity", intensity or 1.0)
    love.graphics.setShader(status_shaders.rooted)
    love.graphics.rectangle("fill", x - radius, y - radius, radius * 2, radius * 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

return status_shaders
