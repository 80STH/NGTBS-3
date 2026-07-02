-- water_shader.lua
-- Adapted from Godot water.gdshader to LOVE2D GLSL
local water_shader = {}

local shaderCode = [[
    extern number time;
    extern number brightness;

    float dot2(vec2 x) {
        return dot(x, x);
    }

    float rand(vec2 x) {
        return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5);
    }

    vec2 rand2(vec2 x) {
        return fract(cos(mod(vec2(dot(x, vec2(13.9898, 8.141)),
                                  dot(x, vec2(3.4562, 17.398))), vec2(3.14))) * 43758.5);
    }

    vec3 rand3(vec2 x) {
        return fract(cos(mod(vec3(dot(x, vec2(13.9898, 8.141)),
                                  dot(x, vec2(3.4562, 17.398)),
                                  dot(x, vec2(13.254, 5.867))), vec3(3.14))) * 43758.5);
    }

    float perlin_noise_2d(vec2 coord, vec2 size, float offset, float seed) {
        vec2 o = floor(coord) + rand2(vec2(seed, 1.0 - seed)) + size;
        vec2 f = fract(coord);
        float a00 = rand(mod(o, size)) * 6.28318530718 + offset * 6.28318530718;
        float a01 = rand(mod(o + vec2(0.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;
        float a10 = rand(mod(o + vec2(1.0, 0.0), size)) * 6.28318530718 + offset * 6.28318530718;
        float a11 = rand(mod(o + vec2(1.0, 1.0), size)) * 6.28318530718 + offset * 6.28318530718;
        vec2 v00 = vec2(cos(a00), sin(a00));
        vec2 v01 = vec2(cos(a01), sin(a01));
        vec2 v10 = vec2(cos(a10), sin(a10));
        vec2 v11 = vec2(cos(a11), sin(a11));
        float p00 = dot(v00, f);
        float p01 = dot(v01, f - vec2(0.0, 1.0));
        float p10 = dot(v10, f - vec2(1.0, 0.0));
        float p11 = dot(v11, f - vec2(1.0, 1.0));
        vec2 t = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        return 0.5 + mix(mix(p00, p10, t.x), mix(p01, p11, t.x), t.y);
    }

    float fbm_perlin(vec2 coord, vec2 size, int octaves, float persistence, float offset, float seed) {
        float normalize_factor = 0.0;
        float value = 0.0;
        float scale = 1.0;
        for (int i = 0; i < 4; i++) {
            if (i >= octaves) break;
            float noise = perlin_noise_2d(coord * size, size, offset, seed + float(i));
            value += noise * scale;
            normalize_factor += scale;
            size *= 2.0;
            scale *= persistence;
        }
        return value / normalize_factor;
    }

    vec3 iq_voronoi(vec2 x, vec2 size, vec2 stretch, float randomness, vec2 seed) {
        vec2 n = floor(x);
        vec2 f = fract(x);
        vec2 mg = vec2(0.0);
        vec2 mr = vec2(0.0);
        vec2 mc = vec2(0.0);
        float md = 8.0;
        for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = randomness * rand2(seed + mod(n + g + size, size));
            vec2 c = g + o;
            vec2 r = c - f;
            vec2 rr = r * stretch;
            float d = dot(rr, rr);
            if (d < md) {
                mc = c;
                md = d;
                mr = r;
                mg = g;
            }
        }
        md = 8.0;
        for (int j = -2; j <= 2; j++)
        for (int i = -2; i <= 2; i++) {
            vec2 g = mg + vec2(float(i), float(j));
            vec2 o = randomness * rand2(seed + mod(n + g + size, size));
            vec2 r = g + o - f;
            vec2 rr = (mr - r) * stretch;
            if (dot(rr, rr) > 0.00001)
                md = min(md, dot(0.5 * (mr + r) * stretch, normalize((r - mr) * stretch)));
        }
        return vec3(md, mc + n);
    }

    vec4 voronoi(vec2 uv, vec2 size, vec2 stretch, float intensity, float randomness, float seed) {
        uv *= size;
        vec3 v = iq_voronoi(uv, size, stretch, randomness, rand2(vec2(seed, 1.0 - seed)));
        return vec4(v.yz, intensity * length((uv - v.yz) * stretch), v.x);
    }

    vec4 adjust_levels(vec4 color, vec4 in_min, vec4 in_mid, vec4 in_max, vec4 out_min, vec4 out_max) {
        color = clamp((color - in_min) / (in_max - in_min), 0.0, 1.0);
        in_mid = (in_mid - in_min) / (in_max - in_min);
        vec4 dark = step(in_mid, color);
        color = 0.5 * mix(color / in_mid, 1.0 + (color - in_mid) / (1.0 - in_mid), dark);
        return out_min + color * (out_max - out_min);
    }

    float pingpong(float a, float b) {
        return (b != 0.0) ? abs(fract((a - b) / (b * 2.0)) * b * 2.0 - b) : 0.0;
    }

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 uv = fract(texcoord);
        float elapsed = time;

        float warp_angle1 = 45.0 * 0.01745329251;
        float warp_strength1 = 0.09;
        float warp_angle2 = -62.0 * 0.01745329251;
        float warp_strength2 = 0.15;

        vec2 scale = vec2(7.0);
        float fbm1 = fbm_perlin(uv, scale, 1, 1.0, elapsed * 0.5, 0.0);

        vec2 warpDir1 = vec2(cos(warp_angle1), sin(warp_angle1));
        vec2 warpedUv1 = uv + warpDir1 * (fbm1 - 0.5) * warp_strength1;

        vec4 vor1 = voronoi(warpedUv1, vec2(4.0), vec2(1.0), 1.0, 1.0, 0.454834551);
        float vorDist1 = vor1.w;
        float vorScaled1 = vorDist1 * 3.88;

        float fbm2 = fbm_perlin(warpedUv1, scale, 1, 1.0, elapsed * 0.5, 0.0);
        vec4 toned = adjust_levels(
            vec4(vec3(fbm2), 1.0),
            vec4(0.0), vec4(0.5), vec4(1.0),
            vec4(0.069853649, 0.069853649, 0.069853649, 0.0),
            vec4(0.269021004, 0.269021004, 0.269021004, 1.0)
        );
        float mask1 = 1.0 - step(dot(toned.rgb, vec3(1.0)) / 3.0, vorScaled1);

        float fbm3 = fbm_perlin(uv + warpDir1 * (fbm1 - 0.5) * warp_strength1, scale, 1, 1.0, elapsed * 0.5, 0.0);
        vec4 toned2 = adjust_levels(
            vec4(vec3(fbm3), 1.0),
            vec4(0.0), vec4(0.5), vec4(1.0),
            vec4(0.069853649, 0.069853649, 0.069853649, 0.0),
            vec4(0.269021004, 0.269021004, 0.269021004, 1.0)
        );
        float vorDist2 = vor1.w;
        float vorScaled2 = vorDist2 * 3.88;
        float mask2 = 1.0 - step(dot(toned2.rgb, vec3(1.0)) / 3.0, vorScaled2);

        vec2 warpDir2 = vec2(cos(warp_angle2), sin(warp_angle2));
        float fbm4 = fbm_perlin(
            uv + warpDir2 * (mask2 - 0.5) * warp_strength2 + warpDir1 * (fbm3 - 0.5) * warp_strength1,
            scale, 1, 1.0, elapsed * 0.5, 0.0
        );
        vec2 warpedUv2 = uv + warpDir2 * (mask2 - 0.5) * warp_strength2 + warpDir1 * (fbm4 - 0.5) * warp_strength1;
        vec4 vor2 = voronoi(warpedUv2, vec2(4.0), vec2(1.0), 1.0, 1.0, 0.454834551);
        float vorDist3 = vor2.w * 3.88;

        float fbm5 = fbm_perlin(warpedUv2, scale, 1, 1.0, elapsed * 0.5, 0.0);
        vec4 toned3 = adjust_levels(
            vec4(vec3(fbm5), 1.0),
            vec4(0.0), vec4(0.5), vec4(1.0),
            vec4(0.069853649, 0.069853649, 0.069853649, 0.0),
            vec4(0.269021004, 0.269021004, 0.269021004, 1.0)
        );
        float mask3 = 1.0 - step(dot(toned3.rgb, vec3(1.0)) / 3.0, vorDist3);

        vec3 deepColor = vec3(0.248168945, 0.626656353, 0.835937500);
        vec3 midColor = vec3(0.391082764, 0.758568466, 0.910156250);
        vec3 lightColor = vec3(0.882476807, 0.949218750, 0.941209733);

        vec3 waterCol = midColor;
        waterCol = mix(waterCol, deepColor, clamp(mask3 * 0.57, 0.0, 1.0));
        waterCol = mix(waterCol, lightColor, clamp(mask1 * 1.0, 0.0, 1.0));

        waterCol = pow(waterCol, vec3(1.0 / 2.2));
        waterCol *= brightness;

        return vec4(waterCol, 1.0);
    }
]]

water_shader.shader = love.graphics.newShader(shaderCode)

function water_shader.drawWaterHex(x, y, radius, mesh, time, bright)
    water_shader.shader:send("time", time)
    water_shader.shader:send("brightness", bright or 1.0)
    love.graphics.setShader(water_shader.shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh, x, y)
    love.graphics.setShader()
end

return water_shader
