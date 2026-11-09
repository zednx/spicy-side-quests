#!/usr/bin/env bash
# Release gate: the version must be higher than every earlier release of the same kind,
# and its CHANGELOG section must be filled in. Used by both release workflows.
#   scripts/check-release.sh addon  0.2.0   # compares against v* tags
#   scripts/check-release.sh plugin 0.1.1   # compares against bare X.Y.Z tags
set -euo pipefail
kind="$1"; v="$2"
if [ "$kind" = addon ]; then tags=$(git tag -l 'v[0-9]*' | sed 's/^v//'); heading="## v$v"
else tags=$(git tag -l '[0-9]*.[0-9]*.[0-9]*'); heading="## Obsidian plugin $v"; fi

# Highest earlier version (re-pushing the same tag is allowed, e.g. to rebuild a release).
prev=$(printf '%s\n' $tags | grep -vx "$v" | sort -V | tail -1 || true)
if [ -n "$prev" ] && [ "$(printf '%s\n%s\n' "$prev" "$v" | sort -V | tail -1)" != "$v" ]; then
  echo "::error::Version $v is not higher than the last $kind release ($prev). Bump it with scripts/bump-version.sh $kind patch|minor."
  exit 1
fi

section=$(awk -v h="$heading" '$0==h{f=1;next} /^## /{f=0} f' CHANGELOG.md)
if [ -z "$(echo "$section" | tr -d '[:space:]')" ]; then
  echo "::error::CHANGELOG.md has no '$heading' section."; exit 1
fi
if echo "$section" | grep -q "TODO"; then
  echo "::error::CHANGELOG.md '$heading' still has a TODO placeholder."; exit 1
fi
echo "✓ $kind $v (previous: ${prev:-none})"
