-- Test harness: a fake slice of the WoW API, plus a loader that runs the
-- addon's files in .toc order the way the client does. Each test file runs
-- in its own Lua process (see tests/run.lua), so globals never leak between
-- them.
local H = { passes = 0, failures = 0, chat = {} }

function H.check(cond, label)
    if cond then
        H.passes = H.passes + 1
    else
        H.failures = H.failures + 1
        print("FAIL: " .. label)
    end
end

function H.finish(name)
    print(string.format("%s: %d passed, %d failed", name, H.passes, H.failures))
    os.exit(H.failures == 0 and 0 or 1)
end

-- Chat, slash commands, clock ----------------------------------------------------

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) H.chat[#H.chat + 1] = msg end }
SlashCmdList = {}

function H.slash(text) SlashCmdList.MARKETFORCES(text) end

-- Chat text with WoW color codes and inline icons removed.
function H.plain(text)
    return (text:gsub("|T.-|t ?", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function H.chatHas(pattern)
    for _, line in ipairs(H.chat) do
        if H.plain(line):find(pattern) then return true end
    end
    return false
end

function H.clearChat() H.chat = {} end

H.now = 1800000000
function time() return H.now end

-- C_Timer.After callbacks queue up; H.runTimers() runs those that are due.
local timers = {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = H.now + delay, fn = fn } end,
}
function H.runTimers()
    local ran = true
    while ran do
        ran = false
        for i, t in ipairs(timers) do
            if t.at <= H.now then
                table.remove(timers, i)
                t.fn()
                ran = true
                break
            end
        end
    end
end
function H.advance(seconds)
    H.now = H.now + seconds
    H.runTimers()
end

-- Frames and events ----------------------------------------------------------------

local frames = {}
local noop = function() end

-- Fake region (frame, texture or font string). Layout methods are no-ops;
-- the rest behave enough for the tests.
local function newRegion(kind, name, parent)
    local r = {
        kind = kind, registered = {}, scripts = {}, name = name, parent = parent,
        shown = kind ~= "Frame" or true, enabled = true, points = {},
    }
    function r:RegisterEvent(e) self.registered[e] = true end
    function r:UnregisterEvent(e) self.registered[e] = nil end
    function r:SetScript(script, fn) self.scripts[script] = fn end
    function r:SetText(text) self.text = text end
    function r:GetText() return self.text or "" end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:GetName() return self.name end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:GetPoint() local p = self.points[1] or {} return p[1], p[2], p[3], p[4], p[5] end
    function r:GetFrameLevel() return 1 end
    function r:GetFrameStrata() return "MEDIUM" end
    function r:HasFocus() return self.focus == true end
    function r:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
    function r:CreateFontString() return newRegion("FontString", nil, self) end
    function r:CreateTexture() return newRegion("Texture", nil, self) end
    for _, method in ipairs({
        "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetFrameLevel", "SetClampedToScreen", "EnableMouse",
        "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetJustifyH", "SetWordWrap",
        "SetTexture", "SetAutoFocus", "ClearFocus",
    }) do
        r[method] = noop
    end
    return r
end

function CreateFrame(kind, name, parent)
    local f = newRegion(kind or "Frame", name, parent)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")

H.shiftDown = false
function IsShiftKeyDown() return H.shiftDown end

-- hooksecurefunc: runs the hook after the original, like the real one.
function hooksecurefunc(target, method, hook)
    if type(target) == "string" then target, method, hook = _G, target, method end
    local original = target[method]
    target[method] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end
C_Item = {
    GetItemInfo = function(itemID)
        local name = H.itemNames and H.itemNames[itemID]
        local sell = H.vendorPrices and H.vendorPrices[itemID]
        if not name and not sell then return nil end
        local icon = H.itemIcons and H.itemIcons[itemID] or 0
        local stack = H.stackSizes and H.stackSizes[itemID] or 1
        return name, nil, 1, 1, 1, "", "", stack, "", icon, sell or 0
    end,
    RequestLoadItemDataByID = function(itemID)
        H.itemRequests = H.itemRequests or {}
        H.itemRequests[itemID] = true
    end,
    GetItemID = function(location) return location.itemID end,
}
H.itemNames = { [2589] = "Linen Cloth", [2770] = "Copper Ore" }

-- Bags: H.bags[bag] = { { itemID =, stackCount =, isBound = }, ... }
H.bags = {}
C_Container = {
    GetContainerNumSlots = function(bag) return H.bags[bag] and #H.bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return H.bags[bag] and H.bags[bag][slot] end,
}

ItemLocation = {
    CreateFromBagAndSlot = function(_, bag, slot)
        return { bag = bag, slot = slot, IsBagAndSlot = function() return true end }
    end,
}
H.cvars = {}
function SetCVar(name, value) H.cvars[name] = value end

-- Blizzard's link paths for shift-clicks (they differ between clients).
ChatFrameUtil = { InsertLink = function() return false end }
function HandleModifiedItemClick() return false end
function IsModifiedClick(action) return action == "CHATLINK" and H.shiftDown end
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }

function H.fire(event, ...)
    for _, f in ipairs(frames) do
        if f.registered[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Unit and realm info ------------------------------------------------------------------

H.realmName = "CAMWOW US1 Realm 9 RP PvP"
H.playerFaction = "Horde"
H.npcFaction = nil -- set to "Neutral" to stand at a goblin auctioneer
function GetRealmName() return H.realmName end
function UnitExists(unit) return unit == "player" or (unit == "npc" and H.npcFaction ~= nil) end
function UnitFactionGroup(unit)
    if unit == "npc" then return H.npcFaction end
    return H.playerFaction
end
function GetAddOnMetadata(_, key) if key == "Version" then return "0.1.0" end end

-- Auction house ---------------------------------------------------------------------------

-- H.auctions is the list a full scan returns: { itemID=, count=, buyout= }.
H.auctions = {}
H.replicateCalls = 0
C_AuctionHouse = {
    ReplicateItems = function() H.replicateCalls = H.replicateCalls + 1 end,
    MakeItemKey = function(itemID)
        return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
    end,
    GetItemKeyInfo = function(itemKey)
        if H.itemKeyUnknown then return nil end
        return { itemID = itemKey.itemID, isCommodity = H.commodities and H.commodities[itemKey.itemID] or false }
    end,
    GetNumReplicateItems = function() return #H.auctions end,
    GetReplicateItemInfo = function(index) -- 0-based like the real API
        local a = H.auctions[index + 1]
        if not a then return nil end
        return "Item " .. a.itemID, 0, a.count, 1, true, 1, 0, a.bid or 0, 0, a.buyout or 0,
            0, false, nil, "Seller", "Seller-Realm", 0, a.itemID, true
    end,
}

-- Which Blizzard window the fake client uses, and whether it appears only
-- after AUCTION_HOUSE_SHOW (load on demand).
H.windowName = "AuctionHouseFrame"
H.windowLoadsLate = false

-- Modern sell frames: SetItem(location) then Blizzard sets a default price.
local function addSellFrames(window)
    for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local sell = CreateFrame("Frame", nil, window)
        sell.PriceInput = { amount = 0, SetAmount = function(self, v) self.amount = v end }
        sell.QuantityInput = { SetQuantity = function(self, v) self.quantity = v end }
        sell.Duration = { SetDuration = function(self, v) self.duration = v end }
        function sell.SetItem(self, location)
            self.item = location
            self.PriceInput:SetAmount(H.blizzardDefaultPrice or 0)
        end
        window[key] = sell
    end
    -- Bag item -> sell slot (commodities to the commodity frame); the other
    -- sell frame hides, like switching display modes.
    function window:SetPostItem(location)
        if H.setPostItemFails then error("no") end
        if H.setPostItemDeclines then return end
        local info = C_Container.GetContainerItemInfo(location.bag, location.slot)
        local commodity = H.commodities and H.commodities[info.itemID]
        local show = commodity and self.CommoditiesSellFrame or self.ItemSellFrame
        local hide = commodity and self.ItemSellFrame or self.CommoditiesSellFrame
        hide:Hide()
        show:Show()
        H.postItemSet = location
        show:SetItem({ itemID = info.itemID, bag = location.bag, slot = location.slot })
    end
    -- Browse result -> buy view, and the search bar.
    H.selected = nil
    function window:SelectBrowseResult(result) H.selected = result end
    window.CategoriesList = {
        selected = "Weapons",
        SetSelectedCategory = function(self, index) self.selected = index end,
    }
    window.SearchBar = {
        SearchBox = { SetText = function(_, text) H.searchedFor = text end },
        StartSearch = function() H.searchStarted = true end,
    }
end

function H.openAuctionHouse()
    local window = _G[H.windowName]
    if not window and not H.windowLoadsLate then
        window = CreateFrame("Frame", H.windowName)
        if H.windowName == "AuctionHouseFrame" then addSellFrames(window) end
    end
    if window then window:Show() end
    H.fire("AUCTION_HOUSE_SHOW")
    if not window and H.windowLoadsLate then
        window = CreateFrame("Frame", H.windowName)
        if H.windowName == "AuctionHouseFrame" then addSellFrames(window) end
        window:Show()
    end
end

function H.closeAuctionHouse()
    local window = _G[H.windowName]
    if window then window:Hide() end
    H.fire("AUCTION_HOUSE_CLOSED")
end

-- Tooltips ----------------------------------------------------------------------------------

-- Modern tooltip hook: H.showItemTooltip(itemID) runs the registered post
-- calls against a fake tooltip and returns its added lines.
Enum = { TooltipDataType = { Item = 0 } }
local postCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end,
}
ITEM_SOULBOUND = "Soulbound"
-- opts.bound adds a "Soulbound" line to the tooltip data; opts.boundText
-- puts it in the tooltip's own text lines instead (older tooltip style).
function H.showItemTooltip(itemID, opts)
    opts = opts or {}
    local tip = { lines = {} }
    local data = { id = itemID, lines = { { leftText = "Item" } } }
    if opts.bound then data.lines[2] = { leftText = ITEM_SOULBOUND } end
    if opts.boundText then
        function tip:GetName() return "FakeTooltip" end
        function tip:NumLines() return 2 end
        _G.FakeTooltipTextLeft1 = { GetText = function() return "Item" end }
        _G.FakeTooltipTextLeft2 = { GetText = function() return ITEM_SOULBOUND end }
    end
    function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = H.plain(left) .. " = " .. H.plain(right) end
    function tip:Show() end
    for _, call in ipairs(postCalls) do
        if call.kind == Enum.TooltipDataType.Item then call.fn(tip, data) end
    end
    return tip.lines
end

-- Loading the addon ---------------------------------------------------------------------------

-- Loads every file in the .toc. beforeCore(ns), if given, runs just before
-- Core\Core.lua so a test can register its own modules. Returns the
-- namespace and the file list.
function H.loadAddon(beforeCore)
    local ns = {}
    local files = {}
    for line in io.lines("MarketForces.toc") do
        if not line:match("^%s*#") and line:match("%S") then
            files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
        end
    end
    for i, path in ipairs(files) do
        if i == #files and beforeCore then beforeCore(ns) end
        assert(loadfile(path))("MarketForces", ns)
    end
    return ns, files
end

-- Loads the addon and runs the startup events.
function H.startAddon(beforeCore)
    local ns, files = H.loadAddon(beforeCore)
    H.fire("ADDON_LOADED", "MarketForces")
    H.fire("PLAYER_LOGIN")
    return ns, files
end

return H
