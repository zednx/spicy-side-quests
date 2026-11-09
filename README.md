# WoW Todo Sync

A lightweight todo list addon for **WoW Forever**, with categories, tags and map waypoints.

It works entirely in-game out of the box. An **optional** companion app (coming soon) syncs the list with a markdown file, such as an Obsidian note, so you can add todos when you're not playing.

## Features

- Movable, resizable window with todos grouped by **category** (click a header to collapse it)
- **Tags** (`#farming`) with a filter box (`#farm`, or plain text)
- **Locations**: attach your current position or a zone and coordinates; click the map icon to set a waypoint (uses TomTom if installed, otherwise the built-in map pin)
- Settings for **background opacity**, **window opacity**, **font size**, lock, show/hide completed, hide in combat
- No libraries, no dependencies

## Install

1. Download the repo (or a release zip).
2. Copy the `WoWTodoSync` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
   - The path should end in `.../AddOns/WoWTodoSync/WoWTodoSync.toc`, not one folder deeper.
3. Restart the game client (a `/reload` is not enough for a new addon).

## Usage

| Action | How |
|---|---|
| Show/hide window | `/todo` or the AddOn compartment button |
| Add | Type in the bottom box and press Enter, or `/todo add <text>` |
| Choose category | Bottom-left box; **Tab** cycles existing categories; right-click a header to add to it |
| Complete | Click the item or its checkbox |
| Edit | Right-click the item (press Enter to save, Esc to cancel) |
| Delete | Hover the item and click the red **X** |
| Waypoint | Click the map icon on the item |
| Settings | Gear icon or `/todo config` |
| Reset position | `/todo reset` |

### Input syntax

```text
Farm Arcanite #farming #alchemy @here
Run SM Cathedral #group
Find the Un'Goro pylons @Un'Goro Crater 44.2, 11.8
Loot chest @52.1, 41.3          (coordinates in your current zone)
```

- `#tag`: any number of tags
- `@here`: your current zone and coordinates (the map button next to the input adds it)
- `@Zone Name x, y`: a zone with coordinates; `@Zone Name` on its own also works

> Coordinates aren't available inside dungeons and raids; only the zone name is stored there.

## Markdown sync (planned)

The companion app will sync a markdown file like this:

```markdown
## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Unlock Tanaris flight path #travel ^d4e5f6
```

How it works: WoW addons can't read files or use the network. The app writes `WoWTodoSync/Inbox.lua` (which the game loads but never overwrites) and reads the addon's SavedVariables. Changes sync both ways on every `/reload` or logout. The addon is fully usable without it.

## Development

```bash
lua5.1 tests/run.lua   # headless smoke test with stubbed WoW API
```

## License

MIT
