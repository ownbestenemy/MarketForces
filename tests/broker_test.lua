-- Broker module: Razzle's window, greetings, bargains and price checks.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
local Broker = MF:GetModule("Broker")
check(Broker and Broker:IsEnabled(), "Broker module loads and is on")

-- Greetings.
local G = Broker.Greeting
check(G({ atAuctionHouse = true, scanned = false, deals = 0 }):find("haven't scouted"), "first visit greeting")
check(G({ atAuctionHouse = true, scanned = true, age = 600, deals = 1 }):find("10m 00s old. 1 bargain on"),
    "recent scan greeting")
check(G({ atAuctionHouse = true, scanned = true, age = 2 * 86400, deals = 0 }):find("Been a while"),
    "stale data greeting")
check(G({ atAuctionHouse = false, scanned = true, age = 5, deals = 0 }):find("What're we pricing"),
    "away from the AH greeting")
check(G({ justScanned = 500, deals = 3 }):find("500 auctions. I found 3 bargains"), "after a scan")

-- Docks beside the AH when it opens.
H.openAuctionHouse()
local frame = MarketForcesRazzleFrame
check(frame and frame.shown and Broker.docked, "window docks when the AH opens")
check(frame.points[1][2] == AuctionHouseFrame, "anchored to the AH window")
check(frame.speech.text:find("haven't scouted"), "first-visit greeting shown")

