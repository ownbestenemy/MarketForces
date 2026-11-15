-- Scan button on a client using the classic AuctionFrame window.
local H = dofile("tests/harness.lua")
local check = H.check

H.windowName = "AuctionFrame"
local MF = H.startAddon()
local Scan = MF:GetModule("Scan")

H.openAuctionHouse()
local button = MarketForcesScanButton
check(button ~= nil and button.parent == AuctionFrame, "button attached to AuctionFrame")
check(Scan:IsAuctionHouseOpen(), "open state read from AuctionFrame")
H.closeAuctionHouse()
check(not Scan:IsAuctionHouseOpen(), "closed state read from AuctionFrame")

H.finish("scan (classic window)")
