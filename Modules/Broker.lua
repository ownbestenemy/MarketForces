-- MarketForces Broker module: Razzle, the goblin broker of Razzle's Dazzles.
--
-- Razzle's window docks beside the auction house when you open it, and
-- /mf razzle opens it anywhere (movable, position saved). Razzle greets
-- you, says how fresh the prices are, lists bargains from the latest scan,
-- talks about items you put up for sale and looks up prices. Razzle only talks: every buy, post and cancel stays
-- with you and Blizzard's own buttons.
--
-- The logic (greetings, finding bargains, lookups) is kept apart from the
-- frames so it can be tested offline.
local _, MF = ...

local Util = MF.Util

local Broker = MF:NewModule("Broker", {
    global = {
        dockAtAuctionHouse = true, -- open beside the AH window
        dealRatio = 0.7,           -- a bargain is listed at or below 70% of market value
        minSavings = 100,          -- and saves at least this much per unit (1s), so junk stays off the board
        maxDeals = 8,
        point = nil,               -- saved position of the free window
    },
})
MF.Broker = Broker

Broker.PORTRAIT = "Interface\\Icons\\INV_Misc_Coin_02"
Broker.TITLE = "Razzle's Dazzles"

local DAY = 24 * 60 * 60

local function getItemInfo(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    return getInfo(itemID)
end

-- Item name, or a placeholder until the client has it cached.
function Broker.ItemName(itemID)
    return getItemInfo(itemID) or ("item #" .. itemID)
end

-- The item's name in its quality colour with its icon, ready for a font
-- string, or nil when the client hasn't loaded the item yet (in which case
-- we ask for it; GET_ITEM_INFO_RECEIVED says when it's there).
function Broker.ItemLabel(itemID)
    local name, _, quality, _, _, _, _, _, _, icon = getItemInfo(itemID)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local label = (color and color.hex) and (color.hex .. name .. "|r") or name
    if icon and icon ~= 0 and icon ~= "" then
        label = "|T" .. icon .. ":14:14|t " .. label
    end
    return label
end

-- Razzle's opening line. info: { scanned = bool, age = seconds since last
-- scan, deals = number, atAuctionHouse = bool, justScanned = auctions }.
function Broker.Greeting(info)
    if info.justScanned then
        return string.format("Fresh off the wire: %d auctions. I found %d %s worth a look.",
            info.justScanned, info.deals, info.deals == 1 and "bargain" or "bargains")
    end
    if not info.atAuctionHouse then
        if not info.scanned then
            return "Razzle's always open for business, but my books are empty. "
                .. "Swing by an auction house and run a scan."
        end
        return "Razzle's always open for business. What're we pricing today?"
    end
    if not info.scanned then
        return "Welcome to Razzle's Dazzles! I haven't scouted this market yet. "
            .. "Hit Full Scan and I'll tell you what's what."
    end
    if info.age >= DAY then
        return string.format("Been a while, boss! My numbers are %s old. A fresh scan would do us both good.",
            Util.FormatDuration(info.age))
    end
    return string.format("Back again? My numbers are %s old. %d %s on the board.",
        Util.FormatDuration(info.age), info.deals, info.deals == 1 and "bargain" or "bargains")
end

-- What Razzle says when you put an item in the sell slot.
function Broker.PostLine(itemID, suggestion, p, filled)
    local name = Broker.ItemName(itemID)
    if not suggestion then
        return "Selling " .. name .. "? I've got no steady price for it here yet. Price it by hand, "
            .. "and a scan or two will teach me."
    end
    local line = string.format("Selling %s? Market value's %s each.", name, Util.FormatMoney(suggestion))
    if p and p.minBuyout then
        line = line .. " Cheapest listed right now is " .. Util.FormatMoney(p.minBuyout) .. "."
    end
    if filled then
        line = line .. " I put my number in. Your call, boss: click Post when you're happy."
    end
    return line
end

