-- MarketForces Broker module: Razzle, the goblin broker of Razzle's Dazzles.
--
-- Razzle's window docks beside the auction house when you open it, and
-- /mf razzle opens it anywhere (movable, position saved). Razzle greets
-- you, says how fresh the prices are, lists bargains from the latest scan,
-- talks about items you put up for sale and looks up prices. The Flips tab
-- says whether an item is worth buying cheap and relisting (see Flip.lua).
-- The Sell tab puts your bags, the competing listings and your own past
-- results side by side (see BrokerSell.lua).
-- Razzle only talks: every buy, post and cancel stays with you and
-- Blizzard's own buttons.
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

-- A row button that shows the item's tooltip on hover.
local function newItemRow(parent, hint, width)
    width = width or 290
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, 16)
    local line = newText(row, "GameFontHighlightSmall", width)
    line:SetPoint("LEFT", row, "LEFT", 0, 0)
    if line.SetWordWrap then line:SetWordWrap(false) end
    row:SetScript("OnEnter", function(button)
        if button.itemID and GameTooltip then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(button.itemID)
            GameTooltip:AddLine(hint, 0.5, 0.8, 1)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row, line
end
Broker.NewText, Broker.NewItemRow = newText, newItemRow

-- Shift-clicking an item puts its link in whichever of Razzle's boxes has
-- focus. Blizzard's link path differs between clients (ChatEdit_InsertLink,
-- ChatFrameUtil.InsertLink, HandleModifiedItemClick), so all of them that
-- exist are hooked, once.
local linkBoxes = {}
local function insertLink(link)
    if type(link) ~= "string" then return end
    for _, box in ipairs(linkBoxes) do
        if box:HasFocus() then
            box:SetText(link)
            return
        end
    end
end

local linkHooked
local function hookLinkInsert()
    if linkHooked or not hooksecurefunc then return end
    linkHooked = true
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if (IsModifiedClick and IsModifiedClick("CHATLINK")) or (IsShiftKeyDown and IsShiftKeyDown()) then
                insertLink(link)
            end
        end)
    end
end
Broker.InsertLink = insertLink

