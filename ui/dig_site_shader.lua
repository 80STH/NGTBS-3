-- dig_site_shader.lua
-- Шейдерный эффект для выкопок (dig sites)
local dig_site_shader = {}

local shaderCode = [[
    extern number time;
    extern vec2 hexCenter;
    extern number hexRadius;
    extern number urgency;

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
        for (int i = 0; i < 4; i++) {
            value += amplitude * noise(p * frequency);
            frequency *= 2.0;
            amplitude *= 0.5;
        }
        return value;
    }

    // Spiral distortion
    vec2 spiral(vec2 p, float strength) {
        float angle = atan(p.y, p.x);
        float dist = length(p);
        float twist = strength * (1.0 - dist);
        float newAngle = angle + twist;
        return vec2(cos(newAngle), sin(newAngle)) * dist;
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 pos = screenCoord - hexCenter;
        float dist = length(pos) / hexRadius;
        
        // Compact size - only 0.45 of hex radius
        float effectRadius = 0.45;
        if (dist > effectRadius) {
            return vec4(0.0);
        }
        
        vec2 uv = pos / hexRadius;
        float normalizedDist = dist / effectRadius;
        
        // Spiral distortion pulling inward
        float spiralStrength = 3.0 + sin(time * 1.5) * 0.5;
        vec2 spiralUv = spiral(uv * 8.0, spiralStrength);
        
        // Swirling cracks
        float crack1 = fbm(spiralUv + time * 0.2);
        float crack2 = fbm(spiralUv * 1.5 - time * 0.15);
        float cracks = smoothstep(0.3, 0.5, crack1) * smoothstep(0.4, 0.6, crack2);
        
        // Dark void in center with rotation
        float voidDist = smoothstep(0.0, 0.3, normalizedDist);
        float rotation = time * 0.8;
        vec2 rotUv = vec2(
            uv.x * cos(rotation) - uv.y * sin(rotation),
            uv.x * sin(rotation) + uv.y * cos(rotation)
        );
        float voidNoise = fbm(rotUv * 6.0);
        vec3 voidColor = mix(vec3(0.02, 0.01, 0.0), vec3(0.08, 0.04, 0.02), voidNoise);
        
        // Pulsing rings expanding outward
        float ringFreq = 8.0;
        float ringSpeed = 2.0;
        float rings = sin(normalizedDist * ringFreq - time * ringSpeed) * 0.5 + 0.5;
        rings = pow(rings, 4.0) * (1.0 - normalizedDist);
        
        // Glowing amber core
        float coreGlow = (1.0 - normalizedDist) * (0.4 + 0.2 * sin(time * 2.5));
        vec3 glowColor = vec3(0.95, 0.55, 0.15) * coreGlow * urgency;
        
        // Earth texture with cracks
        float earthNoise = fbm(uv * 6.0 + time * 0.08);
        vec3 earthColor = mix(vec3(0.25, 0.12, 0.04), vec3(0.45, 0.25, 0.08), earthNoise);
        
        // Combine layers
        vec3 finalColor = voidColor * voidDist;
        finalColor += earthColor * cracks * 0.5 * voidDist;
        finalColor += glowColor * 0.6;
        finalColor += vec3(0.85, 0.45, 0.12) * rings * 0.4 * urgency;
        
        // Edge rim with pulse
        float rim = smoothstep(0.7, 0.95, normalizedDist) * (1.0 - smoothstep(0.95, 1.0, normalizedDist));
        float rimPulse = 0.6 + 0.4 * sin(time * 3.5 + normalizedDist * 4.0);
        finalColor += vec3(0.9, 0.5, 0.15) * rim * rimPulse * urgency;
        
        // Inward-flowing particles
        float particleAngle = atan(uv.y, uv.x) + time * 1.2;
        float particleDist = length(uv) * 10.0;
        float particles = step(0.92, hash(floor(vec2(particleAngle * 3.0, particleDist - time * 3.0))));
        finalColor += vec3(1.0, 0.75, 0.35) * particles * (1.0 - normalizedDist) * 0.6;
        
        float alpha = smoothstep(1.0, 0.8, normalizedDist) * 0.9;
        
        return vec4(finalColor, alpha);
    }
]]

dig_site_shader.shader = love.graphics.newShader(shaderCode)

function dig_site_shader.drawDigSite(x, y, radius, time, urgency)
    love.graphics.setBlendMode("alpha")
    dig_site_shader.shader:send("time", time)
    dig_site_shader.shader:send("hexCenter", {x, y})
    dig_site_shader.shader:send("hexRadius", radius)
    dig_site_shader.shader:send("urgency", urgency or 1.0)
    
    love.graphics.setShader(dig_site_shader.shader)
    love.graphics.rectangle("fill", x - radius * 0.5, y - radius * 0.5, radius, radius)
    love.graphics.setShader()
end

return dig_site_shader
