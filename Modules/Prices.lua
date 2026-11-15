-- MarketForces Prices module.
--
-- Turns each scan into price history for the auction house it came from and
-- answers "what is this item worth?" for the other modules.
--
-- Two numbers per item:
--   market     smoothed market value. Each scan gives a "scan value": the
--              average price of the cheapest 30% of units listed, so a few
--              silly high listings can't drag it up. Each day keeps its
--              lowest scan value, and market blends the days. Recent days
--              count more (a day's weight halves every 7 days), and so do
--              cheap days: a day's weight shrinks with the square of how far
--              it sits above the cheapest day, so a run of high asking
--              prices can't outweigh a realistic low price.
--   minBuyout  the cheapest buyout per unit in the latest scan: what you'd be
--              undercutting right now.
--
-- History older than historyDays (30 by default) is pruned, and items not
-- seen in that long are forgotten, so saved data stays small and current.
--
-- Saved per auction house in db.ah.items[itemID]:
--   l = minBuyout of the latest scan, q = units listed, t = time last seen,
--   d = { [dayNumber] = { sum of that day's scan values, number of scans,
--                         lowest scan value that day } }
--   (Entries saved before the third field existed use the day's average.)
--   b = the latest scan's cheapest listings as a flat { unitPrice, units,
--       unitPrice, units, ... } ladder, cheapest first, same prices merged:
--       every price below market value (up to ladderSteps of them) plus the
--       first one at or above it. bm = true when cheaper-than-market
--       listings were left off the end. Flip advice reads these.
local _, MF = ...

local Util = MF.Util

local Prices = MF:NewModule("Prices", {
    global = {
        historyDays = 30,  -- days of history kept
        halfLifeDays = 7,  -- a day's weight in market value halves this often
        cheapShare = 0.3,  -- share of the cheapest units a scan value averages
        lowWeight = 2,     -- how hard market value leans toward the cheapest days (0 = not at all)
        ladderSteps = 12,  -- cheapest price steps kept from the latest scan
    },
    ah = {
        items = {},
    },
})
MF.Prices = Prices

local floor = math.floor
local DAY = 24 * 60 * 60

local function dayNumber(t)
    return floor(t / DAY)
end

-- Average unit price of the cheapest share of units in a list of
-- { unitPrice, count } listings. Returns nil for an empty list.
function Prices.ScanValue(listings, share)
    if not listings or #listings == 0 then return nil end
    share = share or 0.3
    local sorted = {}
    local totalUnits = 0
    for i, listing in ipairs(listings) do
        sorted[i] = listing
        totalUnits = totalUnits + listing[2]
    end
    table.sort(sorted, function(a, b) return a[1] < b[1] end)

    local wanted = math.max(1, math.ceil(totalUnits * share))
    local units, sum = 0, 0
    for _, listing in ipairs(sorted) do
        local take = math.min(listing[2], wanted - units)
        sum = sum + listing[1] * take
        units = units + take
        if units >= wanted then break end
    end
    return floor(sum / units + 0.5)
end

-- A day's value: its lowest scan value, or its average for older entries.
local function dayValue(entry)
    return entry[3] or (entry[1] / entry[2])
end

-- Blends daily values. A day's weight halves every halfLife days back from
-- today, and is multiplied by (cheapest day's value / its value) ^ lowWeight,
-- so days far above the cheapest barely count.
local function blend(days, today, halfLife, lowWeight)
    local lowest
    for _, entry in pairs(days) do
        local v = dayValue(entry)
        if v > 0 and (not lowest or v < lowest) then lowest = v end
    end
    local weighted, weights = 0, 0
    for day, entry in pairs(days) do
        local v = dayValue(entry)
        if v > 0 then
            local age = today - day
            if age < 0 then age = 0 end
            local w = 0.5 ^ (age / halfLife) * (lowest / v) ^ (lowWeight or 0)
            weighted = weighted + v * w
            weights = weights + w
        end
    end
    if weights == 0 then return nil end
    return floor(weighted / weights + 0.5)
end
Prices.Blend = blend

-- The cheapest listings as a flat ladder (see the header), or nil, more.
function Prices.Ladder(listings, market, steps)
    if not listings or #listings == 0 then return nil end
    local sorted = {}
    for i, listing in ipairs(listings) do sorted[i] = listing end
    table.sort(sorted, function(a, b) return a[1] < b[1] end)
    local flat, more = {}, nil
    for _, listing in ipairs(sorted) do
        local n = #flat
        if n > 0 and flat[n - 1] == listing[1] then
            flat[n] = flat[n] + listing[2]
        else
            -- The step before this one is already at or above market: done.
            if n > 0 and (not market or flat[n - 1] >= market) then break end
            if n / 2 >= steps then
                more = true
                break
            end
            flat[n + 1], flat[n + 2] = listing[1], listing[2]
        end
    end
    return flat, more
end

-- Records a scan snapshot (from MF_SCAN_COMPLETE) into history.
function Prices:RecordSnapshot(snapshot)
    local store = self:ItemsFor(snapshot.key)
    local today = dayNumber(snapshot.time)
    local share = self.db.global.cheapShare
    local recorded = 0
    for itemID, item in pairs(snapshot.items) do
        local entry = store[itemID]
        if not entry then
            entry = { d = {} }
            store[itemID] = entry
        end
        entry.q = item.quantity
        entry.t = snapshot.time
        entry.l = item.minBuyout
        local value = Prices.ScanValue(item.listings, share)
        if value then
            local day = entry.d[today]
            if day then
                day[1] = day[1] + value
                day[2] = day[2] + 1
                day[3] = math.min(day[3] or (day[1] - value) / (day[2] - 1), value)
            else
                entry.d[today] = { value, 1, value }
            end
            recorded = recorded + 1
        end
        local market = blend(entry.d, today, self.db.global.halfLifeDays, self.db.global.lowWeight)
        entry.b, entry.bm = Prices.Ladder(item.listings, market, self.db.global.ladderSteps or 12)
    end
    -- Items listed before but missing from this scan are sold out.
    for itemID, entry in pairs(store) do
        if not snapshot.items[itemID] and entry.t and entry.t < snapshot.time then
            entry.q = 0
            entry.l = nil
            entry.b, entry.bm = nil, nil
        end
    end
    self:Prune(snapshot.key, snapshot.time)
    self:Debug("recorded %d items for %s", recorded, snapshot.key)
    self:SendMessage("MF_PRICES_UPDATED", snapshot.key)
end

-- The items table for an auction house key (current house if nil).
function Prices:ItemsFor(key)
    if not key or key == MF.db.ahKey then
        self.db.ah.items = self.db.ah.items or {}
        return self.db.ah.items
    end
    local house = MarketForcesDB.auctionHouses[key]
    if not house then
        house = {}
        MarketForcesDB.auctionHouses[key] = house
    end
    house.Prices = house.Prices or {}
    house.Prices.items = house.Prices.items or {}
    return house.Prices.items
end

-- Drops an entry's days older than historyDays. Returns true when the
-- whole entry has expired (no history and not seen within historyDays).
function Prices:PruneEntry(entry, now)
    local keep = self.db.global.historyDays
    local oldest = dayNumber(now) - keep + 1
    for day in pairs(entry.d) do
        if day < oldest then entry.d[day] = nil end
    end
    return next(entry.d) == nil and (entry.t or 0) < now - keep * DAY
end

-- Drops days older than historyDays and items with no history left.
function Prices:Prune(key, now)
    now = now or time()
    local store = self:ItemsFor(key)
    for itemID, entry in pairs(store) do
        if self:PruneEntry(entry, now) then store[itemID] = nil end
    end
end

-- Prices for an item at an auction house (current house if key is nil).
-- Returns nil if the item has never been seen, otherwise a table:
--   market, minBuyout, quantity, lastSeen, days (days of history),
--   ladder = { {unitPrice, units}, ... } cheapest listings of the latest
--   scan (see the header; may be empty), ladderMore = listings left off
function Prices:GetPrice(itemID, key)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local store = self:ItemsFor(key)
    local entry = store[itemID]
    if not entry then return nil end
    -- Any house's data may be old (e.g. a neutral AH not visited in weeks).
    if self:PruneEntry(entry, time()) then
        store[itemID] = nil
        return nil
    end
    local days = 0
    for _ in pairs(entry.d) do days = days + 1 end
    local ladder = {}
    if entry.b then
        for i = 1, #entry.b - 1, 2 do ladder[#ladder + 1] = { entry.b[i], entry.b[i + 1] } end
    end
    return {
        ladder = ladder,
        ladderMore = entry.bm == true,
        market = blend(entry.d, dayNumber(time()), self.db.global.halfLifeDays, self.db.global.lowWeight),
        minBuyout = entry.l,
        quantity = entry.q or 0,
        lastSeen = entry.t,
        days = days,
    }
end

-- Item ID from a number, "12345", or an item link.
function Prices.ParseItemID(text)
    if type(text) == "number" then return text end
    if type(text) ~= "string" then return nil end
    return tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
end

function Prices:MF_SCAN_COMPLETE(_, snapshot)
    self:RecordSnapshot(snapshot)
end

function Prices:OnInitialize()
    MF:RegisterSlashCommand("price", "Prices for an item: /mf price <item link or ID>", function(args)
        local itemID = Prices.ParseItemID(args)
        if not itemID then
            MF:Print("Shift-click an item into chat after /mf price, or give its item ID.")
            return
        end
        local p = Prices:GetPrice(itemID)
        if not p then
            MF:Printf("No prices for item %d at %s yet. Run a scan first.", itemID, MF.db.ahKey or "this auction house")
            return
        end
        local money = Util.FormatMoney
        MF:Printf("Item %d at %s:", itemID, MF.db.ahKey)
        MF:Print("  Market value: " .. (p.market and money(p.market) or "none yet")
            .. " (" .. p.days .. (p.days == 1 and " day" or " days") .. " of history)")
        MF:Print("  Cheapest now: " .. (p.minBuyout and money(p.minBuyout) or "none listed")
            .. ", " .. p.quantity .. " listed")
    end)
end

function Prices:MF_AUCTION_HOUSE_CHANGED(_, key)
    self:Prune(key, time())
end

function Prices:OnEnable()
    self:RegisterMessage("MF_SCAN_COMPLETE")
    self:RegisterMessage("MF_AUCTION_HOUSE_CHANGED")
    self:Prune(nil, time())
end
