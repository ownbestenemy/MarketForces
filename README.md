# MarketForces

An auction house addon for WoW: Forever, in the spirit of the classic AH
addons: scan the auction house, keep price history,
show prices on tooltips and help you post.

**Status:** core framework only. The addon loads, saves data and has a `/mf`
command, but the features (scanning, price history, tooltips, posting) are not
built yet. Each one will arrive as its own module.

## Design: your goblin broker

MarketForces presents itself as a goblin auction broker: a character the
player talks to rather than a spreadsheet. When the auction house opens, the
broker greets you, tells you what has changed since your last visit, and
offers advice ("Copper Bars are going cheap today, boss"). Its window is where
you look up prices, review suggested listings and decide what to post. The
broker suggests and explains; you make every decision and every click.

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
tests/run.lua      offline smoke test with a fake WoW API
```

Saved data is split three ways: account-wide settings, per-character settings,
and per auction house data, which is where price history will live. Forever is
realmless, so each auction house is keyed by what `GetRealmName()` reports
(expected to name the ruleset) plus the house: Alliance, Horde or Neutral.

Forever runs on the modern (Mainline-based) client, so the Scan and Post
modules will use the `C_AuctionHouse` API, including commodity (unit-priced)
listings, rather than the old `QueryAuctionItems` API.

## Development

```
luacheck .              # lint
lua5.1 tests/run.lua    # smoke test
```

Both run in CI on every pull request.
