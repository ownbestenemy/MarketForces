-- Post module: shift-click a bag item at the AH to put it up for sale.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
-- Market value here; Razzle's pick has its own tests (pick_test.lua).
MF:GetModule("Post").db.global.method = "market"
local Post = MF:GetModule("Post")

-- Quantity: all you hold, unless the market holds less (at least a stack).
local SQ = Post.SuggestQuantity
check(SQ(24, 100, 20) == 24, "all of it when the market's deep")
local q, capped = SQ(200, 50, 20)
check(q == 50 and capped, "capped at what's listed")
check(SQ(30, 5, 20) == 20, "at least a full stack")
check(SQ(0, 5, 20) == 1, "nothing owned: 1")

-- History: linen 1s 58c market, 85 listed; ore 10s, 10 listed.
H.auctions = {
    { itemID = 2589, count = 5, buyout = 200 },
    { itemID = 2589, count = 10, buyout = 600 },
    { itemID = 2589, count = 20, buyout = 6000 },
    { itemID = 2589, count = 50, buyout = 16000 },
    { itemID = 2770, count = 10, buyout = 100000 },
}
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()

H.commodities = { [2589] = true, [2770] = true }
H.bags = { [0] = {
    { itemID = 9002, stackCount = 1, isBound = true },
    { itemID = 2589, stackCount = 20 },
    { itemID = 2770, stackCount = 20 },
}, [1] = {
    { itemID = 2589, stackCount = 4 },
    { itemID = 2770, stackCount = 15 },
} }
H.itemNames[9002] = "Lead Band"
local window = AuctionHouseFrame
local sell = window.CommoditiesSellFrame
local razzle = MarketForcesRazzleFrame
local linen = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r"

-- Shift-click linen: sell slot, market price, all 24, 24 hours.
H.shiftDown = true
H.blizzardDefaultPrice = 99999
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(H.postItemSet and H.postItemSet.bag == 0 and H.postItemSet.slot == 2, "item goes in the sell slot")
check(H.cvars.auctionHouseDurationDropdown == 2, "24 hours set as Blizzard's default")
H.runTimers()
check(sell.PriceInput.amount == 158, "price filled with market value, copper kept")
check(sell.QuantityInput.quantity == 24, "quantity: all 24 in your bags")
check(sell.Duration.duration == 2, "duration dropdown set to 24 hours")
check(H.plain(razzle.speech.text) == "Putting up 24 Linen Cloth at 1s 58c each for 24 hours. "
    .. "Check it and click Post when you're happy.", "Razzle says what's set up")

-- No location from Blizzard: found by item ID. More than the market holds: capped.
sell.QuantityInput.quantity = nil
HandleModifiedItemClick("|cffffffff|Hitem:2770::::::::60:::::|h[Copper Ore]|h|r")
H.runTimers()
check(H.postItemSet.bag == 0 and H.postItemSet.slot == 3, "found in the bags by item ID")
check(sell.QuantityInput.quantity == 10, "capped at what the market holds")
check(H.plain(razzle.speech.text):find("You've got 35, but the market only holds about 10", 1, true),
    "Razzle explains the cap")

-- Another pick before the next frame keeps its own numbers.
sell.QuantityInput.quantity = nil
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
sell:SetItem({ itemID = 2770 })
H.runTimers()
check(sell.QuantityInput.quantity == nil, "a newer pick doesn't get the old quantity")

-- Bound items aren't sold.
H.postItemSet = nil
local band = "|cffffffff|Hitem:9002::::::::60:::::|h[Lead Band]|h|r"
HandleModifiedItemClick(band, ItemLocation:CreateFromBagAndSlot(0, 1))
check(not H.postItemSet and H.plain(razzle.speech.text):find("Can't sell Lead Band"), "bound: not put up")

