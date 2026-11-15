-- Prices module: scan values, daily history, smoothing, pruning, /mf price.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
local Prices = MF:GetModule("Prices")
check(Prices and Prices:IsEnabled(), "Prices module loads and is on")

-- Scan value: average of the cheapest 30% of units.
local SV = Prices.ScanValue
check(SV({}) == nil, "no listings, no value")
check(SV({ { 100, 1 } }) == 100, "single listing")
-- 10 units: 3 cheapest are 100, 100, 100 -> 100, ignoring the 9999 troll.
check(SV({ { 9999, 7 }, { 100, 3 } }) == 100, "troll listings ignored")
-- 20 units -> 6 cheapest: 2 at 50 and 4 at 80 = 70.
check(SV({ { 80, 10 }, { 50, 2 }, { 200, 8 } }) == 70, "weighted by units across listings")

check(Prices.ParseItemID("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r") == 2589, "item ID from a link")
check(Prices.ParseItemID(" 2770 ") == 2770 and Prices.ParseItemID("linen") == nil, "item ID from text")

local function scanWith(auctions)
    H.auctions = auctions
    H.openAuctionHouse()
    H.slash("scan")
    H.fire("REPLICATE_ITEM_LIST_UPDATE")
    H.runTimers()
    H.closeAuctionHouse()
end

local DAY = 24 * 60 * 60
H.now = 1800000000 - (1800000000 % DAY) + 12 * 3600 -- noon, so +/- hours stay in one day

-- Day 1: linen 100c.
scanWith({ { itemID = 2589, count = 10, buyout = 1000 } })
local p = Prices:GetPrice(2589)
check(p and p.market == 100 and p.minBuyout == 100 and p.quantity == 10 and p.days == 1, "first scan recorded")
check(Prices:GetPrice(9999) == nil, "unseen item has no price")

-- Same day, second scan at 200c: the day averages to 150.
H.advance(15 * 60)
scanWith({ { itemID = 2589, count = 10, buyout = 2000 } })
p = Prices:GetPrice(2589)
check(p.market == 150 and p.minBuyout == 200 and p.days == 1, "scans on one day are averaged")

-- Seven days later at 300c: recent day counts twice as much as the old one.
-- (150 * 0.5 + 300 * 1) / 1.5 = 250
H.advance(7 * DAY)
scanWith({ { itemID = 2589, count = 4, buyout = 1200 } })
p = Prices:GetPrice(2589)
check(p.days == 2 and p.market == 250, "market value weights recent days more")

-- Linen missing from the next scan: sold out now, but history keeps its value.
H.advance(15 * 60)
scanWith({ { itemID = 2770, count = 1, buyout = 500 } })
p = Prices:GetPrice(2589)
check(p.quantity == 0 and p.minBuyout == nil and p.market == 250, "sold-out item keeps market value")

-- Bid-only items are tracked but get no value.
H.advance(15 * 60)
scanWith({ { itemID = 3000, count = 1 } })
p = Prices:GetPrice(3000)
check(p and p.market == nil and p.quantity == 1, "bid-only item tracked without a value")

-- Neutral AH keeps its own history.
H.advance(15 * 60)
H.npcFaction = "Neutral"
scanWith({ { itemID = 2589, count = 1, buyout = 999 } })
check(Prices:GetPrice(2589).market == 999, "neutral AH has its own prices")
check(Prices:GetPrice(2589, "US-RP PvP-Horde").market == 250, "faction AH prices untouched")
H.npcFaction = nil
H.openAuctionHouse()
H.closeAuctionHouse()

-- /mf price
H.clearChat()
H.slash("price |cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
check(H.chatHas("Market value: 2s 50c") and H.chatHas("2 days of history"), "/mf price shows market value")
check(H.chatHas("Cheapest now: none listed, 0 listed"), "/mf price shows current listings")
H.clearChat()
H.slash("price 424242")
check(H.chatHas("No prices for item 424242"), "/mf price for an unknown item")
H.clearChat()
H.slash("price")
check(H.chatHas("Shift%-click an item"), "/mf price with no item explains usage")

-- Pruning: 30 days on, the first day's history drops off.
H.advance(24 * DAY)
H.advance(15 * 60)
scanWith({ { itemID = 2770, count = 1, buyout = 500 } })
p = Prices:GetPrice(2589)
check(p.days == 1, "history older than 30 days pruned")
H.advance(10 * DAY)
scanWith({ { itemID = 2770, count = 1, buyout = 500 } })
check(Prices:GetPrice(2589) == nil, "item not seen for 30 days forgotten")
check(Prices:GetPrice(2770) ~= nil, "recently seen item kept")

-- Saved where expected.
check(MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Prices.items[2770] ~= nil, "history saved per auction house")

H.finish("prices")
