-- combat/push_animator.lua
-- Purely visual push/knockback animation queue.
-- Does NOT change game state: only interpolates entity.currentDrawX/Y.

local push_animator = {
    queue = {},
    active = false,
    globalCallback = nil,
    onQueueEmpty = nil,
}

local function getDrawCoords(q, r)
    return _G.getDrawCoords(q, r)
end

local function easeMove(t)
    return t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
end

local function easeBounce(t)
    -- Incomplete push: lunge forward to the obstacle/edge, then snap back instantly.
    local peak = 0.5
    if t <= 0.5 then
        return t / 0.5 * peak
    else
        return 0
    end
end

-- Internal: start all not-yet-moving anims at once.
function push_animator._initNext()
    for _, anim in ipairs(push_animator.queue) do
        if not anim.isMoving then
            if anim.type ~= "shake" then
                if anim.fromX then
                    anim.startX, anim.startY = anim.fromX, anim.fromY
                    anim.endX, anim.endY = anim.toX, anim.toY
                else
                    anim.startX, anim.startY = getDrawCoords(anim.fromQ, anim.fromR)
                    anim.endX, anim.endY = getDrawCoords(anim.toQ, anim.toR)
                end
            end
            anim.timer = 0
            anim.isMoving = true
        end
    end
end

function push_animator.addMove(obj, fromQ, fromR, toQ, toR, onComplete)
    table.insert(push_animator.queue, {
        obj = obj,
        type = "move",
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        duration = 0.2,
        timer = 0,
        isMoving = false,
        onComplete = onComplete,
    })
end

-- Pixel-space move: caller supplies exact start/end screen coordinates.
-- Useful for partial lunges where the logical cell differs from the visual endpoint.
function push_animator.addCustomMove(obj, fromX, fromY, toX, toY, duration, onComplete)
    table.insert(push_animator.queue, {
        obj = obj,
        type = "move",
        fromX = fromX, fromY = fromY,
        toX = toX, toY = toY,
        duration = duration or 0.2,
        timer = 0,
        isMoving = false,
        onComplete = onComplete,
    })
end

function push_animator.addBounce(obj, fromQ, fromR, toQ, toR, onComplete)
    table.insert(push_animator.queue, {
        obj = obj,
        type = "bounce",
        fromQ = fromQ, fromR = fromR,
        toQ = toQ, toR = toR,
        duration = 0.25,
        timer = 0,
        isMoving = false,
        onComplete = onComplete,
    })
end

function push_animator.addShake(obj, offsetX, offsetY, duration)
    table.insert(push_animator.queue, {
        obj = obj,
        type = "shake",
        offsetX = offsetX or 0,
        offsetY = offsetY or 0,
        duration = duration or 0.2,
        timer = 0,
        isMoving = false,
    })
end

function push_animator.start(callback)
    if #push_animator.queue == 0 then
        if callback then callback() end
        return
    end
    push_animator.active = true
    push_animator.globalCallback = callback
    push_animator._initNext()
end

function push_animator.update(dt)
    if not push_animator.active or #push_animator.queue == 0 then return end

    local allDone = true
    local queue = push_animator.queue
    local i = 1
    while i <= #queue do
        local anim = queue[i]
        if anim and anim.isMoving then
            anim.timer = anim.timer + dt
            local t = math.min(1, anim.timer / anim.duration)
            local ease = (anim.type == "bounce") and easeBounce(t) or easeMove(t)

            if anim.type == "shake" then
                local x, y = getDrawCoords(anim.obj.q, anim.obj.r)
                anim.obj.currentDrawX = x + anim.offsetX * (1 - ease)
                anim.obj.currentDrawY = y + anim.offsetY * (1 - ease)
            else
                anim.obj.currentDrawX = anim.startX + (anim.endX - anim.startX) * ease
                anim.obj.currentDrawY = anim.startY + (anim.endY - anim.startY) * ease
            end

            if t >= 1 then
                anim.obj.currentDrawX = nil
                anim.obj.currentDrawY = nil
                if anim.onComplete then anim.onComplete(anim.obj) end
                queue[i] = queue[#queue]
                queue[#queue] = nil
            else
                allDone = false
                i = i + 1
            end
        end
    end

    if #push_animator.queue == 0 and allDone then
        push_animator.active = false
        if push_animator.globalCallback then
            push_animator.globalCallback()
            push_animator.globalCallback = nil
        end
        if push_animator.onQueueEmpty then
            push_animator.onQueueEmpty()
        end
    end
end

-- Instantly complete all queued animations. Fires callbacks in case follow-up
-- animations are queued, then fires the global callback.
function push_animator.flush()
    for i = 1, 2 do
        for _, anim in ipairs(push_animator.queue) do
            if anim.obj then
                anim.obj.currentDrawX = nil
                anim.obj.currentDrawY = nil
            end
        end
        local callbacks = {}
        for _, anim in ipairs(push_animator.queue) do
            if anim.onComplete then
                table.insert(callbacks, { fn = anim.onComplete, obj = anim.obj })
            end
        end
        local globalCb = push_animator.globalCallback
        push_animator.queue = {}
        push_animator.active = false
        push_animator.globalCallback = nil
        for _, cb in ipairs(callbacks) do cb.fn(cb.obj) end
        if #push_animator.queue == 0 then
            if globalCb then globalCb() end
            if #push_animator.queue == 0 then break end
        end
    end
    push_animator.queue = {}
    push_animator.active = false
    push_animator.globalCallback = nil
end

function push_animator.clear()
    for _, anim in ipairs(push_animator.queue) do
        if anim.obj then
            anim.obj.currentDrawX = nil
            anim.obj.currentDrawY = nil
        end
    end
    push_animator.queue = {}
    push_animator.active = false
    push_animator.globalCallback = nil
end

function push_animator.isActive()
    return push_animator.active and #push_animator.queue > 0
end

return push_animator
