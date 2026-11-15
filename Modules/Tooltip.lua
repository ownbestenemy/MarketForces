-- MarketForces Tooltip module.
--
-- Adds Razzle's prices to item tooltips: market value and the cheapest
-- current listing at the auction house you last used, plus Razzle's advice:
-- buy it (listed well under market or under vendor price), auction it, or
-- vendor it (when the AH wouldn't pay more after its 5% cut). Reads prices from the
-- Prices module; shows nothing for items that have never been scanned.
local _, MF = ...

local Util = MF.Util

local Tooltip = MF:NewModule("Tooltip", {
    global = {
        show = true,
        advice = true, -- the "Razzle says" line
    },
})
MF.Tooltip = Tooltip

local LABEL_COLOR = { 1, 0.82, 0 }      -- gold labels
local VALUE_COLOR = { 1, 1, 1 }

local function ago(seconds)
    if seconds < 3600 then return math.max(1, math.floor(seconds / 60)) .. "m ago" end
    if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
    return math.floor(seconds / 86400) .. "d ago"
end

local AH_CUT = 0.05 -- the auction house keeps 5% of a sale

-- Vendor sell price per unit (0 if it can't be sold to a vendor).
function Tooltip.VendorPrice(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return 0 end
    local sellPrice = select(11, getInfo(itemID))
    return tonumber(sellPrice) or 0
end

-- Razzle's advice for an item: "Buy it", "Auction it" or "Vendor it" with a
-- short reason, or nil when there's nothing useful to say.
--   p           price table from Prices:GetPrice (may be nil)
--   vendor      vendor sell price per unit
--   dealRatio   a listing this far under market value counts as a bargain
--   bound       true when the copy under the mouse is soulbound or account
--               bound, so it can't go on the auction house
function Tooltip.Advice(p, vendor, dealRatio, bound)
    vendor = vendor or 0
    dealRatio = dealRatio or 0.7
    if bound then
        if vendor > 0 then return "Vendor it", "yours is bound, so it can't be auctioned" end
        return nil
    end
    local market = p and p.market
    local cheapest = p and p.minBuyout
    if cheapest and vendor > 0 and cheapest < vendor then
        return "Buy it", "listed below vendor price"
    end
    if cheapest and market and cheapest <= market * dealRatio then
        return "Buy it", math.floor((1 - cheapest / market) * 100 + 0.5) .. "% under market"
    end
    if market then
        local net = math.floor(market * (1 - AH_CUT))
        if vendor > 0 and net <= vendor then
            return "Vendor it", "the auction house pays no better"
        end
        return "Auction it", "about " .. Util.FormatMoney(net) .. " after the AH cut"
    end
    if vendor > 0 then
        return "Vendor it", "no auction prices yet"
    end
    return nil
end

-- The lines Razzle adds for an item: list of { left, right }. Empty when
-- there's nothing to say. Kept separate from the tooltip so it's testable.
-- bound: the tooltip's copy of the item is bound (see IsBoundTooltip).
function Tooltip:LinesFor(itemID, bound)
    local prices = MF.Prices
    if not (prices and prices:IsEnabled() and itemID) then return {} end
    local p = prices:GetPrice(itemID)
    local lines = {}
    if p and p.market then
        lines[#lines + 1] = { "Razzle's market value", Util.FormatMoney(p.market) }
    end
    if p and p.minBuyout then
        lines[#lines + 1] = { "Cheapest listed", Util.FormatMoney(p.minBuyout) .. " (" .. p.quantity .. ")" }
    elseif p and p.lastSeen then
        lines[#lines + 1] = { "Cheapest listed", "none right now" }
    end
    if p and p.lastSeen then
        lines[#lines + 1] = { "Last scanned", ago(time() - p.lastSeen) }
    end
    if self.db.global.advice then
        local broker = MF.Broker
        local ratio = broker and broker.db and broker.db.global.dealRatio or 0.7
        local verdict, why = Tooltip.Advice(p, Tooltip.VendorPrice(itemID), ratio, bound)
        if verdict then
            lines[#lines + 1] = { "Razzle says", verdict .. " (" .. why .. ")" }
        end
    end
    return lines
end

function Tooltip:Decorate(tooltip, itemID, data)
    if not (self:IsEnabled() and self.db.global.show) then return end
    local lines = self:LinesFor(itemID, Tooltip.IsBoundTooltip(tooltip, data))
    if #lines == 0 then return end
    for _, line in ipairs(lines) do
        tooltip:AddDoubleLine(line[1], line[2],
            LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3])
    end
    tooltip:Show()
end

-- Tooltip text that means this copy can't be traded. Prices are kept by
-- item ID, so a bound copy still gets the unbound copies' prices; the
-- advice must not tell the player to auction it.
local function boundTexts()
    local texts = {}
    for _, name in ipairs({ "ITEM_SOULBOUND", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND" }) do
        local text = _G[name]
        if type(text) == "string" then texts[text] = true end
    end
    if not next(texts) then texts["Soulbound"] = true end
    return texts
end

-- True when the item on this tooltip is bound. Reads the tooltip data's lines
-- (modern client) and the tooltip's own text lines (any client).
function Tooltip.IsBoundTooltip(tooltip, data)
    local texts = boundTexts()
    if data and type(data.lines) == "table" then
        for _, line in ipairs(data.lines) do
            if line.leftText and texts[line.leftText] then return true end
        end
    end
    local name = tooltip and tooltip.GetName and tooltip:GetName()
    local count = tooltip and tooltip.NumLines and tooltip:NumLines() or 0
    if name then
        for i = 1, count do
            local fontString = _G[name .. "TextLeft" .. i]
            local text = fontString and fontString.GetText and fontString:GetText()
            if text and texts[text] then return true end
        end
    end
    return false
end

local function itemIDFromTooltip(tooltip, data)
    if data and data.id then return data.id end
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then return tonumber(link:match("item:(%d+)")) end
    end
end

-- Hooks can't be removed once added, so we hook once and check
-- IsEnabled() each time instead.
function Tooltip:Hook()
    if self.hooked then return end
    self.hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            Tooltip:Decorate(tooltip, itemIDFromTooltip(tooltip, data), data)
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        local function onSetItem(tooltip) Tooltip:Decorate(tooltip, itemIDFromTooltip(tooltip)) end
        GameTooltip:HookScript("OnTooltipSetItem", onSetItem)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onSetItem) end
    end
end

function Tooltip:OnInitialize()
    MF:RegisterSlashCommand("advice", "Turn Razzle's buy/auction/vendor advice on tooltips on or off", function()
        Tooltip.db.global.advice = not Tooltip.db.global.advice
        MF:Print("Razzle's tooltip advice", Tooltip.db.global.advice and "on" or "off")
    end)
    MF:RegisterSlashCommand("tooltip", "Turn tooltip prices on or off", function()
        Tooltip.db.global.show = not Tooltip.db.global.show
        MF:Print("Tooltip prices", Tooltip.db.global.show and "on" or "off")
    end)
end

function Tooltip:OnEnable()
    self:Hook()
end
