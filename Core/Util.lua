-- MarketForces: small helpers shared by all modules.
local _, MF = ...

local Util = {}
MF.Util = Util

local floor = math.floor

local GOLD_ICON = "|cffffd700g|r"
local SILVER_ICON = "|cffc7c7cfs|r"
local COPPER_ICON = "|cffeda55fc|r"

-- Turns a copper amount into "12g 34s 56c". Zero parts are dropped,
-- except that 0 renders as "0c". Negative amounts keep their sign.
function Util.FormatMoney(copper)
    copper = floor(tonumber(copper) or 0)
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = -copper
    end
    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local cop = copper % 100

    local out = {}
    if gold > 0 then out[#out + 1] = gold .. GOLD_ICON end
    if silver > 0 then out[#out + 1] = silver .. SILVER_ICON end
    if cop > 0 or #out == 0 then out[#out + 1] = cop .. COPPER_ICON end
    return sign .. table.concat(out, " ")
end

-- Copies keys from defaults into target where target has no value yet.
-- Nested tables are merged recursively. Returns target.
function Util.ApplyDefaults(target, defaults)
    if type(defaults) ~= "table" then return target end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            Util.ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Splits "first rest of line" into "first", "rest of line".
function Util.SplitFirstWord(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    local first, rest = text:match("^(%S+)%s*(.*)$")
    return first or "", rest or ""
end

-- Key for the auction house the player is using: "<scope>-<house>".
-- house is the faction AH ("Alliance"/"Horde"), or "Neutral" for the goblin
-- AH (pass it in). WoW: Forever is realmless, so scope is whatever
-- GetRealmName() reports there (expected to identify the ruleset); this is
-- the one place to change if that turns out to need different handling.
function Util.GetAuctionKey(faction)
    local realm = (GetRealmName and GetRealmName()) or "UnknownRealm"
    faction = faction or (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    return realm .. "-" .. faction
end
