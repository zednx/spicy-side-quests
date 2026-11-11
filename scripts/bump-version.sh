#!/usr/bin/env bash
# Bumps a version everywhere it appears and starts a CHANGELOG entry.
#
#   scripts/bump-version.sh addon  patch|minor|major   # WoW addon + companion scripts + desktop app (tags: vX.Y.Z)
#   scripts/bump-version.sh plugin patch|minor|major   # Obsidian plugin (tags: X.Y.Z)
#
# patch = bug fixes and small tweaks, minor = new features, major = breaking changes.
set -euo pipefail
cd "$(dirname "$0")/.."
what="${1:-}"; part="${2:-}"

bump() { # version part
  IFS=. read -r a b c <<<"$1"
  case "$2" in
    patch) echo "$a.$b.$((c + 1))" ;;
    minor) echo "$a.$((b + 1)).0" ;;
    major) echo "$((a + 1)).0.0" ;;
    *) echo "Unknown part '$2' (use patch, minor or major)" >&2; exit 1 ;;
  esac
}

# Adds "## <heading>" with a placeholder line right under "# Changelog".
changelog() {
  python3 - "$1" <<'PY'
import sys
heading = sys.argv[1]
p = "CHANGELOG.md"
s = open(p, encoding="utf-8").read()
if f"## {heading}\n" in s:
    sys.exit(f"CHANGELOG.md already has '## {heading}'")
s = s.replace("# Changelog\n", f"# Changelog\n\n## {heading}\n\n- TODO: describe the changes\n", 1)
open(p, "w", encoding="utf-8").write(s)
PY
}

case "$what" in
  addon)
    old=$(sed -n 's/^## Version: *//p' SpicySideQuests/SpicySideQuests.toc | tr -d '\r')
    new=$(bump "$old" "$part")
    sed -i "s/^## Version: .*/## Version: $new/" SpicySideQuests/SpicySideQuests.toc
    sed -i "s/^ns.VERSION = \".*\"/ns.VERSION = \"$new\"/" SpicySideQuests/Core.lua
    sed -i "s/^const VERSION = \".*\";/const VERSION = \"$new\";/" companion/src/index.ts
    sed -i "s/^  \"version\": \".*\",/  \"version\": \"$new\",/" companion/package.json
    sed -i "s/^\$script:VERSION = '.*'/\$script:VERSION = '$new'/" companion/powershell/SpicySideQuests.ps1
    # Desktop app
    sed -i "s/^  \"version\": \".*\",/  \"version\": \"$new\",/" desktop/package.json desktop/src-tauri/tauri.conf.json
    sed -i "s/^const VERSION = \".*\";/const VERSION = \"$new\";/" desktop/src/main.ts
    sed -i "0,/^version = \".*\"/s//version = \"$new\"/" desktop/src-tauri/Cargo.toml
    sed -i "/^name = \"spicy-side-quests\"$/{n;s/^version = .*/version = \"$new\"/}" desktop/src-tauri/Cargo.lock
    changelog "v$new"
    scripts/check-version.sh "$new"
    echo "Addon $old -> $new. Fill in CHANGELOG.md, commit, then: git tag v$new && git push origin v$new"
    ;;
  plugin)
    old=$(node -p "require('./manifest.json').version")
    new=$(bump "$old" "$part")
    node -e "
      const fs = require('fs');
      const m = JSON.parse(fs.readFileSync('manifest.json', 'utf8'));
      m.version = '$new';
      fs.writeFileSync('manifest.json', JSON.stringify(m, null, 2) + '\n');
      const v = JSON.parse(fs.readFileSync('versions.json', 'utf8'));
      v['$new'] = m.minAppVersion;
      fs.writeFileSync('versions.json', JSON.stringify(v, null, 2) + '\n');
      const p = JSON.parse(fs.readFileSync('obsidian-plugin/package.json', 'utf8'));
      p.version = '$new';
      fs.writeFileSync('obsidian-plugin/package.json', JSON.stringify(p, null, 2) + '\n');
    "
    changelog "Obsidian plugin $new"
    echo "Plugin $old -> $new. Fill in CHANGELOG.md, commit, then: git tag $new && git push origin $new"
    ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
