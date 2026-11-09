# Security

## What this project can touch

**Addon:** runs inside WoW's addon sandbox. It never sends chat, mail, trade or addon messages and has no network access. It reads only its own saved data and its own `Inbox.lua`.

**Companion scripts** (optional) run on your computer with your user permissions:

| | Reads | Writes |
|---|---|---|
| Your markdown file | ✓ | ✓ (only todo lines change) |
| `WTF/Account/*/SavedVariables/SpicySideQuests.lua` | ✓ | ✗ |
| `Interface/AddOns/SpicySideQuests/Inbox.lua` | ✓ | ✓ |
| Its own settings folder (`%APPDATA%\SpicySideQuests` or `~/.config/spicysidequests`) | ✓ | ✓ |

They make no network connections, run no other programs and never execute anything they read. Game files are parsed as data, never run.

## Safeguards

- Text from markdown is escaped before it goes into `Inbox.lua`, so a todo can't inject code into the game. Tests round-trip hostile strings through a real Lua interpreter.
- Data from the game is reduced to a single line before it's written to markdown, so it can't add lines, headings or todos to your notes.
- Text is escaped before the addon shows it in tooltips or chat (WoW's `|` codes), and before the scripts print it to the terminal (escape sequences).
- The addon validates every field it imports and caps lengths.
- Very long lines and deeply nested data are skipped or rejected, so they can't hang the parsers.
- Files are written through a temp file with a random, exclusive name, then swapped in.
- The scripts skip a sync rather than delete everything if your markdown file goes missing or is emptied.
- Release zips are built by GitHub Actions with build attestations. Verify one with `gh attestation verify <zip> --repo zednx/spicy-side-quests`.

## Reporting a problem

Please use GitHub's **Report a vulnerability** button (Security tab), or open an issue if it isn't sensitive.
