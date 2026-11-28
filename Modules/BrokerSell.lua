-- MarketForces Broker: Razzle's Sell tab.
--
-- Three columns side by side, modelled on AuctioneerModern's Post tab:
--   Your bags         sellable items, most valuable first. Click one to look
--                     at it; at the auction house it also goes into
--                     Blizzard's sell slot with Razzle's price, quantity and
--                     duration (the same as shift-clicking it, see Post.lua).
--   Competing listings  the item's listings: live from the auction house
--                     once Blizzard's sell slot has searched for it,
--                     otherwise the cheapest ones from your last scan. Your
--                     own listings are marked, and a "vs market" column says
--                     how far each sits from market value (-12%, +8%).
--                     Click one to put its price in
--                     Blizzard's price box.
--   Pricing & results every pricing method's price (market value, median,
--                     trimmed mean, undercut, match cheapest, your sales;
--                     see Post.lua) per unit and for all your copies, the
--                     one in use marked. Click one to price by it from now
--                     on (and, if the sell slot holds the item, put its
--                     price in). WoW: Forever's auction house has no stacks:
--                     stackable goods are posted as a quantity at one price
--                     per unit. Below: what your copies would bring before
--                     and after the 5% cut, then what your auction
--                     mail says about this item (History.lua): sold,
--                     sell-through, expired, bought, and the latest records.
--
-- Razzle never posts. Posting stays your own click on Blizzard's Post
-- button; this tab only fills in Blizzard's sell frame the way you could by
-- hand, and only reads search results Blizzard's own sell frame asked for.
local _, MF = ...

local Util = MF.Util
local Broker = MF.Broker

Broker.SELL_BAG_ROWS = 13
Broker.SELL_LIST_ROWS = 11
Broker.SELL_RECENT_ROWS = 4
Broker.AH_CUT = 0.05

local HOUR, DAY = 60 * 60, 24 * 60 * 60
local GOLD, BLUE, GREY = "|cffffd100", "|cff4fb3ff", "|cff808080"
local TYPE_COLOR = { sold = "|cff33ff33", bought = "|cffffaa33", expired = "|cffff4444", cancelled = "|cffffff33" }

