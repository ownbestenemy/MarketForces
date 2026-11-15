-- MarketForces: SavedVariables.
--
-- MarketForcesDB (account-wide) layout:
--   schema         number, bumped when the layout changes (see MIGRATIONS)
--   global         settings shared by every character
--   auctionHouses  ["<scope>-<house>"] = data for one auction house
--                  (price history etc.). house is Alliance, Horde or
--                  Neutral; scope is region + ruleset, e.g. "US-RP PvP"
--                  (see Util.GetMarketScope).
-- MarketForcesCharDB (per character) holds character-only settings.
--
-- After MF:InitDatabase() runs:
--   MF.db.global  -> MarketForcesDB.global
--   MF.db.char    -> MarketForcesCharDB
-- After MF:InitAuctionHouseDB() runs (at PLAYER_LOGIN, once faction is known):
--   MF.db.ah      -> MarketForcesDB.auctionHouses[<current house key>]
local _, MF = ...

local Util = MF.Util

MF.SCHEMA_VERSION = 2

MF.defaults = {
    global = {
        debug = false,
        modules = {}, -- [moduleName] = { enabled = bool }
    },
    char = {},
    ah = {},
}

-- Ordered upgrade steps. MIGRATIONS[n] upgrades a schema n-1 DB to n.
local MIGRATIONS = {
    -- 2: Prices daily entries change from { average, count } to { sum, count }.
    [2] = function(db)
        for _, house in pairs(db.auctionHouses or {}) do
            local items = type(house.Prices) == "table" and house.Prices.items
            if type(items) == "table" then
                for _, entry in pairs(items) do
                    for _, day in pairs(type(entry.d) == "table" and entry.d or {}) do
                        if type(day[1]) == "number" and type(day[2]) == "number" then
                            day[1] = day[1] * day[2]
                        end
                    end
                end
            end
        end
    end,
}

local function migrate(db)
    local from = db.schema or 0
    if from > MF.SCHEMA_VERSION then
        MF:Print("|cffff4444warning|r: saved data is from a newer version of MarketForces.")
        return
    end
    for v = from + 1, MF.SCHEMA_VERSION do
        if MIGRATIONS[v] then
            MIGRATIONS[v](db)
            MF:Debug("Migrated saved data to schema %d", v)
        end
    end
    db.schema = MF.SCHEMA_VERSION
end

-- Called on ADDON_LOADED, when the client has loaded our SavedVariables.
function MF:InitDatabase()
    if type(MarketForcesDB) ~= "table" then MarketForcesDB = {} end
    if type(MarketForcesCharDB) ~= "table" then MarketForcesCharDB = {} end

    local db = MarketForcesDB
    migrate(db)

    db.global = db.global or {}
    db.auctionHouses = db.auctionHouses or {}

    self.db = {
        global = Util.ApplyDefaults(db.global, self.defaults.global),
        char = Util.ApplyDefaults(MarketForcesCharDB, self.defaults.char),
    }
    self.debug = self.db.global.debug and true or false
end

-- Called on PLAYER_LOGIN. Also points every module's db.ah at the new
-- table and sends MF_AUCTION_HOUSE_CHANGED when the key changes. Pass a faction ("Neutral") to switch to another
-- auction house's table, e.g. when the scan module opens a goblin AH.
function MF:InitAuctionHouseDB(faction)
    local key = Util.GetAuctionKey(faction)
    local all = MarketForcesDB.auctionHouses
    all[key] = Util.ApplyDefaults(all[key] or {}, self.defaults.ah)
    local changed = self.db.ahKey ~= nil and self.db.ahKey ~= key
    self.db.ah = all[key]
    self.db.ahKey = key
    for _, module in self:IterateModules() do
        module:InitModuleAHDB()
    end
    if changed then
        self:SendMessage("MF_AUCTION_HOUSE_CHANGED", key)
    end
    return all[key]
end

-- Wipes all saved data and rebuilds it from defaults.
function MF:ResetDatabase()
    MarketForcesDB = {}
    MarketForcesCharDB = {}
    self:InitDatabase()
    self:InitAuctionHouseDB()
    for _, module in self:IterateModules() do
        module:InitModuleDB()
    end
end
