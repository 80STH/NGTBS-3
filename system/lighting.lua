local lighting = {}

lighting.enabled = false
lighting.ambientLight = 0.12

lighting.sun = {
    pos = {0, 0},
    radius = 0,
    color = {1.0, 0.95, 0.85},
    softness = 0.5,
}

local shaderCode = [[
    extern number ambientLight;
    extern vec2 sunPos;
    extern number sunRadius;
    extern vec3 sunColor;
    extern number sunSoftness;

    vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screenCoord) {
        vec4 scene = Texel(tex, texcoord);

        float totalLight = ambientLight;
        vec3 totalColor = vec3(ambientLight);

        if (sunRadius > 0.0) {
            float sDist = length(screenCoord - sunPos);
            float sAtten = 1.0 - smoothstep(0.0, sunRadius, sDist);
            sAtten = pow(max(sAtten, 0.0), 1.0 + sunSoftness * 2.0);
            totalLight += sAtten;
            totalColor += sunColor * sAtten;
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

    local dpiScale = love.window.getDPIScale()

    self.shader:send("ambientLight", self.ambientLight)
    self.shader:send("sunPos", {self.sun.pos[1] * dpiScale, self.sun.pos[2] * dpiScale})
    self.shader:send("sunRadius", self.sun.radius * dpiScale)
    self.shader:send("sunColor", self.sun.color)
    self.shader:send("sunSoftness", self.sun.softness)

    love.graphics.setShader(self.shader)
    love.graphics.draw(self.canvas)
    love.graphics.setShader()
end

return lighting