-- Items listed well below market value at the current auction house, most
-- coin saved per unit first: { itemID, label, minBuyout, market, quantity,
-- ratio }. label is nil while the client is still loading the item's name
-- (it's requested; the board shows the row once it arrives).
function Broker:FindDeals()
    local prices = MF.Prices
    if not (prices and prices:IsEnabled()) then return {} end
    local ratio = self.db.global.dealRatio
    local minSavings = self.db.global.minSavings or 0
    local deals = {}
    for itemID in pairs(prices:ItemsFor()) do
        local p = prices:GetPrice(itemID)
        if p and p.market and p.minBuyout and p.market > 0 and p.minBuyout <= p.market * ratio
            and p.market - p.minBuyout >= minSavings then
            deals[#deals + 1] = {
                itemID = itemID, minBuyout = p.minBuyout, market = p.market,
                quantity = p.quantity, ratio = p.minBuyout / p.market,
            }
        end
    end
    table.sort(deals, function(a, b)
        local sa, sb = a.market - a.minBuyout, b.market - b.minBuyout
        if sa ~= sb then return sa > sb end
        return a.itemID < b.itemID
    end)
    local limit = self.db.global.maxDeals
    for i = #deals, limit + 1, -1 do deals[i] = nil end
    for _, deal in ipairs(deals) do deal.label = Broker.ItemLabel(deal.itemID) end
    return deals
end

-- One row on the board, e.g. "Lead Band  25s, worth 56s (6 listed)".
function Broker.DealLine(deal)
    return string.format("%s  %s, worth %s (%d listed)", deal.label or Broker.ItemName(deal.itemID),
        Util.FormatMoney(deal.minBuyout), Util.FormatMoney(deal.market), deal.quantity)
end

-- Razzle's answer for a typed item link or ID.
function Broker:Lookup(text)
    local prices = MF.Prices
    local itemID = prices and prices.ParseItemID(text)
    if not itemID then
        return "Shift-click an item into the box, or type its item ID, and I'll price it."
    end
    local p = prices:GetPrice(itemID)
    if not p then
        return "Never seen " .. Broker.ItemName(itemID) .. " at this house. Scan first, then ask again."
    end
    local market = p.market and Util.FormatMoney(p.market) or "no steady price yet"
    local cheapest = p.minBuyout and (Util.FormatMoney(p.minBuyout) .. ", " .. p.quantity .. " listed")
        or "none listed right now"
    return string.format("%s: worth about %s. Cheapest now: %s.", Broker.ItemName(itemID), market, cheapest)
end

function Broker:CurrentInfo(extra)
    local scan = MF.Scan
    local last = scan and scan.db and scan.db.ah and scan.db.ah.lastScan or 0
    local info = {
        scanned = last > 0,
        age = last > 0 and (time() - last) or 0,
        deals = #self:FindDeals(),
        atAuctionHouse = scan and scan:IsAuctionHouseOpen() or false,
    }
    if extra then for k, v in pairs(extra) do info[k] = v end end
    return info
end

-- Frames ------------------------------------------------------------------------

local function newText(parent, template, width)
    local text = parent:CreateFontString(nil, "OVERLAY", template)
    text:SetJustifyH("LEFT")
    if width then text:SetWidth(width) end
    if text.SetWordWrap then text:SetWordWrap(true) end
    return text
end

function Broker:CreateWindow()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "MarketForcesRazzleFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(320, 400)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) if not Broker.docked then frame:StartMoving() end end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        Broker.db.global.point = { point, relPoint, x, y }
    end)
    f:Hide()
    if f.TitleText then f.TitleText:SetText(self.TITLE) end
    if UISpecialFrames then table.insert(UISpecialFrames, "MarketForcesRazzleFrame") end -- Escape closes it

    local portrait = f:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(48, 48)
    portrait:SetPoint("TOPLEFT", 12, -32)
    portrait:SetTexture(self.PORTRAIT)

    f.speech = newText(f, "GameFontHighlight", 236)
    f.speech:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 8, 0)

    local dealsHeader = newText(f, "GameFontNormal")
    dealsHeader:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -40)
    dealsHeader:SetText("Bargains on the board")

    -- Each row is a button so hovering it shows the item's tooltip.
    f.dealLines, f.dealRows = {}, {}
    local previous = dealsHeader
    for i = 1, self.db.global.maxDeals do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(290, 16)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
        local line = newText(row, "GameFontHighlightSmall", 290)
        line:SetPoint("LEFT", row, "LEFT", 0, 0)
        if line.SetWordWrap then line:SetWordWrap(false) end
        row:SetScript("OnEnter", function(button)
            if button.itemID and GameTooltip then
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(button.itemID)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.dealLines[i], f.dealRows[i] = line, row
        previous = row
    end

    local lookupLabel = newText(f, "GameFontNormal")
    lookupLabel:SetPoint("BOTTOMLEFT", 14, 70)
    lookupLabel:SetText("Price check")

    local box = CreateFrame("EditBox", "MarketForcesRazzleLookup", f, "InputBoxTemplate")
    box:SetSize(280, 20)
    box:SetPoint("TOPLEFT", lookupLabel, "BOTTOMLEFT", 6, -4)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function(editBox)
        f.answer:SetText(Broker:Lookup(editBox:GetText()))
        editBox:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
    f.box = box

    f.answer = newText(f, "GameFontHighlightSmall", 290)
    f.answer:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -6)

    -- Shift-clicking an item while the box has focus puts its link in the box.
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if link and box:HasFocus() then box:SetText(link) end
        end)
    end

    self.frame = f
    return f
end

function Broker:Refresh(extra)
    local f = self.frame
    if not f then return end
    f.speech:SetText(self.Greeting(self:CurrentInfo(extra)))
    self:RefreshDeals()
end

