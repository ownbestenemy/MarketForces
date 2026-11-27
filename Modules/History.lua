-- MarketForces History module.
--
-- Keeps a ledger of your auction house results by reading the auction mail
-- in your mailbox: what sold (and for how much), what you bought, and what
-- expired or was cancelled. It only reads mail headers while the mailbox is
-- open; it never opens, takes or deletes mail.
--
-- Ported from AuctioneerModern's History, with its bugs fixed:
--   * Sold mail has no item attached, so the item is worked out from its
--     name: names Razzle has seen (items you put in the sell slot, items
--     attached to other auction mail, your bags) or the client's item cache.
--     Sales whose item can't be found yet keep the name and get their item
--     ID filled in as soon as it's learned.
--   * Each mail is counted once. A mail is recognised by what it says (type,
--     item, count, money) and when it arrived, which stays the same however
--     the inbox is reordered and across sessions. Identical mails that
--     arrived together are each matched to their own record.
--   * The ledger is pruned by age (keepDays) and capped (maxRecords).
--
-- Records are account-wide, tagged with the market scope (region + ruleset)
-- and character, and kept in History.db.global.records:
--   k = what the mail says and whose it is, "type|name|count|money|character|scope"
--       (for matching)
--   at = when the mail arrived, s = market scope, c = character
--   type = "sold" | "bought" | "expired" | "cancelled"
--   id = item ID (nil until known), name, n = units
--   money = coin received (sold: after the AH cut)
--   price = sale or purchase price for the whole lot, when the invoice says
local _, MF = ...

local Util = MF.Util

local History = MF:NewModule("History", {
    global = {
        keepDays = 30,     -- days of records kept
        maxRecords = 2000, -- oldest records go first beyond this
        alertOnSale = true,
        records = {},
        names = {},        -- [item name] = item ID, learned along the way
    },
})
MF.History = History

local DAY = 24 * 60 * 60
local MAIL_DAYS = 30   -- auction mail lasts this long; used to date each mail
local MATCH_SLACK = 300 -- seconds a mail's worked-out arrival may drift

-- Mail subject patterns, built from the client's own (localised) strings.
local SUBJECTS = {
    { "sold", "AUCTION_SOLD_MAIL_SUBJECT" },
    { "bought", "AUCTION_WON_MAIL_SUBJECT" },
    { "expired", "AUCTION_EXPIRED_MAIL_SUBJECT" },
    { "cancelled", "AUCTION_REMOVED_MAIL_SUBJECT" },
}

local function toPattern(format)
    local escaped = format:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    escaped = escaped:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
    return "^" .. escaped .. "$"
end

