# Changelog

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

### Security
- Hardened against malformed or hostile input; see [SECURITY.md](SECURITY.md)
