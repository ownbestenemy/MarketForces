-- MarketForces: module registry.
--
-- Each feature (scanning, price history, tooltips, posting, ...) is a
-- module in its own file under Modules\. A module looks like:
--
--   local _, MF = ...
--   local Scan = MF:NewModule("Scan", {
--       global = { pagesPerTick = 1 }, -- defaults merged into Scan.db.global
--       char   = {},                   -- defaults merged into Scan.db.char
--       ah     = { lastScan = 0 },     -- per auction house, Scan.db.ah
--   })
--   function Scan:OnInitialize() end   -- saved data ready (ADDON_LOADED)
--   function Scan:OnEnable()           -- player logged in, or /mf enable
--       self:RegisterEvent("AUCTION_HOUSE_SHOW")
--   end
--   function Scan:OnDisable() end      -- /mf disable; events and messages auto-removed
--   function Scan:AUCTION_HOUSE_SHOW() end
--
-- Modules are enabled by default; the choice is saved per account.
local _, MF = ...

local Util = MF.Util

local modules = {}     -- name -> module
local moduleOrder = {} -- registration order, so lifecycle runs predictably

local Module = {}
Module.__index = Module

function Module:RegisterEvent(event, handler)
    MF:RegisterEvent(event, self, handler)
end

function Module:UnregisterEvent(event)
    MF:UnregisterEvent(event, self)
end

function Module:RegisterMessage(message, handler)
    MF:RegisterMessage(message, self, handler)
end

function Module:UnregisterMessage(message)
    MF:UnregisterMessage(message, self)
end

function Module:SendMessage(message, ...)
    MF:SendMessage(message, ...)
end

function Module:Print(...)
    MF:Print("[" .. self.name .. "]", ...)
end

function Module:Debug(fmt, ...)
    MF:Debug("[" .. self.name .. "] " .. fmt, ...)
end

function Module:IsEnabled()
    return self.enabled
end

-- Builds self.db from the module's slice of each saved table.
function Module:InitModuleDB()
    local db = MarketForcesDB
    local defaults = self.defaults

    db.global.moduleData = db.global.moduleData or {}
    db.global.moduleData[self.name] = Util.ApplyDefaults(db.global.moduleData[self.name] or {}, defaults.global)

    MarketForcesCharDB.moduleData = MarketForcesCharDB.moduleData or {}
    MarketForcesCharDB.moduleData[self.name] =
        Util.ApplyDefaults(MarketForcesCharDB.moduleData[self.name] or {}, defaults.char)

    self.db = {
        global = db.global.moduleData[self.name],
        char = MarketForcesCharDB.moduleData[self.name],
    }
    self:InitModuleAHDB()
end

-- Points self.db.ah at the module's slice of the current auction house.
function Module:InitModuleAHDB()
    if not (self.db and MF.db and MF.db.ah) then return end
    MF.db.ah[self.name] = Util.ApplyDefaults(MF.db.ah[self.name] or {}, self.defaults.ah)
    self.db.ah = MF.db.ah[self.name]
end

function MF:NewModule(name, defaults)
    assert(type(name) == "string" and name ~= "", "module name required")
    assert(not modules[name], "module '" .. name .. "' already exists")
    local module = setmetatable({
        name = name,
        enabled = false,
        defaults = {
            global = (defaults and defaults.global) or {},
            char = (defaults and defaults.char) or {},
            ah = (defaults and defaults.ah) or {},
        },
    }, Module)
    modules[name] = module
    moduleOrder[#moduleOrder + 1] = name
    return module
end

function MF:GetModule(name)
    return modules[name]
end

-- for name, module in MF:IterateModules() do ... end (registration order)
function MF:IterateModules()
    local i = 0
    return function()
        i = i + 1
        local name = moduleOrder[i]
        if name then return name, modules[name] end
    end
end

local function moduleSetting(name)
    local settings = MF.db.global.modules
    settings[name] = settings[name] or { enabled = true }
    return settings[name]
end

local function call(module, method)
    if type(module[method]) ~= "function" then return true end
    local ok, err = pcall(module[method], module)
    if not ok then
        MF:Print("|cffff4444error|r in", module.name .. ":" .. method, err)
    end
    return ok
end

function MF:InitializeModules()
    for _, module in self:IterateModules() do
        module:InitModuleDB()
        call(module, "OnInitialize")
    end
end

-- Enables a module now and remembers the choice.
function MF:EnableModule(name)
    local module = modules[name]
    if not module then return false end
    moduleSetting(name).enabled = true
    if module.enabled then return true end
    module.enabled = true
    if not call(module, "OnEnable") then
        module.enabled = false
        MF:UnregisterAllEvents(module)
        MF:UnregisterAllMessages(module)
        return false
    end
    return true
end

-- Disables a module now and remembers the choice.
function MF:DisableModule(name)
    local module = modules[name]
    if not module then return false end
    moduleSetting(name).enabled = false
    if not module.enabled then return true end
    call(module, "OnDisable")
    MF:UnregisterAllEvents(module)
    MF:UnregisterAllMessages(module)
    module.enabled = false
    return true
end

-- Enables every module whose saved setting allows it.
function MF:EnableModules()
    for name, module in self:IterateModules() do
        if moduleSetting(name).enabled then
            self:EnableModule(name)
        else
            module.enabled = false
        end
    end
end
