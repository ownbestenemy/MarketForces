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
    "C_AddOns",
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "GetAddOnMetadata",
    "GetRealmName",
    "UnitFactionGroup",
}

files["tests/"] = {
    globals = { "DEFAULT_CHAT_FRAME", "CreateFrame", "GetRealmName", "UnitFactionGroup", "GetAddOnMetadata" },
}
