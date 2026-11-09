<img src="docs/logo.png" width="128" align="right" alt="Spicy Side Quests logo">

# 🌶️ Spicy Side Quests

**Your own side quests for WoW Forever.** A lightweight in-game todo list: jot down the things *you* want to do, sorted by category, tagged, and pinned to the map.

Works entirely in-game. If you like keeping notes outside the game, **optional** syncing keeps the list in a markdown file (an Obsidian plugin, or a small script), so you can plan your next session from your phone or desktop.

## Features

- **Categories**: group side quests under headers like *Professions*, *Dungeons* or *Gold*. Click a header to collapse it.
- **Tags**: add `#farming` or `#group` and filter the list by tag or text.
- **Locations and waypoints**: attach your current position with one click, or type a zone and coordinates. Click the map icon to set a waypoint (uses **TomTom** if installed, otherwise the built-in map pin).
- **Two themes**:
  - **Classic**: the familiar Blizzard look
  - **Modern**: flat and minimal, fits UIs like Daylight or ElvUI
- **Adjustable**: background and window opacity, font size, lock position, hide completed, hide in combat.
- **Lightweight**: no libraries, no dependencies, no ads, nothing phoning home.

## Screenshots

| | |
|-|-|
| Classic theme |<img width="465" height="323" alt="Screenshot 2026-11-10 091327" src="https://github.com/user-attachments/assets/ee2924f4-7de2-4ad5-a4de-4702f0a78aed" />|
| Modern theme |<img width="492" height="355" alt="Screenshot 2026-11-10 091319" src="https://github.com/user-attachments/assets/a4e897f8-0a18-4398-8607-e4bb32ee4368" />|
| Sync with companion|<img width="923" height="621" alt="Screenshot 2026-11-10 091547" src="https://github.com/user-attachments/assets/3fb1ab5e-9aed-4580-b5ff-bca9f5ca0a79" />|


## Install

