#!/usr/bin/env node
// Spicy Side Quests companion — keeps a markdown todo file and the in-game addon in sync.
// Usage: node src/index.ts [--once] [--setup] [--dry-run] [--force] [--config <file>]
import fs from "node:fs";
import path from "node:path";
import { createPrompter } from "./prompt.ts";
import { configProblems, defaultConfigDir, isAddonInstalled, loadConfig, migrateOldConfigDir, type Config } from "./config.ts";
import { runSetup } from "./setup.ts";
import { findSavedVariables, readState, syncOnce, type State } from "./sync.ts";
import { terminalSafe } from "./types.ts";

const VERSION = "0.2.0";
const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const opt = (name: string) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

if (flag("--help") || flag("-h")) {
  console.log(`Spicy Side Quests companion v${VERSION}

  --once      sync one time and exit
  --setup     change the markdown file, WoW folder or account
  --dry-run   show what would change without writing files
  --force     allow a sync that would delete every todo
  --config    path to config.json (default: ${path.join(defaultConfigDir(), "config.json")})`);
  process.exit(0);
}

const tty = process.stdout.isTTY;
const color = (code: string, s: string) => (tty ? `\x1b[${code}m${s}\x1b[0m` : s);
const stamp = () => new Date().toTimeString().slice(0, 8);
// Messages can contain todo text, so strip terminal escape sequences before printing.
const log = (msg: string) => console.log(`${color("90", stamp())} ${terminalSafe(msg)}`);
const warn = (msg: string) => console.log(`${color("90", stamp())} ${color("33", terminalSafe(msg))}`);

if (!opt("--config") && migrateOldConfigDir(defaultConfigDir())) {
  log(`Copied your settings from the old WoW Todo Sync folder to ${defaultConfigDir()}`);
}
const configFile = opt("--config") ?? path.join(defaultConfigDir(), "config.json");
const stateFile = path.join(path.dirname(configFile), "state.json");

let cfg: Config | undefined = loadConfig(configFile);
const previousTodoFile = cfg?.todoFile;
if (!cfg || flag("--setup") || !cfg.todoFile || !cfg.wowPath) {
  cfg = await runSetup(configFile, cfg);
} else {
  // Paths can go stale (moved vault, reinstalled WoW): say so and offer to fix them.
  const problems = configProblems(cfg);
  if (problems.length) {
    for (const p of problems) warn(p);
    if (process.stdin.isTTY && !flag("--once")) {
      const p = createPrompter();
      const a = (await p.ask("Run setup to fix this now? (Y/n)", "y")).toLowerCase();
      p.close();
      if (!a.startsWith("n")) cfg = await runSetup(configFile, cfg);
    } else {
      warn("Run setup (setup-powershell.cmd, setup.cmd/setup.sh, or --setup) to fix it.");
    }
  }
}
const config = cfg;

// A different markdown file has different todos. Forget the old sync history so the
// first sync just merges both sides instead of treating missing todos as deleted.
if (previousTodoFile && path.resolve(previousTodoFile) !== path.resolve(config.todoFile) && fs.existsSync(stateFile)) {
  if (!flag("--dry-run")) fs.rmSync(stateFile);
  log("Markdown file changed: the next sync merges both sides and deletes nothing.");
}

console.log(color("1", `Spicy Side Quests v${VERSION}`) + (flag("--dry-run") ? color("33", "  (dry run)") : ""));
console.log(`  markdown: ${config.todoFile}`);
console.log(`  game:     ${config.wowPath}`);
if (!isAddonInstalled(config.wowPath)) warn("The addon isn't installed in that WoW folder yet.");
const sv = findSavedVariables(config);
console.log(`  saved:    ${sv ?? "(not found yet — log in once with the addon enabled)"}\n`);

let state: State = readState(stateFile);
const opts = { dryRun: flag("--dry-run"), force: flag("--force"), log, warn };

async function pass() {
  const next = await syncOnce(config, state, opts);
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
let busy = false;
async function tick() {
  if (busy) return; // a slow pass never overlaps the next tick
  const sig = signature();
  if (sig === lastSig) return;
  busy = true;
  try {
    await pass();
    lastSig = signature(); // include our own writes
    lastError = "";
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg !== lastError) warn(`Sync failed (will retry): ${msg}`);
    lastError = msg;
    lastSig = sig;
  } finally {
    busy = false;
  }
}

if (flag("--once")) {
  await pass();
  log("Done.");
} else {
  await tick();
  log(`Watching for changes every ${config.pollSeconds}s. Press Ctrl+C to stop.`);
  setInterval(tick, config.pollSeconds * 1000);
}
