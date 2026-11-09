#!/usr/bin/env sh
# Checks every version string matches. Usage: scripts/check-version.sh 0.1.0
set -eu
want="$1"
fail=0
check() { # file, extracted value
  if [ "$2" != "$want" ]; then echo "✗ $1 has '$2', expected '$want'"; fail=1; else echo "✓ $1"; fi
}
check SpicySideQuests/SpicySideQuests.toc "$(sed -n 's/^## Version: *//p' SpicySideQuests/SpicySideQuests.toc | tr -d '\r')"
check SpicySideQuests/Core.lua "$(sed -n 's/^ns.VERSION = "\(.*\)"/\1/p' SpicySideQuests/Core.lua)"
check companion/src/index.ts "$(sed -n 's/^const VERSION = "\(.*\)";/\1/p' companion/src/index.ts)"
check companion/package.json "$(sed -n 's/^  "version": "\(.*\)",/\1/p' companion/package.json)"
check companion/powershell/SpicySideQuests.ps1 "$(sed -n "s/^\$script:VERSION = '\(.*\)'/\1/p" companion/powershell/SpicySideQuests.ps1)"
grep -q "^## v$want\$" CHANGELOG.md && echo "✓ CHANGELOG.md" || { echo "✗ CHANGELOG.md has no '## v$want' section"; fail=1; }
exit $fail
