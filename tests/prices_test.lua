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
local function dayNumber(t) return math.floor(t / DAY) end
H.now = 1800000000 - (1800000000 % DAY) + 12 * 3600 -- noon, so +/- hours stay in one day

-- Day 1: linen 100c.
scanWith({ { itemID = 2589, count = 10, buyout = 1000 } })
local p = Prices:GetPrice(2589)
check(p and p.market == 100 and p.minBuyout == 100 and p.quantity == 10 and p.days == 1, "first scan recorded")
check(Prices:GetPrice(9999) == nil, "unseen item has no price")

-- Same day, second scan at 200c: the day keeps its lowest value, 100.
H.advance(15 * 60)
scanWith({ { itemID = 2589, count = 10, buyout = 2000 } })
p = Prices:GetPrice(2589)
check(p.market == 100 and p.minBuyout == 200 and p.days == 1, "a day keeps its lowest scan value")

-- Seven days later at 300c: the old day's recency weight halves to 0.5, but
-- the new day sits 3x above the cheapest, so its weight is (1/3)^2.
-- (100 * 0.5 + 300 / 9) / (0.5 + 1 / 9) = 136
H.advance(7 * DAY)
scanWith({ { itemID = 2589, count = 4, buyout = 1200 } })
p = Prices:GetPrice(2589)
check(p.days == 2 and p.market == 136, "market value leans on recent and cheap days")

-- Linen missing from the next scan: sold out now, but history keeps its value.
H.advance(15 * 60)
scanWith({ { itemID = 2770, count = 1, buyout = 500 } })
p = Prices:GetPrice(2589)
check(p.quantity == 0 and p.minBuyout == nil and p.market == 136, "sold-out item keeps market value")

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
check(Prices:GetPrice(2589, "US-RP PvP-Horde").market == 136, "faction AH prices untouched")
H.npcFaction = nil
H.openAuctionHouse()
H.closeAuctionHouse()

-- /mf price
H.clearChat()
H.slash("price |cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
check(H.chatHas("Market value: 1s 36c") and H.chatHas("2 days of history"), "/mf price shows market value")
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

-- A day keeps its lowest scan value: 1000 then 49 x 900 -> 900.
H.advance(15 * 60)
for i = 1, 50 do
    local unit = i == 1 and 1000 or 900
    Prices:RecordSnapshot({ key = MF.db.ahKey, time = H.now, auctions = 1,
        items = { [5000] = { quantity = 1, auctions = 1, minBuyout = unit, listings = { { unit, 1 } } } } })
end
check(Prices:GetPrice(5000).market == 900, "day value is its lowest scan")
-- Days saved before the lowest value was kept use their average, exactly.
local legacy = Prices:ItemsFor()[5000].d
for day in pairs(legacy) do legacy[day] = { 1000 + 49 * 900, 50 } end
check(Prices:GetPrice(5000).market == 902, "older saved days use their precise average")

-- Mark's case: one 11s listing among ~8g asks. Days of ~8g values don't
-- outweigh a day at 11s.
local gloves = {}
gloves[dayNumber(H.now) - 2] = { 79600, 1, 79600 }
gloves[dayNumber(H.now) - 1] = { 80000, 1, 80000 }
gloves[dayNumber(H.now)] = { 1123, 1, 1123 }
local glovesValue = Prices.Blend(gloves, dayNumber(H.now), 7, 2)
check(glovesValue >= 1123 and glovesValue < 1200, "a realistic low price beats high asks (about 11s)")
check(Prices.Blend(gloves, dayNumber(H.now), 7, 0) > 50000, "with lowWeight 0 the high asks would win")
-- Ordinary spread barely moves: 100 today, 120 yesterday.
local spread = { [10] = { 100, 1, 100 }, [9] = { 120, 1, 120 } }
local v = Prices.Blend(spread, 10, 7, 2)
check(v > 100 and v < 110, "normal price spread blends gently")
-- A same-day scan: 8g then 11s -> the day is worth 11s.
H.advance(15 * 60)
Prices:RecordSnapshot({ key = MF.db.ahKey, time = H.now, auctions = 1,
    items = { [6000] = { quantity = 2, auctions = 2, minBuyout = 79600, listings = { { 79600, 2 } } } } })
Prices:RecordSnapshot({ key = MF.db.ahKey, time = H.now, auctions = 1,
    items = { [6000] = { quantity = 3, auctions = 1, minBuyout = 1123, listings = { { 1123, 3 } } } } })
check(Prices:GetPrice(6000).market == 1123, "a cheap scan later in the day sets the day's value")

-- Old data at another house expires even without visiting it.
local neutral = Prices:ItemsFor("US-RP PvP-Neutral")
check(neutral[2589] ~= nil, "neutral history still stored")
H.advance(40 * DAY)
check(Prices:GetPrice(2589, "US-RP PvP-Neutral") == nil, "expired neutral prices not returned")
check(neutral[2589] == nil, "expired neutral entry removed on lookup")

-- Saved where expected.
check(MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Prices.items[2770] ~= nil, "history saved per auction house")

H.finish("prices")
