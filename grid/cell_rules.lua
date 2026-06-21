-- cell_rules.lua
-- Единое место для проверок проходимости клеток.
-- Раньше было 5 разбросанных вариантов (isPositionOccupied, isCellPassable,
-- isCellOccupiedForStop в main.lua; isCellPassableForEnemy, ui.isCellReachable
-- в ui.lua) с тонкими различиями. Теперь — один параметризованный API.
--
-- Главные функции:
--   cell_rules.isPassable(q, r, mover, opts)        — можно ли ПРОЙТИ клетку
--   cell_rules.isOccupiedForStop(q, r, mover, opts) — занята ли клетка для ОСТАНОВКИ
--
-- opts (необязательные):
--   entities       — список сущностей (по умолчанию _G.entities)
--   terrainMap     — карта тайлов (по умолчанию _G.terrainMap)
--   hex            — объект гексагональной сетки (по умолчанию _G.hex)
--   passableSide   — "ally" | "enemy" | "none" — чья сторона считается проходимой
--                    ("ally" для союзников, "enemy" для врагов; по умолчанию —
--                    сторона mover)
--   allowPhaseThroughEnemies — учитывать ли mover.phaseThroughEnemies (по умолч. true)
--   ignoreWater    — не проверять воду/underwater_mines (для остановки)

local cell_rules = {}

local function defaultOpts(opts, mover)
    opts = opts or {}
    local function pick(key, globName)
        if opts[key] ~= nil then return opts[key] end
        return _G[globName]
    end
    return {
        entities   = pick("entities", "entities") or {},
        terrainMap = pick("terrainMap", "terrainMap"),
        hex        = pick("hex", "hex"),
        passableSide = opts.passableSide or (mover and mover.isPlayable and "ally" or "enemy"),
        allowPhaseThroughEnemies = (opts.allowPhaseThroughEnemies ~= false),
        ignoreWater = opts.ignoreWater or false,
    }
end

-- Та же сторона, что и mover?
local function sameSide(e, mover, side)
    if not (e:isCharacter() and mover) then return false end
    if side == "ally" then
        return e.isPlayable == true and mover.isPlayable == true
    elseif side == "enemy" then
        return e.isPlayable == false and mover.isPlayable == false
    end
    return false
end

-- Можно ли пройти через клетку (для движения/поиска пути).
function cell_rules.isPassable(q, r, mover, opts)
    local o = defaultOpts(opts, mover)
    local hex = o.hex
    if not hex or not hex:isActiveHex(q, r) then return false end

    if not o.ignoreWater then
        local terrain = o.terrainMap and o.terrainMap[q] and o.terrainMap[q][r] or "grass"
        if terrain == "water" then
            if mover and (mover.waterWalker or mover.flying or mover.hovering) then
                -- ok
            else
                return false
            end
        end
        if terrain == "underwater_mines" then
            return false
        end
    end

    -- Летающие игнорят всё на земле
    if mover and mover.flying then
        return true
    end

    for _, e in ipairs(o.entities) do
        if e ~= mover and e.q == q and e.r == r and not e.isHazard then
            if not sameSide(e, mover, o.passableSide) then
                -- phaseThroughEnemies: можно проходить сквозь врагов (но не союзников)
                if o.allowPhaseThroughEnemies and mover and mover.phaseThroughEnemies
                   and e:isCharacter() and not e.isPlayable then
                    -- skip
                else
                    return false
                end
            end
        end
    end
    return true
end

-- Занята ли клетка для остановки (без учёта phaseThroughEnemies и воды).
function cell_rules.isOccupiedForStop(q, r, mover, opts)
    local o = defaultOpts(opts, mover)
    local hex = o.hex
    if not hex or not hex:isActiveHex(q, r) then return true end
    for _, e in ipairs(o.entities) do
        if e ~= mover and e.q == q and e.r == r and not e.isHazard then
            return true
        end
    end
    return false
end

-- Универсальный "занята ли клетка" (с водой и phaseThroughEnemies).
-- Соответствует старой isPositionOccupied.
function cell_rules.isOccupied(q, r, mover, opts)
    local o = defaultOpts(opts, mover)
    local hex = o.hex
    if not hex or not hex:isActiveHex(q, r) then return true end

    if o.terrainMap and o.terrainMap[q] and o.terrainMap[q][r] == "water" then
        if mover and (mover.waterWalker or mover.flying or mover.hovering) then
            -- ok
        else
            return true
        end
    end

    for _, e in ipairs(o.entities) do
        if e ~= mover and e.q == q and e.r == r and not e.isHazard then
            if not sameSide(e, mover, o.passableSide) then
                if o.allowPhaseThroughEnemies and mover and mover.phaseThroughEnemies
                   and e:isCharacter() and not e.isPlayable then
                    -- skip
                else
                    return true
                end
            end
        end
    end
    return false
end

return cell_rules
