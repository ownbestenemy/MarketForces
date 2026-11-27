-- Razzle's Sell tab: bags, competing listings and your results side by side.
local H = dofile("tests/harness.lua")
local check = H.check

function UnitName() return "Mark" end

local MF = H.startAddon()
local Broker = MF:GetModule("Broker")
local History = MF:GetModule("History")

-- Small pieces.
check(Broker.Ago(30) == "1m ago" and Broker.Ago(3 * 3600) == "3h ago" and Broker.Ago(2 * 86400) == "2d ago",
    "ago")
local merged = Broker.MergeListings({ { 200, 5 }, { 150, 10, true }, { 200, 3 }, { 0, 9 } })
check(#merged == 2 and merged[1][1] == 150 and merged[1][3] == true and merged[2][2] == 8,
    "listings merged by price, cheapest first, free ones dropped")
check(H.plain(Broker.ListingLine({ 150, 10, true })) == "10 at 1s 50c (yours)", "your listing marked")
check(H.plain(Broker.ListingLine({ 200, 8, false })) == "8 at 2s", "listing line")

-- Scan: linen 2s market-ish, ore 10s.
H.auctions = {
    { itemID = 2589, count = 5, buyout = 750 },
    { itemID = 2589, count = 10, buyout = 2000 },
    { itemID = 2589, count = 20, buyout = 6000 },
    { itemID = 2770, count = 10, buyout = 100000 },
}
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()

H.commodities = { [2589] = true, [2770] = true }
H.bags = { [0] = {
    { itemID = 2589, stackCount = 20 },
    { itemID = 2770, stackCount = 4 },
    { itemID = 9002, stackCount = 1, isBound = true },
} }

-- Your results: two linen sales, one expiry, at this market; one elsewhere.
local scope = MF.Util.GetMarketScope()
History.db.global.records = {
    { type = "sold", id = 2589, name = "Linen Cloth", n = 10, money = 1900, price = 2000, at = H.now - 2 * 86400,
      s = scope, c = "Mark" },
    { type = "sold", id = 2589, name = "Linen Cloth", n = 5, money = 950, price = 1000, at = H.now - 3600,
      s = scope, c = "Mark" },
    { type = "expired", id = 2589, name = "Linen Cloth", n = 5, at = H.now - 86400, s = scope, c = "Mark" },
    { type = "sold", id = 2589, name = "Linen Cloth", n = 99, money = 1, at = H.now - 60, s = "EU-Normal", c = "Mark" },
}

local frame = MarketForcesRazzleFrame
check(#frame.tabs == 3 and frame.tabs[3].text == "Sell", "three tabs: Bargains, Flips, Sell")
frame.tabs[3]:Click()
check(Broker.tab == "Sell" and frame.pages.Sell.shown and not frame.pages.Bargains.shown, "Sell tab opens")

-- Bags column: sellable items, most valuable first; bound left out.
check(H.plain(frame.sellBagLines[1].text):find("^Copper Ore x4"), "ore first (most total value)")
check(H.plain(frame.sellBagLines[2].text):find("^Linen Cloth x20"), "linen second")
check(frame.sellBagLines[3].text == "", "bound band left out")
check(H.plain(frame.sellItemName.text) == "Pick something from your bags", "nothing picked yet")

-- Pick linen at the AH: sell slot set (like shift-click), listings from the scan,
-- your results beside them.
local sell = AuctionHouseFrame.CommoditiesSellFrame
frame.sellBagRows[2]:Click()
H.runTimers()
check(Broker.sellItem == 2589, "linen picked")
check(H.postItemSet and H.postItemSet.slot == 1, "linen goes in Blizzard's sell slot")
check(sell.QuantityInput.quantity == 20, "quantity set like a shift-click")
check(H.plain(frame.speech.text):find("Putting up 20 Linen Cloth", 1, true), "Razzle says what's set up")
check(H.plain(frame.sellBagLines[2].text):find("^> Linen Cloth"), "picked row marked")
check(frame.sellSource.text:find("^From your last scan"), "listings from the scan until live ones arrive")
check(H.plain(frame.sellListLines[1].text) == "5 at 1s 50c", "cheapest scan listing first")
check(H.plain(frame.sellPriceLines[1].text):find("^Market value: "), "market value shown")
check(H.plain(frame.sellPriceLines[2].text):find("^Razzle's price: "), "Razzle's price shown")
check(H.plain(frame.sellResultLines[1].text) == "Sold 15 in 2 listings, ~2s each", "sales summed for this market only")
check(H.plain(frame.sellResultLines[2].text) == "Sell-through: 2 of 3 (67%)", "sell-through")
check(H.plain(frame.sellResultLines[3].text) == "Expired 1, cancelled 0", "expired count")
check(H.plain(frame.sellResultLines[4].text) == "Last sold 1h ago", "last sale")
check(H.plain(frame.sellRecentLines[1].text) == "sold 5 for 9s 50c, 1h ago", "newest record first")
check(H.plain(frame.sellRecentLines[2].text) == "expired 5, 1d ago", "then the expiry")
check(frame.sellRecentLines[4].text == "", "other market's sale not listed")

-- Live listings from Blizzard's own search replace the scan's.
C_AuctionHouse.GetNumCommoditySearchResults = function() return 3 end
C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i)
    return ({
        { unitPrice = 140, quantity = 12 },
        { unitPrice = 180, quantity = 4, containsOwnerItem = true },
        { unitPrice = 140, quantity = 3 },
    })[i]
