local hex_demo = {}

local mats = {}
local display_mode = "mixed"
local modes = {"mixed", "flat"}
local modeIndex = 1

local pbrShader
local hexMesh

local hexGrid
local gridW, gridH = 7, 7
local hexR = 56
local materialMap = {}

local brightness = 1.0
local slider = {}
local sliderDragging = false

local water_shader = require("ui.water_shader")

local function initShaders()
    if pbrShader then return end
    pbrShader = love.graphics.newShader([[
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
    ]])
end

local function buildHexMesh()
    local r = hexR
    local cx, cy = 0, 0
    local sqrt3 = math.sqrt(3)
    local hw = r * 1.5
    local hh = r * sqrt3 * 0.5
    local left, right = -hw, hw
    local top, bottom = -hh, hh

    local function addVert(angle)
        local vx = math.cos(angle) * r
        local vy = math.sin(angle) * r
        return { vx, vy, (vx - left) / (right - left), (vy - top) / (bottom - top), 1, 1, 1, 1 }
    end

    local center = { cx, cy, 0.5, 0.5, 1, 1, 1, 1 }
    local corners = {}
    for i = 0, 5 do
        corners[i+1] = addVert(math.rad(60 * i))
    end

    local meshVerts = {}
    for i = 1, 6 do
        local ni = i % 6 + 1
        meshVerts[#meshVerts + 1] = center
        meshVerts[#meshVerts + 1] = corners[i]
        meshVerts[#meshVerts + 1] = corners[ni]
    end
    hexMesh = love.graphics.newMesh(meshVerts, "triangles")
end

local function loadTextures(prefix)
    return {
        albedo = love.graphics.newImage("assets/textures/" .. prefix .. "_albedo.png"),
        normal = love.graphics.newImage("assets/textures/" .. prefix .. "_normal.png"),
        orm    = love.graphics.newImage("assets/textures/" .. prefix .. "_orm.png"),
        height = love.graphics.newImage("assets/textures/" .. prefix .. "_heightmap.png"),
    }
end

local function ensureLoaded()
    if mats.stone then return end
    mats.stone = loadTextures("stone")
    mats.grass = loadTextures("grass")
    for _, set in pairs(mats) do
        for _, tex in pairs(set) do
            tex:setFilter("linear", "linear")
        end
    end
    initShaders()
    buildHexMesh()

    materialMap = {}
    for q = 0, gridW - 1 do
        materialMap[q] = {}
        for r = 0, gridH - 1 do
            local rnd = love.math.random()
            if rnd < 0.33 then
                materialMap[q][r] = "stone"
            elseif rnd < 0.66 then
                materialMap[q][r] = "grass"
            else
                materialMap[q][r] = "water"
            end
        end
    end

    local HexGrid = require("grid.hexgrid")
    hexGrid = HexGrid.new(hexR, gridW, gridH, nil, nil, nil, "flat")
    hexGrid.offsetX = 0
    hexGrid.offsetY = 0
    hexGrid:centerOnScreen(logicalW or 800, logicalH or 1280)
end

local function sendPBR(shader, mat, mx, my)
    shader:send("albedo", mat.albedo)
    shader:send("normalMap", mat.normal)
    shader:send("ormMap", mat.orm)
    shader:send("lightPos", {mx, my})
    shader:send("lightRadius", 300.0 * (dpiScale or 1))
    shader:send("lightIntensity", 1.2)
    shader:send("brightness", brightness)
end

local function drawSlider(w, h, lmx, lmy)
    local fonts = require("util.fonts")
    local sx = w / 2 - 120
    local sy = h - 105
    local sw = 240
    local sh = 14
    local thumbR = 8

    local t = (brightness - 0.1) / 1.9
    local thumbX = sx + t * sw
    local thumbY = sy + sh / 2

    love.graphics.setFont(fonts.get(11))
    love.graphics.setColor(0.6, 0.6, 0.8, 0.7)
    love.graphics.printf("Brightness", sx, sy - 16, sw, "center")

    love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
    love.graphics.rectangle("fill", sx, sy, sw, sh, 5)
    love.graphics.setColor(0.4, 0.4, 0.5, 0.5)
    love.graphics.rectangle("line", sx, sy, sw, sh, 5)

    local fillW = t * sw
    if fillW > 0 then
        love.graphics.setColor(0.5, 0.7, 0.4, 0.6)
        love.graphics.rectangle("fill", sx, sy, fillW, sh, 5)
    end

    local thumbHover = lmx >= thumbX - thumbR and lmx <= thumbX + thumbR and lmy >= thumbY - thumbR and lmy <= thumbY + thumbR + 4
    love.graphics.setColor(thumbHover and 0.9 or 0.7, thumbHover and 0.9 or 0.7, thumbHover and 1 or 0.8, 1)
    love.graphics.circle("fill", thumbX, thumbY, thumbR)

    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setFont(fonts.get(10))
    love.graphics.printf(math.floor(brightness * 100) .. "%", sx + sw + 8, sy - 1, 40, "left")

    slider = { x = sx, y = sy, w = sw, h = sh, thumbR = thumbR, value = brightness }
end

local function hitSlider(lmx, lmy)
    local s = slider
    if not s then return false end
    local dx = lmx - (s.x + (brightness - 0.1) / 1.9 * s.w)
    local dy = lmy - (s.y + s.h / 2)
    return dx * dx + dy * dy < (s.thumbR + 6) * (s.thumbR + 6)
end

local function updateSliderFromMouse(lmx)
    local s = slider
    if not s or s.w <= 0 then return end
    local t = (lmx - s.x) / s.w
    t = math.max(0, math.min(1, t))
    brightness = 0.1 + t * 1.9
end

function hex_demo.init()
    ensureLoaded()
end

function hex_demo.draw()
    hex_demo.init()
    local w, h = logicalW, logicalH
    local fonts = require("util.fonts")

    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(fonts.get(24))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("STONE + GRASS + WATER", 0, 15, w, "center")

    love.graphics.setFont(fonts.get(11))
    love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
    love.graphics.printf("ESC: back  |  M: toggle grid/flat  |  Mouse: move light", 0, 42, w, "center")

    local mx, my = love.mouse.getPosition()
    local isFlat = displayMode == "flat"

    love.graphics.push()
    love.graphics.scale(dpiScale)

    if isFlat then
        local imgW, imgH = mats.stone.albedo:getDimensions()
        local maxW = w * 0.65
        local maxH = h * 0.55
        local scale = math.min(maxW / imgW, maxH / imgH)
        local ix = w / 2 - imgW * scale / 2
        local iy = 70

        love.graphics.setShader(pbrShader)
        sendPBR(pbrShader, mats.stone, mx, my)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(mats.stone.albedo, ix, iy, 0, scale, scale)
        love.graphics.setShader()

        love.graphics.setFont(fonts.get(12))
        love.graphics.setColor(0.6, 0.8, 0.4, 0.8)
        love.graphics.printf("Stone PBR (flat)", 0, iy + imgH * scale + 15, w, "center")
        love.graphics.setFont(fonts.get(11))
        love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
        love.graphics.printf("stone_albedo.png  |  " .. imgW .. "x" .. imgH, 0, iy + imgH * scale + 33, w, "center")
    else
        if hexGrid then
            local currentTime = love.timer.getTime()
            for q = 0, gridW - 1 do
                for r = 0, gridH - 1 do
                    local matName = materialMap[q] and materialMap[q][r] or "stone"
                    local x, y = hexGrid:hexToPixel(q, r)
                    
                    if matName == "water" then
                        water_shader.drawWaterHex(x, y, hexR, hexMesh, currentTime, brightness)
                    else
                        love.graphics.setShader(pbrShader)
                        sendPBR(pbrShader, mats[matName], mx, my)
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.draw(hexMesh, x, y)
                    end
                end
            end
            love.graphics.setShader()

            love.graphics.setFont(fonts.get(12))
            love.graphics.setColor(0.6, 0.8, 0.4, 0.8)
            love.graphics.printf("Stone + Grass + Water — mixed", 0, h - 130, w, "center")
            love.graphics.setFont(fonts.get(11))
            love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
            love.graphics.printf("Grid: " .. gridW .. "x" .. gridH, 0, h - 112, w, "center")
        end
    end

    love.graphics.pop()

    local lmx, lmy = mx / (dpiScale or 1), my / (dpiScale or 1)

    if sliderDragging then
        updateSliderFromMouse(lmx)
    end

    drawSlider(w, h, lmx, lmy)

    local btnW, btnH = 120, 40
    local btnX = w / 2 - btnW / 2
    local btnY = h - 40

    local hover = lmx >= btnX and lmx <= btnX + btnW and lmy >= btnY and lmy <= btnY + btnH
    love.graphics.setColor(hover and 0.3 or 0.2, hover and 0.3 or 0.2, hover and 0.4 or 0.3, 0.9)
    love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 5)
    love.graphics.setColor(0.5, 0.5, 0.7, hover and 0.8 or 0.5)
    love.graphics.rectangle("line", btnX, btnY, btnW, btnH, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(fonts.get(14))
    love.graphics.printf("Back", btnX, btnY + 10, btnW, "center")

    hex_demo.backBtn = { x = btnX, y = btnY, w = btnW, h = btnH }
end

function hex_demo.mousepressed(x, y)
    if hex_demo.backBtn then
        local btn = hex_demo.backBtn
        if x >= btn.x and x <= btn.x + btn.w and y >= btn.y and y <= btn.y + btn.h then
            gamePhase = "menu"
            return true
        end
    end
    if hitSlider(x, y) then
        sliderDragging = true
        return true
    end
    return false
end

function hex_demo.mousereleased(x, y)
    sliderDragging = false
end

function hex_demo.keypressed(key)
    if key == "escape" then
        gamePhase = "menu"
        return true
    elseif key == "m" then
        modeIndex = modeIndex % #modes + 1
        displayMode = modes[modeIndex]
        return true
    end
    return false
end

return hex_demo
