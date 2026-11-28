-- MarketForces Scan module.
--
-- Takes a full snapshot of the open auction house with
-- C_AuctionHouse.ReplicateItems(), the client's built-in "get all" query.
-- One click (the Full Scan button or /mf scan) starts one scan; nothing ever
-- starts a scan on its own. The server only allows a full scan every so
-- often, so we track the cooldown and say how long is left.
--
-- When the snapshot is read, Scan sends:
--   MF_SCAN_COMPLETE(snapshot)
--     snapshot.key       auction house key, e.g. "US-RP PvP-Horde"
--     snapshot.time      time() when the scan finished
--     snapshot.auctions  number of auctions read
--     snapshot.items     [itemID] = {
--         minBuyout = lowest buyout per unit (nil if every listing is bid-only),
--         otherMin  = lowest buyout per unit among other sellers' listings
--                     (nil if only you, or nobody, list one with a buyout),
--         quantity  = units listed,
--         auctions  = number of listings,
--         listings  = { {unitBuyout, count}, ... } for buyout listings,
--     }
-- The snapshot is not saved here; the Prices module turns it into history.
local _, MF = ...

local Util = MF.Util

local Scan = MF:NewModule("Scan", {
    global = {
        cooldown = 15 * 60, -- seconds the server makes us wait between full scans
        lastScan = 0,       -- time() of the last full scan request (account-wide)
        perFrame = 2000,    -- auctions read per frame, so big scans don't freeze the game
        forceGap = 60,      -- seconds between forced scans, so they can't be spammed
        lastForce = 0,      -- time() of the last forced scan request
    },
    ah = {
        lastScan = 0,       -- time() of the last completed scan of this auction house
        lastCount = 0,      -- auctions seen in it
    },
})
MF.Scan = Scan

local WAIT_TIMEOUT = 90 -- seconds to wait for the server before giving up

Scan.state = "idle" -- "idle" | "waiting" | "reading"

local function now()
    return time()
end

-- Which auction house is open: the faction AH, or "Neutral" for goblins.
local function currentHouse()
    if UnitExists and UnitExists("npc") then
        local npcFaction = UnitFactionGroup("npc")
        if npcFaction ~= "Alliance" and npcFaction ~= "Horde" then
            return "Neutral"
        end
    end
    return nil -- player's own faction
end

-- Trusts the window itself when it exists, so state stays right even if
-- events were missed while the module was off.
-- The Blizzard auction window: AuctionHouseFrame on the modern UI,
-- AuctionFrame on the classic one. Both load on demand, so this can be nil
-- until the auction house is first opened.
local function auctionWindow()
    return AuctionHouseFrame or AuctionFrame
end
Scan.AuctionWindow = auctionWindow

function Scan:IsAuctionHouseOpen()
    local window = auctionWindow()
    if window and window.IsShown then
        return window:IsShown() and true or false
    end
    return self.ahOpen == true
end

-- Seconds until a full scan is allowed again (0 when ready).
function Scan:CooldownRemaining()
    local remaining = (self.db.global.lastScan or 0) + self.db.global.cooldown - now()
    return remaining > 0 and remaining or 0
end

local formatDuration = Util.FormatDuration

-- Seconds until a forced scan is allowed again (0 when ready).
function Scan:ForceGapRemaining()
    local remaining = (self.db.global.lastForce or 0) + self.db.global.forceGap - now()
    return remaining > 0 and remaining or 0
end

