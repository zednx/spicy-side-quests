# Code signing policy

> **Status:** applied for free code signing from the SignPath Foundation. **Releases are not signed yet.** This page describes how signing will work once approved. Signed releases will say so in their release notes.

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

## What gets signed

| File | Signed |
|---|---|
| `powershell/SpicySideQuests.ps1` in `SpicySideQuests-Companion-vX.Y.Z.zip` | Yes, Authenticode |
| Everything else (the addon's Lua files, the Node edition's TypeScript, `.cmd`/`.sh` launchers) | No: Windows doesn't run these files as signed code |

Only files built from this repository's source, by its [release workflow](.github/workflows/release.yml) on GitHub-hosted runners, are submitted for signing. Nothing from third parties is signed. The companion has no runtime dependencies.

## Team roles

| Role | Members |
|---|---|
| Authors (commit without review) | [zednx](https://github.com/zednx) |
| Reviewers (review outside contributions) | [zednx](https://github.com/zednx) |
| Approvers (approve every signing request) | [zednx](https://github.com/zednx) |

All team members use multi-factor authentication for GitHub and SignPath.

## How a release is signed

1. A version tag (`vX.Y.Z`) is pushed, and GitHub Actions builds the release from that tag's source.
2. The workflow submits `SpicySideQuests.ps1` to SignPath.
3. An approver reviews and approves the signing request by hand.
4. The signed script is packed into the companion zip, which is attested (`gh attestation verify <zip> --repo zednx/spicy-side-quests`) and published.

## Privacy

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it. The addon, the companion scripts and the Obsidian plugin make no network connections at all; see [SECURITY.md](SECURITY.md).

## Uninstalling

- **Addon:** delete `Interface/AddOns/SpicySideQuests`. Optionally also delete `WTF/Account/<account>/SavedVariables/SpicySideQuests.lua`.
- **Companion scripts:** delete the extracted folder, and the settings folder: `%APPDATA%\SpicySideQuests` (Windows) or `~/.config/spicysidequests`.
- **Obsidian plugin:** disable and uninstall it under Settings → Community plugins.

Nothing is installed system-wide, and no system settings are changed. The `.cmd` launchers use `-ExecutionPolicy Bypass` for that one script only.

## Reporting a problem

Use GitHub's **Report a vulnerability** (Security tab), or open an issue.
