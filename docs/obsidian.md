# Obsidian plugin: releasing and listing

## Releasing a version

1. Bump `version` in `manifest.json` (repo root), and add the same version to `versions.json` (mapped to `minAppVersion`).
2. Push a tag that is **exactly** the version, with no `v` (Obsidian requires this):
   ```bash
   git tag 0.1.0
   git push origin 0.1.0
   ```
3. The **obsidian-release** workflow builds the plugin, checks the tag matches, and publishes a release with `main.js`, `manifest.json` and `styles.css` (plus checksums and a build attestation).

Addon releases keep using `v`-prefixed tags (`v0.1.0`), so the two never collide.

## Getting listed in Obsidian's Community Plugins

Until it's listed, people can install it with BRAT (`zednx/spicy-side-quests`).

To submit it:
1. Make sure a plugin release exists (above).
2. Fork <https://github.com/obsidianmd/obsidian-releases> and add this to the end of `community-plugins.json`:
   ```json
   {
     "id": "spicy-side-quests",
     "name": "Spicy Side Quests",
     "author": "zednx",
     "description": "Sync a todo note with the Spicy Side Quests addon for World of Warcraft: Forever. Add side quests here, tick them off in game.",
     "repo": "zednx/spicy-side-quests"
   }
   ```
3. Open a pull request and fill in its checklist. An automated bot checks the release first, then Obsidian's team reviews it by hand, which can take a few weeks.

## Local development

```bash
cd obsidian-plugin
npm install
npm run dev     # rebuilds main.js on save
npm test
```

To try it in a vault, copy `obsidian-plugin/main.js`, `obsidian-plugin/styles.css` and `manifest.json` (from the repo root) into `<vault>/.obsidian/plugins/spicy-side-quests/`, then enable the plugin.