-- Fills the board. Rows whose item names are still loading are skipped
-- until GET_ITEM_INFO_RECEIVED brings them in.
function Broker:RefreshDeals()
    local f = self.frame
    if not f then return end
    local deals = self:FindDeals()
    local shown, loading = {}, 0
    for _, deal in ipairs(deals) do
        if deal.label then shown[#shown + 1] = deal else loading = loading + 1 end
    end
    for i, line in ipairs(f.dealLines) do
        local deal = shown[i]
        f.dealRows[i].itemID = deal and deal.itemID
        if deal then
            line:SetText(self.DealLine(deal))
        elseif i == #shown + 1 and loading > 0 then
            line:SetText("|cff808080Looking up " .. loading .. " more...|r")
        elseif i == 1 then
            line:SetText("Nothing cheap enough to shout about.")
        else
            line:SetText("")
        end
    end
end

-- Beside the auction house window.
function Broker:Dock(window)
    local f = self:CreateWindow()
    self.docked = true
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, 0)
    self:Refresh()
    f:Show()
end

-- Free-standing, at the saved position.
function Broker:OpenFree()
    local f = self:CreateWindow()
    self.docked = false
    f:ClearAllPoints()
    local p = self.db.global.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    self:Refresh()
    f:Show()
end

function Broker:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:OpenFree()
    end
end

-- Events -----------------------------------------------------------------------------

function Broker:AUCTION_HOUSE_SHOW()
    self.ahOpen = true
    if not self.db.global.dockAtAuctionHouse then return end
    -- The window may finish loading a moment after the event. Each open gets
    -- a token; closing the AH or turning Broker off invalidates it.
    self.dockToken = (self.dockToken or 0) + 1
    local token = self.dockToken
    local tries = 0
    local function dock()
        if token ~= Broker.dockToken or not Broker.ahOpen or not Broker:IsEnabled() then return end
        local window = MF.Scan and MF.Scan.AuctionWindow and MF.Scan.AuctionWindow()
        if window then
            Broker:Dock(window)
        elseif tries < 10 then
            tries = tries + 1
            C_Timer.After(0.1, dock)
        end
    end
    dock()
end

function Broker:AUCTION_HOUSE_CLOSED()
    self.ahOpen = false
    self.dockToken = (self.dockToken or 0) + 1
    if self.docked and self.frame then
        self.frame:Hide()
        self.docked = false
    end
end

function Broker:MF_POST_ITEM_SELECTED(_, itemID, suggestion, p)
    if not (self.frame and self.frame:IsShown()) then return end
    local filled = suggestion and MF.Post and MF.Post.db.global.fillPrice
    self.frame.speech:SetText(self.PostLine(itemID, suggestion, p, filled))
end

-- An item the board was waiting on has loaded: refill the board once, a
-- moment later, since these arrive in bursts. Razzle's speech is left alone.
function Broker:GET_ITEM_INFO_RECEIVED()
    if self.namesPending or not (self.frame and self.frame:IsShown()) then return end
    self.namesPending = true
    C_Timer.After(0.2, function()
        Broker.namesPending = false
        if Broker:IsEnabled() and Broker.frame and Broker.frame:IsShown() then Broker:RefreshDeals() end
    end)
end

-- Faction and goblin auction houses keep separate prices: when the house
-- switches (possibly after we docked), show the new house's numbers.
function Broker:MF_AUCTION_HOUSE_CHANGED()
    if self.frame and self.frame:IsShown() then self:Refresh() end
end

-- Prices records each scan and then sends MF_PRICES_UPDATED, so refresh
-- then to show fresh bargains. (Scan saves its count before either message.)
function Broker:MF_PRICES_UPDATED()
    if self.frame and self.frame:IsShown() then
        local count = MF.Scan and MF.Scan.db.ah.lastCount or 0
        self:Refresh({ justScanned = count })
    end
end

function Broker:OnInitialize()
    MF:RegisterSlashCommand("razzle", "Open or close Razzle's window", function()
        if not Broker:IsEnabled() then
            MF:Print("Razzle is off. Turn the Broker module on with /mf enable broker.")
            return
        end
        Broker:Toggle()
    end)
    MF:RegisterSlashCommand("dock", "Toggle Razzle opening beside the auction house", function()
        Broker.db.global.dockAtAuctionHouse = not Broker.db.global.dockAtAuctionHouse
        MF:Print("Razzle", Broker.db.global.dockAtAuctionHouse and "will open beside the auction house"
            or "won't open with the auction house")
    end)
end

function Broker:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")
    self:RegisterMessage("MF_PRICES_UPDATED")
    self:RegisterMessage("MF_AUCTION_HOUSE_CHANGED")
    self:RegisterMessage("MF_POST_ITEM_SELECTED")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

function Broker:OnDisable()
    self.dockToken = (self.dockToken or 0) + 1
    if self.frame then self.frame:Hide() end
    self.docked = false
end