-- An item box: Enter calls onEnter(text); shift-clicking an item while it
-- has focus puts the item's link in it.
local function newItemBox(parent, name, onEnter)
    local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    box:SetSize(280, 20)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function(editBox)
        onEnter(editBox:GetText())
        editBox:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)
    linkBoxes[#linkBoxes + 1] = box
    hookLinkInsert()
    return box
end

Broker.TABS = { "Bargains", "Flips", "Sell" }
-- The Sell tab's three columns need a wide, tall window:
-- 12 + bags + 12 + listings + 12 + pricing + 12.
Broker.SELL_BAGS_WIDTH, Broker.SELL_LISTINGS_WIDTH, Broker.SELL_PRICING_WIDTH = 236, 216, 300
Broker.WIDTH = 320
Broker.WIDE = 12 + Broker.SELL_BAGS_WIDTH + 12 + Broker.SELL_LISTINGS_WIDTH + 12 + Broker.SELL_PRICING_WIDTH + 12
Broker.HEIGHT, Broker.TALL = 480, 620
Broker.FLIP_ROWS = 6

function Broker:CreateWindow()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "MarketForcesRazzleFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(self.WIDTH, self.HEIGHT)
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

    -- Tabs: one button per page; the open page's button is disabled.
    f.tabs, f.pages = {}, {}
    for i, title in ipairs(self.TABS) do
        local tab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        tab:SetSize(90, 22)
        if i == 1 then
            tab:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -36)
        else
            tab:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 4, 0)
        end
        tab:SetText(title)
        tab:SetScript("OnClick", function() Broker:ShowTab(title) end)
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -150)
        page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
        f.tabs[i], f.pages[title] = tab, page
    end

    -- Bargains page --------------------------------------------------------
    local bargains = f.pages.Bargains
    local dealsHeader = newText(bargains, "GameFontNormal")
    dealsHeader:SetPoint("TOPLEFT", bargains, "TOPLEFT", 2, 0)
    dealsHeader:SetText("Bargains on the board")

    -- Each row is a button: hover shows the item's tooltip, a click opens the
    -- item in the auction house's buy view (the player buys it themselves).
    f.dealLines, f.dealRows = {}, {}
    local previous = dealsHeader
    for i = 1, self.db.global.maxDeals do
        local row, line = newItemRow(bargains, "Click to see it at the auction house")
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
        row:SetScript("OnClick", function(button)
            if button.itemID then f.speech:SetText(Broker:ShowDeal(button.itemID, button.price)) end
        end)
        f.dealLines[i], f.dealRows[i] = line, row
        previous = row
    end

    local lookupLabel = newText(bargains, "GameFontNormal")
    lookupLabel:SetPoint("BOTTOMLEFT", bargains, "BOTTOMLEFT", 2, 60)
    lookupLabel:SetText("Price check")

    f.box = newItemBox(bargains, "MarketForcesRazzleLookup", function(text)
        f.answer:SetText(Broker:Lookup(text))
    end)
    f.box:SetPoint("TOPLEFT", lookupLabel, "BOTTOMLEFT", 6, -4)

    f.answer = newText(bargains, "GameFontHighlightSmall", 290)
    f.answer:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", -6, -6)

    -- Flips page -----------------------------------------------------------
    local flips = f.pages.Flips
    local flipLabel = newText(flips, "GameFontNormal")
    flipLabel:SetPoint("TOPLEFT", flips, "TOPLEFT", 2, 0)
    flipLabel:SetText("Flip check: type a name, or pick from your bags")

    f.flipBox = newItemBox(flips, "MarketForcesRazzleFlip", function(text) Broker:CheckFlip(text) end)
    f.flipBox:SetPoint("TOPLEFT", flipLabel, "BOTTOMLEFT", 6, -4)

    f.flipAnswer = newText(flips, "GameFontHighlightSmall", 290)
    f.flipAnswer:SetPoint("TOPLEFT", f.flipBox, "BOTTOMLEFT", -6, -6)
    f.flipAnswer:SetText("Ask me about anything you've seen on the board, boss.")

    -- Opens the item in the buy view, like a bargain row. Never buys.
    f.flipShow = CreateFrame("Button", nil, flips, "UIPanelButtonTemplate")
    f.flipShow:SetSize(150, 22)
    f.flipShow:SetPoint("TOPLEFT", flips, "TOPLEFT", 0, -150)
    f.flipShow:SetText("Show me at the AH")
    f.flipShow:SetScript("OnClick", function(button)
        if button.itemID then f.speech:SetText(Broker:ShowDeal(button.itemID, button.price)) end
    end)
    f.flipShow:Hide()

    -- The list below: your bags (default) or Razzle's best flips. Clicking a
    -- row gives Razzle's numbers and, at the auction house, searches for it.
    f.listButtons = {}
    for i, mode in ipairs({ { "bags", "Your bags" }, { "picks", "Best flips" } }) do
        local button = CreateFrame("Button", nil, flips, "UIPanelButtonTemplate")
        button:SetSize(90, 20)
        if i == 1 then
            button:SetPoint("TOPLEFT", flips, "TOPLEFT", 0, -180)
        else
            button:SetPoint("LEFT", f.listButtons.bags, "RIGHT", 4, 0)
        end
        button:SetText(mode[2])
        button:SetScript("OnClick", function() Broker:ShowFlipList(mode[1]) end)
        f.listButtons[mode[1]] = button
    end
    f.pageNext = CreateFrame("Button", nil, flips, "UIPanelButtonTemplate")
    f.pageNext:SetSize(24, 20)
    f.pageNext:SetPoint("TOPRIGHT", flips, "TOPRIGHT", 0, -180)
    f.pageNext:SetText(">")
    f.pageNext:SetScript("OnClick", function() Broker:TurnBagPage(1) end)
    f.pagePrev = CreateFrame("Button", nil, flips, "UIPanelButtonTemplate")
    f.pagePrev:SetSize(24, 20)
    f.pagePrev:SetPoint("RIGHT", f.pageNext, "LEFT", -2, 0)
    f.pagePrev:SetText("<")
    f.pagePrev:SetScript("OnClick", function() Broker:TurnBagPage(-1) end)

    f.flipLines, f.flipRows = {}, {}
    previous = f.listButtons.bags
    for i = 1, Broker.FLIP_ROWS do
        local row, line = newItemRow(flips, "Click for Razzle's numbers (and the AH, when it's open)")
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
        row:SetScript("OnClick", function(button)
            if button.itemID then Broker:PickFlipItem(button.itemID) end
        end)
        f.flipLines[i], f.flipRows[i] = line, row
        previous = row
    end

    if self.BuildSellPage then self:BuildSellPage(f, f.pages.Sell) end

    self.frame = f
    self:ShowTab(self.tab or "Bargains")
    return f