-- Scan: linen has a cheap listing, ore doesn't.
H.auctions = {
    { itemID = 2589, count = 1, buyout = 400 },     -- linen at 4s
    { itemID = 2589, count = 9, buyout = 9000 },    -- linen at 10s
    { itemID = 2770, count = 10, buyout = 10000 },  -- ore at 10s
}
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
-- market for linen: cheapest 30% of 10 units = 3 units: 4s + 10s + 10s -> 8s; 4s <= 0.7 * 8s
local deals = Broker:FindDeals()
check(#deals == 1 and deals[1].itemID == 2589, "cheap linen found as a bargain")
check(H.plain(Broker.DealLine(deals[1])) == "Linen Cloth  4s, worth 8s (10 listed)", "bargain line")
check(deals[1].label == "|cffffffffLinen Cloth|r", "name in its quality colour")
check(frame.speech.text:find("3 auctions. I found 1 bargain worth"), "Razzle reports the scan")
check(H.plain(frame.dealLines[1].text):find("Linen Cloth"), "bargain listed in the window")

-- Price check box.
check(H.plain(Broker:Lookup("|cffffffff|Hitem:2770::::::::60:::::|h[Copper Ore]|h|r"))
    == "Copper Ore: worth about 10s. Cheapest now: 10s, 10 listed.", "price check by link")
check(Broker:Lookup("424242"):find("Never seen item #424242"), "price check for an unknown item")
check(Broker:Lookup("hello"):find("Shift%-click"), "price check with no item")
frame.box:SetText("2589")
frame.box.scripts.OnEnterPressed(frame.box)
check(H.plain(frame.answer.text):find("Linen Cloth: worth about 8s"), "pressing Enter answers")

-- The board: names load late, junk stays off, most coin saved comes first.
H.auctions = {
    { itemID = 2589, count = 1, buyout = 400 },     -- linen: saves 4s
    { itemID = 2589, count = 9, buyout = 9000 },
    { itemID = 9001, count = 1, buyout = 2 },       -- junk: 2c vs 4c, saves 2c
    { itemID = 9001, count = 9, buyout = 54 },
    { itemID = 9002, count = 1, buyout = 1000 },    -- unloaded item: 10s vs 70s, saves 60s
    { itemID = 9002, count = 9, buyout = 90000 },
}
H.itemNames[9001] = "Broken Fang"
H.advance(20 * 60)
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
deals = Broker:FindDeals()
check(#deals == 2 and deals[1].itemID == 9002 and deals[2].itemID == 2589,
    "sorted by coin saved; tiny savings left off")
check(deals[1].label == nil and H.itemRequests and H.itemRequests[9002], "unloaded name requested")
check(H.plain(frame.dealLines[1].text) == "Linen Cloth  4s, worth 8s (10 listed)",
    "rows still loading aren't shown as item #")
check(H.plain(frame.dealLines[2].text) == "Looking up 1 more...", "board says a row is loading")
check(frame.speech.text:find("I found 2 bargains"), "greeting counts the loading row")
local greeting = frame.speech.text
H.itemNames[9002] = "Lead Band"
H.itemIcons = { [9002] = 133345 }
H.fire("GET_ITEM_INFO_RECEIVED", 9002, true)
H.fire("GET_ITEM_INFO_RECEIVED", 2589, true)
H.advance(1)
check(H.plain(frame.dealLines[1].text) == "Lead Band  10s, worth 70s (10 listed)", "row appears once the name loads")
check(frame.dealLines[1].text:find("|T133345:14:14|t", 1, true), "row shows the item icon")
check(frame.dealRows[1].itemID == 9002, "row knows its item for the hover tooltip")
check(frame.speech.text == greeting, "name loading leaves Razzle's speech alone")

-- Closing the AH closes the docked window.
H.closeAuctionHouse()
check(not frame.shown and not Broker.docked, "docked window closes with the AH")

-- /mf razzle opens it anywhere and toggles.
H.slash("razzle")
check(frame.shown and not Broker.docked, "/mf razzle opens the free window")
check(frame.points[1][1] == "CENTER", "free window starts centered")
check(frame.speech.text:find("What're we pricing"), "away-from-AH greeting")
Broker.db.global.point = { "TOPLEFT", "TOPLEFT", 100, -100 }
H.slash("razzle")
check(not frame.shown, "/mf razzle closes it")
H.slash("razzle")
check(frame.points[1][1] == "TOPLEFT" and frame.points[1][4] == 100, "free window reopens where it was left")

-- Opening the AH while the free window is up docks it; closing leaves it hidden.
H.openAuctionHouse()
check(Broker.docked and frame.points[1][2] == AuctionHouseFrame, "free window docks at the AH")
H.closeAuctionHouse()

-- /mf dock turns docking off.
H.slash("dock")
H.openAuctionHouse()
check(not frame.shown, "no docking after /mf dock")
H.closeAuctionHouse()
H.slash("dock")

-- Switching to a goblin AH shows that house's numbers, not the faction's.
H.npcFaction = "Neutral"
H.openAuctionHouse()
check(Broker.docked and frame.speech.text:find("haven't scouted"), "neutral AH shows its own (empty) data")
check(H.plain(frame.dealLines[1].text) == "Nothing cheap enough to shout about.",
    "no faction bargains at the goblin AH")
H.closeAuctionHouse()
H.npcFaction = nil
H.openAuctionHouse()
check(H.plain(frame.dealLines[1].text):find("Lead Band") and H.plain(frame.dealLines[2].text):find("Linen Cloth"),
    "faction bargains back at the faction AH")
H.closeAuctionHouse()

-- A late-loading AH window closed before it appears: no stray window.
AuctionHouseFrame = nil
H.windowLoadsLate = true
H.windowName = "LateAuctionFrame"
H.fire("AUCTION_HOUSE_SHOW")
H.fire("AUCTION_HOUSE_CLOSED")
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame")
AuctionHouseFrame:Hide()
H.advance(1)
check(not frame.shown, "pending dock cancelled when the AH closes")
H.windowName = "AuctionHouseFrame"
H.windowLoadsLate = false

-- Module off.
H.slash("disable broker")
H.clearChat()
H.slash("razzle")
check(H.chatHas("Razzle is off"), "/mf razzle explains the module is off")
H.openAuctionHouse()
check(not frame.shown, "disabled Broker doesn't dock")

H.finish("broker")
