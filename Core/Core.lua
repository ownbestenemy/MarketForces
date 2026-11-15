-- MarketForces: startup. Loaded last so every module has registered.
--
--   ADDON_LOADED  -> saved data loaded, modules' OnInitialize
--   PLAYER_LOGIN  -> per auction house data ready, modules' OnEnable
local ADDON_NAME, MF = ...

function MF:ADDON_LOADED(_, addon)
    if addon ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    self:InitDatabase()
    self:InitializeModules()
end

function MF:PLAYER_LOGIN()
    self:UnregisterEvent("PLAYER_LOGIN")
    self:InitAuctionHouseDB()
    self:EnableModules()
    self:Debug("loaded v%s for %s", self.version, self.db.ahKey)
end

MF:RegisterEvent("ADDON_LOADED")
MF:RegisterEvent("PLAYER_LOGIN")
