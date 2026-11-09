# Spicy Side Quests: working notes for Claude

A WoW Forever addon (in-game side quest/todo list) with optional markdown sync, through a companion script (PowerShell or Node) or an Obsidian plugin.

## Layout

| Path | What |
|---|---|
| `SpicySideQuests/` | The addon (Lua). Interface 16001. Only this folder ships to CurseForge. |
| `companion/src/` | Sync engine + Node CLI (TypeScript, no runtime deps, runs with `node src/index.ts`). |
| `companion/powershell/` | PowerShell edition of the CLI: must behave the same as the Node one and share config/state files. |
| `obsidian-plugin/` | Obsidian plugin. Bundles the engine from `companion/src` with esbuild. Its manifest is `manifest.json` at the repo root. |
| `scripts/` | `bump-version.sh`, `check-version.sh`, `check-release.sh`, `curseforge-upload.sh`. |

## Tests (run before pushing)

```bash
lua5.1 tests/run.lua                                   # addon
cd companion && npm test && npx tsc --noEmit -p .      # engine + Node CLI
cd obsidian-plugin && npm run build && npm test        # plugin (typecheck: npm run typecheck)
pwsh companion/powershell/test.ps1                     # PowerShell (CI also runs it on Windows PowerShell 5.1)
```

A change to the sync behaviour must land in **both** the Node engine and the PowerShell edition, with tests in both.

## Versioning and releases

Every release **must** bump the version:
- **patch** (0.1.0 → 0.1.1): bug fixes and small tweaks
- **minor** (0.1.0 → 0.2.0): new features
- **major**: breaking changes (e.g. the saved data or markdown format changes incompatibly)

There are two version tracks:

| Track | Bump | Tag | Workflow |
|---|---|---|---|
| Addon + companion scripts | `scripts/bump-version.sh addon patch\|minor` | `vX.Y.Z` | `release.yml`: GitHub Release + CurseForge upload |
| Obsidian plugin | `scripts/bump-version.sh plugin patch\|minor` | `X.Y.Z` (no `v`, Obsidian requires it) | `obsidian-release.yml` |

The bump script updates every version string and adds a CHANGELOG section with a `TODO` placeholder. Fill it in before tagging. `scripts/check-release.sh` (run by both workflows) refuses a release whose version isn't higher than the last one, or whose CHANGELOG section is missing or still says TODO.

Code signing (SignPath) for `SpicySideQuests.ps1` is wired into `release.yml` and switches on with the `SIGNPATH_*` secret and variables; see `docs/signing.md`. A signed release needs the user to approve the request in SignPath.

Claude sessions can't push tags. Ask the user to run `git tag … && git push origin …`.

## Rules that matter

- **No network access anywhere** (addon, scripts, plugin), apart from the CurseForge upload in CI. Never execute anything read from files.
- **Escape user text:** `|` in anything the addon shows (`ns.Escape`), terminal escape sequences in script output (`terminalSafe` / `Get-TerminalSafe`), Lua strings via `toLua` / `ConvertTo-Lua`. Values written to markdown go through `oneLine`.
- **Never delete the user's todos by accident:** keep the mass-delete guard, and reset the sync history when the markdown file changes.
- **Leave non-todo markdown untouched.**
- GitHub owner is **zednx**. Don't reintroduce the old username anywhere.
- Pin GitHub Actions to commit SHAs; pin new npm dev dependencies to versions at least two weeks old.
