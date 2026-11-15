-- Flip module: is an item worth buying cheap and relisting? And Razzle's Flips tab.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
local Flip = MF:GetModule("Flip")
local Prices = MF:GetModule("Prices")
local Broker = MF:GetModule("Broker")
check(Flip and Flip:IsEnabled(), "Flip module loads and is on")

-- Prices keeps the cheapest listings as a ladder, up to the first step at
-- or above market value, same prices merged.
local flat, more = Prices.Ladder({ { 300, 20 }, { 40, 5 }, { 60, 4 }, { 60, 6 }, { 320, 50 } }, 158, 12)
check(table.concat(flat, ",") == "40,5,60,10,300,20" and not more, "ladder stops at the first step over market")
flat, more = Prices.Ladder({ { 10, 1 }, { 20, 1 }, { 30, 1 }, { 40, 1 } }, 100, 2)
check(table.concat(flat, ",") == "10,1,20,1" and more, "ladder cut short says so")

local opts = Flip.db.global

-- The best flip: buy the 40c and 60c steps, relist under market at 1s.
local plan = Flip.Analyze({ market = 158, ladder = { { 40, 5 }, { 60, 10 }, { 300, 20 } } }, opts)
check(plan and plan.units == 15 and plan.maxPrice == 60 and plan.resale == 100, "buys the cheap steps, relists at 1s")
check(plan.net == 95 and plan.profit == 95 * 15 - 800, "profit after the 5% cut")
check(plan.wall == 300, "knows what's left after buying")

-- Relisting undercuts the next listing when that's below market.
plan = Flip.Analyze({ market = 50000, ladder = { { 10000, 4 }, { 30000, 2 }, { 60000, 9 } } }, opts)
check(plan and plan.units == 6 and plan.resale == 50000, "buys both steps when relisting at market pays")
plan = Flip.Analyze({ market = 50000, ladder = { { 10000, 4 }, { 45000, 2 }, { 60000, 9 } } }, opts)
check(plan and plan.units == 4 and plan.resale == 44900, "undercuts the 45s step by a silver instead of buying it")

-- No flip: nothing cheap, margin too thin, no market, nothing listed.
check(select(2, Flip.Analyze({ market = 1000, ladder = { { 1000, 5 } } }, opts)) == "nothingcheap", "nothing cheap")
check(select(2, Flip.Analyze({ market = 98, ladder = { { 95, 1 }, { 100, 9 } } }, opts)) == "thin",
    "under a silver to sell: too thin")
check(select(2, Flip.Analyze({ market = 1000, ladder = { { 950, 1 }, { 1100, 9 } } }, opts)) == "thin",
    "5% under market doesn't cover the cut")
check(select(2, Flip.Analyze({ ladder = {} }, opts)) == "nomarket", "no market value")
check(select(2, Flip.Analyze({ market = 100, ladder = {} }, opts)) == "nolistings", "nothing listed")

-- A ladder cut short can't plan past its last step.
plan = Flip.Analyze({ market = 50000, ladderMore = true, ladder = { { 10000, 4 }, { 20000, 2 } } }, opts)
check(plan and plan.units == 4 and plan.resale == 19900, "cut-short ladder stops before its last step")

-- From a real scan.
H.vendorPrices = { [2589] = 13 }
H.itemNames[9002] = "Lead Band"
H.auctions = {
    { itemID = 2589, count = 5, buyout = 200 },     -- linen: 5 at 40c
    { itemID = 2589, count = 10, buyout = 600 },    -- 10 at 60c
    { itemID = 2589, count = 20, buyout = 6000 },   -- 20 at 3s
    { itemID = 2589, count = 50, buyout = 16000 },  -- 50 at 3s 20c
    { itemID = 2770, count = 10, buyout = 10000 },  -- ore: all at 1s, no flip
    { itemID = 9002, count = 10, buyout = 100000 }, -- lead band: 10 at 1g
    { itemID = 9002, count = 30, buyout = 1500000 },-- 30 at 5g
}
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
H.closeAuctionHouse()

