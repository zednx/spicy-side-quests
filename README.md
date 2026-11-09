<img src="docs/logo.png" width="128" align="right" alt="Spicy Side Quests logo">

# 🌶️ Spicy Side Quests

**Your own side quests for WoW Forever.** A lightweight in-game todo list: jot down the things *you* want to do, sorted by category, tagged, and pinned to the map.

Works entirely in-game. If you like keeping notes outside the game, an **optional** sync script keeps the list in a markdown file, so you can plan your next session from your phone or desktop.

## Features

- **Categories**: group side quests under headers like *Professions*, *Dungeons* or *Gold*. Click a header to collapse it.
- **Tags**: add `#farming` or `#group` and filter the list by tag or text.
- **Locations and waypoints**: attach your current position with one click, or type a zone and coordinates. Click the map icon to set a waypoint (uses **TomTom** if installed, otherwise the built-in map pin).
- **Two themes**:
  - **Classic**: the familiar Blizzard look
  - **Modern**: flat and minimal, fits UIs like Daylight or ElvUI
- **Adjustable**: background and window opacity, font size, lock position, hide completed, hide in combat.
- **Lightweight**: no libraries, no dependencies, no ads, nothing phoning home.

## Install

Install from CurseForge, or download `SpicySideQuests-vX.Y.Z.zip` from [Releases](https://github.com/zednx/spicy-side-quests/releases). Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, then restart the game.

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

## Optional: sync with a markdown file

Keep the addon and a markdown file in step, so you can add or tick off side quests when you're not playing. I use an [Obsidian](https://obsidian.md) note synced to my phone, but **any `.md` file works**.

There are two ways to sync. Both behave the same:

| | For | Install |
|---|---|---|
| **Obsidian plugin** (recommended) | Obsidian on desktop | Inside Obsidian, so nothing for Windows to block |
| **Sync script** | Any `.md` file, any editor | Download and run (see below) |

```markdown
## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Unlock Tanaris flight path #travel ^d4e5f6
```

### How it works

Addons can't access files or the internet, so syncing happens outside the game: in the Obsidian plugin, or in a script running in a terminal window that shows each change as it happens. Either way, it only reads and writes this addon's own files and your chosen markdown file.

- **Two-way:** changes sync every time you `/reload` or log out. If the same side quest changed on both sides, the newest change wins.
- **Leaves your notes alone:** it only rewrites todo lines. Frontmatter, other text, sub-tasks and code blocks stay as they are.
- **Safe:** if the file goes missing or suddenly has no todos, it skips the sync rather than deleting anything.

### Obsidian plugin

1. In Obsidian, install the **BRAT** community plugin (it installs plugins straight from GitHub).
2. Run **BRAT: Add a beta plugin** and enter `zednx/spicy-side-quests`.
3. Enable **Spicy Side Quests** under Settings → Community plugins.
4. In its settings:
   - Pick your note (it's created if it doesn't exist).
   - Click **Find** to locate your WoW Forever folder, or paste the path in.

That's it. It syncs while Obsidian is open, whenever you edit the note or `/reload` in game. 🌶 in the status bar shows the last sync; click it to sync now.

Desktop only: phones can't reach the WoW folder. Edits made on your phone sync once your desktop Obsidian has them.

### Sync script setup

1. Download `SpicySideQuests-Companion-vX.Y.Z.zip` from [Releases](https://github.com/zednx/spicy-side-quests/releases) and extract it anywhere.
2. Start it:
   - **Windows:** double-click `start-powershell.cmd`. Nothing to install; it uses the PowerShell built into Windows 10/11.
   - **Linux/macOS:** run `./start.sh`. It needs [Node.js](https://nodejs.org) 22.18 or newer.
3. The first time, it walks you through picking your markdown file, your WoW Forever folder (e.g. `C:\Program Files (x86)\World of Warcraft\_forever_`) and, if you have several, your WoW account.
4. Leave it running while you play.

### Changing paths later

Moved your vault, reinstalled WoW or want a different file? Run **`setup-powershell.cmd`** (Windows), or `./setup.sh` (Linux/macOS). Press Enter to keep any value as it is.

You don't have to remember this, though. If a saved path stops existing, the script tells you and offers to run setup.

Pointing it at a different markdown file is safe. The first sync merges what's in the game with what's in the new file and deletes nothing.

Settings are saved in `%APPDATA%\SpicySideQuests` on Windows, or `~/.config/spicysidequests` elsewhere.

### Markdown format

- `## Headings` are categories.
- `#tags` are normal tags.
- `[zone:: ]` and `[xy:: ]` are optional locations. They're [Dataview](https://blacksmithgames.github.io/obsidian-dataview/)-style fields, so you can query them in Obsidian.
- `^a1b2c3` is an ID the script adds to each line. Leave it alone.

### Blocked by Windows?

The scripts aren't code-signed yet, so Windows may block them because they were downloaded from the internet. Please **don't turn off Smart App Control** to get around this: once it's off, Windows 11 can't turn it back on without a reinstall.

| You see | Fix |
|---|---|
| **"Windows protected your PC"** | Click **More info → Run anyway**, or unblock the zip (below). |
| **"Smart App Control blocked…"** | Unblock the zip **before** extracting it (below). If it's still blocked, use the Node option or a git clone (below). |
| **"…running scripts is disabled on this system"** | Unblock the zip (below). On a work PC, a policy may prevent scripts entirely. |

**Unblock the zip:** delete any folder you already extracted. Right-click `SpicySideQuests-Companion-vX.Y.Z.zip` → **Properties** → tick **Unblock** → **OK**. Then extract it again.

Already extracted? Run this in PowerShell inside the extracted folder:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

**Still blocked by Smart App Control?** Use one of these:
- **Obsidian plugin:** if you use Obsidian, the [plugin](#obsidian-plugin) needs no scripts at all.
- **Node option:** install [Node.js](https://nodejs.org) (signed and trusted by Windows). Open a terminal in the companion folder and run `node src\index.ts --setup`, then `node src\index.ts` from then on. Run it from a terminal; the `.cmd` launchers may still be blocked.
- **Git clone:** files from `git clone` aren't marked as downloaded. Run `companion\setup-powershell.cmd` from a clone of this repo.

Using Obsidian? The [Obsidian plugin](#obsidian-plugin) avoids all of this. Signed scripts are on the way.

## Security

The addon has no network access and only touches its own data. The optional scripts never connect to the internet and only touch the files listed in [SECURITY.md](SECURITY.md).

## Contributing

Run the tests listed in [CLAUDE.md](CLAUDE.md#tests-run-before-pushing). Releases follow semantic versioning (patch for fixes, minor for new features); `scripts/bump-version.sh` does the bumping.

## License

[MIT](LICENSE)

---

> **Disclaimer:** This is a hobby project, 100% vibe coded with AI for my own use. I'm sharing it in case it's useful to someone else. It's provided as-is, with no guarantees, so back up anything important. Feedback and bug reports are welcome!