-- Starts one full scan. Call this only from a click or a typed command.
-- force skips the 15 minute wait (the server may still say no), but forced
-- scans are limited to one per forceGap seconds.
-- Returns true if a scan started, or false and a reason.
function Scan:Start(force)
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        return false, "This client doesn't offer full auction house scans."
    end
    if not self:IsAuctionHouseOpen() then
        return false, "Open the auction house first."
    end
    if self.state ~= "idle" then
        return false, "A scan is already running."
    end
    if force then
        local gap = self:ForceGapRemaining()
        if gap > 0 then
            return false, "Easy, boss. You can force another scan in " .. formatDuration(gap) .. "."
        end
        self.db.global.lastForce = now()
    else
        local wait = self:CooldownRemaining()
        if wait > 0 then
            return false, "The auction house won't take another full scan for " .. formatDuration(wait)
                .. ". Shift-click Full Scan or type /mf scan force to try anyway."
        end
    end

    self.forced = force and self:CooldownRemaining() > 0 or false
    self.state = "waiting"
    self.scanID = (self.scanID or 0) + 1
    self.db.global.lastScan = now()
    self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_AuctionHouse.ReplicateItems()
    self:UpdateButton()
    self:SendMessage("MF_SCAN_STARTED", MF.db.ahKey)

    local id = self.scanID
    C_Timer.After(WAIT_TIMEOUT, function()
        if self.state == "waiting" and self.scanID == id then
            if self.forced then
                self:Abort("The auction house didn't answer. It's probably still on its own cooldown; "
                    .. "try again in a few minutes.")
            else
                self:Abort("The auction house didn't answer. Try again in a few minutes.")
            end
        end
    end)
    return true
end

function Scan:Abort(reason)
    if self.state == "idle" then return end
    self.state = "idle"
    self.scanID = (self.scanID or 0) + 1 -- stops any reading still queued
    self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    self:UpdateButton()
    if reason then self:Print(reason) end
    self:SendMessage("MF_SCAN_ABORTED", reason)
end

