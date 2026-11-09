# CurseForge listing

Everything to fill in when creating the project at <https://authors.curseforge.com> (Create Project → World of Warcraft → Addon).

## Project settings

| Field | Value |
|---|---|
| Name | Spicy Side Quests |
| Summary (one line) | Your own side quests: an in-game todo list with categories, tags and waypoints, with optional sync to Obsidian/markdown. |
| Primary category | Quests & Leveling |
| Other categories | Map & Minimap, Miscellaneous |
| License | MIT |
| Source | GitHub: `https://github.com/zednx/spicy-side-quests` |
| Issues | `https://github.com/zednx/spicy-side-quests/issues` |
| Logo / avatar | `docs/logo.png` (1024×1024), or `docs/logo-400.png` if the uploader wants a smaller file |
| File to upload | `SpicySideQuests-v0.1.0.zip` from the GitHub Release |
| Game version for the file | WoW Forever |
| Release type | Release (or Beta for a soft launch) |

## Description

Paste everything below the line into the description editor (switch it to Markdown).

---

# 🌶️ Spicy Side Quests

**Your own side quests for WoW Forever.** A lightweight in-game todo list: jot down the things *you* want to do, sorted by category, tagged, and pinned to the map.

Works entirely in-game. If you like keeping notes outside the game, an **optional** companion script syncs the list with a markdown file (great with **Obsidian**), so you can plan your next session from your phone or desktop.

## Features

- **Categories**: group side quests under headers like *Professions*, *Dungeons* or *Gold*. Click a header to collapse it.
- **Tags**: add `#farming` or `#group` and filter the list by tag or text.
- **Locations and waypoints**: attach your current position with one click, or type a zone and coordinates. Click the map icon to set a waypoint (uses **TomTom** if installed, otherwise the built-in map pin).
- **Two themes**:
  - **Classic**: the familiar Blizzard look
  - **Modern**: flat and minimal, fits UIs like Daylight or ElvUI
- **Adjustable**: background and window opacity, font size, lock position, hide completed, hide in combat.
- **Lightweight**: no libraries, no dependencies, no ads, nothing phoning home.

## Commands

| Command | What it does |
|---|---|
| `/spicy` or `/ssq` | Show or hide the window |
| `/ssq add <text>` | Add a side quest |
| `/ssq config` | Settings |
| `/ssq reset` | Reset the window position |

## Adding side quests

Type in the box at the bottom of the window and press Enter:

```
Farm Arcanite #farming #alchemy @here
Run SM Cathedral #group
Find the Un'Goro pylons @Un'Goro Crater 44.2, 11.8
Loot chest @52.1, 41.3
```

- `#tag`: add any number of tags
- `@here`: your current zone and coordinates (or click the map button next to the input)
- `@Zone Name x, y`: a specific zone and coordinates

**Click** to complete, **right-click** to edit, hover and click the **X** to delete. Press **Tab** in the category box to cycle through existing categories.

## Optional: sync with Obsidian / markdown

Want to add side quests when you're not playing? The companion script keeps a markdown file and the addon in sync:

```markdown
## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Unlock Tanaris flight path #travel ^d4e5f6
```

- **Nothing to install on Windows**: it runs on the PowerShell built into Windows 10/11. There's also a Node.js version for Linux and macOS.
- **Readable**: plain source code you can inspect, running in a terminal window that shows every change it makes.
- **Two-way**: changes sync every time you `/reload` or log out.
- **Leaves your notes alone**: it only touches todo lines, never your other notes.

Addons can't access files or the internet, so the companion runs outside the game. It only reads and writes this addon's own files.

**Download and instructions:** see the GitHub page linked on this project.

## Feedback

Bugs and ideas are welcome on GitHub Issues. Happy questing! 🌶️
