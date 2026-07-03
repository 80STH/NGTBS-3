-- pbr_shader.lua
-- PBR shader for terrain textures (stone, grass, sand)
local pbr_shader = {}

local shaderCode = [[
    extern Image albedo;
    extern Image normalMap;
    extern Image ormMap;
    extern vec2 lightPos;
    extern number lightRadius;
    extern number lightIntensity;
    extern number brightness;

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec2 uv = texcoord;
        vec4 albedoCol = Texel(albedo, uv);
        vec3 normalRaw = Texel(normalMap, uv).rgb * 2.0 - 1.0;
        normalRaw.z = sqrt(max(1.0 - dot(normalRaw.xy, normalRaw.xy), 0.0));
        vec3 N = normalize(normalRaw);

        vec3 orm = Texel(ormMap, uv).rgb;
        float ao = orm.r;
        float roughness = orm.g;

        vec2 delta = lightPos - screenCoord;
        float dist = length(delta);
        float atten = 1.0 - smoothstep(0.0, lightRadius, dist);
        atten = max(atten, 0.0) * lightIntensity;

        vec3 L = normalize(vec3(delta, 0.5));
        vec3 V = vec3(0.0, 0.0, 1.0);
        vec3 H = normalize(L + V);

        float diff = max(dot(N, L), 0.0) * ao;
        float spec = pow(max(dot(N, H), 0.0), 16.0 / max(roughness * 4.0, 0.01)) * 0.3;

        vec3 ambient = albedoCol.rgb * 0.12;
        vec3 diffuse = albedoCol.rgb * diff * atten;
        vec3 specular = vec3(1.0) * spec * atten;

        vec3 finalColor = (ambient + diffuse + specular) * brightness;
        finalColor = finalColor / (finalColor + vec3(1.0));
        return vec4(finalColor, albedoCol.a);
    }
]]

pbr_shader.shader = love.graphics.newShader(shaderCode)

local materials = {}

local function loadMaterial(prefix)
    return {
        albedo = love.graphics.newImage("assets/textures/" .. prefix .. "_albedo.png"),
        normal = love.graphics.newImage("assets/textures/" .. prefix .. "_normal.png"),
        orm    = love.graphics.newImage("assets/textures/" .. prefix .. "_orm.png"),
        height = love.graphics.newImage("assets/textures/" .. prefix .. "_heightmap.png"),
    }
end

function pbr_shader.getMaterial(name)
    if not materials[name] then
        materials[name] = loadMaterial(name)
        for _, tex in pairs(materials[name]) do
            tex:setFilter("linear", "linear")
        end
    end
    return materials[name]
end

function pbr_shader.drawPBRHex(mesh, x, y, materialName, lightX, lightY, bright)
    local mat = pbr_shader.getMaterial(materialName)
    pbr_shader.shader:send("albedo", mat.albedo)
    pbr_shader.shader:send("normalMap", mat.normal)
    pbr_shader.shader:send("ormMap", mat.orm)
    pbr_shader.shader:send("lightPos", {lightX, lightY})
    pbr_shader.shader:send("lightRadius", 300.0)
    pbr_shader.shader:send("lightIntensity", 1.2)
    pbr_shader.shader:send("brightness", bright or 1.0)
    
    love.graphics.setShader(pbr_shader.shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh, x, y)
    love.graphics.setShader()
end

return pbr_shader
