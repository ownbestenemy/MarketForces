-- MarketForces Flip module: should I buy the cheap ones and sell them again?
--
-- For an item, Flip walks the cheapest listings from the latest scan (kept by
-- Prices) and works out the best flip: how many units to buy and up to what
-- price, what to relist them at, and the profit after the auction house's
-- 5% cut. The relist price undercuts whatever listing would be left
-- cheapest after you buy, but never goes above market value, and is whole
-- silver since the sell frames don't take copper. A step is only worth
-- buying when it clears a minimum profit per unit and a minimum margin.
--
-- Razzle's window shows this on its Flips tab, along with the best flips on
-- the board; /mf flip <item> prints it. Flip only advises: buying and
-- posting stay with the player and Blizzard's own buttons, one click each.
local _, MF = ...

local Util = MF.Util

local Flip = MF:NewModule("Flip", {
    global = {
        ahCut = 0.05,          -- the auction house's cut of a sale
        minUnitProfit = 10,    -- a unit must earn at least this (copper) after the cut
        minMargin = 0.15,      -- and at least this share of what it cost
        minFlipProfit = 2000,  -- flips worth less in total (20s) stay off the best-flips list
        maxPicks = 5,
        depositHours = 24,     -- deposit estimate assumes a 24 hour listing
    },
})
MF.Flip = Flip

local floor = math.floor
local SILVER = 100
local HOUR = 60 * 60

local function getItemInfo(item)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    return getInfo(item)
end

-- The best flip for a price ladder. p is a Prices:GetPrice() result;
-- opts holds the settings above. Returns a plan:
--   { units, maxPrice, cost, resale, net (per unit after the cut),
--     profit, market, wall (the cheapest price left after buying, or nil) }
-- or nil and a reason: "nomarket", "nolistings", "nothingcheap", "thin".
function Flip.Analyze(p, opts)
    if not (p and p.market and p.market > 0) then return nil, "nomarket" end
    local ladder = p.ladder or {}
    if #ladder == 0 then return nil, "nolistings" end
    local market = p.market
    if ladder[1][1] >= market then return nil, "nothingcheap" end
    local cut = opts.ahCut or 0.05
    local best
    local units, cost = 0, 0
    for k, step in ipairs(ladder) do
        units = units + step[2]
        cost = cost + step[1] * step[2]
        local nextStep = ladder[k + 1]
        -- When the ladder was cut short we don't know what would be left
        -- after buying the last step, so we can't plan past it.
        if not nextStep and p.ladderMore then break end
        local wall = nextStep and nextStep[1]
        local target = market
        if wall and wall - 1 < target then target = wall - 1 end
        local resale = floor(target / SILVER) * SILVER
        if resale >= SILVER then
            local net = floor(resale * (1 - cut))
            local unitProfit = net - step[1] -- the dearest unit bought so far
            local needed = math.max(opts.minUnitProfit or 0, step[1] * (opts.minMargin or 0))
            if unitProfit >= needed then
                local profit = net * units - cost
                if not best or profit > best.profit then
                    best = {
                        units = units, maxPrice = step[1], cost = cost, resale = resale, net = net,
                        profit = profit, market = market, wall = wall,
                    }
                end
            end
        end
    end
    if not best then return nil, "thin" end
    return best
end

-- Deposit for posting the units, or nil if we can't tell. At the auction
-- house Blizzard's own calculator answers for commodities; elsewhere it's
-- estimated from the vendor price (15% of it per 12 hours listed).
function Flip:Deposit(itemID, units)
    local scan = MF.Scan
    if C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit and scan and scan:IsAuctionHouseOpen() then
        local duration = self.db.global.depositHours >= 48 and 3 or (self.db.global.depositHours >= 24 and 2 or 1)
        local ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, units)
        if ok and type(deposit) == "number" then return deposit end
    end
    local sellPrice = select(11, getItemInfo(itemID))
    if not sellPrice or sellPrice <= 0 then return nil end
    return floor(sellPrice * 0.15 * (self.db.global.depositHours / 12) * units + 0.5)
end

