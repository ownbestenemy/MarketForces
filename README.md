# MarketForces

An auction house addon for WoW: Forever, in the spirit of the classic AH
addons: scan the auction house, keep price history,
show prices on tooltips and help you post.

**Status:** the core framework and the Scan module are built: open the
auction house and click **Full Scan** (or type `/mf scan`) to read every
auction. Price history, tooltips, posting and Razzle's window are next, each
as its own module.

## Design: Razzle's Dazzles

MarketForces presents itself as Razzle, the goblin auction broker behind
Razzle's Dazzles: a character the player talks to rather than a spreadsheet. When the auction house opens,
Razzle greets you, tells you what has changed since your last visit, and
offers advice ("Copper Bars are going cheap today, boss"). Its window is where
you look up prices, review suggested listings and decide what to post. Razzle
suggests and explains; you make every decision and every click.

The persona lives in its own Broker module (UI and voice), on top of the data
modules, so the data side stays plain and testable.

## Staying within Blizzard's rules

MarketForces is built to follow Blizzard's UI Add-On Development Policy and
Terms of Use for WoW: Forever, and never to work around them:

- **No automation.** Every buy, bid, post and cancel happens only when you
  click a button. The addon never chains auction actions together or acts
  on a timer, and it only calls Blizzard's protected auction functions from
  a hardware click, as the client requires.
- **Scans stay polite.** Searches go through the normal `C_AuctionHouse`
  API, respect the client's throttle, and only run while the auction house
  window is open.
- **No outside connections.** The addon makes no web requests and does not
  use the Battle.net web API. Price data comes only from what your own
  client sees, and it stays in your SavedVariables on your PC.
- **Free and readable.** The code is open source and not obfuscated. There
  are no ads, paid features or in-game donation requests.
- **Old data gets pruned.** Price history is trimmed to a rolling window
  (30 days by default), so the saved file stays small and the data stays
  current.

If a Blizzard rule changes, the rule wins: features get changed or removed to
match.

## Install

1. Copy this folder into `World of Warcraft/_forever_/Interface/AddOns/`
   and name it `MarketForces`.
2. Restart the game or `/reload`.

If the addon shows as "out of date", check your client's interface number in
game with `/dump select(4, GetBuildInfo())` and update `## Interface:` in
`MarketForces.toc` to match.

## Commands

| Command | What it does |
| --- | --- |
| `/mf` or `/mf help` | List commands |
| `/mf version` | Show the addon version |
| `/mf scan` | Full scan of the open auction house (same as the Full Scan button) |
| `/mf status` | When this auction house was last scanned, and when the next scan is allowed |
| `/mf modules` | List modules and whether each is on |
| `/mf enable <module>` / `/mf disable <module>` | Turn a module on or off (saved) |
| `/mf debug` | Toggle debug messages |
| `/mf reset confirm` | Erase all saved data |

## Layout

```
MarketForces.toc   load order and SavedVariables
Core/
  Init.lua         shared namespace, chat output
  Util.lua         money formatting, defaults merging, AH key
  Events.lua       game events and internal messages
  Database.lua     SavedVariables setup, schema migrations
  Modules.lua      module registry and lifecycle
  Slash.lua        /mf command and subcommand registry
  Core.lua         startup (loaded last)
Modules/           feature modules (see Modules/README.md)
  Scan.lua         full auction house scan, one per click
tests/             offline tests against a fake WoW API (run.lua runs them all)
```

Saved data is split three ways: account-wide settings, per-character settings,
and per auction house data, which is where price history will live. Forever is
realmless: `GetRealmName()` reports a backend shard like
`CAMWOW US1 Realm 9 RP PvP`, so each auction house is keyed by region,
ruleset and house instead, e.g. `US-RP PvP-Horde` (house is Alliance, Horde
or Neutral).

Forever runs on the modern (Mainline-based) client, so the Scan and Post
modules will use the `C_AuctionHouse` API, including commodity (unit-priced)
listings, rather than the old `QueryAuctionItems` API.

## Development

```
luacheck .              # lint
lua5.1 tests/run.lua    # tests
```

Both run in CI on every pull request.
