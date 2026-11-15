-- Scan module: one full scan per click, cooldown, reading, neutral AH.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
local Scan = MF:GetModule("Scan")
check(Scan and Scan:IsEnabled(), "Scan module loads and is on")

local snapshots = {}
local listener = {}
function listener.MF_SCAN_COMPLETE(_, _, snapshot) snapshots[#snapshots + 1] = snapshot end
MF:RegisterMessage("MF_SCAN_COMPLETE", listener)

-- Nothing happens until the player asks.
H.openAuctionHouse()
check(H.replicateCalls == 0, "opening the AH does not scan")
check(MarketForcesScanButton and MarketForcesScanButton.text == "Full Scan", "Full Scan button added to the AH")

-- Scanning needs the AH open.
H.closeAuctionHouse()
H.clearChat()
H.slash("scan")
check(H.replicateCalls == 0 and H.chatHas("Open the auction house first"), "/mf scan refuses with AH closed")

-- A click starts one scan.
H.auctions = {
    { itemID = 2589, count = 20, buyout = 2000 },  -- linen, 100c each
    { itemID = 2589, count = 10, buyout = 800 },   -- linen, 80c each
    { itemID = 2589, count = 5 },                  -- bid-only
    { itemID = 2770, count = 1, buyout = 1500 },   -- copper ore
}
H.openAuctionHouse()
MarketForcesScanButton:Click()
check(H.replicateCalls == 1, "clicking Full Scan sends one replicate request")
check(Scan.state == "waiting" and not MarketForcesScanButton.enabled, "button disabled while waiting")
MarketForcesScanButton:Click()
check(H.replicateCalls == 1, "a second click during a scan does nothing")

H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
check(Scan.state == "idle" and #snapshots == 1, "scan finishes and sends MF_SCAN_COMPLETE")
local snap = snapshots[1]
check(snap.key == "US-RP PvP-Horde", "snapshot keyed by region-ruleset-faction")
check(snap.auctions == 4, "every auction counted")
local linen = snap.items[2589]
check(linen.quantity == 35 and linen.auctions == 3, "linen quantity and listings")
check(linen.minBuyout == 80, "minimum buyout is per unit")
check(#linen.listings == 2, "bid-only listings left out of buyout listings")
check(snap.items[2770].minBuyout == 1500, "single item buyout")
check(Scan.db.ah.lastCount == 4 and Scan.db.ah.lastScan == H.now, "last scan saved for this AH")
check(MarketForcesScanButton.enabled and MarketForcesScanButton.text == "Full Scan", "button ready again")

-- Late or repeated server events don't start anything.
H.fire("REPLICATE_ITEM_LIST_UPDATE")
check(#snapshots == 1, "stray REPLICATE_ITEM_LIST_UPDATE ignored")

-- Cooldown.
H.clearChat()
MarketForcesScanButton:Click()
check(H.replicateCalls == 1 and H.chatHas("won't take another full scan for 15m"), "cooldown blocks a second scan")
H.clearChat()
H.slash("status")
check(H.chatHas("last scanned 0s ago, 4 auctions") and H.chatHas("Next full scan allowed in"), "/mf status")
H.advance(15 * 60)

-- Big scans are read across frames.
H.auctions = {}
for i = 1, 5000 do H.auctions[i] = { itemID = 1000 + (i % 7), count = 1, buyout = i } end
H.slash("scan")
check(H.replicateCalls == 2, "/mf scan starts a scan after the cooldown")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
check(Scan.state == "reading" and #snapshots == 1, "large scan reads in chunks")
H.runTimers()
check(#snapshots == 2 and snapshots[2].auctions == 5000, "large scan completes")

-- Closing the AH mid-scan stops it.
H.advance(15 * 60)
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.clearChat()
H.closeAuctionHouse()
H.runTimers()
check(Scan.state == "idle" and #snapshots == 2, "closing the AH aborts the scan")
check(H.chatHas("auction house closed"), "abort explained")

-- Server never answers.
H.advance(15 * 60)
H.openAuctionHouse()
H.slash("scan")
H.clearChat()
H.advance(91)
check(Scan.state == "idle" and H.chatHas("didn't answer"), "timeout when the server never answers")

-- Goblin auction house.
H.advance(15 * 60)
H.closeAuctionHouse()
H.npcFaction = "Neutral"
H.auctions = { { itemID = 2589, count = 1, buyout = 50 } }
H.openAuctionHouse()
check(MF.db.ahKey == "US-RP PvP-Neutral", "neutral auction house detected")
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
check(snapshots[3].key == "US-RP PvP-Neutral", "neutral scan keyed separately")
check(MarketForcesDB.auctionHouses["US-RP PvP-Horde"].Scan.lastCount == 5000, "faction AH data untouched")

-- Turning the module off hides the button and blocks scans.
H.slash("disable scan")
check(not MarketForcesScanButton.shown, "button hidden when Scan is off")
H.clearChat()
H.slash("scan")
check(H.chatHas("Scan module is off"), "/mf scan explains the module is off")

-- A client without full scans.
H.slash("enable scan")
C_AuctionHouse.ReplicateItems = nil
local ok, reason = Scan:Start()
check(not ok and reason:find("doesn't offer"), "missing API reported, not an error")

H.finish("scan")