Install from [CurseForge](https://www.curseforge.com/wow/addons/spicy-side-quest), or download `SpicySideQuests-vX.Y.Z.zip` from [Releases](https://github.com/zednx/spicy-side-quests/releases). Extract it into `World of Warcraft/_forever_/Interface/AddOns/`, then restart the game.

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

```markdown
## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Unlock Tanaris flight path #travel ^d4e5f6
```

- **Two-way:** changes sync every time you `/reload` or log out in game. If the same side quest changed on both sides, the newest change wins.
- **Leaves your notes alone:** only todo lines are rewritten. Frontmatter, other text, sub-tasks and code blocks stay as they are.
- **Safe:** if the file goes missing or suddenly has no todos, the sync is skipped rather than deleting anything.

Pick **one** way to sync (they behave the same; don't run both at once):

| | For | |
|---|---|---|
| **[Obsidian plugin](#obsidian-plugin)** (recommended) | Obsidian on desktop | Installs inside Obsidian; nothing for Windows to block |
| **[Sync script](#sync-script)** | Any `.md` file, any editor | A script you run in a terminal window |

### Obsidian plugin

Syncs a note in your vault while Obsidian is open. Desktop only.

<details>
<summary><b>Install and set up</b></summary>

1. In Obsidian, go to **Settings → Community plugins → Browse**, install **BRAT** and enable it. BRAT installs plugins straight from GitHub.
2. Open the command palette (`Ctrl/Cmd+P`), run **BRAT: Add a beta plugin**, and enter `zednx/spicy-side-quests`.
3. Enable **Spicy Side Quests** under **Settings → Community plugins**.
4. Open its settings:
   - **Side quests note:** pick a note, or type a new name and it's created on the first sync.
   - **WoW Forever folder:** click **Find**, or paste the path, e.g. `C:\Program Files (x86)\World of Warcraft\_forever_`. It should say **✓ Addon found**.
   - **WoW account:** only shown if you have more than one. *Auto* picks the one you played last.

Your in-game side quests appear in the note within a few seconds.

</details>

<details>
<summary><b>Using it</b></summary>

- **When it syncs:** a moment after you edit the note, and whenever the game saves (on `/reload` or logout). New side quests from the note show up in game after your next `/reload`.
- **🌶 in the status bar** shows the last sync time. Click it to sync now.
- **Commands** (`Ctrl/Cmd+P`): *Sync now* and *Open side quests note*. The 🔥 ribbon button also opens the note.
- **Rename or move the note freely:** the plugin follows it.
- **On your phone:** edit the note as usual (e.g. with [Obsidian Git](https://github.com/Vinzent03/obsidian-git) or Obsidian Sync). It syncs to the game once your desktop Obsidian has the changes.
- **Recent activity** in the plugin settings lists what changed and when.

</details>

<details>
<summary><b>Switching from the sync script</b></summary>

1. Close the script's window, so only one thing syncs.
2. Set up the plugin with the same note.

The first sync merges what's in the game with what's in the note. Nothing is deleted.

</details>

<details>
<summary><b>Install without BRAT</b></summary>

1. Download `main.js`, `manifest.json` and `styles.css` from the latest **Obsidian plugin** release on the [Releases](https://github.com/zednx/spicy-side-quests/releases) page.
2. Put them in `<your vault>/.obsidian/plugins/spicy-side-quests/`.
3. Restart Obsidian and enable the plugin.

BRAT is easier for updates: it checks for new versions for you.

</details>

### Sync script

For any markdown file and any editor. Runs in a terminal window that shows each change as it happens.

<details>
<summary><b>Set up</b></summary>

1. Download `SpicySideQuests-Companion-vX.Y.Z.zip` from [Releases](https://github.com/zednx/spicy-side-quests/releases). On Windows, **unblock it first**: right-click → **Properties** → tick **Unblock** → **OK**. Then extract it anywhere.
2. Start it:
   - **Windows:** double-click `start-powershell.cmd`. Nothing to install; it uses the PowerShell built into Windows 10/11.
   - **Linux/macOS:** run `./start.sh`. It needs [Node.js](https://nodejs.org) 22.18 or newer.
3. The first time, it walks you through picking:
   - your markdown file
   - your WoW Forever folder (e.g. `C:\Program Files (x86)\World of Warcraft\_forever_`)
   - your WoW account, if you have several
4. Leave it running while you play.

</details>

<details>
<summary><b>Changing paths later</b></summary>

Moved your vault, reinstalled WoW or want a different file? Run **`setup-powershell.cmd`** (Windows), or `./setup.sh` (Linux/macOS). Press Enter to keep any value as it is.

You don't have to remember this, though. If a saved path stops existing, the script tells you and offers to run setup.

Pointing it at a different markdown file is safe. The first sync merges what's in the game with what's in the new file and deletes nothing.

Settings are saved in `%APPDATA%\SpicySideQuests` on Windows, or `~/.config/spicysidequests` elsewhere.

</details>

<details>
<summary><b>Blocked by Windows?</b></summary>

The scripts aren't code-signed yet, so Windows may block them because they were downloaded from the internet. Please **don't turn off Smart App Control** to get around this: once it's off, Windows 11 can't turn it back on without a reinstall.

| You see | Fix |
|---|---|
| **"Windows protected your PC"** | Click **More info → Run anyway**, or unblock the zip (below). |
| **"Smart App Control blocked…"** | Unblock the zip **before** extracting it (below). If it's still blocked, see the options below. |
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

Signed scripts are on the way.

</details>

### Markdown format

<details>
<summary><b>How todos are written in the file</b></summary>

- `## Headings` are categories. Todos above the first heading go to **General**.
- `#tags` are normal tags.
- `[zone:: ]` and `[xy:: ]` are optional locations. They're [Dataview](https://blacksmithgames.github.io/obsidian-dataview/)-style fields, so you can query them in Obsidian.
- `^a1b2c3` is an ID added to each line so the sync can track it. Leave it alone.
- `- [x]` (or any mark, like `- [-]`) counts as done.
- Indented sub-tasks, code blocks and lines longer than 1000 characters are left alone.

</details>

## Security

The addon has no network access and only touches its own data. The optional scripts and Obsidian plugin never connect to the internet, and only touch the files listed in [SECURITY.md](SECURITY.md).

**Code signing policy:** see [CODE_SIGNING_POLICY.md](CODE_SIGNING_POLICY.md). The Windows PowerShell script is set to be signed through the SignPath Foundation (application pending; releases aren't signed yet).

<details>
<summary><b>Uninstalling</b></summary>

- **Addon:** delete `Interface/AddOns/SpicySideQuests`. Optionally also delete `WTF/Account/<account>/SavedVariables/SpicySideQuests.lua`.
- **Sync script:** delete the folder you extracted, and the settings folder: `%APPDATA%\SpicySideQuests` (Windows) or `~/.config/spicysidequests`.
- **Obsidian plugin:** disable and uninstall it under Settings → Community plugins.

Nothing is installed system-wide. Your markdown note is never deleted.

</details>

## Contributing

Run the tests listed in [CLAUDE.md](CLAUDE.md#tests-run-before-pushing). Releases follow semantic versioning (patch for fixes, minor for new features); `scripts/bump-version.sh` does the bumping.

## License

[MIT](LICENSE)

---

> **Disclaimer:** This is a hobby project, 100% vibe coded with AI for my own use. I'm sharing it in case it's useful to someone else. It's provided as-is, with no guarantees, so back up anything important. Feedback and bug reports are welcome!
