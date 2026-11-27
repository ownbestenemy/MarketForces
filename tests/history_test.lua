-- History module: auction mail ledger, item ID for sales, no double counting.
local H = dofile("tests/harness.lua")
local check = H.check

-- Fake mailbox ------------------------------------------------------------------
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
function UnitName() return "Mark" end

-- H.mail = { { subject=, money=, daysLeft=, invoice = {type, bid, count}, item = {id, count} }, ... }
H.mail = {}
function GetInboxNumItems() return #H.mail end
function GetInboxHeaderInfo(i)
    local m = H.mail[i]
    return nil, nil, "Auction House", m.subject, m.money or 0, 0, m.daysLeft or 30, m.item and 1 or 0, false
end
function GetInboxInvoiceInfo(i)
    local inv = H.mail[i].invoice
    if not inv then return nil end
    return inv[1], "", "Someone", inv[2], inv[2], 0, 0, 0, 0, 0, inv[3]
end
function GetInboxItem(i)
    local item = H.mail[i].item
    if not item then return nil end
    return "Item", item[1], 0, item[2]
end
function GetInboxItemLink(i)
    local item = H.mail[i].item
    return item and ("|Hitem:" .. item[1] .. "|h[Item]|h")
end

-- The item cache also answers by name, like the real GetItemInfo.
local byID = C_Item.GetItemInfo
C_Item.GetItemInfo = function(key)
    if type(key) == "string" then
        for id, n in pairs(H.itemNames) do
            if n == key then return n, "|cffffffff|Hitem:" .. id .. "::|h[" .. n .. "]|h|r" end
        end
        return nil
    end
    return byID(key)
end

local function openMail()
    H.fire("MAIL_SHOW")
    H.advance(1)
end
local function closeMail() H.fire("MAIL_CLOSED") end

local MF = H.startAddon()
local History = MF:GetModule("History")
check(History and History:IsEnabled(), "History module loads and is on")

-- Subject parsing.
local P = History.ParseSubject
local kind, name, count = P("Auction successful: Linen Cloth (20)")
check(kind == "sold" and name == "Linen Cloth" and count == 20, "sold subject with a count")
kind, name = P("Auction expired: Copper Ore")
check(kind == "expired" and name == "Copper Ore", "expired subject")
check(P("Hello there") == nil and P(nil) == nil, "other mail ignored")
check(select(2, P("Auction won: Big (Red) Hat")) == "Big (Red) Hat", "parentheses in a name survive")

