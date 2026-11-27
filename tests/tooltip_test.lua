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
check(lines[4] == "Razzle's read = Low confidence (1 day of history)", "trend and confidence line")
check(lines[5] == "Razzle says = Auction it (about 2s 37c after the AH cut)", "advice line")
check(#H.showItemTooltip(424242) == 0, "unscanned item gets no lines")

H.slash("tooltip")
check(#H.showItemTooltip(2589) == 0, "/mf tooltip turns lines off")
H.slash("tooltip")
check(#H.showItemTooltip(2589) == 5, "/mf tooltip turns them back on")

H.slash("disable tooltip")
check(#H.showItemTooltip(2589) == 0, "disabled module adds nothing")
H.slash("enable tooltip")
H.slash("disable prices")
check(#H.showItemTooltip(2589) == 0, "no lines when Prices is off")

-- Razzle's advice, case by case.
local A = Tooltip.Advice
local function says(p, vendor)
    local v, why = A(p, vendor, 0.7)
    return v and H.plain(v .. " (" .. why .. ")")
end
check(says({ market = 1000, minBuyout = 600 }, 0) == "Buy it (40% under market)", "buy a bargain")
check(says({ market = 1000, minBuyout = 900 }, 950) == "Buy it (listed below vendor price)", "buy to vendor")
check(says({ market = 1000, minBuyout = 1000 }, 960) == "Vendor it (the auction house pays no better)",
    "vendor when the AH cut eats the margin")
check(says({ market = 1000, minBuyout = 1000 }, 0) == "Auction it (about 9s 50c after the AH cut)", "auction it")
check(says(nil, 25) == "Vendor it (no auction prices yet)", "vendor with no AH data")
check(says(nil, 0) == nil, "nothing to say about an unsellable, unscanned item")
local function saysBound(p, vendor)
    local v, why = A(p, vendor, 0.7, true)
    return v and H.plain(v .. " (" .. why .. ")")
end
check(saysBound({ market = 1000, minBuyout = 1000 }, 50) == "Vendor it (yours is bound, so it can't be auctioned)",
    "bound copy: vendor, never auction")
check(saysBound({ market = 1000, minBuyout = 300 }, 0) == nil, "bound copy: no buy or auction advice")

-- Vendor-only item gets just the advice line.
H.slash("enable prices")
H.vendorPrices = { [7777] = 30 }
local vendorOnly = H.showItemTooltip(7777)
check(#vendorOnly == 1 and vendorOnly[1] == "Razzle says = Vendor it (no auction prices yet)", "vendor-only tooltip")

-- A bound copy of a scanned item never hears "Auction it".
local boundLines = H.showItemTooltip(2589, { bound = true })
check(#boundLines == 4, "bound copy: prices shown, no auction advice (tooltip data)")
H.vendorPrices[2589] = 5
boundLines = H.showItemTooltip(2589, { bound = true })
check(boundLines[5] == "Razzle says = Vendor it (yours is bound, so it can't be auctioned)",
    "bound copy with vendor price: vendor it")
boundLines = H.showItemTooltip(2589, { boundText = true })
check(boundLines[5] == "Razzle says = Vendor it (yours is bound, so it can't be auctioned)",
    "bound copy found from the tooltip's text lines")
H.vendorPrices[2589] = nil

-- /mf advice turns the line off.
H.slash("advice")
check(#H.showItemTooltip(2589) == 4 and #H.showItemTooltip(7777) == 0, "/mf advice hides the advice")
H.slash("advice")

-- /mf read turns the trend and confidence line off.
H.slash("read")
check(#H.showItemTooltip(2589) == 4, "/mf read hides the read line")
H.slash("read")

H.finish("tooltip")