local patterns
local function subjectPatterns()
    if patterns then return patterns end
    patterns = {}
    for _, entry in ipairs(SUBJECTS) do
        local format = _G[entry[2]]
        if type(format) == "string" and format:find("%%s") then
            patterns[#patterns + 1] = { entry[1], toPattern(format) }
        end
    end
    return patterns
end

-- Mail type and item name for an auction mail subject, or nil. Strips a
-- trailing stack count "Name (20)" and returns it as the third value.
function History.ParseSubject(subject)
    if type(subject) ~= "string" then return nil end
    for _, p in ipairs(subjectPatterns()) do
        local name = subject:match(p[2])
        if name then
            local base, count = name:match("^(.-)%s*%((%d+)%)$")
            if base and base ~= "" then return p[1], base, tonumber(count) end
            return p[1], name, nil
        end
    end
    return nil
end

local function itemIDFromLink(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function nameFromLink(link)
    return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

-- Item names ------------------------------------------------------------------

-- Remembers an item's name so later sales of it can be matched, and fills
-- in records that were waiting for it.
function History:LearnItem(itemID, name)
    itemID = tonumber(itemID)
    if not itemID then return end
    if not name then
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        name = getInfo and getInfo(itemID)
    end
    if type(name) ~= "string" or name == "" then return end
    local names = self.db.global.names
    if names[name] == itemID then return end
    names[name] = itemID
    for _, r in ipairs(self.db.global.records) do
        if not r.id and r.name == name then r.id = itemID end
    end
end

-- Item ID for a name: learned names first, then the client's item cache,
-- then your bags. nil when it can't be found (yet).
function History:ResolveName(name)
    if not name then return nil end
    local known = self.db.global.names[name]
    if known then return known end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
        local ok, _, link = pcall(getInfo, name)
        local id = ok and itemIDFromLink(link)
        if id then
            self:LearnItem(id, name)
            return id
        end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID and nameFromLink(info.hyperlink) == name then
                    self:LearnItem(info.itemID, name)
                    return info.itemID
                end
            end
        end
    end
    return nil
end

-- Reading mail ----------------------------------------------------------------

-- An auction mail at an inbox index as a record (not yet saved), or nil.
function History:ReadMail(index, now)
    local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
    local kind, name, subjectCount = History.ParseSubject(subject)
    if not kind then return nil end
    money = money or 0
    local record = {
        type = kind,
        name = name,
        money = money,
        at = math.floor(now - (MAIL_DAYS - (daysLeft or MAIL_DAYS)) * DAY + 0.5),
        s = Util.GetMarketScope(),
        c = UnitName and UnitName("player") or nil,
    }
    local count
    if kind == "sold" or kind == "bought" then
        local invoiceType, _, _, bid, _, _, _, _, _, _, invoiceCount = GetInboxInvoiceInfo(index)
        if invoiceType == "seller" or invoiceType == "buyer" then
            record.price = (bid and bid > 0) and bid or nil
            count = invoiceCount
        end
    end
    if kind ~= "sold" and GetInboxItem then
        -- Bought, expired and cancelled mail carries the item itself.
        local _, attachedID, _, attachedCount = GetInboxItem(index, 1)
        local id = tonumber(attachedID) or (GetInboxItemLink and itemIDFromLink(GetInboxItemLink(index, 1)))
        if id then
            record.id = id
            self:LearnItem(id, name)
        end
        count = count or attachedCount
    end
    record.n = (tonumber(count) and count > 0 and count) or subjectCount or 1
    record.id = record.id or self:ResolveName(name)
    -- The ledger is account-wide, so the same mail text on another character
    -- or in another market scope is a different mail.
    record.k = table.concat({ kind, name, record.n, money, record.c or "", record.s }, "|")
    return record
end

-- Reads every auction mail in the inbox and saves the ones not seen before.
-- Returns how many were new.
function History:ScanInbox()
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return 0 end
    local now = time()
    local records = self.db.global.records
    local byKey = {}
    for _, r in ipairs(records) do
        if r.k then
            byKey[r.k] = byKey[r.k] or {}
            table.insert(byKey[r.k], r)
        end
    end
    local used = {}
    local added = 0
    for index = 1, GetInboxNumItems() or 0 do
        local record = self:ReadMail(index, now)
        if record then
            local match
            for _, r in ipairs(byKey[record.k] or {}) do
                if not used[r] and math.abs((r.at or 0) - record.at) <= MATCH_SLACK then
                    match = r
                    break
                end
            end
            if match then
                used[match] = true
                if not match.id and record.id then match.id = record.id end
                if not match.price and record.price then match.price = record.price end
            else
                records[#records + 1] = record
                added = added + 1
                if record.type == "sold" and self.db.global.alertOnSale and record.at > now - DAY then
                    self:Print("Sold " .. record.name .. (record.n > 1 and (" x" .. record.n) or "")
                        .. " for " .. Util.FormatMoney(record.money))
                end
            end
        end
    end
    if added > 0 then
        self:Prune(now)
        self:SendMessage("MF_HISTORY_UPDATED", added)
    end
    return added
end

-- Drops records older than keepDays, then the oldest beyond maxRecords.
function History:Prune(now)
    now = now or time()
    local g = self.db.global
    local cutoff = now - g.keepDays * DAY
    local kept = {}
    for _, r in ipairs(g.records) do
        if (r.at or 0) >= cutoff then kept[#kept + 1] = r end
    end
    table.sort(kept, function(a, b) return (a.at or 0) < (b.at or 0) end)
    while #kept > g.maxRecords do table.remove(kept, 1) end
    g.records = kept
end

-- Questions -------------------------------------------------------------------

local function inScope(r, scope, since)
    return (r.s == nil or r.s == scope) and (r.at or 0) >= since
end

-- Your results for an item over the last `days` (default keepDays) in the
-- current market scope, or nil when there are none:
--   sold, bought (units), soldListings, expired, cancelled (listings),
--   soldEach (average sale price per unit, before the cut), boughtEach,
--   lastSold, sellThrough (share of finished listings that sold, 0-1)
function History:ItemStats(itemID, days)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    days = days or self.db.global.keepDays
    local since = time() - days * DAY
    local scope = Util.GetMarketScope()
    local s = { sold = 0, bought = 0, soldListings = 0, expired = 0, cancelled = 0 }
    local soldCoin, soldUnits, boughtCoin, boughtUnits = 0, 0, 0, 0
    local any = false
    for _, r in ipairs(self.db.global.records) do
        if r.id == itemID and inScope(r, scope, since) then
            any = true
            if r.type == "sold" then
                s.sold = s.sold + r.n
                s.soldListings = s.soldListings + 1
                soldCoin = soldCoin + (r.price or math.floor(r.money / 0.95 + 0.5))
                soldUnits = soldUnits + r.n
                if not s.lastSold or r.at > s.lastSold then s.lastSold = r.at end
            elseif r.type == "bought" then
                s.bought = s.bought + r.n
                if r.price then
                    boughtCoin = boughtCoin + r.price
                    boughtUnits = boughtUnits + r.n
                end
            elseif r.type == "expired" then
                s.expired = s.expired + 1
            elseif r.type == "cancelled" then
                s.cancelled = s.cancelled + 1
            end
        end
    end
    if not any then return nil end
    if soldUnits > 0 then s.soldEach = math.floor(soldCoin / soldUnits + 0.5) end
    if boughtUnits > 0 then s.boughtEach = math.floor(boughtCoin / boughtUnits + 0.5) end
    local finished = s.soldListings + s.expired + s.cancelled
    if finished > 0 then s.sellThrough = s.soldListings / finished end
    return s
end

-- Totals for the last `days` (default 7) in the current market scope.
function History:Summary(days)
    days = days or 7
    local since = time() - days * DAY
    local scope = Util.GetMarketScope()
    local t = { sales = 0, salesCount = 0, purchases = 0, purchasesCount = 0, expired = 0, cancelled = 0 }
    for _, r in ipairs(self.db.global.records) do
        if inScope(r, scope, since) then
            if r.type == "sold" then
                t.sales = t.sales + r.money
                t.salesCount = t.salesCount + 1
            elseif r.type == "bought" then
                t.purchases = t.purchases + (r.price or 0)
                t.purchasesCount = t.purchasesCount + 1
            elseif r.type == "expired" then
                t.expired = t.expired + 1
            elseif r.type == "cancelled" then
                t.cancelled = t.cancelled + 1
            end
        end
    end
    t.profit = t.sales - t.purchases
    return t
end

-- The newest records in the current market scope, newest first.
function History:Recent(limit)
    local scope = Util.GetMarketScope()
    local out = {}
    for _, r in ipairs(self.db.global.records) do
        if r.s == nil or r.s == scope then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
    while #out > (limit or 10) do table.remove(out) end
    return out
end

-- One line about your own results with an item, for tooltips and Razzle,
-- or nil when you have none.
function History:Line(itemID)
    local s = self:ItemStats(itemID)
    if not s then return nil end
    local parts = {}
    if s.sold > 0 then
        parts[#parts + 1] = s.sold .. " sold" .. (s.soldEach and (" at ~" .. Util.FormatMoney(s.soldEach)) or "")
    end
    local finished = s.soldListings + s.expired + s.cancelled
    if finished > 0 and (s.expired + s.cancelled) > 0 then
        parts[#parts + 1] = s.soldListings .. " of " .. finished .. " listings sold"
    end
    if s.bought > 0 then
        local each = s.boughtEach and (" at ~" .. Util.FormatMoney(s.boughtEach)) or ""
        parts[#parts + 1] = s.bought .. " bought" .. each
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Events ----------------------------------------------------------------------

function History:MAIL_SHOW()
    self.mailOpen = true
    self:QueueScan()
end

function History:MAIL_INBOX_UPDATE()
    if self.mailOpen then self:QueueScan() end
end

function History:MAIL_CLOSED()
    self.mailOpen = false
end

-- The inbox updates in bursts; read it once when the burst settles.
function History:QueueScan()
    if self.scanQueued then return end
    self.scanQueued = true
    C_Timer.After(0.5, function()
        History.scanQueued = false
        if History:IsEnabled() then History:ScanInbox() end
    end)
end

function History:MF_POST_ITEM_SELECTED(_, itemID)
    self:LearnItem(itemID)
end

local TYPE_COLOR = { sold = "|cff33ff33", bought = "|cffffaa33", expired = "|cffff4444", cancelled = "|cffffff33" }

function History:OnInitialize()
    MF:RegisterSlashCommand("history",
        "Your auction results: /mf history [recent | <item link or ID> | clear]", function(args)
            local first = Util.SplitFirstWord(args):lower()
            local money = Util.FormatMoney
            if first == "clear" then
                if args:lower():find("confirm") then
                    History.db.global.records = {}
                    MF:Print("Auction history cleared.")
                else
                    MF:Print("This erases your auction history. Type /mf history clear confirm to do it.")
                end
            elseif first == "recent" then
                local recent = History:Recent(10)
                if #recent == 0 then
                    MF:Print("No auction mail read yet. Open your mailbox and Razzle will keep count.")
                end
                for _, r in ipairs(recent) do
                    local coin = r.type == "sold" and r.money or r.price
                    MF:Print("  " .. (TYPE_COLOR[r.type] or "") .. r.type .. "|r " .. r.name
                        .. (r.n > 1 and (" x" .. r.n) or "") .. (coin and (" " .. money(coin)) or ""))
                end
            elseif first ~= "" then
                local itemID = MF.Prices and MF.Prices.ParseItemID(args) or tonumber(args)
                itemID = itemID or History:ResolveName(args)
                local line = itemID and History:Line(itemID)
                MF:Print(line and ("Your results: " .. line) or "No auction results for that item yet.")
            else
                local t = History:Summary(7)
                MF:Print("Last 7 days:")
                MF:Print("  Sold " .. t.salesCount .. " listings for " .. money(t.sales) .. " (after the cut)")
                MF:Print("  Bought " .. t.purchasesCount .. " for " .. money(t.purchases))
                MF:Print("  Expired " .. t.expired .. ", cancelled " .. t.cancelled)
                MF:Print("  Net " .. money(t.profit))
            end
        end)
end

function History:OnEnable()
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_INBOX_UPDATE")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterMessage("MF_POST_ITEM_SELECTED")
    self:Prune()
end