local p = Prices:GetPrice(2589)
check(p.market == 158 and #p.ladder == 3 and p.ladder[3][1] == 300, "linen's ladder saved with the scan")

local text, linen = Flip:Advise("linen cloth")
text = H.plain(text)
check(linen and linen.itemID == 2589, "finds an item by name")
check(text:find("Linen Cloth: flip it, boss!", 1, true), "says flip it")
check(text:find("Buy 15 at up to 60c each (8s in all).", 1, true), "how many and up to what price")
check(text:find("Relist at 1s each (worth about 1s 58c).", 1, true), "relist price")
check(text:find("Profit about 6s 25c after the house's 5% cut.", 1, true), "profit")
check(text:find("Deposit about 59c, lost only if they don't sell.", 1, true), "deposit estimate from vendor price")
check(text:find("only 1 day of history", 1, true), "warns about short history")
check(select(2, Flip:Advise("linen")).itemID == 2589, "partial names work")
check(select(2, Flip:Advise("2589")).itemID == 2589, "item IDs work")
check(H.plain(Flip:Advise("Copper Ore")):find("No flip here"), "no flip when nothing's cheap")
check(Flip:Advise("Bogus Widget"):find("Never heard of \"Bogus Widget\""), "unknown names")
check(Flip:Advise(""):find("Type an item's name"), "empty box")

-- Price data saved before ladders existed asks for a fresh scan.
local saved = Prices:ItemsFor()[2589].b
Prices:ItemsFor()[2589].b = nil
check(Flip:Advise("linen"):find("Run a fresh scan"), "old data without a ladder asks for a scan")
Prices:ItemsFor()[2589].b = saved

-- At the auction house Blizzard's deposit calculator is used.
C_AuctionHouse.CalculateCommodityDeposit = function(itemID, duration, units)
    return itemID == 2589 and duration == 2 and units * 7 or nil
end
H.openAuctionHouse()
check(H.plain(Flip:Advise("linen")):find("Deposit about 1s 5c", 1, true), "Blizzard's deposit at the AH")
H.closeAuctionHouse()

-- Old listings get a warning.
H.advance(2 * 60 * 60)
check(H.plain(Flip:Advise("linen")):find("These listings are 2 hours old", 1, true), "stale listings warning")

-- Best flips: big enough ones only, most profit first.
local picks = Flip:FindFlips()
check(#picks == 1 and picks[1].itemID == 9002, "small flips stay off the best-flips list")
check(H.plain(Flip.PickLine(picks[1])) == "Lead Band  buy 10 to 1g, sell 1g 66s: +5g 77s", "pick line")

-- /mf flip prints the advice.
H.clearChat()
H.slash("flip Linen Cloth")
check(H.chatHas("Linen Cloth: flip it") and H.chatHas("Buy 15 at up to 60c"), "/mf flip prints the advice")

-- Razzle's Flips tab.
H.slash("razzle")
local frame = MarketForcesRazzleFrame
check(frame.pages.Bargains.shown and not frame.pages.Flips.shown, "opens on the Bargains tab")
frame.tabs[2]:Click()
check(frame.pages.Flips.shown and not frame.pages.Bargains.shown and not frame.tabs[2].enabled,
    "Flips tab switches pages")
check(H.plain(frame.flipLines[1].text) == "Lead Band  buy 10 to 1g, sell 1g 66s: +5g 77s", "best flips listed")
check(not frame.flipShow.shown, "no AH button before a check")
frame.flipBox:SetText("Linen Cloth")
frame.flipBox.scripts.OnEnterPressed(frame.flipBox)
check(H.plain(frame.flipAnswer.text):find("Buy 15 at up to 60c"), "Enter checks the flip")
check(frame.flipShow.shown and frame.flipShow.itemID == 2589, "AH button offered for a flip")
frame.flipBox:SetText("Copper Ore")
frame.flipBox.scripts.OnEnterPressed(frame.flipBox)
check(not frame.flipShow.shown, "no AH button without a flip")
frame.flipRows[1]:Click()
check(frame.flipBox.text == "Lead Band" and H.plain(frame.flipAnswer.text):find("Lead Band: flip it"),
    "clicking a best flip checks it")

-- The button opens the buy view at the AH (only shows it; nothing bought).
H.commodities = { [9002] = true }
H.openAuctionHouse()
check(Broker.tab == "Flips" and frame.pages.Flips.shown, "tab stays put when docking")
local replicateBefore = H.replicateCalls
frame.flipShow:Click()
check(H.selected and H.selected.itemKey.itemID == 9002 and H.selected.minPrice == 10000,
    "Show me at the AH opens the buy view")
check(H.replicateCalls == replicateBefore, "no scan, no buy")
frame.tabs[1]:Click()
check(frame.pages.Bargains.shown and not frame.pages.Flips.shown, "back to Bargains")
H.closeAuctionHouse()

-- Flip off.
H.slash("disable flip")
H.clearChat()
H.slash("flip linen")
check(H.chatHas("Flip advice is off"), "/mf flip explains it's off")
H.slash("razzle")
frame.tabs[2]:Click()
check(H.plain(frame.flipLines[1].text) == "Flip advice is off.", "Flips tab says it's off")

H.finish("flip")
