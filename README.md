# MarketForces

An auction house addon for WoW: Forever, in the spirit of the classic AH
addons: scan the auction house, keep price history,
show prices on tooltips and help you post.

**Status:** core framework only. The addon loads, saves data and has a `/mf`
command, but the features (scanning, price history, tooltips, posting) are not
built yet. Each one will arrive as its own module.

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
