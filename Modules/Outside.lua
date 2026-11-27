-- MarketForces Outside module.
--
-- Prices from other auction addons you may have installed, for items Razzle
-- hasn't scanned yet. Reads TradeSkillMaster (TSM_API) and Auctionator
-- (Auctionator.API.v1) in game through their public addon APIs; it never
-- reaches the internet. Ported from AuctioneerModern's TSM fallback.
--
-- Prices read live are cached per auction house for cacheDays, so a
-- character without TSM or Auctionator loaded still gets them (log in once
-- on a character that has them and hover or check the items).
--
-- Outside prices are always labelled with where they came from and never
-- mixed into Razzle's own market value.
local _, MF = ...

local Util = MF.Util

local Outside = MF:NewModule("Outside", {
    global = {
        show = "missing",  -- tooltip line: "missing" (only with no own price), "always" or "off"
        tsmSources = { "DBMarket", "DBRegionMarketAvg" },
        auctionator = true,
        cacheDays = 7,
    },
    ah = {
        cache = {}, -- [itemID] = { price, source label, time() read }
    },
})
MF.Outside = Outside

local DAY = 24 * 60 * 60

-- Live TSM price: price, label, or nil.
function Outside.FromTSM(itemID, sources)
    local api = _G.TSM_API
    if not (api and api.GetCustomPriceValue) then return nil end
    for _, source in ipairs(sources or {}) do
        local ok, price = pcall(api.GetCustomPriceValue, source, "i:" .. itemID)
        if ok and type(price) == "number" and price > 0 then
            return math.floor(price), "TSM " .. source
        end
    end
    return nil
end

-- Live Auctionator price: price, label, or nil.
function Outside.FromAuctionator(itemID)
    local a = _G.Auctionator
    local api = a and a.API and a.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "MarketForces", itemID)
    if ok and type(price) == "number" and price > 0 then
        return math.floor(price), "Auctionator"
    end
    return nil
end

-- Outside price for an item at the current auction house:
-- price, label, cachedAt (nil when read live), or nil.
function Outside:GetPrice(itemID)
    itemID = tonumber(itemID)
    if not (itemID and self:IsEnabled()) then return nil end
    local g = self.db.global
    local price, label = Outside.FromTSM(itemID, g.tsmSources)
    if not price and g.auctionator then
        price, label = Outside.FromAuctionator(itemID)
    end
    local cache = self.db.ah.cache
    if price then
        cache[itemID] = { price, label, time() }
        return price, label, nil
    end
    local hit = cache[itemID]
    if hit then
        if hit[3] >= time() - g.cacheDays * DAY then
            return hit[1], hit[2], hit[3]
        end
        cache[itemID] = nil
    end
    return nil
end

-- Drops cached prices older than cacheDays.
function Outside:Prune()
    local cutoff = time() - self.db.global.cacheDays * DAY
    for itemID, hit in pairs(self.db.ah.cache) do
        if (hit[3] or 0) < cutoff then self.db.ah.cache[itemID] = nil end
    end
end

-- Tooltip line text for an item, or nil. hasOwn: Razzle has its own price.
function Outside:Line(itemID, hasOwn)
    local mode = self.db.global.show
    if mode == "off" or (mode == "missing" and hasOwn) then return nil end
    local price, label, cachedAt = self:GetPrice(itemID)
    if not price then return nil end
    local text = Util.FormatMoney(price) .. " (" .. label
    if cachedAt then
        local age = time() - cachedAt
        text = text .. ", " .. (age < DAY and "today" or (math.floor(age / DAY) .. "d old"))
    end
    return text .. ")"
end

function Outside:OnInitialize()
    MF:RegisterSlashCommand("outside",
        "Prices from TSM or Auctionator on tooltips: /mf outside [missing | always | off]", function(args)
            local mode = Util.SplitFirstWord(args):lower()
            if mode == "missing" or mode == "always" or mode == "off" then
                Outside.db.global.show = mode
            end
            local g = Outside.db.global
            local found = {}
            if _G.TSM_API then found[#found + 1] = "TSM" end
            if _G.Auctionator and _G.Auctionator.API then found[#found + 1] = "Auctionator" end
            MF:Print("Outside prices on tooltips: " .. g.show .. ". Loaded now: "
                .. (#found > 0 and table.concat(found, ", ") or "none (using cached prices)"))
        end)
end

function Outside:MF_AUCTION_HOUSE_CHANGED()
    self:Prune()
end

function Outside:OnEnable()
    self:RegisterMessage("MF_AUCTION_HOUSE_CHANGED")
    self:Prune()
end
