-- MarketForces: shared namespace.
-- Every file receives the same private table as its second vararg. We also
-- expose it globally so other addons and /dump can reach it.
local ADDON_NAME, MF = ...

MF.name = ADDON_NAME
MF.title = "MarketForces"
local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
MF.version = (getMetadata and getMetadata(ADDON_NAME, "Version")) or "dev"
MF.debug = false

_G.MarketForces = MF

local PREFIX = "|cff33ff99MarketForces|r: "

local function output(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    else
        print(PREFIX .. msg)
    end
end

-- Print to the chat frame. Arguments are joined with spaces like print().
function MF:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    output(table.concat(parts, " "))
end

-- Formatted print, e.g. MF:Printf("Scanned %d items", n).
function MF:Printf(fmt, ...)
    output(string.format(fmt, ...))
end

-- Only prints when debug mode is on (/mf debug).
function MF:Debug(fmt, ...)
    if self.debug then
        output("|cff999999[debug]|r " .. string.format(fmt, ...))
    end
end
