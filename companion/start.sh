#!/usr/bin/env sh
# Start syncing. Needs Node.js 22.18 or newer.
cd "$(dirname "$0")" && exec node src/index.ts "$@"
