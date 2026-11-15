-- MarketForces Prices module.
--
-- Turns each scan into price history for the auction house it came from and
-- answers "what is this item worth?" for the other modules.
--
-- Two numbers per item:
--   market     smoothed market value. Each scan gives a "scan value": the
--              average price of the cheapest 30% of units listed, so a few
--              silly high listings can't drag it up. Scan values are kept per
--              day, and market blends the days, with recent days counting
--              more (a day's weight halves every 7 days).
--   minBuyout  the cheapest buyout per unit in the latest scan: what you'd be
--              undercutting right now.
--
-- History older than historyDays (30 by default) is pruned, and items not
-- seen in that long are forgotten, so saved data stays small and current.
--
-- Saved per auction house in db.ah.items[itemID]:
--   l = minBuyout of the latest scan, q = units listed, t = time last seen,
--   d = { [dayNumber] = { sum of that day's scan values, number of scans } }
local _, MF = ...

local Util = MF.Util

local Prices = MF:NewModule("Prices", {
    global = {
        historyDays = 30,  -- days of history kept
        halfLifeDays = 7,  -- a day's weight in market value halves this often
        cheapShare = 0.3,  -- share of the cheapest units a scan value averages
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

-- Blends daily values: weight halves every halfLife days back from today.
local function blend(days, today, halfLife)
    local weighted, weights = 0, 0
    for day, entry in pairs(days) do
        local age = today - day
        if age < 0 then age = 0 end
        local w = 0.5 ^ (age / halfLife)
        weighted = weighted + (entry[1] / entry[2]) * w
        weights = weights + w
    end
    if weights == 0 then return nil end
    return floor(weighted / weights + 0.5)
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
            else
                entry.d[today] = { value, 1 }
            end
            recorded = recorded + 1
        end
    end
    -- Items listed before but missing from this scan are sold out.
    for itemID, entry in pairs(store) do
        if not snapshot.items[itemID] and entry.t and entry.t < snapshot.time then
            entry.q = 0
            entry.l = nil
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
--   market, minBuyout, quantity, lastSeen, days (days of history)
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
    return {
        market = blend(entry.d, dayNumber(time()), self.db.global.halfLifeDays),
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
