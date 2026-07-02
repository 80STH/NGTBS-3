local lighting = {}

lighting.enabled = false
lighting.ambientLight = 0.12

lighting.cursor = {
    radius = 180,
    color = {1.0, 0.95, 0.85},
    softness = 0.4,
}

lighting.fire = {
    radius = 130,
    color = {1.0, 0.55, 0.15},
    softness = 0.5,
}

lighting.maxLights = 16

local shaderCode = [[
    extern number ambientLight;

    extern vec2 cursorPos;
    extern number cursorRadius;
    extern vec3 cursorColor;
    extern number cursorSoftness;

    extern number fireCount;
    extern vec2 firePositions[16];
    extern number fireRadii[16];
    extern vec3 fireColor;
    extern number fireSoftness;

    extern number time;

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec4 scene = Texel(tex, texcoord);

        float totalLight = ambientLight;
        vec3 totalColor = vec3(ambientLight);

        float cDist = length(screenCoord - cursorPos);
        float cAtten = 1.0 - smoothstep(0.0, cursorRadius, cDist);
        cAtten = pow(max(cAtten, 0.0), 1.0 + cursorSoftness * 2.0);
        totalLight += cAtten;
        totalColor += cursorColor * cAtten;

        for (int i = 0; i < 16; i++) {
            if (float(i) >= fireCount) break;
            float fDist = length(screenCoord - firePositions[i]);
            float flicker = 0.85 + 0.15 * sin(time * 10.0 + float(i) * 2.7);
            float fRadius = fireRadii[i] * flicker;
            float fAtten = 1.0 - smoothstep(0.0, fRadius, fDist);
            fAtten = pow(max(fAtten, 0.0), 1.0 + fireSoftness * 2.0);
            totalLight += fAtten;
            totalColor += fireColor * fAtten;
        }

        totalLight = min(totalLight, 1.0);
        vec3 lightCol = totalColor / max(totalLight, 0.001);

        vec3 finalColor = scene.rgb * lightCol;
        return vec4(finalColor, scene.a);
    }
]]

function lighting:init()
    self.shader = love.graphics.newShader(shaderCode)
    self:resize()
end

function lighting:resize()
    local w = love.graphics.getWidth()
    local h = love.graphics.getHeight()
    self.canvas = love.graphics.newCanvas(w, h)
    self.width = w
    self.height = h
end

function lighting:beginRender()
    if not self.canvas or self.canvas:getWidth() ~= love.graphics.getWidth() then
        self:resize()
    end
    love.graphics.setCanvas({self.canvas, stencil = true})
    love.graphics.clear(0, 0, 0, 1)
end

function lighting:endRender(state)
    love.graphics.setCanvas()

    if not self.enabled then
        love.graphics.draw(self.canvas)
        return
    end

    local mx, my = love.mouse.getPosition()
    local dpiScale = love.window.getDPIScale()

    local status_mod = require("system.status")

    local firePositions = {}
    local fireRadii = {}
    local fireCount = 0

    if state and state.entities and state.hex then
        for _, entity in ipairs(state.entities) do
            if entity.health > 0 and status_mod.hasEntityStatus(entity, "fire") then
                local x, y = state.hex:hexToPixel(entity.q, entity.r)
                fireCount = fireCount + 1
                if fireCount <= self.maxLights then
                    firePositions[fireCount] = {x * dpiScale, y * dpiScale}
                    fireRadii[fireCount] = self.fire.radius * dpiScale
                end
            end
        end
    end

    if state and state.hex then
        for key, statuses in pairs(status_mod.hexStatuses) do
            for _, st in ipairs(statuses) do
                if st == "fire" then
                    local q, r = key:match("(-?%d+),(-?%d+)")
                    q = tonumber(q)
                    r = tonumber(r)
                    if q and r then
                        local x, y = state.hex:hexToPixel(q, r)
                        fireCount = fireCount + 1
                        if fireCount <= self.maxLights then
                            firePositions[fireCount] = {x * dpiScale, y * dpiScale}
                            fireRadii[fireCount] = self.fire.radius * dpiScale
                        end
                    end
                end
            end
        end
    end

    self.shader:send("ambientLight", self.ambientLight)

    self.shader:send("cursorPos", {mx, my})
    self.shader:send("cursorRadius", self.cursor.radius * dpiScale)
    self.shader:send("cursorColor", self.cursor.color)
    self.shader:send("cursorSoftness", self.cursor.softness)

    self.shader:send("fireCount", fireCount)

    local firePosArray = {}
    local fireRadArray = {}
    for i = 1, self.maxLights do
        if i <= fireCount then
            firePosArray[i] = firePositions[i]
            fireRadArray[i] = fireRadii[i]
        else
            firePosArray[i] = {0, 0}
            fireRadArray[i] = 0
        end
    end
    self.shader:send("firePositions", unpack(firePosArray))
    self.shader:send("fireRadii", unpack(fireRadArray))
    self.shader:send("fireColor", self.fire.color)
    self.shader:send("fireSoftness", self.fire.softness)

    self.shader:send("time", love.timer.getTime())

    love.graphics.setShader(self.shader)
    love.graphics.draw(self.canvas)
    love.graphics.setShader()
end

return lighting
