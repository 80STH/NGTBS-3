-- src/render/camera.lua
-- Keeps a fixed design resolution (720x1280 portrait) and scales uniformly to
-- the real window, centering with letterboxing. Avoids the old DPI double-scale bug:
-- we use the framebuffer pixel dimensions directly and apply ONE scale factor.

local camera = {}

camera.designW = 720
camera.designH = 1280

function camera.new()
    return setmetatable({ scale = 1, offX = 0, offY = 0, w = 720, h = 1280 }, { __index = camera })
end

function camera:resize(pixelW, pixelH)
    self.w = pixelW
    self.h = pixelH
    self.scale = math.min(pixelW / camera.designW, pixelH / camera.designH)
    local usedW = camera.designW * self.scale
    local usedH = camera.designH * self.scale
    self.offX = (pixelW - usedW) / 2
    self.offY = (pixelH - usedH) / 2
end

-- Apply the transform: call in love.draw before rendering the design-space scene.
function camera:apply()
    love.graphics.push()
    love.graphics.translate(self.offX, self.offY)
    love.graphics.scale(self.scale, self.scale)
    -- clip to design area so letterbox bars stay clean
    love.graphics.setScissor(self.offX, self.offY, camera.designW * self.scale, camera.designH * self.scale)
end

function camera:release()
    love.graphics.setScissor()
    love.graphics.pop()
end

-- Convert a screen pixel position (mouse/touch) to design-space coordinates.
function camera:toDesign(sx, sy)
    return (sx - self.offX) / self.scale, (sy - self.offY) / self.scale
end

return camera
