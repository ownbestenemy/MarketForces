# Modules

Every feature is a module in this folder, added to `MarketForces.toc` between
the Core files and `Core\Core.lua`.

| Module | Status | Job |
| --- | --- | --- |
| Scan | Built | Query the auction house through `C_AuctionHouse` (items and commodities) and send `MF_SCAN_COMPLETE` with the results |
| Prices | Built | Listen for scans and keep per item price history in `db.ah` |
| Tooltip | Built | Show stored prices on item tooltips |
| Post | Next | Suggest prices; post or cancel only when the player clicks |
| Broker | Built | Razzle, the goblin broker of Razzle's Dazzles: the window, greetings and advice, built on the modules above |

Scan uses `C_AuctionHouse.ReplicateItems()`, the client's full "get all"
query, which the server allows about once every 15 minutes. Each scan is
started by a click, and results are read a few thousand per frame so the game
doesn't stall. Items are grouped by item ID; random-suffix variants share one
entry for now.

Prices keeps two numbers per item. **Market value** averages the cheapest
30% of units in each scan (so troll listings don't count), keeps one value
per day, and blends the days with recent ones weighted more (a day's weight
halves every 7 days). **Cheapest now** is the lowest buyout per unit in the
latest scan. Other modules read both with `MF.Prices:GetPrice(itemID)`.
History older than 30 days is pruned.

Broker is Razzle's window. It docks beside the auction house window when
that opens (turn off with `/mf dock`) and `/mf razzle` opens it anywhere,
movable, with its position saved. Razzle greets you with how fresh the
prices are, lists bargains (items whose cheapest listing is at or below 70%
of market value, biggest discount first) and answers price checks typed or
shift-clicked into its box. Razzle never buys, posts or cancels anything.

Modules never call each other directly. They send and listen for messages
(`self:SendMessage("MF_SCAN_COMPLETE", results)`), so any one can be turned
off with `/mf disable <name>` without breaking the others.

## Rules every module follows

These keep MarketForces within Blizzard's add-on policy (see the main
README). A pull request that breaks one doesn't get merged.

- Protected auction calls (post, bid, buyout, cancel) run only inside a
  click handler, one action per click. No loops, timers or queues that
  fire them.
- Searches use `C_AuctionHouse`, wait for the client's throttle, and stop
  when the auction house closes (`AUCTION_HOUSE_CLOSED`).
- No web requests or outside data. Store only what the client shows.
- Saved data is pruned so it doesn't grow forever.

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
