# MarketForces

An auction house addon for World of Warcraft: The Burning Crusade, in the
spirit of the classic AH addons: scan the auction house, keep price history,
show prices on tooltips and help you post.

**Status:** core framework only. The addon loads, saves data and has a `/mf`
command, but the features (scanning, price history, tooltips, posting) are not
built yet. Each one will arrive as its own module.

## Install

1. Copy this folder into `World of Warcraft/_anniversary_/Interface/AddOns/`
   (or your TBC client's `Interface/AddOns/`) and name it `MarketForces`.
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
and per auction house data keyed `Realm-Faction` (`Realm-Neutral` for the
goblin auction houses), which is where price history will live.

## Development

```
luacheck .              # lint
lua5.1 tests/run.lua    # smoke test
```

Both run in CI on every pull request.
