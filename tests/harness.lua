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

-- Chat text with WoW color codes removed.
function H.plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
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
function CreateFrame(_, name, parent)
    local f = { registered = {}, scripts = {}, name = name, parent = parent, shown = true, enabled = true }
    function f:RegisterEvent(e) self.registered[e] = true end
    function f:UnregisterEvent(e) self.registered[e] = nil end
    function f:SetScript(script, fn) self.scripts[script] = fn end
    function f:SetSize() end
    function f:SetPoint() end
    function f:SetText(text) self.text = text end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:Enable() self.enabled = true end
    function f:Disable() self.enabled = false end
    function f:GetName() return self.name end
    function f:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end

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

function H.openAuctionHouse()
    local window = _G[H.windowName]
    if not window and not H.windowLoadsLate then
        window = CreateFrame("Frame", H.windowName)
    end
    if window then window:Show() end
    H.fire("AUCTION_HOUSE_SHOW")
    if not window and H.windowLoadsLate then
        CreateFrame("Frame", H.windowName):Show()
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
function H.showItemTooltip(itemID)
    local tip = { lines = {} }
    function tip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = H.plain(left) .. " = " .. H.plain(right) end
    function tip:Show() end
    for _, call in ipairs(postCalls) do
        if call.kind == Enum.TooltipDataType.Item then call.fn(tip, { id = itemID }) end
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