-- A sale of an item Razzle has never seen keeps its name until it's learned.
H.mail = {
    { subject = "Auction successful: Linen Cloth (20)", money = 1900, daysLeft = 29.9,
      invoice = { "seller", 2000, 20 } },
}
openMail()
local recs = History.db.global.records
check(#recs == 1 and recs[1].type == "sold" and recs[1].n == 20 and recs[1].money == 1900, "sale recorded")
check(recs[1].id == 2589, "sale gets its item ID from the item cache by name")

H.itemNames[4306] = nil
H.mail[2] = { subject = "Auction successful: Silk Cloth (5)", money = 950, daysLeft = 29.8,
    invoice = { "seller", 1000, 5 } }
H.fire("MAIL_INBOX_UPDATE")
H.advance(1)
local silk = recs[2]
check(#recs == 2 and silk.name == "Silk Cloth" and silk.id == nil, "unknown sale keeps its name")
-- Putting silk in the sell slot teaches Razzle the name; the waiting sale gets its ID.
H.itemNames[4306] = "Silk Cloth"
MF:SendMessage("MF_POST_ITEM_SELECTED", 4306)
check(silk.id == 4306, "waiting sale filled in once the item is learned")

-- Reopening the mailbox, reordering and later sessions don't count mail twice.
closeMail()
H.advance(3600)
for _, m in ipairs(H.mail) do m.daysLeft = m.daysLeft - 1 / 24 end
H.mail[1], H.mail[2] = H.mail[2], H.mail[1]
openMail()
check(#History.db.global.records == 2, "same mail after an hour and reorder is not recorded again")

-- Two identical sales arriving together are two records; reading again adds none.
local twin = { subject = "Auction successful: Copper Ore (10)", money = 950, daysLeft = 29.95,
    invoice = { "seller", 1000, 10 } }
H.mail[3] = twin
H.mail[4] = { subject = twin.subject, money = twin.money, daysLeft = twin.daysLeft, invoice = twin.invoice }
H.fire("MAIL_INBOX_UPDATE")
H.advance(1)
check(#History.db.global.records == 4, "identical twin mails are each recorded")
H.fire("MAIL_INBOX_UPDATE")
H.advance(1)
check(#History.db.global.records == 4, "twins not recorded again")
-- One twin taken; the other still there: nothing new.
table.remove(H.mail, 4)
H.fire("MAIL_INBOX_UPDATE")
H.advance(1)
check(#History.db.global.records == 4, "taking mail adds nothing")

-- The same mail on another character is that character's own record.
local playerName = "Mark"
function UnitName() return playerName end
playerName = "Alt"
H.fire("MAIL_INBOX_UPDATE")
H.advance(1)
check(#History.db.global.records == 7, "another character's identical mail is recorded separately")
playerName = "Mark"
local keep = {}
for _, r in ipairs(History.db.global.records) do if r.c ~= "Alt" then keep[#keep + 1] = r end end
History.db.global.records = keep

-- Purchases, expiries and cancellations carry the item.
H.mail[#H.mail + 1] = { subject = "Auction won: Linen Cloth", daysLeft = 29.9,
    invoice = { "buyer", 600, nil }, item = { 2589, 10 } }
H.mail[#H.mail + 1] = { subject = "Auction expired: Linen Cloth", daysLeft = 29.9, item = { 2589, 20 } }
H.mail[#H.mail + 1] = { subject = "Auction cancelled: Copper Ore", daysLeft = 29.9, item = { 2770, 5 } }
H.fire("MAIL_INBOX_UPDATE")
H.advance(1)
check(#History.db.global.records == 7, "won, expired and cancelled recorded")

local s = History:ItemStats(2589)
check(s.sold == 20 and s.soldEach == 100 and s.bought == 10 and s.boughtEach == 60, "item stats: sold and bought")
check(s.expired == 1 and s.sellThrough == 0.5, "item stats: sell-through")
check(H.plain(History:Line(2589)) == "20 sold at ~1s, 1 of 2 listings sold, 10 bought at ~60c", "results line")
check(History:ItemStats(424242) == nil and History:Line(424242) == nil, "no results for an untouched item")

local t = History:Summary(7)
check(t.salesCount == 4 and t.sales == 1900 + 950 + 950 + 950 and t.purchases == 600, "summary totals")
check(t.expired == 1 and t.cancelled == 1 and t.profit == t.sales - 600, "summary counts and net")

-- Tooltip shows your results.
local found = false
for _, line in ipairs(H.showItemTooltip(2589)) do
    if line == "Your results = 20 sold at ~1s, 1 of 2 listings sold, 10 bought at ~60c" then found = true end
end
check(found, "tooltip shows your results")

-- Slash commands.
H.clearChat()
H.slash("history")
check(H.chatHas("Sold 4 listings"), "/mf history summary")
H.clearChat()
H.slash("history recent")
check(H.chatHas("sold Linen Cloth x20"), "/mf history recent")
H.clearChat()
H.slash("history 2589")
check(H.chatHas("Your results: 20 sold"), "/mf history <item>")

-- Old records are pruned; the cap holds.
H.mail = {}
H.advance(31 * 24 * 3600)
History:Prune()
check(#History.db.global.records == 0, "records older than keepDays pruned")
History.db.global.maxRecords = 2
for i = 1, 3 do
    History.db.global.records[i] = { k = tostring(i), at = H.now - i, type = "sold", name = "x", n = 1, money = 1 }
end
History:Prune()
check(#History.db.global.records == 2 and History.db.global.records[1].k == "2", "oldest dropped beyond the cap")

H.slash("history clear")
check(#History.db.global.records == 2, "clear needs confirm")
H.slash("history clear confirm")
check(#History.db.global.records == 0, "clear confirm erases")

H.finish("history")
