# Changelog

## Obsidian plugin 0.1.1

- Fix: the plugin no longer syncs while you're typing in the note. It used to add `^id`s to half-written lines and send them to the game mid-sentence.
- It now waits until you've stopped typing for **30 seconds**, or syncs straight away when you switch to another note or app (like WoW). Change the wait under **Wait after typing** in the plugin settings.
- **Sync now** (status bar or command) still syncs immediately.

## v0.2.0

### Addon
- Long side quests now wrap onto extra lines instead of being cut off. Turn it off with **Wrap long side quests** in `/ssq config`.

### Companion
- Internal: the sync engine is shared with the new Obsidian plugin. No change in behaviour.
- Docs: troubleshooting for Windows blocking scripts, and an uninstall section.

## Obsidian plugin 0.1.0

- New: sync a note in your vault with the addon, from inside Obsidian (desktop). No scripts to run, nothing for Windows to block.
- Settings: note picker, WoW folder with **Find**, account choice, check interval, **Sync now**, recent activity.
- Syncs when you edit the note and when the game saves (on `/reload` or logout). Follows the note if you rename or move it.
- Same sync engine and safety checks as the companion scripts.

## v0.1.0

First release.

### Addon
- In-game side quest list with categories (collapsible headers) and `#tags`
- Filter box: plain text or `#tag`
- Locations: `@here`, `@Zone x, y` or `@x, y`; click the map icon to set a waypoint (TomTom if installed, otherwise the built-in map pin)
- Click to complete, right-click to edit, hover and click X to delete
- Two themes: Classic and Modern (flat, minimal; suits Daylight / ElvUI-style UIs)
- Settings: background and window opacity, font size, lock, show completed, hide in combat
- Commands: `/spicy`, `/ssq`, `/ssq add <text>`, `/ssq config`, `/ssq reset`
- AddOn compartment button

### Companion (optional)
- Two-way sync between the addon and a markdown file (e.g. an Obsidian note) on every `/reload` or logout
- PowerShell edition (nothing to install on Windows 10/11) and Node.js edition (Linux/macOS), sharing the same settings
- Keeps non-todo markdown untouched; refuses syncs that would delete everything
- Guided setup (`setup-powershell.cmd`, `setup.sh`, `--setup`): numbered WoW folder and account choices, Enter keeps current values; warns and offers setup when a saved path no longer exists; switching markdown files never deletes todos

### Security
- Hardened against malformed or hostile input; see [SECURITY.md](SECURITY.md)
