-- log.lua
-- Centralized logging. Replaces scattered print() with levels.
-- Usage:
--   local log = require("util.log")
--   log.debug("state", "turn", turnCount)       -- debug noise (off by default)
--   log.info("phase changed:", phase)
--   log.warn("no dig sites")
--   log.error("getAtHex called with nil q", q)
--
-- Enable output:  log.enabled = true   (or _G.LOG_ENABLED = true in main.lua)
-- Level:         log.level = "info"   ("debug"|"info"|"warn"|"error")
-- Categories:       log.categories.ai = true  — enable only the "ai" category
--
-- Additionally: if log.file (path) is set, write there (append).
-- _G.LOG_FILE = "log_run.txt" in main.lua enables file writing.

local log = {}

log.enabled = false            -- global on/off (overridden in main.lua)
log.level = "debug"            -- minimum level
log.categories = {}            -- empty = all allowed; otherwise whitelist
log.file = nil                 -- path to file for duplication (or nil)

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

local function levelOk(lvl)
    return (LEVELS[lvl] or 0) >= (LEVELS[log.level] or 0)
end

local function categoryOk(cat)
    if cat == nil then return true end
    if next(log.categories) == nil then return true end   -- whitelist empty -> all
    return log.categories[cat] == true
end

local function writeOut(line)
    io.write(line, "\n")
    if log.file then
        local f = io.open(log.file, "a")
        if f then f:write(line, "\n"); f:close() end
    end
end

local function emit(tag, cat, ...)
    if not log.enabled then return end
    if not levelOk(tag) then return end
    if not categoryOk(cat) then return end
    local prefix = "[" .. tag:upper() .. "]"
    if cat then prefix = prefix .. " (" .. cat .. ")" end
    local n = select("#", ...)
    if n == 0 then
        writeOut(prefix)
        return
    end
    local parts = { prefix }
    for i = 1, n do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    writeOut(table.concat(parts, " "))
end

function log.debug(cat, ...) emit("debug", cat, ...) end
function log.info (cat, ...) emit("info",  cat, ...) end
function log.warn (cat, ...) emit("warn",  cat, ...) end
function log.error(cat, ...) emit("error", cat, ...) end

-- printf-style: log.debugf("ai", "%s moves to %d,%d", name, q, r)
local function formatEmit(tag, cat, fmt, ...)
    if not log.enabled then return end
    if not levelOk(tag) then return end
    if not categoryOk(cat) then return end
    local msg = string.format(fmt, ...)
    local prefix = "[" .. tag:upper() .. "]"
    if cat then prefix = prefix .. " (" .. cat .. ")" end
    writeOut(prefix .. " " .. msg)
end

function log.debugf(cat, fmt, ...) formatEmit("debug", cat, fmt, ...) end
function log.infof (cat, fmt, ...) formatEmit("info",  cat, fmt, ...) end
function log.warnf (cat, fmt, ...) formatEmit("warn",  cat, fmt, ...) end
function log.errorf(cat, fmt, ...) formatEmit("error", cat, fmt, ...) end

return log
