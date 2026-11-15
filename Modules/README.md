# Modules

Every feature is a module in this folder, added to `MarketForces.toc` between
the Core files and `Core\Core.lua`. Planned modules:

| Module | Job |
| --- | --- |
| Scan | Query the auction house (full or page by page) and send `MF_SCAN_COMPLETE` with the results |
| Prices | Listen for scans and keep per item price history in `db.ah` |
| Tooltip | Show stored prices on item tooltips |
| Post | Suggest prices and post auctions |

Modules never call each other directly. They send and listen for messages
(`self:SendMessage("MF_SCAN_COMPLETE", results)`), so any one can be turned
off with `/mf disable <name>` without breaking the others.

## Template

```lua
local _, MF = ...

local Example = MF:NewModule("Example", {
    global = {},              -- account-wide settings  -> self.db.global
    char = {},                -- per character settings -> self.db.char
    ah = {},                  -- per auction house data -> self.db.ah
})

function Example:OnInitialize()
    -- Saved data is loaded. Register slash commands here.
end

function Example:OnEnable()
    -- Player is in the world (or the module was just enabled).
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
end

function Example:OnDisable()
    -- Events and messages are removed for you after this runs.
end

function Example:AUCTION_HOUSE_SHOW(event)
    self:Debug("auction house opened")
end
```

`self.db.ah` points at the current auction house. When it changes (for
example at a goblin AH), the core sends `MF_AUCTION_HOUSE_CHANGED`.
Register slash commands with `MF:RegisterSlashCommand(name, help, func)`.