end

-- Shows one page of the window: "Bargains", "Flips" or "Sell".
function Broker:ShowTab(title)
    local f = self.frame
    if not (f and f.pages[title]) then return end
    self.tab = title
    for i, name in ipairs(self.TABS) do
        if name == title then
            f.pages[name]:Show()
            f.tabs[i]:Disable()
        else
            f.pages[name]:Hide()
            f.tabs[i]:Enable()
        end
    end
    f:SetWidth(title == "Sell" and self.WIDE or self.WIDTH)
    f:SetHeight(title == "Sell" and self.TALL or self.HEIGHT)
    f.speech:SetWidth((title == "Sell" and self.WIDE or self.WIDTH) - 84) -- beside the portrait
    if title == "Flips" then self:RefreshFlips() end
    if title == "Sell" and self.RefreshSell then self:RefreshSell() end
end

-- Razzle's flip numbers for typed text, an item link or an item ID.
function Broker:CheckFlip(text)
    local f = self.frame
    if not f then return end
    local flip = MF.Flip
    if not (flip and flip:IsEnabled()) then
        f.flipAnswer:SetText("Flip advice is off. Turn it on with /mf enable flip.")
        f.flipShow:Hide()
        return
    end
    -- Remember the item, not the text, so a name still works at a house
    -- that hasn't seen it.
    self.flipQuery = flip.ResolveItem(text) or text
    local answer, plan = flip:Advise(text)
    f.flipAnswer:SetText(answer)
    f.flipShow.itemID = plan and plan.itemID
    f.flipShow.price = plan and plan.maxPrice
    if plan then f.flipShow:Show() else f.flipShow:Hide() end
end

-- A row on the Flips tab was clicked: Razzle's numbers for the item, and
-- at the auction house, the item in the buy view (or a search for it).
-- That's all one click does; buying is still the player's own click.
function Broker:PickFlipItem(itemID)
    local f = self.frame
    if not f then return end
    f.flipBox:SetText(Broker.ItemName(itemID))
    self:CheckFlip(itemID)
    local scan = MF.Scan
    if scan and scan:IsAuctionHouseOpen() then
        local p = MF.Prices and MF.Prices:GetPrice(itemID)
        f.speech:SetText(self:ShowDeal(itemID, p and p.minBuyout))
    end
end

-- Which list the Flips tab shows: "bags" or "picks".
function Broker:ShowFlipList(mode)
    self.flipList = mode
    self.bagPage = 1
    self:RefreshFlips()
end

function Broker:TurnBagPage(delta)
    self.bagPage = (self.bagPage or 1) + delta
    self:RefreshFlips()
end

-- Your bag items for the Flips tab, priced ones first (most total value
-- first), each with a label (nil while its name loads) and market value.
function Broker:BagRows()
    local flip, prices = MF.Flip, MF.Prices
    local items = flip and flip.BagItems() or {}
    for _, item in ipairs(items) do
        local p = prices and prices:IsEnabled() and prices:GetPrice(item.itemID)
        item.market = p and p.market
        item.label = Broker.ItemLabel(item.itemID)
    end
    table.sort(items, function(a, b)
        local va, vb = (a.market or -1) * a.count, (b.market or -1) * b.count
        if va ~= vb then return va > vb end
        return a.itemID < b.itemID
    end)
    return items
end

-- One bag row, e.g. "Linen Cloth x20, 1s 58c each".
function Broker.BagLine(item)
    local name = item.label or Broker.ItemName(item.itemID)
    if not item.market then return string.format("%s x%d, no price yet", name, item.count) end
    return string.format("%s x%d, %s each", name, item.count, Util.FormatMoney(item.market))
end

