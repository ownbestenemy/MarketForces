-- Razzle's pick: the default pricing method, priced to sell. Commodities
-- match the cheapest other seller, gear goes 1c under, a thin layer of
-- lowball listings isn't chased, and the floor holds.
local H = dofile("tests/harness.lua")
local check = H.check

function UnitName() return "Mark" end

local MF = H.startAddon()
local Post = MF:GetModule("Post")
local Prices = MF:GetModule("Prices")
local Broker = MF:GetModule("Broker")
check(Post.db.global.method == "pick" and Post:Method() == "pick", "Razzle's pick is the default")
check(Post.METHODS[1].key == "pick" and Post.METHOD_LABEL.pick == "Razzle's pick", "listed first")
check(Post.MethodName("pick") == "Razzle's pick" and Post.MethodName("median") == "median", "method names")

-- The cheapest that counts.
local CTC = Prices.CheapestThatCounts
local function counts(listings, price, skipped, what)
    local p, s = CTC(listings)
    check(p == price and s == skipped, what .. " (got " .. tostring(p) .. ", " .. tostring(s) .. ")")
end
counts({ { 50, 5 }, { 100, 95 } }, 100, 5, "5 of 100 at half price: skipped")
counts({ { 50, 5 }, { 60, 3 }, { 100, 92 } }, 100, 8, "two thin lowball steps: both skipped")
counts({ { 98, 3 }, { 100, 97 } }, 98, 0, "a near price isn't lowball")
counts({ { 50, 1 }, { 100, 2 } }, 50, 0, "a third of a tiny market isn't a thin layer")
counts({ { 50, 30 }, { 100, 70 } }, 50, 0, "a big cheap step is the market")
counts({ { 50, 5, true }, { 100, 95 } }, 100, 0, "your own listings aren't counted")
counts({ { 50, 5, true } }, nil, 0, "only you: nobody to count")
counts({}, nil, 0, "nobody")

-- Scan: your linen at 30c (not competition), 5 lowball at 50c, the real
-- supply at 1s. Linen is a commodity; the sword is gear.
H.commodities = { [2589] = true }
H.stackSizes = { [2589] = 20 }
H.itemNames[9003] = "Iron Sword"
H.auctions = {
    { itemID = 2589, count = 10, buyout = 300, owner = "Mark" },
    { itemID = 2589, count = 5, buyout = 250 },
    { itemID = 2589, count = 95, buyout = 9500 },
}
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
local p = Prices:GetPrice(2589)
check(p.cheapestOther == 50 and p.cheapestCounted == 100 and p.lowballUnits == 5, "scan keeps the cheapest that counts")
local floor = math.ceil(p.market * Post.db.global.undercutFloor)

check(Post.IsCommodity(2589) and not Post.IsCommodity(9003), "commodity or gear")
local opts = Post:PriceOptions(2589)
check(opts.pick == 100 and opts.pickWhy == "match" and opts.lowball == 5, "pick from the scan: match the real supply")
check(opts.match == 50 and opts.undercut == math.max(49, floor), "match and undercut stay literal")
check(Post:Reason("pick", opts) == "Matching the cheapest that counts: same price, and the newest listing "
    .. "sells first. I skipped 5 lowball units under it", "Razzle says why")
local price, _, method = Post:Suggest(2589)
check(price == 100 and method == "pick", "suggestion uses the pick")

-- Live listings: the same rules.
opts = Post:PriceOptions(2589, { { 95, 20 }, { 100, 80 } })
check(opts.pick == 95 and opts.pickWhy == "match" and opts.lowball == nil, "plain match")
check(Post:Reason("pick", opts) == "Matching the cheapest: same price, and the newest listing sells first",
    "plain match reason")
opts = Post:PriceOptions(9003, { { 50000, 1 }, { 60000, 1 } })
check(opts.pick == 49999 and opts.pickWhy == "undercut", "gear: 1c under")
check(Post:Reason("pick", opts) == "1c under the cheapest listing", "undercut reason")
opts = Post:PriceOptions(2589, { { 40, 60 }, { 100, 40 } })
check(opts.pick == floor and opts.pickWhy == "floor", "dumping: held at the floor")
check(Post:Reason("pick", opts) == "The cheapest is dumping, so I held at 80% of market", "floor reason")
opts = Post:PriceOptions(2589, { { 60, 10, true } })
check(opts.pick == p.market and opts.pickWhy == "market", "only you: market value")
check(Post:Reason("pick", opts) == "Nobody else is selling, so it's market value", "market reason")
check(Post:PriceOptions(424242, {}).pick == nil, "nothing to go on: no pick")
check(Post:Reason("median", {}) == "Priced by median" and Post:Reason("market", {}) == nil, "other reasons")

-- In the sell slot: the pick goes in, and Razzle says why.
local sell = AuctionHouseFrame.CommoditiesSellFrame
sell:SetItem({ itemID = 2589 })
H.runTimers()
check(sell.PriceInput.amount == 100, "the pick fills the price box")
check(H.plain(MarketForcesRazzleFrame.speech.text):find(
    "Selling Linen Cloth? 1s each. Matching the cheapest that counts", 1, true), "Razzle explains the pick")

-- The Sell tab marks it and says why under the methods.
local frame = MarketForcesRazzleFrame
frame.tabs[3]:Click()
Broker:SelectSellItem(2589)
check(H.plain(frame.sellMethodRows[1].label.text) == "> Razzle's pick", "pick marked in use")
check(H.plain(frame.sellBreakdown[1].text):find("^Matching the cheapest that counts"), "reason under the methods")

-- Picking it from the tab or the slash command.
H.slash("pricing market")
check(Post:Method() == "market", "/mf pricing market")
frame.sellMethodRows[1]:Click()
check(Post:Method() == "pick" and H.plain(frame.speech.text):find("^Pricing by Razzle's pick from now on"),
    "picked again on the tab")
Post.db.global.method = "nonsense"
check(Post:Method() == "pick", "an unknown saved method means the pick")

H.finish("pick")
