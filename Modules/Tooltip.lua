-- MarketForces Tooltip module.
--
-- Adds Razzle's prices to item tooltips: market value and the cheapest
-- current listing at the auction house you last used. Reads prices from the
-- Prices module; shows nothing for items that have never been scanned.
local _, MF = ...

local Util = MF.Util

local Tooltip = MF:NewModule("Tooltip", {
    global = {
        show = true,
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

-- The lines Razzle adds for an item: list of { left, right }. Empty when
-- there's nothing to say. Kept separate from the tooltip so it's testable.
function Tooltip:LinesFor(itemID)
    local prices = MF.Prices
    if not (prices and prices:IsEnabled() and itemID) then return {} end
    local p = prices:GetPrice(itemID)
    if not p then return {} end
    local lines = {}
    if p.market then
        lines[#lines + 1] = { "Razzle's market value", Util.FormatMoney(p.market) }
    end
    if p.minBuyout then
        lines[#lines + 1] = { "Cheapest listed", Util.FormatMoney(p.minBuyout) .. " (" .. p.quantity .. ")" }
    elseif p.lastSeen then
        lines[#lines + 1] = { "Cheapest listed", "none right now" }
    end
    if p.lastSeen then
        lines[#lines + 1] = { "Last scanned", ago(time() - p.lastSeen) }
    end
    return lines
end

function Tooltip:Decorate(tooltip, itemID)
    if not (self:IsEnabled() and self.db.global.show) then return end
    local lines = self:LinesFor(itemID)
    if #lines == 0 then return end
    for _, line in ipairs(lines) do
        tooltip:AddDoubleLine(line[1], line[2],
            LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3])
    end
    tooltip:Show()
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
            Tooltip:Decorate(tooltip, itemIDFromTooltip(tooltip, data))
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        local function onSetItem(tooltip) Tooltip:Decorate(tooltip, itemIDFromTooltip(tooltip)) end
        GameTooltip:HookScript("OnTooltipSetItem", onSetItem)
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onSetItem) end
    end
end

function Tooltip:OnInitialize()
    MF:RegisterSlashCommand("tooltip", "Turn tooltip prices on or off", function()
        Tooltip.db.global.show = not Tooltip.db.global.show
        MF:Print("Tooltip prices", Tooltip.db.global.show and "on" or "off")
    end)
end

function Tooltip:OnEnable()
    self:Hook()
end
