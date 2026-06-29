-- visual_shaders.lua
-- Шейдеры для визуальных эффектов (shockwave, sparks, blood, magic_explosion, lightning, ghost_hit, drown)
local visual_shaders = {}

-- ============================================================
-- SHOCKWAVE SHADER - ударная волна с пульсацией
-- ============================================================
local shockwaveShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Текущий радиус
    extern float progress;     // Прогресс анимации (0.0-1.0)
    extern float maxRadius;    // Максимальный радиус волны

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
        float wavePos = progress * maxRadius;  // Позиция фронта волны
        
        // Ширина кольца волны (зависит от radius)
        float waveWidth = radius * 0.4;
        float wave = smoothstep(wavePos - waveWidth, wavePos, dist) - smoothstep(wavePos, wavePos + waveWidth, dist);
        
        // Пульсация внутри (заполнение)
        float inner = 1.0 - smoothstep(0.0, wavePos * 0.7, dist);
        inner *= 0.3 * (1.0 - progress);
        
        // Шум для деформации волны
        float angle = atan(pos.y, pos.x);
        float noiseVal = noise(vec2(angle * 3.0, dist * 0.1)) * 0.3;
        
        float alpha = (wave + inner) * (1.0 - progress);
        vec3 col = mix(vec3(1.0, 1.0, 0.8), vec3(0.8, 0.5, 0.2), progress);
        
        return vec4(col, alpha * (0.7 + noiseVal));
    }
]]

-- ============================================================
-- SPARKS SHADER - искры с свечением
-- ============================================================
local sparksShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус разлёта искр
    extern float progress;     // Прогресс анимации (0.0-1.0)
    extern float count;        // Количество искр

    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - center;
        float dist = length(pos);
        float angle = atan(pos.y, pos.x);
        
        // Создаём лучи искр
        float sparkAngle = angle * count / 6.28318;
        float sparkId = floor(sparkAngle);
        float sparkFrac = fract(sparkAngle);
        
        // Каждая искра имеет свою длину и яркость
        float sparkLen = hash(vec2(sparkId, 0.0)) * radius * (1.0 - progress * 0.5);
        float sparkBright = hash(vec2(sparkId, 1.0));
        
        // Форма искры (плавные переходы)
        float spark = smoothstep(0.0, 0.3, sparkFrac) * smoothstep(1.0, 0.7, sparkFrac);
        spark *= smoothstep(sparkLen, sparkLen * 0.3, dist);
        
        // Свечение в центре
        float glow = 1.0 - smoothstep(0.0, radius * 0.3, dist);
        glow *= 0.5 * (1.0 - progress);
        
        float alpha = (spark * sparkBright + glow) * (1.0 - progress);
        vec3 col = mix(vec3(1.0, 0.9, 0.5), vec3(1.0, 0.4, 0.1), progress);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- MAGIC EXPLOSION SHADER - магический взрыв
