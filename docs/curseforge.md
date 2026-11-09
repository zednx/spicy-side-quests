# CurseForge listing

Project: <https://authors.curseforge.com/#/projects/1794870/general> (id **1794870**)

## Automatic uploads

Each `v*` tag uploads the addon zip to CurseForge, set to the newest **WoW Forever** game version, with the changelog section as release notes. To turn it on:

1. On CurseForge, create an **API token** (your account settings → API tokens).
2. On GitHub, open the repo's **Settings → Secrets and variables → Actions → New repository secret**:
   - Name: `CF_API_KEY`
   - Secret: the token
3. If the upload picks the wrong game version, also add a repository **variable** `CF_GAME_VERSIONS` with the right version id(s), comma-separated. The workflow log lists them.

Without the secret, releases still publish on GitHub and just skip CurseForge.

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
- **Adjustable**: background and window opacity, font size, wrap long side quests, lock position, hide completed, hide in combat.
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

Want to add side quests when you're not playing? Keep the addon in sync with a markdown file:

```markdown
## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Unlock Tanaris flight path #travel ^d4e5f6
```

- **Obsidian plugin** (recommended for Obsidian users): installs inside Obsidian on desktop, with a settings page to pick your note and WoW folder. Nothing to download or run.
- **Sync script**, for any markdown file: uses the PowerShell built into Windows 10/11 (nothing to install), or Node.js on Linux and macOS. It's plain, readable source code running in a terminal window that shows every change.

Either way:
- **Two-way:** changes sync every time you `/reload` or log out.
- **Leaves your notes alone:** only todo lines are touched, never your other notes.

Addons can't access files or the internet, so syncing runs outside the game, and only reads and writes this addon's own files and your chosen note.

**Setup instructions:** see the GitHub page linked on this project.

## Feedback

Bugs and ideas are welcome on GitHub Issues. Happy questing! 🌶️

---

> **Disclaimer:** This is a hobby project, 100% vibe coded with AI for my own use. I'm sharing it in case it's useful to someone else. It's provided as-is, with no guarantees, so back up anything important. Feedback and bug reports are welcome!
