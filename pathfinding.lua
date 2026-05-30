-- pathfinding.lua
-- Алгоритм поиска пути на гексагональной сетке (BFS)

local pathfinding = {}

--- Поиск пути методом BFS с ограничением максимальной длины
-- @param startQ number    Начальная координата q
-- @param startR number    Начальная координата r
-- @param targetQ number   Целевая координата q
-- @param targetR number   Целевая координата r
-- @param maxSteps number|nil  Максимальная длина пути (если nil – без ограничения)
-- @param isBlocked function(q, r)  Возвращает true, если клетка непроходима
-- @param hex object       Объект гексагональной сетки (должен иметь методы getNeighbors, isValidHex, опционально isActiveHex)
-- @return table|nil       Массив шагов { {q, r}, ... } или nil, если путь не найден
function pathfinding.findPath(startQ, startR, targetQ, targetR, maxSteps, isBlocked, hex)
    if startQ == targetQ and startR == targetR then
        return {}
    end

    local queue = {{q = startQ, r = startR, path = {}}}
    local visited = { [startQ .. "," .. startR] = true }

    while #queue > 0 do
        local current = table.remove(queue, 1)
        local currentPathLen = #current.path

        -- Если превысили лимит шагов, не расширяем дальше
        if maxSteps and currentPathLen >= maxSteps then
            goto continue
        end

        local neighbors = hex:getNeighbors(current.q, current.r)
        for _, nb in ipairs(neighbors) do
            local key = nb.q .. "," .. nb.r
            if not visited[key] then
                -- Проверка валидности и активности клетки
                local valid = hex:isValidHex(nb.q, nb.r)
                if valid and hex.isActiveHex then
                    valid = hex:isActiveHex(nb.q, nb.r)
                end
                if valid and not isBlocked(nb.q, nb.r) then
                    visited[key] = true
                    local newPath = {}
                    for _, step in ipairs(current.path) do
                        table.insert(newPath, step)
                    end
                    table.insert(newPath, {q = nb.q, r = nb.r})
                    if nb.q == targetQ and nb.r == targetR then
                        return newPath
                    end
                    table.insert(queue, {q = nb.q, r = nb.r, path = newPath})
                end
            end
        end
        ::continue::
    end
    return nil
end

return pathfinding