end
H.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2770) -- another item: ignored
check(frame.sellSource.text:find("^From your last scan"), "results for other items ignored")
H.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
check(frame.sellSource.text == "Live from the auction house", "live listings shown")
check(H.plain(frame.sellListLines[1].text) == "15 at 1s 40c", "live listings merged")
check(H.plain(frame.sellListLines[2].text) == "4 at 1s 80c (yours)", "your live listing marked")

-- Click a listing: its price goes in Blizzard's price box (whole silver).
sell.PriceInput.amount = 0
frame.sellListRows[1]:Click()
check(sell.PriceInput.amount == 100, "1s 40c rounds to 1s")
check(H.plain(frame.speech.text):find("Matched at 1s each (whole silver)", 1, true), "Razzle says it matched")

-- The sell slot now holds ore (put there by hand): the tab follows it, and a
-- listing click can't touch ore's price with linen's numbers.
sell:SetItem({ itemID = 2770 })
H.runTimers()
check(Broker.sellItem == 2770 and Broker.sellLive == nil, "tab follows the sell slot; old live listings dropped")
check(H.plain(frame.sellItemName.text) == "Copper Ore", "ore shown")
check(H.plain(frame.sellResultLines[1].text):find("No results for this yet"), "no results for ore")
sell.PriceInput.amount = 7
frame.sellListRows[1]:Click()
check(sell.PriceInput.amount == 10000, "ore's own listing matched into ore's slot")

-- A different sell frame holds the item: nothing changes.
Broker.sellItem = 2589
sell.PriceInput.amount = 7
Broker:MatchListing(150)
check(sell.PriceInput.amount == 7, "no price set when the slot holds another item")
check(H.plain(frame.speech.text):find("Pick Linen Cloth from your bags first"), "Razzle says to pick it")

-- Post off while the slot changes hands: the old item's listing can't be
-- matched into the new item once Post is back.
Broker.sellItem = 2770
MF:DisableModule("Post")
sell:SetItem({ itemID = 2589 })
MF:EnableModule("Post")
sell.PriceInput.amount = 7
Broker:MatchListing(150)
check(sell.PriceInput.amount == 7, "a swap while Post was off isn't missed")

-- Non-commodity results: read by item key.
H.bags[0][4] = { itemID = 9003, stackCount = 1 }
H.itemNames[9003] = "Iron Sword"
Broker:SelectSellItem(9003)
C_AuctionHouse.GetNumItemSearchResults = function() return 2 end
C_AuctionHouse.GetItemSearchResultInfo = function(_, i)
    return ({ { buyoutAmount = 50000, quantity = 1 }, { minBid = 100, quantity = 1 } })[i]
end
H.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 9003 })
check(H.plain(frame.sellListLines[1].text) == "1 at 5g" and frame.sellListLines[2].text == "",
    "gear listings read; bid-only left out")
check(frame.sellSource.text == "Live from the auction house", "gear live")

-- Leaving the AH: live listings go, picking just looks.
H.closeAuctionHouse()
check(Broker.sellLive == nil, "live listings dropped when the AH closes")
H.slash("razzle")
frame.tabs[3]:Click()
H.postItemSet = nil
frame.sellBagRows[2]:Click()
check(not H.postItemSet, "away from the AH nothing goes in a sell slot")
check(H.plain(frame.speech.text):find("Bring it to the auction house"), "Razzle says to bring it")
check(H.plain(frame.speech.text):find("Your record: 15 sold", 1, true), "Razzle mentions your record")
Broker:MatchListing(150)
check(H.plain(frame.speech.text):find("Meet me at the auction house"), "matching needs the AH")

-- History off: the results column says so.
MF:DisableModule("History")
Broker:RefreshSell()
check(H.plain(frame.sellResultLines[1].text):find("/mf enable history", 1, true), "history off message")

H.finish("selltab")
