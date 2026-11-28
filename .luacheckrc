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
    "AuctionHouseFrameDisplayMode",
    "ChatEdit_GetActiveWindow",
    "ItemLocation",
    "MarketForcesRazzleFrame",
    "SetCVar",
    "GetCVar",
    "C_AddOns",
    "C_AuctionHouse",
    "C_Container",
    "ChatFrameUtil",
    "HandleModifiedItemClick",
    "IsModifiedClick",
    "C_Item",
    "C_Timer",
    "ChatEdit_InsertLink",
    "CreateFrame",
    "DEFAULT_CHAT_FRAME",
    "Enum",
    "GameTooltip",
    "GetAddOnMetadata",
    "GetItemInfo",
    "IsShiftKeyDown",
    "ItemRefTooltip",
    "ITEM_QUALITY_COLORS",
    "TooltipDataProcessor",
    "GetRealmName",
    "UIParent",
    "UISpecialFrames",
    "UnitExists",
    "UnitFactionGroup",
    "hooksecurefunc",
    "time",
    "GetInboxHeaderInfo",
    "GetInboxInvoiceInfo",
    "GetInboxItem",
    "GetInboxItemLink",
    "GetInboxNumItems",
    "UnitName",
}

files["tests/"] = {
    globals = {
        "AuctionFrame", "AuctionHouseFrame", "C_AuctionHouse", "C_Timer", "CreateFrame", "DEFAULT_CHAT_FRAME", "Enum",
        "TooltipDataProcessor", "UIParent", "C_Item", "C_Container", "ChatFrameUtil", "HandleModifiedItemClick", "MarketForcesRazzleFrame", "hooksecurefunc",
        "IsShiftKeyDown", "IsModifiedClick", "ItemLocation", "SetCVar", "ChatEdit_GetActiveWindow", "ITEM_SOULBOUND", "ITEM_QUALITY_COLORS",
        "GetAddOnMetadata", "GetRealmName", "MarketForcesScanButton", "UnitExists", "UnitFactionGroup", "time",
        "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem", "GetInboxItemLink", "GetInboxNumItems",
        "UnitName", "TSM_API", "Auctionator", "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT",
        "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
        "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE",
    },
}
