#!/usr/bin/env node
// WoW Todo Sync companion — keeps a markdown todo file and the in-game addon in sync.
// Usage: node src/index.ts [--once] [--setup] [--dry-run] [--force] [--config <file>]
import fs from "node:fs";
import path from "node:path";
import { defaultConfigDir, isAddonInstalled, loadConfig, runSetup, type Config } from "./config.ts";
import { findSavedVariables, readState, syncOnce, type State } from "./sync.ts";

const VERSION = "0.1.0";
const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const opt = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

if (flag("--help") || flag("-h")) {
  console.log(`WoW Todo Sync companion v${VERSION}

  --once      sync one time and exit
  --setup     (re)configure the markdown file and WoW folder
  --dry-run   show what would change without writing files
  --force     allow a sync that would delete every todo
  --config    path to config.json (default: ${path.join(defaultConfigDir(), "config.json")})`);
  process.exit(0);
}

const tty = process.stdout.isTTY;
const color = (code: string, s: string) => (tty ? `\x1b[${code}m${s}\x1b[0m` : s);
const stamp = () => new Date().toTimeString().slice(0, 8);
const log = (msg: string) => console.log(`${color("90", stamp())} ${msg}`);
const warn = (msg: string) => console.log(`${color("90", stamp())} ${color("33", msg)}`);

const configFile = opt("--config") ?? path.join(defaultConfigDir(), "config.json");
const stateFile = path.join(path.dirname(configFile), "state.json");

let cfg: Config | undefined = loadConfig(configFile);
if (!cfg || flag("--setup") || !cfg.todoFile || !cfg.wowPath) {
  cfg = await runSetup(configFile, cfg);
}
const config = cfg;

console.log(color("1", `WoW Todo Sync v${VERSION}`) + (flag("--dry-run") ? color("33", "  (dry run)") : ""));
console.log(`  markdown: ${config.todoFile}`);
console.log(`  game:     ${config.wowPath}`);
if (!isAddonInstalled(config.wowPath)) warn("The addon isn't installed in that WoW folder yet.");
const sv = findSavedVariables(config);
console.log(`  saved:    ${sv ?? "(not found yet — log in once with the addon enabled)"}\n`);

let state: State = readState(stateFile);
const opts = { dryRun: flag("--dry-run"), force: flag("--force"), log, warn };

function pass() {
  const next = syncOnce(config, state, opts);
  if (next) {
    state = next;
    if (!opts.dryRun) fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
  }
}

// Change detection by polling mtime/size: simple and works the same everywhere.
function signature(): string {
  const files = [config.todoFile, findSavedVariables(config)];
  return files
    .map((f) => {
      try {
        const s = fs.statSync(f ?? "");
        return `${s.mtimeMs}:${s.size}`;
      } catch {
        return "-";
      }
    })
    .join("|");
}

let lastSig = "";
let lastError = "";
function tick() {
  const sig = signature();
  if (sig === lastSig) return;
  try {
    pass();
    lastSig = signature(); // include our own writes
    lastError = "";
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg !== lastError) warn(`Sync failed (will retry): ${msg}`);
    lastError = msg;
    lastSig = sig;
  }
}

if (flag("--once")) {
  pass();
  log("Done.");
} else {
  tick();
  log(`Watching for changes every ${config.pollSeconds}s. Press Ctrl+C to stop.`);
  setInterval(tick, config.pollSeconds * 1000);
}
