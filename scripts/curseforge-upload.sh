#!/usr/bin/env bash
# Uploads the addon zip to CurseForge. Used by the release workflow.
# Usage: scripts/curseforge-upload.sh <zip> <version> <notes.md>
# Env:   CF_API_KEY        CurseForge API token (GitHub secret)
#        CF_PROJECT_ID     CurseForge project id
#        CF_GAME_VERSIONS  optional comma-separated game version ids, to override auto-detection
set -euo pipefail
zip="$1"; version="$2"; notes="$3"
api="${CF_API_URL:-https://wow.curseforge.com/api}" # override only for testing
auth=(-H "X-Api-Token: ${CF_API_KEY}")

if [ -n "${CF_GAME_VERSIONS:-}" ]; then
  ids=$(jq -cn --arg v "$CF_GAME_VERSIONS" '$v | split(",") | map(tonumber)')
else
  # Find CurseForge's "WoW Forever" game-version type, then use its newest version.
  types=$(curl -fsS "${auth[@]}" "$api/game/version-types")
  type_id=$(jq -r '[.[] | select((.name + " " + .slug) | test("forever"; "i"))][0].id // empty' <<<"$types")
  if [ -z "$type_id" ]; then
    echo "::error::No WoW Forever game-version type found on CurseForge. Available types:"
    jq -r '.[] | "  \(.id)  \(.name) (\(.slug))"' <<<"$types"
    echo "Set the repo variable CF_GAME_VERSIONS to the right version id(s) and re-run."
    exit 1
  fi
  versions=$(curl -fsS "${auth[@]}" "$api/game/versions")
  ids=$(jq -c --argjson t "$type_id" '[.[] | select(.gameVersionTypeID == $t)] | sort_by(.id) | last | [.id]' <<<"$versions")
  echo "Using WoW Forever game version: $(jq -c --argjson t "$type_id" '[.[] | select(.gameVersionTypeID == $t)] | sort_by(.id) | last | {id, name}' <<<"$versions")"
fi

metadata=$(jq -cn \
  --arg name "Spicy Side Quests v$version" \
  --rawfile changelog "$notes" \
  --argjson gameVersions "$ids" \
  '{displayName: $name, changelog: $changelog, changelogType: "markdown", gameVersions: $gameVersions, releaseType: "release"}')

curl -fsS "${auth[@]}" \
  --form-string "metadata=$metadata" \
  -F "file=@$zip" \
  "$api/projects/${CF_PROJECT_ID}/upload-file"
echo
echo "Uploaded $zip to CurseForge project $CF_PROJECT_ID"