-- "5m ago", "3h ago", "2d ago".
function Broker.Ago(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds < HOUR then return math.max(1, math.floor(seconds / 60)) .. "m ago" end
    if seconds < DAY then return math.floor(seconds / HOUR) .. "h ago" end
    return math.floor(seconds / DAY) .. "d ago"
end

-- Listings ---------------------------------------------------------------------

-- Merges { price, units, yours, yourUnits } listings at the same price,
-- cheapest first. yourUnits (default: all of them when yours) is kept per
-- price, so a price you share with other sellers still counts theirs.
function Broker.MergeListings(listings)
    local byPrice, out = {}, {}
    for _, l in ipairs(listings) do
        local price, units = l[1], l[2] or 0
        if price and price > 0 then
            local row = byPrice[price]
            if not row then
                row = { price, 0, false, 0 }
                byPrice[price] = row
                out[#out + 1] = row
            end
            local own = math.min(l[4] or (l[3] == true and units or 0), units)
            row[2] = row[2] + units
            row[3] = row[3] or l[3] == true or own > 0
            row[4] = row[4] + own
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

-- Live commodity listings Blizzard's sell frame searched for.
function Broker.ReadCommodityResults(itemID)
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumCommoditySearchResults and AH.GetCommoditySearchResultInfo) then return nil end
    local listings = {}
    for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
        local info = AH.GetCommoditySearchResultInfo(itemID, i)
        if info then
            local own = info.numOwnerItems or (info.containsOwnerItem and info.quantity) or 0
            listings[#listings + 1] = { info.unitPrice, info.quantity, own > 0 or info.containsOwnerItem == true, own }
        end
    end
    return Broker.MergeListings(listings)
end

-- Live listings of a non-commodity item (gear and the like). Bid-only
-- auctions have no buyout and are left out.
function Broker.ReadItemResults(itemKey)
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumItemSearchResults and AH.GetItemSearchResultInfo) then return nil end
    local listings = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
        local info = AH.GetItemSearchResultInfo(itemKey, i)
        if info and info.buyoutAmount then
            listings[#listings + 1] = { info.buyoutAmount, info.quantity or 1, info.containsOwnerItem == true }
        end
    end
    return Broker.MergeListings(listings)
end

-- The listings to show for an item: live ones when we have them, else the
-- latest scan's. Returns listings, a line saying where they're from, and
-- whether more were left off.
function Broker:SellListings(itemID)
    local live = self.sellLive
    if live and live.itemID == itemID then
        return live.listings, "Live from the auction house", false
    end
    local prices = MF.Prices
    local p = prices and prices:IsEnabled() and prices:GetPrice(itemID)
    if not p then return {}, "Not in your scans at this house yet", false end
    local listings = {}
    for i, step in ipairs(p.ladder or {}) do listings[i] = { step[1], step[2], false } end
    local age = p.lastSeen and Broker.Ago(time() - p.lastSeen) or "a while ago"
    if #listings == 0 then return listings, "None listed at your last scan (" .. age .. ")", false end
    return listings, "From your last scan, " .. age, p.ladderMore
end

-- One listing row, e.g. "20 at 1s 50c" (your own in blue).
function Broker.ListingLine(listing)
    local line = string.format("%d at %s", listing[2], Util.FormatMoney(listing[1]))
    if listing[3] then return BLUE .. line .. " (yours)|r" end
    return line
end

-- How far a price sits from market value, e.g. "-12%" (green, under
-- market), "+8%" (orange, over) or "0%". Empty without a market value.
function Broker.VsMarket(price, market)
    if not (price and market and market > 0) then return "" end
    local pct = math.floor((price - market) / market * 100 + 0.5)
    if pct < 0 then return "|cff33ff33" .. pct .. "%|r" end
    if pct > 0 then return "|cffff9933+" .. pct .. "%|r" end
    return "0%"
end

-- Your results -----------------------------------------------------------------

local function stackSizeOf(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local size = getInfo and tonumber((select(8, getInfo(itemID))))
    return (size and size > 1) and size or 1
end

-- The pricing block for an item: { rows = { { key, label, each, total,
-- active (the one you chose) } }, count (your copies), chosen, method (in
-- use: the chosen one, or market value while it has no number), price (per
-- unit), breakdown = lines about your copies, read = Razzle's read of the
-- market, off = message when selling is off }. Prices per unit are to the
-- copper; total is that times your copies (only when you hold more than one).
function Broker:SellPricing(itemID)
    local post = MF.Post
    if not (post and post:IsEnabled()) then
        return { rows = {}, count = 0, breakdown = {}, off = "Selling's off. Turn it on with /mf enable post." }
    end
    local live = self:LiveListings(itemID)
    local options, p = post:PriceOptions(itemID, live)
    local price, _, method = post:Suggest(itemID, live)
    local chosen = post.METHOD_LABEL[post.db.global.method] and post.db.global.method or "market"
    local count = MF.Flip and MF.Flip.CountInBags(itemID) or 0
    local out = { rows = {}, count = count, method = method, chosen = chosen, price = price, breakdown = {} }
    for _, m in ipairs(post.METHODS) do
        local each = options[m.key] and post.RoundPrice(options[m.key])
        local label = m.label
        if m.key == "undercut" and options.undercutFloored then label = label .. " (floor)" end
        out.rows[#out.rows + 1] = {
            key = m.key, label = label, each = each,
            total = each and count > 1 and each * count or nil,
            active = m.key == chosen,
        }
    end
    if price and method ~= chosen then
        out.breakdown[1] = GREY .. "Market value until " .. post.METHOD_LABEL[chosen]:lower() .. " has a number|r"
    end
    if price and count > 0 then
        local total = price * count
        out.breakdown[#out.breakdown + 1] = string.format("Your %d at %s: %s, %s after the cut", count,
            Util.FormatMoney(price), Util.FormatMoney(total), Util.FormatMoney(math.floor(total * (1 - self.AH_CUT))))
        -- The quantity a shift-click or bag click would put up (Post.lua).
        local quantity, capped = post.SuggestQuantity(count, p and p.quantity, stackSizeOf(itemID))
        if capped then
            out.breakdown[#out.breakdown + 1] = string.format(
                "I'd put up %d of your %d at a time, so a pile doesn't sit unsold", quantity, count)
        end
    elseif not price then
        out.breakdown[1] = GREY .. "No price to go on yet. A scan or two will teach me.|r"
    end
    if p and p.market then
        local read = {}
        if p.trend then read[#read + 1] = p.trend end
        if p.confidence and MF.Prices.ConfidenceLabel then
            read[#read + 1] = MF.Prices.ConfidenceLabel(p.confidence) .. " confidence"
        end
        if #read > 0 then out.read = "Market's " .. table.concat(read, ", ") end
    end
    return out
end

-- What your auction mail says about the item: summary lines, then recent
-- records (each a line).
function Broker:SellResultLines(itemID)
    local history = MF.History
    if not (history and history:IsEnabled()) then
        return { GREY .. "Your results are off. Turn them on with /mf enable history.|r" }, {}
    end
    local s = history:ItemStats(itemID)
    if not s then
        return { GREY .. "No results for this yet. Check your mailbox after auctions end and I'll keep score.|r" }, {}
    end
    local lines = {}
    if s.sold > 0 then
        lines[#lines + 1] = string.format("Sold %d in %d %s%s", s.sold, s.soldListings,
            s.soldListings == 1 and "listing" or "listings",
            s.soldEach and (", ~" .. Util.FormatMoney(s.soldEach) .. " each") or "")
    else
        lines[#lines + 1] = "Nothing sold yet"
    end
    local finished = s.soldListings + s.expired + s.cancelled
    if finished > 0 then
        lines[#lines + 1] = string.format("Sell-through: %d of %d (%d%%)", s.soldListings, finished,
            math.floor((s.sellThrough or 0) * 100 + 0.5))
    end
    if s.expired + s.cancelled > 0 then
        lines[#lines + 1] = string.format("Expired %d, cancelled %d", s.expired, s.cancelled)
    end
    if s.bought > 0 then
        lines[#lines + 1] = string.format("Bought %d%s", s.bought,
            s.boughtEach and (" at ~" .. Util.FormatMoney(s.boughtEach)) or "")
    end
    if s.lastSold then lines[#lines + 1] = "Last sold " .. Broker.Ago(time() - s.lastSold) end
    local recent = {}
    for _, r in ipairs(history:ItemRecords(itemID, self.SELL_RECENT_ROWS)) do
        local text = string.format("%s%s|r %d", TYPE_COLOR[r.type] or "", r.type, r.n or 1)
        if r.type == "sold" and r.money then
            text = text .. " for " .. Util.FormatMoney(r.money)
        elseif r.type == "bought" and r.price then
            text = text .. " for " .. Util.FormatMoney(r.price)
        end
        recent[#recent + 1] = text .. GREY .. ", " .. Broker.Ago(time() - (r.at or time())) .. "|r"
    end
    return lines, recent
end

-- What Razzle says about an item picked away from the sell slot.
function Broker:SellLine(itemID)
    local name = Broker.ItemName(itemID)
    local prices = MF.Prices
    local p = prices and prices:IsEnabled() and prices:GetPrice(itemID)
    local line
    if p and p.market then
        line = name .. ": worth about " .. Util.FormatMoney(p.market) .. "."
        if p.minBuyout then line = line .. " Cheapest at my last scan: " .. Util.FormatMoney(p.minBuyout) .. "." end
    else
        line = name .. "? I've got no steady price for it here yet."
    end
    local history = MF.History
    local record = history and history:IsEnabled() and history:Line(itemID)
    if record then line = line .. " Your record: " .. record .. "." end
    local scan = MF.Scan
    if not (scan and scan:IsAuctionHouseOpen()) then
        line = line .. " Bring it to the auction house and I'll set it up."
    end
    return line
end

-- Actions ----------------------------------------------------------------------

-- The Sell tab now looks at this item (from a click, or from anything put
-- in Blizzard's sell slot). Another item's live listings are dropped.
function Broker:SelectSellItem(itemID)
    if not itemID then return end
    if self.sellItem ~= itemID then
        self.sellItem = itemID
        if self.sellLive and self.sellLive.itemID ~= itemID then self.sellLive = nil end
    end
    if self.tab == "Sell" and self.frame and self.frame:IsShown() then self:RefreshSell() end
end

-- A bag row was clicked. At the auction house the item also goes into
-- Blizzard's sell slot, priced; posting is still the player's click.
function Broker:PickSellItem(itemID)
    local f = self.frame
    if not (f and itemID) then return end
    self:SelectSellItem(itemID)
    local scan, post = MF.Scan, MF.Post
    local line
    if scan and scan:IsAuctionHouseOpen() then
        if post and post:IsEnabled() then
            line = post:SellFromBags(itemID)
        else
            line = "Selling's off (/mf enable post). Drag " .. Broker.ItemName(itemID)
                .. " into the sell slot yourself."
        end
    end
    f.speech:SetText(line or self:SellLine(itemID))
    self:RefreshSell()
end

-- A listing row was clicked: its price goes in Blizzard's price box, if the
-- sell slot holds this item. Rounded to silver like Razzle's own price.
function Broker:MatchListing(price)
    local f = self.frame
    if not (f and price and self.sellItem) then return end
    local scan, post = MF.Scan, MF.Post
    local name = Broker.ItemName(self.sellItem)
    if not (scan and scan:IsAuctionHouseOpen()) then
        f.speech:SetText("Meet me at the auction house and I'll put that price in for you.")
        return
    end
    local sellFrame = post and post:IsEnabled() and post:SellFrameFor(self.sellItem)
    local input = sellFrame and sellFrame.PriceInput
    if not (input and input.SetAmount) then
        f.speech:SetText("Pick " .. name .. " from your bags first, so it's in the sell slot.")
        return
    end
    local amount = post.RoundPrice(price)
    input:SetAmount(amount)
    local line = "Matched at " .. Util.FormatMoney(amount) .. " each"
    f.speech:SetText(line .. ". Click Post when you're happy, boss.")
end

-- A pricing row was clicked: price by that method from now on, and if the
-- sell slot holds this item, put the new price in its price box.
function Broker:PickPriceMethod(key)
    local f, post = self.frame, MF.Post
    if not (f and post and post:IsEnabled() and post.METHOD_LABEL[key]) then return end
    post.db.global.method = key
    local label = post.METHOD_LABEL[key]
    local line = "Pricing by " .. label:lower() .. " from now on."
    local itemID = self.sellItem
    if itemID then
        local price, _, used = post:Suggest(itemID, self:LiveListings(itemID))
        if price and used ~= key then
            line = line .. " " .. label .. " has no number for " .. Broker.ItemName(itemID)
                .. " yet, so it's market value for now."
        end
        local sellFrame = price and post:SellFrameFor(itemID)
        local input = sellFrame and sellFrame.PriceInput
        if input and input.SetAmount then
            input:SetAmount(price)
            line = line .. " Set " .. Util.FormatMoney(price) .. " each. Click Post when you're happy, boss."
        end
    end
    f.speech:SetText(line)
    self:RefreshSell()
end

-- Frames -----------------------------------------------------------------------

local function column(page, x, width, title)
    local col = CreateFrame("Frame", nil, page)
    col:SetPoint("TOPLEFT", page, "TOPLEFT", x, 0)
    col:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", x, 0)
    col:SetWidth(width)
    local header = Broker.NewText(col, "GameFontNormal", width)
    header:SetPoint("TOPLEFT", col, "TOPLEFT", 2, 0)
    header:SetText(title)
    col.header = header
    return col
end

local function textLines(col, anchor, count, width, gap, wrap)
    local lines, previous = {}, anchor
    for i = 1, count do
        local line = Broker.NewText(col, "GameFontHighlightSmall", width)
        line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -(gap or 3))
        if line.SetWordWrap then line:SetWordWrap(wrap == true) end
        lines[i], previous = line, line
    end
    return lines
end

function Broker:BuildSellPage(f, page)
    if not page then return end
    local W, W2 = self.SELL_BAGS_WIDTH, self.SELL_LISTINGS_WIDTH

    -- Your bags.
    local bags = column(page, 0, W, "Your bags")
    f.sellBagLines, f.sellBagRows = {}, {}
    local previous = bags.header
    for i = 1, self.SELL_BAG_ROWS do
        local row, line = Broker.NewItemRow(bags, "Click to look; at the AH it goes in the sell slot", W)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
        row:SetScript("OnClick", function(button)
            if button.itemID then Broker:PickSellItem(button.itemID) end
        end)
        f.sellBagLines[i], f.sellBagRows[i] = line, row
        previous = row
    end
    f.sellNext = CreateFrame("Button", nil, bags, "UIPanelButtonTemplate")
    f.sellNext:SetSize(24, 20)
    f.sellNext:SetPoint("BOTTOMRIGHT", bags, "BOTTOMRIGHT", 0, 0)
    f.sellNext:SetText(">")
    f.sellNext:SetScript("OnClick", function() Broker:TurnSellPage(1) end)
    f.sellPrev = CreateFrame("Button", nil, bags, "UIPanelButtonTemplate")
    f.sellPrev:SetSize(24, 20)
    f.sellPrev:SetPoint("RIGHT", f.sellNext, "LEFT", -2, 0)
    f.sellPrev:SetText("<")
    f.sellPrev:SetScript("OnClick", function() Broker:TurnSellPage(-1) end)

    -- Competing listings.
    local listings = column(page, W + 12, W2, "Competing listings")
    f.sellItemName = Broker.NewText(listings, "GameFontHighlight", W2)
    f.sellItemName:SetPoint("TOPLEFT", listings.header, "BOTTOMLEFT", 0, -4)
    if f.sellItemName.SetWordWrap then f.sellItemName:SetWordWrap(false) end
    f.sellSource = Broker.NewText(listings, "GameFontDisableSmall", W2)
    f.sellSource:SetPoint("TOPLEFT", f.sellItemName, "BOTTOMLEFT", 0, -2)
    -- The "vs market" column: each listing's distance from market value.
    local vsHeader = Broker.NewText(listings, "GameFontNormalSmall", 60)
    vsHeader:SetPoint("TOPRIGHT", listings, "TOPRIGHT", 0, -2)
    vsHeader:SetJustifyH("RIGHT")
    vsHeader:SetText("vs market")
    f.sellListLines, f.sellListRows, f.sellListPcts = {}, {}, {}
    previous = f.sellSource
    for i = 1, self.SELL_LIST_ROWS do
        local row, line = Broker.NewItemRow(listings, "Click to put this price in the sell slot", W2)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -3)
        row:SetScript("OnClick", function(button)
            if button.price then Broker:MatchListing(button.price) end
        end)
        local pct = Broker.NewText(row, "GameFontHighlightSmall", 44)
        pct:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        pct:SetJustifyH("RIGHT")
        line:SetWidth(W2 - 46)
        f.sellListLines[i], f.sellListRows[i], f.sellListPcts[i] = line, row, pct
        previous = row
    end

    -- Pricing & results.
    local W3 = self.SELL_PRICING_WIDTH
    local results = column(page, W + W2 + 24, W3, "Pricing")
    -- Column heads: method, per unit, for all your copies.
    local function cells(parent)
        local each = Broker.NewText(parent, "GameFontHighlightSmall", 70)
        each:SetPoint("RIGHT", parent, "RIGHT", -76, 0)
        each:SetJustifyH("RIGHT")
        local total = Broker.NewText(parent, "GameFontHighlightSmall", 72)
        total:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        total:SetJustifyH("RIGHT")
        return each, total
    end
    local heads = CreateFrame("Frame", nil, results)
    heads:SetSize(W3, 14)
    heads:SetPoint("TOPLEFT", results.header, "BOTTOMLEFT", 0, -4)
    f.sellHeadEach, f.sellHeadTotal = cells(heads)
    f.sellHeadEach:SetText("per unit")
    f.sellMethodRows = {}
    previous = heads
    for i = 1, #MF.Post.METHODS do
        local row, line = Broker.NewItemRow(results, "Click to price by this from now on", W3)
        row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
        row:SetScript("OnClick", function(button)
            if button.method then Broker:PickPriceMethod(button.method) end
        end)
        row:SetScript("OnEnter", function(button)
            if GameTooltip and button.method then
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:AddLine(MF.Post.METHOD_LABEL[button.method])
                GameTooltip:AddLine("Click to price by this from now on.", 0.5, 0.8, 1)
                GameTooltip:Show()
            end
        end)
        line:SetWidth(W3 - 150)
        row.label = line
        row.each, row.total = cells(row)
        f.sellMethodRows[i] = row
        previous = row
    end
    f.sellBreakdown = textLines(results, previous, 4, W3, 3, true)
    f.sellBreakdown[1]:ClearAllPoints()
    f.sellBreakdown[1]:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)

    local resultsHeader = Broker.NewText(results, "GameFontNormal", W3)
    resultsHeader:SetPoint("TOPLEFT", f.sellBreakdown[4], "BOTTOMLEFT", 0, -8)
    resultsHeader:SetText("Your results")
    f.sellResultLines = textLines(results, resultsHeader, 5, W3, 3, true)
    local recentHeader = Broker.NewText(results, "GameFontNormalSmall", W3)
    recentHeader:SetPoint("TOPLEFT", f.sellResultLines[5], "BOTTOMLEFT", 0, -6)
    recentHeader:SetText("Latest")
    f.sellRecentLines = textLines(results, recentHeader, self.SELL_RECENT_ROWS, W3, 3)

    local hint = Broker.NewText(results, "GameFontDisableSmall", W3)
    hint:SetPoint("BOTTOMLEFT", results, "BOTTOMLEFT", 2, 0)
    hint:SetText("Posting is always your click on Blizzard's Post button.")
end

function Broker:TurnSellPage(delta)
    self.sellPage = (self.sellPage or 1) + delta
    self:RefreshSell()
end

local function fill(lines, texts)
    for i, line in ipairs(lines) do line:SetText(texts[i] or "") end
end

function Broker:RefreshSell()
    local f = self.frame
    if not (f and f.sellBagLines) then return end

    -- Bags, paged; names still loading wait, like the other lists.
    local shown, loading = {}, 0
    self.sellWaitingFor = {}
    for _, item in ipairs(self:BagRows()) do
        if item.label then
            shown[#shown + 1] = item
        else
            loading = loading + 1
            self.sellWaitingFor[item.itemID] = true
        end
    end
    local rows = #f.sellBagLines
    local pages = math.max(1, math.ceil(#shown / rows))
    local page = math.min(math.max(self.sellPage or 1, 1), pages)
    self.sellPage = page
    if pages > 1 then
        f.sellPrev:Show()
        f.sellNext:Show()
        if page > 1 then f.sellPrev:Enable() else f.sellPrev:Disable() end
        if page < pages then f.sellNext:Enable() else f.sellNext:Disable() end
    else
        f.sellPrev:Hide()
        f.sellNext:Hide()
    end
    local first = (page - 1) * rows
    for i, line in ipairs(f.sellBagLines) do
        local item = shown[first + i]
        f.sellBagRows[i].itemID = item and item.itemID
        if item then
            local text = self.BagLine(item)
            if item.itemID == self.sellItem then text = GOLD .. ">|r " .. text end
            line:SetText(text)
        elseif first + i == #shown + 1 and loading > 0 then
            line:SetText(GREY .. "Looking up " .. loading .. " more...|r")
        elseif i == 1 and first == 0 then
            line:SetText("Nothing in your bags I can sell.")
        else
            line:SetText("")
        end
    end

    -- Listings and results for the picked item.
    local itemID = self.sellItem
    for _, row in ipairs(f.sellListRows) do row.itemID, row.price = nil, nil end
    if not itemID then
        f.sellItemName:SetText(GREY .. "Pick something from your bags|r")
        f.sellSource:SetText("")
        fill(f.sellListLines, {})
        fill(f.sellListPcts, {})
        self:FillPricing(nil)
        fill(f.sellResultLines, {})
        fill(f.sellRecentLines, {})
        return
    end
    f.sellItemName:SetText(Broker.ItemLabel(itemID) or Broker.ItemName(itemID))
    local listings, source, more = self:SellListings(itemID)
    f.sellSource:SetText(source)
    local prices = MF.Prices
    local p = prices and prices:IsEnabled() and prices:GetPrice(itemID)
    local market = p and p.market
    local n = #f.sellListLines
    for i, line in ipairs(f.sellListLines) do
        local listing = listings[i]
        local pct = ""
        if listing and i == n and (#listings > n or more) then
            line:SetText(GREY .. "...and more|r")
        elseif listing then
            line:SetText(self.ListingLine(listing))
            pct = self.VsMarket(listing[1], market)
            f.sellListRows[i].itemID, f.sellListRows[i].price = itemID, listing[1]
        else
            line:SetText("")
        end
        f.sellListPcts[i]:SetText(pct)
    end
    self:FillPricing(itemID)
    local summary, recent = self:SellResultLines(itemID)
    fill(f.sellResultLines, summary)
    fill(f.sellRecentLines, recent)
end

-- Fills the pricing rows and breakdown (cleared for nil).
function Broker:FillPricing(itemID)
    local f = self.frame
    local pricing = itemID and self:SellPricing(itemID) or { rows = {}, count = 0, breakdown = {} }
    f.sellHeadTotal:SetText(pricing.count > 1 and ("your " .. pricing.count) or "")
    f.sellHeadEach:SetText(itemID and "per unit" or "")
    for i, row in ipairs(f.sellMethodRows) do
        local r = pricing.rows[i]
        row.method = r and r.key
        if r then
            local label = r.active and (GOLD .. "> " .. r.label .. "|r") or r.label
            row.label:SetText(label)
            row.each:SetText(r.each and Util.FormatMoney(r.each) or (GREY .. "-|r"))
            row.total:SetText(r.total and Util.FormatMoney(r.total) or "")
        else
            row.label:SetText(i == 1 and pricing.off or "")
            row.each:SetText("")
            row.total:SetText("")
        end
    end
    local lines = {}
    for _, line in ipairs(pricing.breakdown) do lines[#lines + 1] = line end
    if pricing.read then lines[#lines + 1] = GREY .. pricing.read .. "|r" end
    fill(f.sellBreakdown, lines)
end

-- Events -----------------------------------------------------------------------

-- The live listings the Sell tab holds for an item (an empty table when
-- the search found none), or nil when it has none for that item.
function Broker:LiveListings(itemID)
    local live = self.sellLive
    return live and itemID and live.itemID == itemID and live.listings or nil
end

-- Search results Blizzard's sell frame (or the player) asked for. Only the
-- item the Sell tab is looking at is read; nothing here sends a search.
function Broker:COMMODITY_SEARCH_RESULTS_UPDATED(_, itemID)
    if not itemID or itemID ~= self.sellItem then return end
    local listings = Broker.ReadCommodityResults(itemID)
    if not listings then return end
    self.sellLive = { itemID = itemID, listings = listings }
    if self.tab == "Sell" and self.frame and self.frame:IsShown() then self:RefreshSell() end
end

function Broker:ITEM_SEARCH_RESULTS_UPDATED(_, itemKey)
    local itemID = type(itemKey) == "table" and itemKey.itemID
    if not itemID or itemID ~= self.sellItem then return end
    local listings = Broker.ReadItemResults(itemKey)
    if not listings then return end
    self.sellLive = { itemID = itemID, listings = listings }
    if self.tab == "Sell" and self.frame and self.frame:IsShown() then self:RefreshSell() end
end

-- Older clients may not know these events; registering an unknown one is
-- an error, so each is tried on its own.
function Broker:RegisterSellEvents()
    for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" }) do
        pcall(self.RegisterEvent, self, event)
    end
end
