-- Tooltip module: Razzle's lines on item tooltips.
local H = dofile("tests/harness.lua")
local check = H.check

local MF = H.startAddon()
local Tooltip = MF:GetModule("Tooltip")
check(Tooltip and Tooltip:IsEnabled(), "Tooltip module loads and is on")

check(#H.showItemTooltip(2589) == 0, "nothing added before any scan")

H.auctions = { { itemID = 2589, count = 10, buyout = 2500 } }
H.openAuctionHouse()
H.slash("scan")
H.fire("REPLICATE_ITEM_LIST_UPDATE")
H.runTimers()
H.closeAuctionHouse()

H.now = H.now + 2 * 3600
local lines = H.showItemTooltip(2589)
check(lines[1] == "Razzle's market value = 2s 50c", "market value line")
check(lines[2] == "Cheapest listed = 2s 50c (10)", "cheapest listing line")
check(lines[3] == "Last scanned = 2h ago", "last scanned line")
check(#H.showItemTooltip(424242) == 0, "unscanned item gets no lines")

H.slash("tooltip")
check(#H.showItemTooltip(2589) == 0, "/mf tooltip turns lines off")
H.slash("tooltip")
check(#H.showItemTooltip(2589) == 3, "/mf tooltip turns them back on")

H.slash("disable tooltip")
check(#H.showItemTooltip(2589) == 0, "disabled module adds nothing")
H.slash("enable tooltip")
H.slash("disable prices")
check(#H.showItemTooltip(2589) == 0, "no lines when Prices is off")

H.finish("tooltip")
