-- MarketForces: /mf and /marketforces.
-- Modules add their own subcommands with MF:RegisterSlashCommand, e.g.
--   MF:RegisterSlashCommand("scan", "Scan the open auction house", function(args) ... end)
local _, MF = ...

local Util = MF.Util

local commands = {}     -- name -> { help = string, func = function(args) }
local commandOrder = {}

function MF:RegisterSlashCommand(name, help, func)
    name = name:lower()
    assert(not commands[name], "slash command '" .. name .. "' already exists")
    commands[name] = { help = help, func = func }
    commandOrder[#commandOrder + 1] = name
end

local function printHelp()
    MF:Printf("v%s commands:", MF.version)
    for _, name in ipairs(commandOrder) do
        MF:Print("  /mf " .. name .. " - " .. commands[name].help)
    end
end

function MF:HandleSlashCommand(input)
    local name, args = Util.SplitFirstWord(input)
    name = name:lower()
    if name == "" then
        printHelp()
        return
    end
    local command = commands[name]
    if not command then
        self:Printf("Unknown command '%s'. Type /mf help for a list.", name)
        return
    end
    local ok, err = pcall(command.func, args)
    if not ok then
        self:Print("|cffff4444error|r in /mf " .. name .. ":", err)
    end
end

SLASH_MARKETFORCES1 = "/mf"
SLASH_MARKETFORCES2 = "/marketforces"
SlashCmdList["MARKETFORCES"] = function(input)
    MF:HandleSlashCommand(input)
end

-- Built-in commands -------------------------------------------------------

MF:RegisterSlashCommand("help", "Show this list", printHelp)

MF:RegisterSlashCommand("version", "Show the addon version", function()
    MF:Printf("version %s (saved data schema %d)", MF.version, MF.SCHEMA_VERSION)
end)

MF:RegisterSlashCommand("debug", "Toggle debug messages", function()
    MF.debug = not MF.debug
    MF.db.global.debug = MF.debug
    MF:Print("debug messages", MF.debug and "on" or "off")
end)

MF:RegisterSlashCommand("modules", "List modules and whether they are on", function()
    local count = 0
    for name, module in MF:IterateModules() do
        count = count + 1
        MF:Print("  " .. name .. ": " .. (module:IsEnabled() and "|cff33ff33on|r" or "|cffff3333off|r"))
    end
    if count == 0 then
        MF:Print("No modules installed yet.")
    end
end)

local function findModule(args)
    local name = Util.SplitFirstWord(args)
    if name == "" then
        MF:Print("Give a module name. See /mf modules.")
        return
    end
    for moduleName in MF:IterateModules() do
        if moduleName:lower() == name:lower() then return moduleName end
    end
    MF:Printf("No module named '%s'. See /mf modules.", name)
end

MF:RegisterSlashCommand("enable", "Turn a module on: /mf enable <module>", function(args)
    local name = findModule(args)
    if name and MF:EnableModule(name) then MF:Print(name, "enabled") end
end)

MF:RegisterSlashCommand("disable", "Turn a module off: /mf disable <module>", function(args)
    local name = findModule(args)
    if name and MF:DisableModule(name) then MF:Print(name, "disabled") end
end)

MF:RegisterSlashCommand("reset", "Erase all saved data: /mf reset confirm", function(args)
    if Util.SplitFirstWord(args):lower() ~= "confirm" then
        MF:Print("This erases all MarketForces data, including price history. Type /mf reset confirm to do it.")
        return
    end
    MF:ResetDatabase()
    MF:Print("All saved data erased.")
end)
