-- Core framework: startup, modules, events, saved data, slash commands.
local H = dofile("tests/harness.lua")
local check = H.check


local calls = {}
local Test, Broken
local MF, files = H.loadAddon(function(MF)

Test = MF:NewModule("Test", { global = { a = 1 }, ah = { seen = 0 } })
function Test:OnInitialize() calls[#calls + 1] = "init" end
function Test:OnEnable()
    calls[#calls + 1] = "enable"
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterMessage("MF_TEST")
end
function Test:OnDisable() calls[#calls + 1] = "disable" end
function Test:AUCTION_HOUSE_SHOW() self.db.ah.seen = self.db.ah.seen + 1 end
function Test:MF_TEST(_, value) self.got = value end

Broken = MF:NewModule("Broken")
function Broken:OnEnable() error("boom") end
end)
check(files[1] == "Core/Init.lua" and files[#files] == "Core/Core.lua", "toc loads Init first and Core last")

-- Startup -------------------------------------------------------------------------
check(_G.MarketForces == MF, "namespace is global")
check(MF.version == "0.1.0", "version read from toc metadata")
H.fire("ADDON_LOADED", "SomeOtherAddon")
check(MF.db == nil, "ignores other addons' ADDON_LOADED")
H.fire("ADDON_LOADED", "MarketForces")
check(type(MarketForcesDB) == "table" and MarketForcesDB.schema == MF.SCHEMA_VERSION, "saved data created with schema")
check(calls[1] == "init" and Test.db.global.a == 1, "module initialized with defaults")
H.fire("PLAYER_LOGIN")
check(MF.db.ahKey == "US-RP PvP-Horde", "auction house key is region-ruleset-faction")
check(calls[2] == "enable" and Test:IsEnabled(), "module enabled at login")
check(not Broken:IsEnabled(), "module whose OnEnable errors stays off")
check(H.chatHas("Broken:OnEnable"), "OnEnable error reported in chat")

-- Events and messages ---------------------------------------------------------------
H.fire("AUCTION_HOUSE_SHOW")
check(Test.db.ah.seen == 1, "module receives game events")
check(MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Test.seen == 1, "module ah data lands in saved variables")
MF:SendMessage("MF_TEST", 42)
check(Test.got == 42, "module receives messages")

MF:InitAuctionHouseDB("Neutral")
check(MF.db.ahKey == "US-RP PvP-Neutral" and Test.db.ah.seen == 0, "switching to a neutral AH swaps module ah data")
MF:InitAuctionHouseDB()

-- Slash commands ----------------------------------------------------------------------
H.slash("")
check(H.chatHas("/mf modules"), "/mf lists commands")
H.slash("disable test")
check(not Test:IsEnabled() and calls[3] == "disable", "/mf disable turns a module off")
check(MarketForcesDB.global.modules.Test.enabled == false, "disabled state saved")
H.fire("AUCTION_HOUSE_SHOW")
check(Test.db.ah.seen == 1, "disabled module gets no events")
H.slash("enable Test")
check(Test:IsEnabled(), "/mf enable turns it back on")
H.slash("bogus")
check(H.chatHas("Unknown command 'bogus'"), "unknown command reported")
H.slash("debug")
check(MF.debug and MarketForcesDB.global.debug, "/mf debug toggles and saves")

H.slash("reset")
check(MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Test.seen == 1, "/mf reset without confirm keeps data")
H.slash("reset confirm")
check(MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Test.seen == 0, "/mf reset confirm wipes data")
check(Test.db.ah == MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Test, "module db rebound after reset")

-- Util ------------------------------------------------------------------------------
local strip = function(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
check(strip(MF.Util.FormatMoney(123456)) == "12g 34s 56c", "FormatMoney full")
check(strip(MF.Util.FormatMoney(10000)) == "1g", "FormatMoney drops zero parts")
check(strip(MF.Util.FormatMoney(0)) == "0c", "FormatMoney zero")
check(strip(MF.Util.FormatMoney(-250)) == "-2s 50c", "FormatMoney negative")

local scope = MF.Util.GetMarketScope
check(scope("CAMWOW US1 Realm 9 RP PvP") == "US-RP PvP", "Forever shard reduced to region-ruleset")
check(scope("CAMWOW EU2 Realm 14 PvP") == "EU-PvP", "Forever PvP shard")
check(scope("CAMWOW US1 Realm 3") == "US-Normal", "Forever shard with no ruleset is Normal")
check(scope("Faerlina") == "Faerlina", "ordinary realm name unchanged")
H.realmName = "CAMWOW US1 Realm 9 RP PvP"
check(MF.Util.GetAuctionKey() == "US-RP PvP-Horde", "auction key on Forever")
check(MF.Util.GetAuctionKey("Neutral") == "US-RP PvP-Neutral", "neutral auction key on Forever")
H.realmName = "CAMWOW US1 Realm 12 RP PvP"
check(MF.Util.GetAuctionKey() == "US-RP PvP-Horde", "different shard, same auction house")

check(MF.Util.FormatDuration(305) == "5m 05s" and MF.Util.FormatDuration(9) == "9s", "FormatDuration")

H.finish("core")
