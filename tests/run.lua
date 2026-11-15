-- Offline smoke test: loads the addon the way the WoW client does (files in
-- .toc order, sharing one namespace table), fires the startup events with a
-- fake API, and checks the core behaves. Run from the repo root:
--   lua5.1 tests/run.lua
local failures, passes = 0, 0
local function check(cond, label)
    if cond then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL: " .. label)
    end
end

-- Fake WoW API --------------------------------------------------------------
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
SlashCmdList = {}
local frames = {}
function CreateFrame()
    local f = { registered = {}, scripts = {} }
    function f:RegisterEvent(e) self.registered[e] = true end
    function f:UnregisterEvent(e) self.registered[e] = nil end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    frames[#frames + 1] = f
    return f
end
function GetRealmName() return "Testrealm" end
function UnitFactionGroup() return "Horde" end
function GetAddOnMetadata(_, key) if key == "Version" then return "0.1.0" end end

local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f.registered[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
local function slash(text) SlashCmdList.MARKETFORCES(text) end
local function chatHas(pattern)
    for _, line in ipairs(chat) do if line:find(pattern) then return true end end
    return false
end

-- Load files in .toc order, plus a test module ---------------------------------
local ns = {}
local function load(path)
    local chunk = assert(loadfile(path))
    chunk("MarketForces", ns)
end
local files = {}
for line in io.lines("MarketForces.toc") do
    if not line:match("^%s*#") and line:match("%S") then
        files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
    end
end
check(files[1] == "Core/Init.lua" and files[#files] == "Core/Core.lua", "toc loads Init first and Core last")

for i = 1, #files - 1 do load(files[i]) end

local MF = ns
local calls = {}
local Test = MF:NewModule("Test", { global = { a = 1 }, ah = { seen = 0 } })
function Test:OnInitialize() calls[#calls + 1] = "init" end
function Test:OnEnable()
    calls[#calls + 1] = "enable"
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterMessage("MF_TEST")
end
function Test:OnDisable() calls[#calls + 1] = "disable" end
function Test:AUCTION_HOUSE_SHOW() self.db.ah.seen = self.db.ah.seen + 1 end
function Test:MF_TEST(_, value) self.got = value end

local Broken = MF:NewModule("Broken")
function Broken:OnEnable() error("boom") end

load(files[#files])

-- Startup -------------------------------------------------------------------------
check(_G.MarketForces == MF, "namespace is global")
check(MF.version == "0.1.0", "version read from toc metadata")
fire("ADDON_LOADED", "SomeOtherAddon")
check(MF.db == nil, "ignores other addons' ADDON_LOADED")
fire("ADDON_LOADED", "MarketForces")
check(type(MarketForcesDB) == "table" and MarketForcesDB.schema == MF.SCHEMA_VERSION, "saved data created with schema")
check(calls[1] == "init" and Test.db.global.a == 1, "module initialized with defaults")
fire("PLAYER_LOGIN")
check(MF.db.ahKey == "Testrealm-Horde", "auction house key is realm-faction")
check(calls[2] == "enable" and Test:IsEnabled(), "module enabled at login")
check(not Broken:IsEnabled(), "module whose OnEnable errors stays off")
check(chatHas("Broken:OnEnable"), "OnEnable error reported in chat")

-- Events and messages ---------------------------------------------------------------
fire("AUCTION_HOUSE_SHOW")
check(Test.db.ah.seen == 1, "module receives game events")
check(MarketForcesDB.auctionHouses["Testrealm-Horde"].Test.seen == 1, "module ah data lands in saved variables")
MF:SendMessage("MF_TEST", 42)
check(Test.got == 42, "module receives messages")

MF:InitAuctionHouseDB("Neutral")
check(MF.db.ahKey == "Testrealm-Neutral" and Test.db.ah.seen == 0, "switching to a neutral AH swaps module ah data")
MF:InitAuctionHouseDB()

-- Slash commands ----------------------------------------------------------------------
slash("")
check(chatHas("/mf modules"), "/mf lists commands")
slash("disable test")
check(not Test:IsEnabled() and calls[3] == "disable", "/mf disable turns a module off")
check(MarketForcesDB.global.modules.Test.enabled == false, "disabled state saved")
fire("AUCTION_HOUSE_SHOW")
check(Test.db.ah.seen == 1, "disabled module gets no events")
slash("enable Test")
check(Test:IsEnabled(), "/mf enable turns it back on")
slash("bogus")
check(chatHas("Unknown command 'bogus'"), "unknown command reported")
slash("debug")
check(MF.debug and MarketForcesDB.global.debug, "/mf debug toggles and saves")

slash("reset")
check(MarketForcesDB.auctionHouses["Testrealm-Horde"].Test.seen == 1, "/mf reset without confirm keeps data")
slash("reset confirm")
check(MarketForcesDB.auctionHouses["Testrealm-Horde"].Test.seen == 0, "/mf reset confirm wipes data")
check(Test.db.ah == MarketForcesDB.auctionHouses["Testrealm-Horde"].Test, "module db rebound after reset")

-- Util ------------------------------------------------------------------------------
local strip = function(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
check(strip(MF.Util.FormatMoney(123456)) == "12g 34s 56c", "FormatMoney full")
check(strip(MF.Util.FormatMoney(10000)) == "1g", "FormatMoney drops zero parts")
check(strip(MF.Util.FormatMoney(0)) == "0c", "FormatMoney zero")
check(strip(MF.Util.FormatMoney(-250)) == "-2s 50c", "FormatMoney negative")

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
