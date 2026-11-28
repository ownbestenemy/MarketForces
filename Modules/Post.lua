-- MarketForces Post module.
--
-- When you put an item in the auction house's sell slot, Razzle fills in
-- the price box using the pricing method you picked (default: the item's
-- smoothed market value, Mark's choice: steady prices, no racing
-- undercutters). The methods, after the ones seller addons offer:
--   market    Razzle's smoothed market value (see Prices.lua)
--   median    the median unit price of the listings
--   trimmed   the average unit price with the cheapest and dearest 10% of
--             units left out
--   undercut  1 copper below the cheapest other listing,
--             but never under 80% of market value (undercutFloor)
--   match     the cheapest other listing, to the copper
--   history   what your own sales averaged (from your auction mail)
-- Listings are live from the auction house when Razzle's Sell tab has them
-- (also when Razzle fills in a price by itself),
-- otherwise the latest scan's. A method with no number yet falls back to
-- market value. You check it and click Blizzard's own Post button; this
-- module never posts, buys or cancels anything.
--
-- It also sends MF_POST_ITEM_SELECTED(itemID, suggestion) so Razzle's window
-- can talk about the item.
--
-- Shift-clicking a bag item while the auction house is open puts it in the
-- sell slot (Blizzard's own SetPostItem, the same as right-clicking it on
-- the Sell tab), then sets the quantity Razzle suggests and the duration
-- (24 hours by default). Posting stays the player's click on Post.
local _, MF = ...

local Post = MF:NewModule("Post", {
    global = {
        fillPrice = true, -- put the suggestion into the price box
        shiftSell = true, -- shift-click a bag item at the AH to put it up for sale
        duration = 2,     -- 1 = 12 hours, 2 = 24 hours, 3 = 48 hours
        method = "market", -- pricing method, see the header
        undercutFloor = 0.8, -- undercut never goes below this share of market value
    },
})
MF.Post = Post

-- A price per unit in whole copper (at least 1c). Prices keep their copper:
-- the sell frames take gold, silver and copper.
function Post.RoundPrice(copper)
    local rounded = math.floor((tonumber(copper) or 0) + 0.5)
    if rounded < 1 then rounded = 1 end
    return rounded
end

-- Pricing methods in the order Razzle lists them.
Post.METHODS = {
    { key = "market", label = "Market value" },
    { key = "median", label = "Median" },
    { key = "trimmed", label = "Trimmed mean" },
    { key = "undercut", label = "Undercut" },
    { key = "match", label = "Match cheapest" },
    { key = "history", label = "Your sales" },
}
local METHOD_LABEL = {}
for _, m in ipairs(Post.METHODS) do METHOD_LABEL[m.key] = m.label end
Post.METHOD_LABEL = METHOD_LABEL

