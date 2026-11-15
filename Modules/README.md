# Modules

Every feature is a module in this folder, added to `MarketForces.toc` between
the Core files and `Core\Core.lua`.

| Module | Status | Job |
| --- | --- | --- |
| Scan | Built | Query the auction house through `C_AuctionHouse` (items and commodities) and send `MF_SCAN_COMPLETE` with the results |
| Prices | Built | Listen for scans and keep per item price history in `db.ah` |
| Tooltip | Built | Show stored prices on item tooltips |
| Post | Built | Fill in the sell price with market value; the player clicks Post |
| Flip | Built | Flip advice: which cheap listings to buy, the relist price and the profit after the cut |
| Broker | Built | Razzle, the goblin broker of Razzle's Dazzles: the window, greetings and advice, built on the modules above |

Scan uses `C_AuctionHouse.ReplicateItems()`, the client's full "get all"
query, which the server allows about once every 15 minutes. Each scan is
started by a click, and results are read a few thousand per frame so the game
doesn't stall. Items are grouped by item ID; random-suffix variants share one
entry for now.

Prices keeps two numbers per item. **Market value** averages the cheapest
30% of units in each scan (so troll listings don't count), keeps each
day's lowest scan value, and blends the days with recent ones weighted more
(a day's weight halves every 7 days) and cheap ones weighted more (a day's
weight is multiplied by (cheapest day / this day)^2, so a run of high asks
can't outweigh a realistic low price; `lowWeight` sets the power). **Cheapest now** is the lowest buyout per unit in the
latest scan. Other modules read both with `MF.Prices:GetPrice(itemID)`.
History older than 30 days is pruned.

Broker is Razzle's window. It docks beside the auction house window when
that opens (turn off with `/mf dock`) and `/mf razzle` opens it anywhere,
movable, with its position saved. Razzle greets you with how fresh the
prices are, lists bargains (items whose cheapest listing is at or below 70%
of market value and saves at least 1s a unit, most coin saved first, each
row showing the item's icon and quality colour; hover a row for the item's
tooltip, click it to open a commodity's buy view, or search for other items, on
the auction house's Buy tab; the player buys with Blizzard's own button) and answers price checks typed or
shift-clicked into its box. Razzle never buys, posts or cancels anything.

Flip reads the cheapest listings Prices keeps from the latest scan (a
"ladder" of price steps, up to the first one at or above market value) and
finds the most profitable flip: buy every step up to some price, relist the
lot one silver under whatever listing would be left cheapest (never above
market value, whole silver since the sell frames take no copper), and keep
the profit after the 5% cut. Each step bought must earn at least 10c a unit
and 15% on its cost. Razzle's window has a **Flips** tab: type a name (or
shift-click an item) for the plan, with the deposit (Blizzard's own figure
at the AH, otherwise estimated from the vendor price; it comes back when
the items sell), a warning when the history is short or the listings are
old, and a **Show me at the AH** button that opens the buy view, like a
bargain row. Below it, Razzle's best flips (20s profit or more). Flip never
buys or posts: each purchase and each post is the player's own click.

Post hooks Blizzard's sell frames (`ItemSellFrame`, `CommoditiesSellFrame`).
When an item goes in, it sets the price box to the market value, rounded to
the nearest silver, one frame after Blizzard sets its default. It never calls
a posting function: the Post click is always the player's. `/mf autofill`
turns the fill-in off and leaves Razzle's advice.

Tooltip also adds a "Razzle says" line: **Buy it** when the cheapest
listing is under the vendor price or at least 30% under market value,
**Vendor it** when the auction house wouldn't pay more than a vendor after its
5% cut (or there are no auction prices yet), otherwise **Auction it** with
the expected take after the cut. `/mf advice` hides it.

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