-- ============================================================
local magicExplosionShaderCode = [[
    extern vec2 center;        // Центр взрыва
    extern float radius;       // Радиус взрыва
    extern float progress;     // Прогресс анимации (0.0-1.0)
    extern vec3 magicColor;    // Цвет магии (R, G, B)

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
        for (int i = 0; i < 4; i++) {  // Количество октав шума
            value += amplitude * noise(p * frequency);
            frequency *= 2.0;
            amplitude *= 0.5;
        }
        return value;
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - center;
        float dist = length(pos);
        float angle = atan(pos.y, pos.x);
        
        // Расширяющееся кольцо
        float ringPos = progress * radius * 1.5;
        float ring = smoothstep(ringPos - 10.0, ringPos, dist) - smoothstep(ringPos, ringPos + 10.0, dist);
        ring *= 1.0 - progress;
        
        // Внутренний взрыв с шумом
        vec2 noiseCoord = vec2(angle * 2.0, dist * 0.05) + progress * 2.0;
        float n = fbm(noiseCoord);
        float inner = (1.0 - smoothstep(0.0, radius * (0.5 + progress * 0.5), dist)) * n;
        inner *= 1.0 - progress * 0.5;
        
        // Лучи энергии (количество = 6, угол = 60°)
        float rays = 0.0;
        for (float i = 0.0; i < 6.0; i++) {
            float rayAngle = i * 1.0472 + progress * 3.0;  // 1.0472 = 60°
            float rayDist = abs(sin(angle - rayAngle));
            float ray = smoothstep(0.95, 1.0, rayDist) * (1.0 - smoothstep(0.0, radius * 1.5, dist));
            rays += ray * (1.0 - progress);
        }
        
        float alpha = ring + inner * 0.8 + rays * 0.3;
        vec3 col = magicColor * (1.0 + ring * 0.5);
        col = mix(col, vec3(1.0), ring * 0.5);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- LIGHTNING SHADER - молния с ветвлениями
-- ============================================================
local lightningShaderCode = [[
    extern vec2 target;        // Цель молнии (нижняя точка)
    extern float progress;     // Прогресс анимации (0.0-1.0)
    extern float intensity;    // Интенсивность свечения

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
        vec2 pos = screenCoord;
        
        // Направление молнии (сверху к цели)
        vec2 start = vec2(target.x, 0.0);
        vec2 end = target;
        vec2 dir = end - start;
        float totalLen = length(dir);
        
        // Проецируем позицию на линию молнии
        vec2 toPixel = pos - start;
        float proj = dot(toPixel, dir) / totalLen;
        
        if (proj < 0.0 || proj > totalLen) {
            return vec4(0.0);
        }
        
        // Основная линия с шумом (амплитуда изгиба)
        vec2 linePos = start + dir * (proj / totalLen);
        float noiseVal = noise(vec2(proj * 0.1, progress * 10.0)) * 20.0 * (1.0 - proj / totalLen);
        linePos.x += noiseVal;
        
        float dist = length(pos - linePos);
        
        // Толщина молнии (уменьшается к концу)
        float thickness = 4.0 * (1.0 - proj / totalLen * 0.7);
        float bolt = 1.0 - smoothstep(0.0, thickness, dist);
        
        // Свечение вокруг молнии (радиус свечения)
        float glow = 1.0 - smoothstep(0.0, thickness * 3.0, dist);
        glow *= 0.3;
        
        // Вспышка в точке удара (радиус вспышки)
        float hitDist = length(pos - target);
        float flash = 1.0 - smoothstep(0.0, 30.0 * (1.0 - progress), hitDist);
        flash *= (1.0 - progress);
        
        float alpha = (bolt + glow) * (1.0 - progress * 0.5) * intensity + flash * 0.5;
        vec3 col = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 1.0, 1.0), bolt);
        col += flash * vec3(1.0, 0.9, 0.5);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- BLOOD SHADER - брызги крови
-- ============================================================
local bloodShaderCode = [[
    extern vec2 center;        // Центр брызга
    extern float radius;       // Радиус разлёта капель
    extern float progress;     // Прогресс анимации (0.0-1.0)

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
        
        // Количество капель
        float dropCount = 8.0;
        float dropAngle = angle * dropCount / 6.28318;
        float dropId = floor(dropAngle);
        float dropFrac = fract(dropAngle);
        
        // Каждая капля имеет свою траекторию
        float dropDist = hash(vec2(dropId, 0.0)) * radius * progress;
        float dropSize = hash(vec2(dropId, 1.0)) * 4.0 + 2.0;
        
        // Форма капли
        vec2 dropCenter = vec2(cos(angle), sin(angle)) * dropDist;
        float drop = 1.0 - smoothstep(0.0, dropSize, length(pos - dropCenter));
        
        // Центральный всплеск
        float splash = 1.0 - smoothstep(0.0, radius * 0.3 * (1.0 - progress), dist);
        splash *= 1.0 - progress;
        
        float alpha = (drop + splash) * (1.0 - progress);
        vec3 col = vec3(0.8, 0.1, 0.1);
        col = mix(col, vec3(0.5, 0.0, 0.0), progress);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- GHOST HIT SHADER - призрачный удар
-- ============================================================
local ghostHitShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус эффекта
    extern float progress;     // Прогресс анимации (0.0-1.0)

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
        
        // Призрачное свечение с шумом
        float angle = atan(pos.y, pos.x);
        float noiseVal = noise(vec2(angle * 3.0, dist * 0.1 + progress * 5.0));
        
        // Расширяющееся кольцо
        float ring = 1.0 - smoothstep(0.0, 5.0, abs(dist - radius * progress * 2.0));
        ring *= 1.0 - progress;
        
        // Внутреннее свечение
        float inner = 1.0 - smoothstep(0.0, radius * (0.5 + progress), dist);
        inner *= noiseVal * (1.0 - progress);
        
        float alpha = (ring + inner * 0.5) * (0.8 - progress);
        vec3 col = mix(vec3(0.7, 0.3, 1.0), vec3(0.9, 0.6, 1.0), ring);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- DROWN SHADER - эффект утопления
-- ============================================================
local drownShaderCode = [[
    extern vec2 center;        // Центр эффекта
    extern float radius;       // Радиус эффекта
    extern float progress;     // Прогресс анимации (0.0-1.0)

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
        
        // Водные круги (частота волн)
        float ripple1 = sin(dist * 0.5 - progress * 10.0) * 0.5 + 0.5;
        float ripple2 = sin(dist * 0.3 - progress * 8.0 + 1.0) * 0.5 + 0.5;
        float ripples = (ripple1 + ripple2) * 0.5;
        
        // Пузырьки (количество = 12)
        float bubbles = 0.0;
        for (float i = 0.0; i < 12.0; i++) {
            float bubbleAngle = i * 0.5236 + progress * 3.0;  // 0.5236 = 30°
            float bubbleDist = hash(vec2(i, 0.0)) * radius * progress;
            vec2 bubblePos = vec2(cos(bubbleAngle), sin(bubbleAngle)) * bubbleDist;
            bubblePos.y -= progress * 20.0;  // Скорость всплытия
            float bubble = 1.0 - smoothstep(0.0, 5.0, length(pos - bubblePos));
            bubbles += bubble * (1.0 - progress);
        }
        
        // Центральный водоворот
        float vortex = 1.0 - smoothstep(0.0, radius * (1.0 - progress * 0.5), dist);
        vortex *= ripples;
        
        float alpha = (vortex * 0.7 + bubbles * 0.3) * (1.0 - progress * 0.5);
        vec3 col = mix(vec3(0.2, 0.6, 0.9), vec3(0.3, 0.7, 1.0), ripples);
        
        return vec4(col, alpha);
    }
]]

-- ============================================================
-- UNIT COLLISION SHADER - столкновение юнитов (ударная волна + искры + вспышка)
-- ============================================================
local unitCollisionShaderCode = [[
    extern vec2 center;        // Центр столкновения
    extern float radius;       // Радиус эффекта
    extern float progress;     // Прогресс анимации (0.0-1.0)
    extern float intensity;    // Интенсивность (0.0-1.0)

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
        
        // === УДАРНАЯ ВОЛНА ===
        // Кольцо волны расширяется от центра
        float wavePos = progress * radius * 1.5;
        float waveWidth = radius * 0.25;
        float wave = smoothstep(wavePos - waveWidth, wavePos, dist) - smoothstep(wavePos, wavePos + waveWidth, dist);
        wave *= (1.0 - progress);
        
        // === ИСКРЫ ===
        // Лучи искр разлетаются от центра (количество = 8)
        float sparks = 0.0;
        for (float i = 0.0; i < 8.0; i++) {
            float sparkAngle = i * 0.7854;  // 0.7854 = 45°
            float sparkLen = radius * (0.6 + hash(vec2(i, 0.0)) * 0.4) * progress;
            float sparkDist = hash(vec2(i, 1.0)) * 0.5 + 0.5;
            
            // Направление искры
            vec2 sparkDir = vec2(cos(sparkAngle), sin(sparkAngle));
            vec2 toPixel = pos - sparkDir * sparkLen * 0.5;
            
            // Расстояние до линии искры
            float along = dot(toPixel, sparkDir);
            float perp = length(toPixel - sparkDir * along);
            
            // Толщина искры
            float thickness = 2.0 * (1.0 - progress);
            float spark = 1.0 - smoothstep(0.0, thickness, perp);
            spark *= smoothstep(-sparkLen * 0.5, 0.0, along) * smoothstep(sparkLen * 0.5, 0.0, along);
            spark *= sparkDist * (1.0 - progress);
            sparks += spark;
        }
        
        // === ВСПЫШКА В ЦЕНТРЕ ===
        float flash = 1.0 - smoothstep(0.0, radius * 0.4 * (1.0 - progress * 0.5), dist);
        flash *= (1.0 - progress) * 0.8;
        
        // === ШУМ ДЛЯ ДЕФОРМАЦИИ ===
        float noiseVal = noise(vec2(angle * 4.0, dist * 0.1 + progress * 5.0)) * 0.3;
        
        // === ИТОГОВАЯ ЯРКОСТЬ ===
        float alpha = (wave * 0.6 + sparks * 0.4 + flash) * intensity;
        
        // === ЦВЕТ ===
        // Жёлто-оранжевый с белым в центре
        vec3 col = mix(vec3(1.0, 0.6, 0.2), vec3(1.0, 0.9, 0.5), flash);
        col = mix(col, vec3(1.0, 1.0, 0.8), wave * 0.3);
        
        return vec4(col, alpha * (0.8 + noiseVal));
    }
]]

-- Инициализация шейдеров
function visual_shaders.init()
    visual_shaders.shockwave = love.graphics.newShader(shockwaveShaderCode)
    visual_shaders.sparks = love.graphics.newShader(sparksShaderCode)
    visual_shaders.magicExplosion = love.graphics.newShader(magicExplosionShaderCode)
    visual_shaders.lightning = love.graphics.newShader(lightningShaderCode)
    visual_shaders.blood = love.graphics.newShader(bloodShaderCode)
    visual_shaders.ghostHit = love.graphics.newShader(ghostHitShaderCode)
    visual_shaders.drown = love.graphics.newShader(drownShaderCode)
    visual_shaders.unitCollision = love.graphics.newShader(unitCollisionShaderCode)
end

-- Функции отрисовки
function visual_shaders.drawShockwave(x, y, radius, progress, maxRadius)
    love.graphics.setBlendMode("add")
    visual_shaders.shockwave:send("center", {x, y})
    visual_shaders.shockwave:send("radius", radius)
    visual_shaders.shockwave:send("progress", progress)
    visual_shaders.shockwave:send("maxRadius", maxRadius or 50.0)
    love.graphics.setShader(visual_shaders.shockwave)
    love.graphics.rectangle("fill", x - maxRadius, y - maxRadius, maxRadius * 2, maxRadius * 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function visual_shaders.drawSparks(x, y, radius, progress, count)
    love.graphics.setBlendMode("add")
    visual_shaders.sparks:send("center", {x, y})
    visual_shaders.sparks:send("radius", radius)
    visual_shaders.sparks:send("progress", progress)
    visual_shaders.sparks:send("count", count or 8)
    love.graphics.setShader(visual_shaders.sparks)
    love.graphics.rectangle("fill", x - radius, y - radius, radius * 2, radius * 2)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function visual_shaders.drawMagicExplosion(x, y, radius, progress, r, g, b)
    love.graphics.setBlendMode("add")
    visual_shaders.magicExplosion:send("center", {x, y})
    visual_shaders.magicExplosion:send("radius", radius)
    visual_shaders.magicExplosion:send("progress", progress)
    visual_shaders.magicExplosion:send("magicColor", {r or 0.6, g or 0.2, b or 1.0})
    love.graphics.setShader(visual_shaders.magicExplosion)
    love.graphics.rectangle("fill", x - radius * 2, y - radius * 2, radius * 4, radius * 4)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function visual_shaders.drawLightning(x, y, progress, intensity)
    love.graphics.setBlendMode("add")
    visual_shaders.lightning:send("target", {x, y})
    visual_shaders.lightning:send("progress", progress)
    visual_shaders.lightning:send("intensity", intensity or 1.0)
    love.graphics.setShader(visual_shaders.lightning)
    love.graphics.rectangle("fill", x - 50, 0, 100, y)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function visual_shaders.drawBlood(x, y, radius, progress)
    love.graphics.setBlendMode("alpha")
    visual_shaders.blood:send("center", {x, y})
    visual_shaders.blood:send("radius", radius)
    visual_shaders.blood:send("progress", progress)
    love.graphics.setShader(visual_shaders.blood)
    love.graphics.rectangle("fill", x - radius, y - radius, radius * 2, radius * 2)
    love.graphics.setShader()
end

function visual_shaders.drawGhostHit(x, y, radius, progress)
    love.graphics.setBlendMode("add")
    visual_shaders.ghostHit:send("center", {x, y})
    visual_shaders.ghostHit:send("radius", radius)
    visual_shaders.ghostHit:send("progress", progress)
    love.graphics.setShader(visual_shaders.ghostHit)
    love.graphics.rectangle("fill", x - radius * 2, y - radius * 2, radius * 4, radius * 4)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

function visual_shaders.drawDrown(x, y, radius, progress)
    love.graphics.setBlendMode("alpha")
    visual_shaders.drown:send("center", {x, y})
    visual_shaders.drown:send("radius", radius)
    visual_shaders.drown:send("progress", progress)
    love.graphics.setShader(visual_shaders.drown)
    love.graphics.rectangle("fill", x - radius, y - radius, radius * 2, radius * 2)
    love.graphics.setShader()
end

function visual_shaders.drawUnitCollision(x, y, radius, progress, intensity)
    love.graphics.setBlendMode("add")
    visual_shaders.unitCollision:send("center", {x, y})
    visual_shaders.unitCollision:send("radius", radius)
    visual_shaders.unitCollision:send("progress", progress)
    visual_shaders.unitCollision:send("intensity", intensity or 1.0)
    love.graphics.setShader(visual_shaders.unitCollision)
    love.graphics.rectangle("fill", x - radius * 1.5, y - radius * 1.5, radius * 3, radius * 3)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
end

return visual_shaders