-- Fills the list on the Flips tab (names still loading wait, like the board).
function Broker:RefreshFlips()
    local f = self.frame
    if not (f and f.flipLines) then return end
    local flip = MF.Flip
    local on = flip and flip:IsEnabled()
    local mode = self.flipList or "bags"
    f.listButtons.bags:Enable()
    f.listButtons.picks:Enable()
    f.listButtons[mode]:Disable()
    local entries, empty = {}
    if not on then
        empty = "Flip advice is off."
    elseif mode == "picks" then
        entries, empty = flip:FindFlips(), "No flips worth the bother right now."
    else
        entries, empty = self:BagRows(), "Nothing in your bags I can sell."
    end
    local shown, loading = {}, 0
    self.flipsWaitingFor = {}
    for _, entry in ipairs(entries) do
        if entry.label then
            shown[#shown + 1] = entry
        else
            loading = loading + 1
            self.flipsWaitingFor[entry.itemID] = true
        end
    end
    -- Bags page through; best flips are only ever one page.
    local rows = #f.flipLines
    local pages = math.max(1, math.ceil(#shown / rows))
    local page = mode == "bags" and math.min(math.max(self.bagPage or 1, 1), pages) or 1
    self.bagPage = page
    if mode == "bags" and pages > 1 then
        f.pagePrev:Show()
        f.pageNext:Show()
        if page > 1 then f.pagePrev:Enable() else f.pagePrev:Disable() end
        if page < pages then f.pageNext:Enable() else f.pageNext:Disable() end
    else
        f.pagePrev:Hide()
        f.pageNext:Hide()
    end
    local first = (page - 1) * rows
    for i, line in ipairs(f.flipLines) do
        local entry = shown[first + i]
        f.flipRows[i].itemID = entry and entry.itemID
        if entry then
            line:SetText(mode == "picks" and flip.PickLine(entry) or self.BagLine(entry))
        elseif first + i == #shown + 1 and loading > 0 then
            line:SetText("|cff808080Looking up " .. loading .. " more...|r")
        elseif i == 1 and first == 0 then
            line:SetText(empty)
        else
            line:SetText("")
        end
    end
end

function Broker:Refresh(extra)
    local f = self.frame
    if not f then return end
    f.speech:SetText(self.Greeting(self:CurrentInfo(extra)))
    self:RefreshDeals()
    -- New prices or another house: redo the item on the Flips tab too, so
    -- its advice and AH button never describe old listings.
    if self.flipQuery then self:CheckFlip(self.flipQuery) end
    if self.tab == "Flips" then self:RefreshFlips() end
    if self.tab == "Sell" and self.RefreshSell then self:RefreshSell() end
end

-- Fills the board. Rows whose item names are still loading are skipped
-- until GET_ITEM_INFO_RECEIVED brings them in.
function Broker:RefreshDeals()
    local f = self.frame
    if not f then return end
    local deals = self:FindDeals()
    local shown, loading = {}, 0
    self.waitingFor = {}
    for _, deal in ipairs(deals) do
        if deal.label then
            shown[#shown + 1] = deal
        else
            loading = loading + 1
            self.waitingFor[deal.itemID] = true
        end
    end
    for i, line in ipairs(f.dealLines) do
        local deal = shown[i]
        f.dealRows[i].itemID = deal and deal.itemID
        f.dealRows[i].price = deal and deal.minBuyout
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

-- Opens an item in the auction house's buy view, the same as clicking it in
-- Blizzard's browse results, so the player can look and buy it with their
-- own click. This only shows the item; it never buys. Returns Razzle's line.
function Broker:ShowDeal(itemID, price)
    local name = Broker.ItemName(itemID)
    local window = AuctionHouseFrame
    local scan = MF.Scan
    if not (window and scan and scan:IsAuctionHouseOpen()) then
        return "Meet me at the auction house and I'll show you the " .. name .. "."
    end
    -- Commodities are keyed by item ID alone, so Blizzard's own path from a
    -- browse result opens the quantity buy frame directly. Other items' keys
    -- carry an item level and suffix we don't know, so those get a search.
    if window.SelectBrowseResult and C_AuctionHouse and C_AuctionHouse.MakeItemKey
        and C_AuctionHouse.GetItemKeyInfo then
        local itemKey = C_AuctionHouse.MakeItemKey(itemID)
        local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
        if info and info.isCommodity
            and pcall(window.SelectBrowseResult, window, { itemKey = itemKey, minPrice = price }) then
            return "Here's the " .. name .. ". Have a look; if you like it, the buy button's all yours, boss."
        end
    end
    -- Otherwise search for it by name on the Buy tab, with any category the
    -- player picked cleared so it can't hide the item.
    local bar = window.SearchBar
    if bar and bar.SearchBox and bar.StartSearch then
        if window.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
            window:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
        end
        local categories = window.CategoriesList
        if categories and categories.SetSelectedCategory then
            pcall(categories.SetSelectedCategory, categories, nil, nil, nil)
        end
        bar.SearchBox:SetText(name)
        bar:StartSearch()
        return "I searched the board for " .. name .. ". Pick your listing, boss."
    end
    return "I can't open that for you here. Search the auction house for " .. name .. "."
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
    self.sellLive = nil -- live listings only mean something while you're there
    self.dockToken = (self.dockToken or 0) + 1
    if self.docked and self.frame then
        self.frame:Hide()
        self.docked = false
    end
end

-- Post put a bag item up for sale: Razzle says what was set up (after,
-- and in place of, the sell slot's own MF_POST_ITEM_SELECTED line).
function Broker:MF_POST_SAYS(_, line)
    if self.frame and self.frame:IsShown() then self.frame.speech:SetText(line) end
end

function Broker:MF_POST_ITEM_SELECTED(_, itemID, suggestion, p)
    -- Whatever goes in the sell slot is what the Sell tab looks at.
    if self.SelectSellItem then self:SelectSellItem(itemID) end
    if not (self.frame and self.frame:IsShown()) then return end
    local filled = suggestion and MF.Post and MF.Post.db.global.fillPrice
    self.frame.speech:SetText(self.PostLine(itemID, suggestion, p, filled))
end

-- An item the board was waiting on has loaded: refill the board once, a
-- moment later, since these arrive in bursts. Other items' events are
-- ignored, since refilling walks the whole price history. Razzle's speech
-- is left alone.
function Broker:GET_ITEM_INFO_RECEIVED(_, itemID)
    if not itemID then return end
    local deal = self.waitingFor and self.waitingFor[itemID]
    local pick = self.tab == "Flips" and self.flipsWaitingFor and self.flipsWaitingFor[itemID]
    local bag = self.tab == "Sell" and self.sellWaitingFor and self.sellWaitingFor[itemID]
    if not (deal or pick or bag) then return end
    if self.namesPending or not (self.frame and self.frame:IsShown()) then return end
    self.namesPending = true
    C_Timer.After(0.2, function()
        Broker.namesPending = false
        if Broker:IsEnabled() and Broker.frame and Broker.frame:IsShown() then
            Broker:RefreshDeals()
            if Broker.tab == "Flips" then Broker:RefreshFlips() end
            if Broker.tab == "Sell" and Broker.RefreshSell then Broker:RefreshSell() end
        end
    end)
end

-- Faction and goblin auction houses keep separate prices: when the house
-- switches (possibly after we docked), show the new house's numbers.
function Broker:MF_AUCTION_HOUSE_CHANGED()
    self.sellLive = nil -- another house's listings
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
    self:RegisterMessage("MF_POST_SAYS")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    if self.RegisterSellEvents then self:RegisterSellEvents() end
end

-- Your bags changed: redo the checked item (its advice counts your copies)
-- and the bag list if it's showing.
function Broker:BAG_UPDATE_DELAYED()
    if not (self.frame and self.frame:IsShown()) then return end
    if self.flipQuery then self:CheckFlip(self.flipQuery) end
    if self.tab == "Flips" and (self.flipList or "bags") == "bags" then self:RefreshFlips() end
    if self.tab == "Sell" and self.RefreshSell then self:RefreshSell() end
end

function Broker:OnDisable()
    self.dockToken = (self.dockToken or 0) + 1
    -- Events stop while off, so a house change or the AH closing would go
    -- unseen: live listings can't be trusted after this.
    self.sellLive = nil
    if self.frame then self.frame:Hide() end
    self.docked = false
end
