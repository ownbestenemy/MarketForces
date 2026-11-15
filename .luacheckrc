std = "lua51"
max_line_length = 120
exclude_files = { ".luarocks", "lua_modules" }
-- `self` is often unused in handlers that follow the method signature.
self = false

-- Globals the addon defines.
globals = {
    "MarketForces",
    "MarketForcesDB",
    "MarketForcesCharDB",
    "SLASH_MARKETFORCES1",
    "SLASH_MARKETFORCES2",
    "SlashCmdList",
}

-- WoW API the addon reads. Add to this as modules use more of the API.
read_globals = {
    "AuctionFrame",
    "AuctionHouseFrame",
    "C_AddOns",
    "C_AuctionHouse",
    "C_Timer",
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "Enum",
    "GameTooltip",
    "GetAddOnMetadata",
    "ItemRefTooltip",
    "TooltipDataProcessor",
    "GetRealmName",
    "UnitExists",
    "UnitFactionGroup",
    "time",
}

files["tests/"] = {
    globals = {
        "AuctionFrame", "AuctionHouseFrame", "C_AuctionHouse", "C_Timer", "CreateFrame", "DEFAULT_CHAT_FRAME", "Enum",
        "TooltipDataProcessor",
        "GetAddOnMetadata", "GetRealmName", "MarketForcesScanButton", "UnitExists", "UnitFactionGroup", "time",
    },
}