-- Every method's price per unit (raw copper, nil when it has no number)
-- for an item at the current auction house. listings: optional live
-- { unitPrice, units, yours, yourUnits } listings, authoritative even when
-- empty (nobody's selling: no median, match or undercut); without them the
-- latest scan's numbers are used. Returns the prices and Prices:GetPrice's entry.
function Post:PriceOptions(itemID, listings)
    local out = {}
    local prices = MF.Prices
    local p = prices and prices:IsEnabled() and itemID and prices:GetPrice(itemID) or nil
    local market = p and p.market
    out.market = market
    local cheapest
    if listings then
        out.median = MF.Prices.Median(listings)
        out.trimmed = MF.Prices.TrimmedMean(listings)
        -- Other sellers' cheapest: a price counts if anyone else has units there.
        for _, l in ipairs(listings) do
            local own = l[4] or (l[3] and l[2] or 0)
            if (l[2] or 0) - own > 0 and (not cheapest or l[1] < cheapest) then cheapest = l[1] end
        end
    elseif p then
        out.median, out.trimmed, cheapest = p.median, p.trimmed, p.minBuyout
    end
    if cheapest then
        -- Match is the cheapest to the copper; undercut is 1c under it,
        -- floored so a price war can't drag us under a share of market value.
        out.match = cheapest
        local under = cheapest - 1
        local minimum = market and math.ceil(market * (self.db.global.undercutFloor or 0)) or 0
        out.undercut = math.max(under, minimum, 1)
        out.undercutFloored = under < minimum
    end
    local history = MF.History
    local stats = history and history:IsEnabled() and itemID and history:ItemStats(itemID)
    out.history = stats and stats.soldEach
    return out, p
end

-- The suggested buyout per unit for an item at the current auction house,
-- by the chosen pricing method (falling back to market value), rounded to
-- whole copper (at least 1c).
-- Returns the price (nil when there's nothing to go on), Prices' entry, and
-- the method used.
function Post:Suggest(itemID, listings)
    if not itemID then return nil end
    -- Live listings Razzle's Sell tab has for this item, so the price filled
    -- in agrees with the one the tab shows.
    if listings == nil and MF.Broker and MF.Broker.LiveListings then
        listings = MF.Broker:LiveListings(itemID)
    end
    local options, p = self:PriceOptions(itemID, listings)
    local method = self.db.global.method or "market"
    if not METHOD_LABEL[method] then method = "market" end
    local value = options[method]
    if not value then method, value = "market", options.market end
    if not value then return nil, p end
    return Post.RoundPrice(value), p, method
end

local function itemIDFrom(itemLocation)
    if not itemLocation then return nil end
    if C_Item and C_Item.GetItemID and (not itemLocation.IsValid or itemLocation:IsValid()) then
        local ok, id = pcall(C_Item.GetItemID, itemLocation)
        if ok then return id end
    end
end

local pending = {}  -- sellFrame -> token of the latest selection
local selected = {} -- sellFrame -> item ID of the latest selection

-- Called after Blizzard's sell frame takes an item.
function Post:OnItemSet(sellFrame, itemLocation)
    -- Every selection invalidates any price still waiting to be filled in,
    -- so a quick second pick can't get the first item's price.
    pending[sellFrame] = (pending[sellFrame] or 0) + 1
    local token = pending[sellFrame]
    -- Which item each frame holds is tracked even while Post is off, so
    -- SellFrameFor never vouches for an item that has since been swapped.
    local itemID = itemIDFrom(itemLocation)
    selected[sellFrame] = itemID
    if not self:IsEnabled() then return end
    if not itemID then return end
    local suggestion, p = self:Suggest(itemID)
    self:SendMessage("MF_POST_ITEM_SELECTED", itemID, suggestion, p)
    if not (suggestion and self.db.global.fillPrice) then return end
    -- Blizzard fills in its own default price right after SetItem; set ours
    -- on the next frame so it sticks.
    C_Timer.After(0, function()
        if pending[sellFrame] ~= token or not Post:IsEnabled() then return end
        local input = sellFrame.PriceInput
        if input and input.SetAmount and sellFrame:IsShown() then
            input:SetAmount(suggestion)
        end
    end)
end

-- Blizzard's sell frame showing this item right now (the one it went in
-- last), or nil. Razzle's Sell tab only touches a price box through this,
-- so it can never change the price of a different item.
function Post:SellFrameFor(itemID)
    local window = AuctionHouseFrame
    if not (window and itemID) then return nil end
    for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local sellFrame = window[key]
        if sellFrame and sellFrame.IsShown and sellFrame:IsShown() and selected[sellFrame] == itemID then
            return sellFrame
        end
    end
end

-- Hooks each sell frame once. Hooks can't be removed, so OnItemSet checks
-- IsEnabled() itself.
function Post:HookSellFrames()
    local window = AuctionHouseFrame
    if not (window and hooksecurefunc) then return false end
    self.hooked = self.hooked or {}
    local any = false
    for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local sellFrame = window[key]
        if sellFrame and sellFrame.SetItem and not self.hooked[sellFrame] then
            hooksecurefunc(sellFrame, "SetItem", function(frame, itemLocation)
                Post:OnItemSet(frame, itemLocation)
            end)
            self.hooked[sellFrame] = true
        end
        any = any or (sellFrame ~= nil and self.hooked[sellFrame] == true)
    end
    return any
end

function Post:AUCTION_HOUSE_SHOW()
    if self:HookSellFrames() then return end
    -- The modern AH UI loads on demand; try again shortly.
    local tries = 0
    local function retry()
        if Post:HookSellFrames() or tries >= 10 then return end
        tries = tries + 1
        C_Timer.After(0.1, retry)
    end
    C_Timer.After(0.1, retry)
end

-- How many to put up: everything you hold, unless that's more than the
-- market holds right now (other sellers' listed units, at least one full
-- stack), so a pile doesn't sit unsold. Returns the quantity and whether
-- it was capped.
function Post.SuggestQuantity(owned, listed, stackSize)
    if not owned or owned < 1 then return 1, false end
    local cap = math.max(listed or 0, stackSize or 1, 1)
    if owned > cap then return cap, true end
    return owned, false
end

local DURATION_NAMES = { "12 hours", "24 hours", "48 hours" }

-- Unbound copies of an item in your bags, and the first one's location.
local function findInBags(itemID)
    local count, location = 0, nil
    if not (C_Container and C_Container.GetContainerNumSlots) then return 0 end
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isBound then
                count = count + (info.stackCount or 1)
                if not location and ItemLocation and ItemLocation.CreateFromBagAndSlot then
                    location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                end
            end
        end
    end
    return count, location
end

-- Something else wants this shift-click: a chat box, the AH search box or
-- one of Razzle's boxes.
local function typingSomewhere()
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return true end
    local window = AuctionHouseFrame
    local box = window and window.SearchBar and window.SearchBar.SearchBox
    if box and box.HasFocus and box:HasFocus() then return true end
    local razzle = MarketForcesRazzleFrame
    for _, key in ipairs({ "box", "flipBox" }) do
        local b = razzle and razzle[key]
        if b and b.HasFocus and b:HasFocus() then return true end
    end
    return false
end

-- Puts a bag item up for sale at the open auction house: sell slot, price
-- (via OnItemSet), quantity and duration. Never posts. Returns Razzle's
-- line, or nil when the click isn't ours to handle.
function Post:SellFromBags(link, location)
    local window = AuctionHouseFrame
    local scan = MF.Scan
    if not (window and window.SetPostItem and scan and scan:IsAuctionHouseOpen()) then return nil end
    local itemID = MF.Prices and MF.Prices.ParseItemID(link)
    if not itemID then return nil end
    local owned, found = findInBags(itemID)
    location = location or found
    local name = MF.Broker and MF.Broker.ItemName(itemID) or ("item #" .. itemID)
    if owned < 1 or not location then
        return "Can't sell " .. name .. ", boss: it's bound, or not in your bags."
    end
    if C_AuctionHouse and C_AuctionHouse.IsSellItemValid then
        local ok, valid = pcall(C_AuctionHouse.IsSellItemValid, location, false)
        if ok and not valid then return "The auction house won't take " .. name .. ", boss." end
    end
    -- The duration Blizzard's sell frames start with is remembered in a
    -- CVar; set it first so it sticks even if the dropdown can't be set.
    local duration = self.db.global.duration
    if SetCVar then pcall(SetCVar, "auctionHouseDurationDropdown", duration) end
    local before = {}
    for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        if window[key] then before[window[key]] = pending[window[key]] end
    end
    if not pcall(window.SetPostItem, window, location) then
        return "I couldn't open the sell slot. Drag " .. name .. " in yourself, boss."
    end
    local p = MF.Prices and MF.Prices:GetPrice(itemID)
    local stackSize = select(8, (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID))
    local quantity, capped = Post.SuggestQuantity(owned, p and p.quantity, tonumber(stackSize))
    -- The sell frame now holding this item, and its selection token, so a
    -- different pick before the next frame doesn't get this item's numbers.
    -- Blizzard can decline without an error (item data not loaded yet, a
    -- multisell running), so only a fresh selection of this item counts.
    local target, token
    for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
        local sellFrame = window[key]
        if sellFrame and sellFrame.IsShown and sellFrame:IsShown() and pending[sellFrame] ~= before[sellFrame]
            and selected[sellFrame] == itemID then
            target, token = sellFrame, pending[sellFrame]
            break
        end
    end
    if not target then
        return "The auction house didn't take " .. name .. " just now. Give it a moment and try again, boss."
    end
    -- After Blizzard (and OnItemSet's price) settle, on the next frame.
    C_Timer.After(0, function()
        if not (target and Post:IsEnabled() and pending[target] == token and target:IsShown()) then return end
        local qty = target.QuantityInput
        if qty and qty.SetQuantity then pcall(qty.SetQuantity, qty, quantity) end
        local drop = target.Duration or target.DurationDropdown
        if drop and drop.SetDuration then pcall(drop.SetDuration, drop, duration) end
    end)
    local suggestion = self:Suggest(itemID)
    local line = string.format("Putting up %d %s", quantity, name)
    if suggestion and self.db.global.fillPrice then
        line = line .. " at " .. MF.Util.FormatMoney(suggestion) .. " each"
    end
    line = line .. " for " .. (DURATION_NAMES[duration] or "24 hours") .. "."
    if capped then
        line = line .. string.format(" You've got %d, but the market only holds about %d right now.",
            owned, quantity)
    end
    return line .. " Check it and click Post when you're happy."
end

-- Shift-click on a bag item. Blizzard passes the item's location on modern
-- clients; otherwise we find it by item ID.
function Post:OnModifiedClick(link, location)
    if not (self:IsEnabled() and self.db.global.shiftSell) then return end
    if not (IsShiftKeyDown and IsShiftKeyDown()) or typingSomewhere() then return end
    if location and location.IsBagAndSlot and not location:IsBagAndSlot() then return end
    local line = self:SellFromBags(link, location)
    if line then self:SendMessage("MF_POST_SAYS", line) end
end

function Post:OnInitialize()
    MF:RegisterSlashCommand("autofill", "Toggle Razzle filling in sell prices", function()
        Post.db.global.fillPrice = not Post.db.global.fillPrice
        MF:Print("Razzle", Post.db.global.fillPrice and "will fill in sell prices with market value"
            or "won't touch the sell price")
    end)
    MF:RegisterSlashCommand("shiftsell", "Toggle shift-clicking bag items into the sell slot", function()
        Post.db.global.shiftSell = not Post.db.global.shiftSell
        MF:Print("Shift-click", Post.db.global.shiftSell and "puts bag items up for sale at the auction house"
            or "no longer puts items up for sale")
    end)
    MF:RegisterSlashCommand("pricing",
        "How Razzle prices sales: /mf pricing market, median, trimmed, undercut, match or history", function(args)
        local key = (args or ""):lower():match("^%s*(%S*)")
        if not METHOD_LABEL[key] then
            MF:Print("Use /mf pricing market, median, trimmed, undercut, match or history. Now:",
                METHOD_LABEL[Post.db.global.method] or METHOD_LABEL.market)
            return
        end
        Post.db.global.method = key
        MF:Print("Razzle will price sales by", METHOD_LABEL[key])
    end)
    MF:RegisterSlashCommand("duration", "Sell duration: /mf duration 12, 24 or 48", function(args)
        local hours = tonumber(args)
        local value = hours == 12 and 1 or hours == 24 and 2 or hours == 48 and 3
        if not value then
            MF:Print("Use /mf duration 12, 24 or 48. Now:", DURATION_NAMES[Post.db.global.duration])
            return
        end
        Post.db.global.duration = value
        MF:Print("Razzle will list for", DURATION_NAMES[value])
    end)
    -- Hooked once; OnModifiedClick checks IsEnabled() itself.
    if hooksecurefunc and HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link, location) Post:OnModifiedClick(link, location) end)
    end
end

function Post:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    -- Turned on with the auction house already open: hook it now.
    if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then
        self:AUCTION_HOUSE_SHOW()
    end
end
