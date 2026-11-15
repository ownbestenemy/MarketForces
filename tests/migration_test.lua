-- Saved data from older versions is upgraded on load.
local H = dofile("tests/harness.lua")
local check = H.check

local DAY = 24 * 60 * 60
local today = math.floor(H.now / DAY)

-- Schema 1 data: Prices stored { daily average, scans that day }.
MarketForcesDB = {
    schema = 1,
    global = {},
    auctionHouses = {
        ["US-RP PvP-Horde"] = { Prices = { items = {
            [2589] = { l = 900, q = 5, t = H.now, d = { [today] = { 1000, 4 } } },
        } } },
        ["US-RP PvP-Neutral"] = { Prices = { items = {
            [2770] = { l = 50, q = 1, t = H.now, d = { [today] = { 60, 1 }, [today - 1] = { 80, 3 } } },
        } } },
        ["US-RP PvP-Alliance"] = { Scan = { lastScan = 0 } },
    },
}

local MF = H.startAddon()
check(MarketForcesDB.schema == 2, "schema bumped to 2")
local horde = MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Prices.items[2589].d[today]
check(horde[1] == 4000 and horde[2] == 4, "daily average turned into a sum")
local neutral = MarketForcesDB.auctionHouses["US-RP PvP-Neutral"].Prices.items[2770].d
check(neutral[today][1] == 60 and neutral[today - 1][1] == 240, "every house and day migrated")
check(MF.Prices:GetPrice(2589).market == 1000, "market value unchanged by the upgrade")

-- Loading again doesn't migrate twice.
local again = MarketForcesDB
check(again.schema == 2 and horde[1] == 4000, "migration runs once")

H.finish("migration")
