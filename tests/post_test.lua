-- Post module: Razzle fills in the sell price with market value.
local H = dofile("tests/harness.lua")
local check = H.check

function UnitName() return "Mark" end

local MF = H.startAddon()
-- Market value here; Razzle's pick has its own tests (pick_test.lua).
MF:GetModule("Post").db.global.method = "market"
local Post = MF:GetModule("Post")
check(Post and Post:IsEnabled(), "Post module loads and is on")

-- Build history: linen market 80c (cheapest 30% of 10 units: 40, 100, 100).
H.auctions = {
    { itemID = 2589, count = 1, buyout = 40 },
    { itemID = 2589, count = 9, buyout = 900 },
    { itemID = 2770, count = 4, buyout = 50000 }, -- ore 1g 25s each
    { itemID = 2771, count = 2, buyout = 1000, owner = "Mark" }, -- your tin at 5s, the cheapest
    { itemID = 2771, count = 2, buyout = 1400 },                 -- someone else's at 7s
    { itemID = 2772, count = 3, buyout = 900, owner = "Mark" },  -- iron only you sell
}
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()

check(Post:Suggest(2770) == 12500, "suggestion is market value")
check(Post:Suggest(2589) == 80, "prices keep their copper")
check(Post.RoundPrice(0.2) == 1 and Post.RoundPrice(495) == 495, "at least 1c; copper kept")
check(Post:Suggest(424242) == nil, "no suggestion without history")

-- The scan's own listings aren't competition: match and undercut go by
-- other sellers only, and have no number when nobody else sells.
local tin = Post:PriceOptions(2771)
check(tin.match == 700 and tin.undercut == 699, "your cheaper auction isn't undercut (got "
    .. tostring(tin.match) .. ", " .. tostring(tin.undercut) .. ")")
local iron = Post:PriceOptions(2772)
check(iron.match == nil and iron.undercut == nil and iron.market, "only you sell it: no match or undercut")
MF.Prices:ItemsFor()[2771].o = nil
check(Post:PriceOptions(2771).match == nil, "a scan from before owner tracking isn't trusted")

-- Putting an item in the sell slot fills in the price on the next frame.
H.blizzardDefaultPrice = 99999
local sell = AuctionHouseFrame.CommoditiesSellFrame
sell:SetItem({ itemID = 2770 })
check(sell.PriceInput.amount == 99999, "Blizzard's default first")
H.runTimers()
check(sell.PriceInput.amount == 12500, "Razzle's market value fills the price box")
check(MarketForcesRazzleFrame.speech.text:find("Selling Copper Ore%? Market value's"), "Razzle talks about the item")
check(MarketForcesRazzleFrame.speech.text:find("click Post when you're happy"), "Razzle leaves the Post click to you")

-- Unknown item: price left alone, Razzle says so.
local itemSell = AuctionHouseFrame.ItemSellFrame
itemSell:SetItem({ itemID = 424242 })
H.runTimers()
check(itemSell.PriceInput.amount == 99999, "unknown item keeps Blizzard's price")
check(MarketForcesRazzleFrame.speech.text:find("no steady price"), "Razzle admits it doesn't know")

-- /mf autofill off: suggestion shown, price untouched.
H.slash("autofill")
sell:SetItem({ itemID = 2770 })
H.runTimers()
check(sell.PriceInput.amount == 99999, "autofill off leaves the price box alone")
check(not MarketForcesRazzleFrame.speech.text:find("I put my number in"), "Razzle doesn't claim to fill it")
H.slash("autofill")

-- Module off: nothing happens.
H.slash("disable post")
sell:SetItem({ itemID = 2770 })
H.runTimers()
check(sell.PriceInput.amount == 99999, "disabled Post doesn't fill prices")

-- A quick second pick before the first price lands: no stale price.
H.slash("enable post")
sell:SetItem({ itemID = 2770 })
sell:SetItem({ itemID = 424242 })
H.runTimers()
check(sell.PriceInput.amount == 99999, "a newer selection cancels the pending price")

-- The sell frames are only hooked once across AH visits.
H.slash("enable post")
H.closeAuctionHouse()
H.openAuctionHouse()
H.closeAuctionHouse()
H.openAuctionHouse()
local calls = 0
local original = Post.OnItemSet
Post.OnItemSet = function(...) calls = calls + 1 return original(...) end
sell:SetItem({ itemID = 2770 })
check(calls == 1, "sell frame hooked once")

-- Enabled while the AH is already open (and never hooked before): works now.
H.closeAuctionHouse()
AuctionHouseFrame = nil -- a fresh window Post hasn't hooked
H.slash("disable post")
H.openAuctionHouse()
H.slash("enable post")
local fresh = AuctionHouseFrame.CommoditiesSellFrame
fresh:SetItem({ itemID = 2770 })
H.runTimers()
check(fresh.PriceInput.amount == 12500, "enabling Post at an open AH hooks the sell frames")

H.finish("post")
