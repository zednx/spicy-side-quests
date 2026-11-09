<img src="docs/logo.png" width="128" align="right" alt="Spicy Side Quests logo">

# Spicy Side Quests

Your own **side quests** for WoW Forever: a lightweight todo list addon with categories, tags and map waypoints.

It works entirely in-game out of the box. An **optional** companion script syncs the list with a markdown file, such as an Obsidian note, so you can add todos when you're not playing.

## Features

- Movable, resizable window with todos grouped by **category** (click a header to collapse it)
- **Tags** (`#farming`) with a filter box (`#farm`, or plain text)
- **Locations**: attach your current position or a zone and coordinates; click the map icon to set a waypoint (uses TomTom if installed, otherwise the built-in map pin)
- **Two themes**: *Classic* (Blizzard style) and *Modern* (flat and minimal, suits UIs like Daylight or ElvUI)
- Settings for **background opacity**, **window opacity**, **font size**, lock, show/hide completed, hide in combat
- No libraries, no dependencies

## Install

1. Download the repo (or a release zip).
2. Copy the `SpicySideQuests` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
   - The path should end in `.../AddOns/SpicySideQuests/SpicySideQuests.toc`, not one folder deeper.
3. Restart the game client (a `/reload` is not enough for a new addon).

## Usage

| Action | How |
|---|---|
| Show/hide window | `/spicy` or `/ssq`, or the AddOn compartment button |
| Add | Type in the bottom box and press Enter, or `/ssq add <text>` |
| Choose category | Bottom-left box; **Tab** cycles existing categories; right-click a header to add to it |
| Complete | Click the item or its checkbox |
| Edit | Right-click the item (press Enter to save, Esc to cancel) |
| Delete | Hover the item and click the red **X** |
| Waypoint | Click the map icon on the item |
| Settings | Gear icon or `/ssq config` |
| Reset position | `/ssq reset` |

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

## Markdown sync (optional)

The `companion/` folder has a small script that keeps a markdown file (e.g. an Obsidian note) and the addon in sync. It runs in a terminal and logs each change it makes. It comes in two versions that behave the same and share settings, so you can switch between them:

| Version | Needs | File |
|---|---|---|
| **PowerShell** | Nothing on Windows 10/11 (built in) | `companion/powershell/SpicySideQuests.ps1` |
| **Node** | [Node.js](https://nodejs.org) 22.18+; good for Linux/macOS | `companion/src/` (TypeScript, no dependencies) |

Both are plain source code, so you can read every line before running them.

### How it works

WoW addons can't read files or use the network, so the script works through two files:

| Direction | File |
|---|---|
| Markdown → game | Writes `Interface/AddOns/SpicySideQuests/Inbox.lua`. The game loads it but never overwrites it. |
| Game → markdown | Reads `WTF/Account/<ACCOUNT>/SavedVariables/SpicySideQuests.lua`. The game writes it on `/reload` and logout. |

So changes go both ways **every time you `/reload`** (or log out). If the same todo changes on both sides, the newest change wins.

### Run it

1. Download this repo.
2. Start a script:
   - **Windows, no install:** double-click `companion/start-powershell.cmd`
   - **Windows with Node:** double-click `companion/start.cmd`
   - **Linux/macOS:** `./companion/start.sh` (Node), or `pwsh companion/powershell/SpicySideQuests.ps1`
3. The first time, it asks for your markdown file and WoW folder (e.g. `C:\Program Files (x86)\World of Warcraft\_forever_`).

> The PowerShell launcher uses `-ExecutionPolicy Bypass` for this one script only, because Windows blocks downloaded scripts by default. It doesn't change any system settings.

Settings are saved to `%APPDATA%\SpicySideQuests\config.json` on Windows, or `~/.config/spicysidequests/config.json` elsewhere.

| Node flag | PowerShell flag | What it does |
|---|---|---|
| `--once` | `-Once` | Sync one time and exit |
| `--setup` | `-Setup` | Change the markdown file or WoW folder |
| `--dry-run` | `-DryRun` | Show what would change without writing |
| `--config <file>` | `-Config <file>` | Use a different config file |

### Markdown format

```markdown
## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Unlock Tanaris flight path #travel ^d4e5f6
```

- `##` headings are categories. Todos above the first heading go to **General**.
- `#tags` are normal Obsidian tags.
- `[zone:: ]` and `[xy:: ]` are [Dataview](https://blacksmithgames.github.io/obsidian-dataview/) inline fields, and both are optional.
- `^a1b2c3` is a block ID that the script adds to each line so it can track that todo. Don't edit it.
- The script only rewrites todo lines. Frontmatter, notes, indented sub-tasks and code blocks are left as they are.

> **Safety:** if the markdown file goes missing or suddenly has no todos, the script skips syncing rather than deleting everything in game.

## Development

```bash
lua5.1 tests/run.lua          # addon smoke test with a stubbed WoW API
cd companion && npm test      # companion tests (node:test, no install needed)
pwsh powershell/test.ps1      # PowerShell edition tests (also run on Windows PowerShell 5.1 in CI)
npm install && npm run typecheck
npm run build:exe             # optional single-file Windows exe (needs Bun)
python3 tools/make_art.py     # regenerate the icon and logo (needs Pillow)
scripts/check-version.sh 0.1.0  # check all version strings match before tagging
```

## License

MIT

---

> **Disclaimer:** This is a hobby project, 100% vibe coded with AI for my own use. I'm sharing it in case it's useful to someone else. It's provided as-is, with no guarantees, so back up anything important. Feedback and bug reports are welcome!
