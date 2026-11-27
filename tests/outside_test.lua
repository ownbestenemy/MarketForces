-- Outside module: TSM and Auctionator prices, cache, tooltip line.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
local Outside = MF:GetModule("Outside")
check(Outside and Outside:IsEnabled(), "Outside module loads and is on")

check(Outside:GetPrice(2589) == nil, "nothing without TSM or Auctionator")

-- TSM: first source with a price wins; a bad source can't break us.
local tsmPrices = { DBRegionMarketAvg = { [2589] = 150 } }
TSM_API = {
    GetCustomPriceValue = function(source, itemString)
        if source == "Broken" then error("bad source") end
        local id = tonumber(itemString:match("^i:(%d+)$"))
        return tsmPrices[source] and tsmPrices[source][id]
    end,
}
local price, label, cachedAt = Outside:GetPrice(2589)
check(price == 150 and label == "TSM DBRegionMarketAvg" and cachedAt == nil, "TSM fallback source")
Outside.db.global.tsmSources = { "Broken", "DBMarket", "DBRegionMarketAvg" }
tsmPrices.DBMarket = { [2589] = 120 }
price, label = Outside:GetPrice(2589)
check(price == 120 and label == "TSM DBMarket", "erroring source skipped, DBMarket used")

-- Auctionator when TSM has nothing.
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
    assert(caller == "MarketForces")
    return id == 2770 and 80 or nil
end } } }
price, label = Outside:GetPrice(2770)
check(price == 80 and label == "Auctionator", "Auctionator price")

-- Without the addons loaded, cached prices are used until they're too old.
TSM_API, Auctionator = nil, nil
H.advance(2 * 24 * 3600)
price, label, cachedAt = Outside:GetPrice(2589)
check(price == 120 and label == "TSM DBMarket" and cachedAt, "cached price used when TSM is not loaded")

-- Tooltip: only for items Razzle has no price for, by default.
local lines = H.showItemTooltip(2589)
check(lines[1] == "Outside price = 1s 20c (TSM DBMarket, 2d old)", "tooltip outside line for unscanned item")
H.auctions = { { itemID = 2589, count = 10, buyout = 2500 } }
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
H.closeAuctionHouse()
local has = false
for _, line in ipairs(H.showItemTooltip(2589)) do if line:find("^Outside price") then has = true end end
check(not has, "no outside line once Razzle has its own price")
H.slash("outside always")
has = false
for _, line in ipairs(H.showItemTooltip(2589)) do if line:find("^Outside price") then has = true end end
check(has, "/mf outside always shows it anyway")
H.slash("outside off")
check(Outside:Line(2770, false) == nil, "/mf outside off hides it")

H.advance(6 * 24 * 3600)
check(Outside:GetPrice(2589) == nil, "cache expires after cacheDays")
Outside.db.ah.cache[1] = { 1, "x", 0 }
Outside:Prune()
check(Outside.db.ah.cache[1] == nil, "prune drops old cache entries")

H.finish("outside")