function Scan:REPLICATE_ITEM_LIST_UPDATE()
    if self.state ~= "waiting" then return end
    self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    self.state = "reading"
    self:UpdateButton()

    local total = C_AuctionHouse.GetNumReplicateItems()
    local snapshot = { key = MF.db.ahKey, auctions = 0, items = {} }
    local id = self.scanID
    local index = 0 -- replicate indices start at 0
    -- Your own listings don't count as competition (Post's undercut/match).
    local me = UnitName and UnitName("player")
    local function mine(owner, ownerFull)
        return me ~= nil and (owner == me or ownerFull == me)
    end

    local function step()
        if self.state ~= "reading" or self.scanID ~= id then return end
        local last = math.min(index + self.db.global.perFrame, total) - 1
        for i = index, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, ownerFull, _, itemID =
                C_AuctionHouse.GetReplicateItemInfo(i)
            if itemID then
                count = (count and count > 0) and count or 1
                local item = snapshot.items[itemID]
                if not item then
                    item = { quantity = 0, auctions = 0, listings = {} }
                    snapshot.items[itemID] = item
                end
                item.quantity = item.quantity + count
                item.auctions = item.auctions + 1
                if buyout and buyout > 0 then
                    local unit = math.floor(buyout / count)
                    item.listings[#item.listings + 1] = { unit, count }
                    if not item.minBuyout or unit < item.minBuyout then
                        item.minBuyout = unit
                    end
                    if not mine(owner, ownerFull) and (not item.otherMin or unit < item.otherMin) then
                        item.otherMin = unit
                    end
                end
                snapshot.auctions = snapshot.auctions + 1
            end
        end
        index = last + 1
        if index < total then
            C_Timer.After(0, step)
        else
            self:Finish(snapshot)
        end
    end
    step()
end

function Scan:Finish(snapshot)
    self.state = "idle"
    snapshot.time = now()
    self.db.ah.lastScan = snapshot.time
    self.db.ah.lastCount = snapshot.auctions
    self.lastSnapshot = snapshot
    self:UpdateButton()
    local itemCount = 0
    for _ in pairs(snapshot.items) do itemCount = itemCount + 1 end
    self:Printf("Scan done: %d auctions of %d different items.", snapshot.auctions, itemCount)
    self:SendMessage("MF_SCAN_COMPLETE", snapshot)
end

function Scan:Printf(fmt, ...)
    self:Print(string.format(fmt, ...))
end

-- Auction house window ------------------------------------------------------

function Scan:AUCTION_HOUSE_SHOW()
    self.ahOpen = true
    MF:InitAuctionHouseDB(currentHouse())
    self:CreateButton()
    self:UpdateButton()
end

function Scan:AUCTION_HOUSE_CLOSED()
    self.ahOpen = false
    if self.state ~= "idle" then
        self:Abort("Scan stopped because the auction house closed.")
    end
end

-- The window's UI addon may finish loading just after AUCTION_HOUSE_SHOW, so
-- if it isn't there yet we try again on the next few frames.
function Scan:CreateButton(attempt)
    if self.button then return end
    local window = auctionWindow()
    if not window then
        attempt = (attempt or 0) + 1
        if attempt <= 10 then
            C_Timer.After(0.1, function()
                if Scan.ahOpen then Scan:CreateButton(attempt) end
            end)
        else
            self:Debug("no auction window found; use /mf scan")
        end
        return
    end
    local button = CreateFrame("Button", "MarketForcesScanButton", window, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    -- Just below the window's bottom-right corner, clear of its tabs and art.
    button:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", -4, -2)
    if button.SetFrameStrata and window.GetFrameStrata then button:SetFrameStrata(window:GetFrameStrata()) end
    if button.SetFrameLevel and window.GetFrameLevel then button:SetFrameLevel(window:GetFrameLevel() + 10) end
    button:SetText("Full Scan")
    -- Shift-click forces a scan past the 15 minute wait.
    button:SetScript("OnClick", function()
        local ok, reason = Scan:Start(IsShiftKeyDown and IsShiftKeyDown() or false)
        if not ok then Scan:Print(reason) end
    end)
    self.button = button
    self:Debug("Full Scan button added to %s", window.GetName and window:GetName() or "auction window")
    self:UpdateButton()
end

function Scan:UpdateButton()
    local button = self.button
    if not button then return end
    if not self:IsEnabled() then
        button:Hide()
        return
    end
    button:Show()
    if self.state == "waiting" then
        button:SetText("Waiting...")
        button:Disable()
    elseif self.state == "reading" then
        button:SetText("Reading...")
        button:Disable()
    else
        button:SetText("Full Scan")
        button:Enable()
    end
end

-- Lifecycle -------------------------------------------------------------------

function Scan:OnInitialize()
    MF:RegisterSlashCommand("scan", "Full scan of the open auction house (/mf scan force skips the wait)",
        function(args)
        if not Scan:IsEnabled() then
            Scan:Print("The Scan module is off. Turn it on with /mf enable scan.")
            return
        end
        local force = Util.SplitFirstWord(args):lower() == "force"
        local ok, reason = Scan:Start(force)
        if not ok then Scan:Print(reason) end
    end)
    MF:RegisterSlashCommand("status", "When this auction house was last scanned", function()
        local ah = Scan.db.ah
        if (ah.lastScan or 0) == 0 then
            MF:Printf("%s has not been scanned yet.", MF.db.ahKey or "This auction house")
        else
            MF:Printf("%s: last scanned %s ago, %d auctions.", MF.db.ahKey,
                formatDuration(now() - ah.lastScan), ah.lastCount or 0)
        end
        local wait = Scan:CooldownRemaining()
        if wait > 0 then
            MF:Print("Next full scan allowed in " .. formatDuration(wait) .. ".")
        else
            MF:Print("A full scan is allowed now.")
        end
    end)
end

function Scan:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    -- Turned on while the auction house is already open: catch up.
    if self:IsAuctionHouseOpen() then
        self:AUCTION_HOUSE_SHOW()
    else
        self.ahOpen = false
    end
    self:UpdateButton()
end

function Scan:OnDisable()
    self:Abort()
    self.ahOpen = false
    self.enabled = false
    self:UpdateButton()
end

Scan.CurrentHouse = currentHouse
