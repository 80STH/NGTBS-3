-- src/core/registry.lua
-- Generic registry: name -> definition. Content modules register here.
-- Makes adding new attacks/abilities/units/statuses trivial: just registry.register("name", def).

local Registry = {}
Registry.__index = Registry

function Registry.new()
    return setmetatable({ items = {}, order = {} }, Registry)
end

function Registry:register(name, def)
    assert(name, "registry: register needs a name")
    assert(def, "registry: register needs a def for '" .. tostring(name) .. "'")
    if self.items[name] == nil then
        table.insert(self.order, name)
    end
    self.items[name] = def
    return def
end

function Registry:get(name) return self.items[name] end
function Registry:has(name) return self.items[name] ~= nil end
function Registry:list() return self.order end
function Registry:all()
    local out = {}
    for _, name in ipairs(self.order) do table.insert(out, self.items[name]) end
    return out
end

return Registry