-- Item ID from a link, an ID, or a name. Names match items in the client's
-- cache first, then items seen at this auction house (exact name first,
-- then the shortest name containing the text).
function Flip.ResolveItem(text)
    local prices = MF.Prices
    if not prices then return nil end
    local itemID = prices.ParseItemID(text)
    if itemID then return itemID end
    if type(text) ~= "string" then return nil end
    local wanted = text:match("^%s*(.-)%s*$"):lower()
    if wanted == "" then return nil end
    local _, link = getItemInfo(text)
    itemID = link and prices.ParseItemID(link)
    if itemID then return itemID end
    if not prices:IsEnabled() then return nil end
    local bestID, bestLen
    for id in pairs(prices:ItemsFor()) do
        local name = getItemInfo(id)
        if name then
            local lower = name:lower()
            if lower == wanted then return id end
            if lower:find(wanted, 1, true) and (not bestLen or #lower < bestLen
                or (#lower == bestLen and id < bestID)) then
                bestID, bestLen = id, #lower
            end
        end
    end
    return bestID
end

local function ago(seconds)
    if seconds < HOUR then return Util.FormatDuration(seconds) end
    if seconds < 48 * HOUR then return floor(seconds / HOUR) .. " hours" end
    return floor(seconds / (24 * HOUR)) .. " days"
end

-- Razzle's flip advice for typed text. Returns the text and the plan (nil
-- when there's nothing to flip) with plan.itemID set.
function Flip:Advise(text)
    local prices = MF.Prices
    if not (prices and prices:IsEnabled()) then
        return "My price books are closed (the Prices module is off)."
    end
    local itemID = Flip.ResolveItem(text)
    if not itemID then
        if text and text:match("%S") then
            return "Never heard of \"" .. text:match("^%s*(.-)%s*$") .. "\" here. Try shift-clicking it in."
        end
        return "Type an item's name or shift-click it in, and I'll tell you if it's worth a flip."
    end
    local name = MF.Broker and MF.Broker.ItemName(itemID) or ("item #" .. itemID)
    local p = prices:GetPrice(itemID)
    if not p then
        return "Never seen " .. name .. " at this house. Scan first, then ask again."
    end
    local plan, why = Flip.Analyze(p, self.db.global)
    local money = Util.FormatMoney
    if not plan then
        if why == "nomarket" then
            return name .. ": I've got no steady price for it yet. A scan or two more and I'll know."
        elseif why == "nolistings" and (p.quantity or 0) > 0 then
            return name .. ": my notes on its listings are from before I learned flipping. "
                .. "Run a fresh scan and ask again."
        elseif why == "nolistings" then
            return name .. ": nobody's selling any right now. Nothing to flip, boss."
        elseif why == "nothingcheap" then
            return string.format("%s: cheapest is %s and it's worth about %s. No flip here, boss.",
                name, money(p.ladder[1][1]), money(p.market))
        end
        return string.format("%s: cheapest is %s, worth about %s. After the house's cut the margin's "
            .. "too thin to bother.", name, money(p.ladder[1][1]), money(p.market))
    end
    plan.itemID = itemID
    local lines = {
        string.format("%s: flip it, boss!", name),
        string.format("Buy %d at up to %s each (%s in all).", plan.units, money(plan.maxPrice), money(plan.cost)),
        string.format("Relist at %s each (worth about %s).", money(plan.resale), money(p.market)),
        string.format("Profit about %s after the house's 5%% cut.", money(plan.profit)),
    }
    if plan.units > (p.quantity or 0) * 0.5 and plan.units >= 20 then
        lines[#lines + 1] = string.format("That's %d of the %d listed, so it may take a while to sell.",
            plan.units, p.quantity)
    end
    local deposit = self:Deposit(itemID, plan.units)
    if deposit then
        lines[#lines + 1] = "Deposit about " .. money(deposit) .. ", lost only if they don't sell."
    end
    if p.days < 3 then
        lines[#lines + 1] = string.format("Careful: only %d %s of history on this one.", p.days,
            p.days == 1 and "day" or "days")
    end
    if p.lastSeen and time() - p.lastSeen > HOUR then
        lines[#lines + 1] = "These listings are " .. ago(time() - p.lastSeen) .. " old; some may be gone."
    end
    return table.concat(lines, "\n"), plan
end

-- The most profitable flips at this auction house, best first, each a plan
-- with itemID and label (nil while the name loads, like the bargain board).
function Flip:FindFlips()
    local prices = MF.Prices
    if not (prices and prices:IsEnabled()) then return {} end
    local opts = self.db.global
    local flips = {}
    for itemID, entry in pairs(prices:ItemsFor()) do
        -- Only items with something listed under market can flip; skip the
        -- rest before working out a price.
        if entry.b and entry.b[3] then
            local plan = Flip.Analyze(prices:GetPrice(itemID), opts)
            if plan and plan.profit >= opts.minFlipProfit then
                plan.itemID = itemID
                flips[#flips + 1] = plan
            end
        end
    end
    table.sort(flips, function(a, b)
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.itemID < b.itemID
    end)
    for i = #flips, opts.maxPicks + 1, -1 do flips[i] = nil end
    for _, plan in ipairs(flips) do
        plan.label = MF.Broker and MF.Broker.ItemLabel(plan.itemID)
    end
    return flips
end

-- One row of the best-flips list, e.g. "Linen Cloth  buy 12 to 40c, sell 1s: +5s".
function Flip.PickLine(plan, name)
    return string.format("%s  buy %d to %s, sell %s: +%s", plan.label or name or ("item #" .. plan.itemID),
        plan.units, Util.FormatMoney(plan.maxPrice), Util.FormatMoney(plan.resale), Util.FormatMoney(plan.profit))
end

function Flip:OnInitialize()
    MF:RegisterSlashCommand("flip", "Is an item worth flipping? /mf flip <item name, link or ID>", function(args)
        if not Flip:IsEnabled() then
            MF:Print("Flip advice is off. Turn it on with /mf enable flip.")
            return
        end
        for line in (Flip:Advise(args) .. "\n"):gmatch("(.-)\n") do MF:Print(line) end
    end)
end
