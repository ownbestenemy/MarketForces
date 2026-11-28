# Modules

Every feature is a module in this folder, added to `MarketForces.toc` between
the Core files and `Core\Core.lua`.

| Module | Status | Job |
| --- | --- | --- |
| Scan | Built | Query the auction house through `C_AuctionHouse` (items and commodities) and send `MF_SCAN_COMPLETE` with the results |
| Prices | Built | Listen for scans and keep per item price history in `db.ah` |
| Tooltip | Built | Show stored prices on item tooltips |
| Post | Built | Fill in the sell price with market value; the player clicks Post |
| History | Built | Read auction mail into a ledger: what sold (and for how much), what you bought, what expired or was cancelled |
| Outside | Built | Optional prices from TSM or Auctionator, read in game, for items Razzle hasn't scanned |
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
lot one copper under whatever listing would be left cheapest (never above
market value), and keep
the profit after the 5% cut. Each step bought must earn at least 10c a unit
and 15% on its cost. Razzle's window has a **Flips** tab: type a name (or
shift-click an item) for the plan, with the deposit (Blizzard's own figure
at the AH, otherwise estimated from the vendor price; it comes back when
the items sell), a warning when the history is short or the listings are
old, a line on what to list your own copies at, and a **Show me at the AH**
button that opens the buy view, like a bargain row. Below it is a list:
**Your bags** (sellable items, most valuable first, paged, refreshed when
your bags change) or **Best flips** (20s profit or more). Clicking a row
shows Razzle's numbers and, at the auction house, opens or searches for the
item. Shift-clicking an item into a focused box hooks every link path the
client may use (`ChatEdit_InsertLink`, `ChatFrameUtil.InsertLink`,
`HandleModifiedItemClick`). Flip never
buys or posts: each purchase and each post is the player's own click.

Razzle's **Sell** tab widens the window to three columns side by side,
after AuctioneerModern's Post tab: **Your bags** (sellable items, most
valuable first, paged), **Competing listings** for the picked item, and
**Your results** (market value and Razzle's price, then what History has
from your auction mail: sold, sell-through, expired, bought, the latest
records). Clicking a bag row at the auction house puts the item in
Blizzard's sell slot the same way shift-clicking does (below), so
Blizzard's own sell frame searches for its listings; the tab reads those
results (`COMMODITY_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_UPDATED`)
and shows them live, your own marked, and until then shows the latest
scan's cheapest listings. A **vs market** column gives each listing's
distance from market value (-12% in green, +8% in orange). Clicking a listing puts its exact price
in Blizzard's price box, only when the sell slot holds that item. Whatever
goes in the sell slot by hand is followed too. The tab never sends a
search, never posts: the Post click is the player's.

The Sell tab's third column, **Pricing**, lists every pricing method's price
per unit and for all your copies, with the one in use marked:
market value, median, trimmed mean (cheapest and dearest 10% of units left
out), undercut (1 copper below the cheapest other listing,
never under 80% of market value), match cheapest (to the copper) and your sales (your average sale price from History). Median,
trimmed mean, undercut and match use the live listings when the tab has
them, otherwise the latest scan's (Prices keeps each scan's median and
trimmed mean, and the cheapest listing from other sellers: Scan knows your
own auctions by seller name, so you never undercut yourself). Click a method to price by it from now on (also
`/mf pricing <method>`); if the sell slot holds the item, its price box
gets the new price. A method with no number yet falls back to market
value, and the tab says so. Below the methods: what your copies would
bring before and after the 5% cut, and how many Razzle would put up at a
time when that's fewer than you hold. WoW: Forever has the retail-style
auction house, so there are no stacks: a commodity (cloth, ore, potions) is
posted as one quantity at one price per unit, and buyers take the cheapest
units first. Then your results from History.

Post hooks Blizzard's sell frames (`ItemSellFrame`, `CommoditiesSellFrame`).
When an item goes in, it sets the price box to the chosen pricing method's
price (market value by default), to the copper, one frame after Blizzard sets its default. It never calls
a posting function: the Post click is always the player's. `/mf autofill`
turns the fill-in off and leaves Razzle's advice.

Shift-clicking a bag item while the auction house is open puts it up for
sale: Post finds it in the bags, calls Blizzard's `AuctionHouseFrame:SetPostItem`
(the same as right-clicking it on the Sell tab), and on the next frame sets
the quantity and duration. The quantity is everything you hold, capped at
what other sellers list right now (but never fewer than one bag slot
holds, e.g. 20 cloth); the duration is
Blizzard's middle choice unless changed with `/mf duration <hours>`, also
saved to Blizzard's `auctionHouseDurationDropdown` default. Durations are
named from the client's own strings (`AUCTION_DURATION_ONE` etc.; Forever's
dropdown shows 8 hours where retail shows 24), and if the dropdown ends up
on another duration, Razzle says the one it shows. It's skipped while a chat box, the
AH search box or one of Razzle's boxes has focus, so shift-click still
links items there. Razzle says what it set up; the player clicks Post.
`/mf shiftsell` turns it off.

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

History reads auction mail headers while the mailbox is open (it never
opens, takes or deletes mail). Sold mail has no item attached, so the item is
found by name: names learned from the sell slot and other auction mail, the
item cache, then your bags; a sale whose item isn't known yet keeps its name
and gets its ID once learned. Each mail is matched by what it says plus when
it arrived, so reopening the mailbox, reordering it or logging in again never
counts it twice. Records are account-wide per market scope, kept 30 days and
capped at 2,000. Tooltips get a **Your results** line; `/mf history` gives a
7-day summary, `/mf history recent` and `/mf history <item>` the details.

Outside reads `TSM_API.GetCustomPriceValue` (DBMarket, then
DBRegionMarketAvg) and `Auctionator.API.v1.GetAuctionPriceByItemID`, and
caches what it reads per auction house for 7 days so characters without
those addons still see them. Its tooltip line is labelled with the source and
shows only when Razzle has no price of its own (`/mf outside always|off`).
It is never mixed into Razzle's market value.

Prices also reports a **trend** (average of the last 3 days against the 4 to
14 days before; rising or falling at 10% or more) and a **confidence** score
from days of history, how steady they are, freshness and units listed. The
tooltip's **Razzle's read** line shows both (`/mf read` toggles it).