-- Shift-click while typing goes to the box, not the sell slot.
razzle.flipBox.focus = true
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(not H.postItemSet and razzle.flipBox.text:find("item:2589", 1, true), "Razzle's box gets the link instead")
razzle.flipBox.focus = false
ChatEdit_GetActiveWindow = function() return {} end
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(not H.postItemSet, "chat box open: link goes to chat")
ChatEdit_GetActiveWindow = nil

-- Plain (non-shift) modified clicks, or /mf shiftsell off: nothing.
H.shiftDown = false
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(not H.postItemSet, "ctrl-click etc. ignored")
H.shiftDown = true
H.slash("shiftsell")
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(not H.postItemSet, "/mf shiftsell turns it off")
H.slash("shiftsell")

-- /mf duration 48.
H.slash("duration 48")
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
H.runTimers()
check(sell.Duration.duration == 3 and H.cvars.auctionHouseDurationDropdown == 3, "48 hours when chosen")
check(H.plain(razzle.speech.text):find("for 48 hours", 1, true), "Razzle says 48 hours")
H.slash("duration 24")

-- Sell slot refused: Razzle says to drag it in.
H.setPostItemFails = true
H.postItemSet = nil
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(H.plain(razzle.speech.text):find("Drag Linen Cloth in yourself"), "fallback when the slot can't be set")
H.setPostItemFails = false

-- Declined quietly (e.g. item data not loaded): no claims, old item untouched.
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
H.runTimers()
sell.QuantityInput.quantity = 7
H.setPostItemDeclines = true
HandleModifiedItemClick("|cffffffff|Hitem:2770::::::::60:::::|h[Copper Ore]|h|r")
H.runTimers()
check(sell.QuantityInput.quantity == 7, "declined pick doesn't change the item in the slot")
check(H.plain(razzle.speech.text):find("didn't take Copper Ore just now"), "Razzle says it didn't take")
H.setPostItemDeclines = false

-- The client's own duration names (WoW: Forever's dropdown: 2, 8, 24 hours).
AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE = "2 Hours", "8 Hours", "24 Hours"
H.slash("duration 24")
check(MF.Post.db.global.duration == 3 and H.chatHas("Razzle will list for 24 hours"),
    "/mf duration uses the client's hours")
H.slash("duration 12")
check(MF.Post.db.global.duration == 3 and H.chatHas("Use /mf duration 2, 8 or 24"), "unknown hours explained")
H.slash("duration 8")
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(H.plain(razzle.speech.text):find("for 8 hours.", 1, true), "Razzle names the dropdown's duration")
-- The dropdown lands on another duration than Razzle's: Razzle says what it shows.
local realGet = sell.Duration.GetDuration
sell.Duration.GetDuration = function() return 1 end
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
H.runTimers()
check(H.plain(razzle.speech.text):find("for 2 hours.", 1, true), "Razzle reads the duration actually selected")
sell.Duration.GetDuration = realGet

-- You pick another duration in Blizzard's dropdown afterwards: Razzle keeps up.
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
H.runTimers()
check(H.plain(razzle.speech.text):find("for 8 hours.", 1, true), "starts at 8 hours")
sell.Duration.duration = 3 -- the player's choice in the dropdown
sell:OnDurationUpdated()
check(H.plain(razzle.speech.text):find("Putting up 24 Linen Cloth at 1s 58c each for 24 hours.", 1, true),
    "Razzle follows the dropdown live")
H.chat = {}
local before = razzle.speech.text
sell:OnDurationUpdated()
check(razzle.speech.text == before, "no change, nothing said again")
-- Another item in the slot since: the old line isn't brought back.
sell:SetItem({ itemID = 2770 })
razzle.speech:SetText("something else")
sell.Duration.duration = 1
sell:OnDurationUpdated()
check(razzle.speech.text == "something else", "a newer item's slot isn't talked over")

-- Away from the AH: nothing.
H.closeAuctionHouse()
H.postItemSet = nil
HandleModifiedItemClick(linen, ItemLocation:CreateFromBagAndSlot(0, 2))
check(not H.postItemSet, "AH closed: shift-click is left alone")

H.finish("sell")
