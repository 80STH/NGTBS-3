-- tests/run.lua
-- Простой тест-раннер на чистом Lua (без busted/luarocks).
-- Запуск:  lua tests/run.lua
--
-- Каждый тестовый файл возвращает таблицу вида:
--   { name = "hex_utils", tests = {
--       { name = "axialToCube roundtrip", fn = function() ... end },
--       ...
--   } }
-- Функция fn должна вернуть true[, сообщение] при успехе или false, сообщение при неудаче.
-- Если fn выбрасывает ошибку — тест считается проваленным.

local passed, failed = 0, 0
local failures = {}

-- Перехват ошибок
local function safeCall(fn)
    local ok, result = pcall(fn)
    if not ok then return false, "error: " .. tostring(result) end
    if result == true then return true, nil end
    if type(result) == "table" then
        return result.ok ~= false, result.msg or "(no message)"
    end
    return false, "test returned: " .. tostring(result)
end

local function runSuite(suite)
    io.write("[" .. suite.name .. "]\n")
    for _, t in ipairs(suite.tests) do
        local ok, msg = safeCall(t.fn)
        if ok then
            io.write(string.format("  ok    %s\n", t.name))
            passed = passed + 1
        else
            io.write(string.format("  FAIL  %s -- %s\n", t.name, msg or "?"))
            failed = failed + 1
            table.insert(failures, suite.name .. "/" .. t.name .. ": " .. (msg or "?"))
        end
    end
end

-- Загружаем все suites
local suite1 = require("tests.hex_utils_test")
local suite2 = require("tests.cell_rules_test")
local suite3 = require("tests.attack_preview_test")
local suites = { suite1, suite2, suite3 }

for _, s in ipairs(suites) do
    runSuite(s)
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if #failures > 0 then
    io.write("\nFailures:\n")
    for _, f in ipairs(failures) do io.write("  - " .. f .. "\n") end
    os.exit(1)
end
os.exit(0)
