#!/usr/bin/env sh
# (Re)configure the markdown file, WoW folder and account, then start syncing. Needs Node.js 22.18+.
cd "$(dirname "$0")" && exec node src/index.ts --setup "$@"
