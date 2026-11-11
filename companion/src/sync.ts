// Node file access for the sync engine (used by the Node CLI and the Obsidian plugin).
// The sync logic itself lives in engine.ts and is shared with the desktop app.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import {
  ADDON,
  fileTodoIOWith,
  parseGame,
  stateFromJSON,
  syncOnceWith,
  type Config,
  type Fsys,
  type GameData,
  type State,
  type SyncOptions,
  type TodoIO,
} from "./engine.ts";
import { dict } from "./types.ts";

export { NEW_FILE, renderInbox, stateFromJSON, type State, type SyncOptions, type TodoIO } from "./engine.ts";

function writeAtomic(file: string, content: string) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  // Random, exclusive temp name: never follows a pre-existing file or symlink.
  const tmp = `${file}.${crypto.randomBytes(6).toString("hex")}.tmp`;
  fs.writeFileSync(tmp, content, { flag: "wx" });
  try {
    fs.renameSync(tmp, file);
  } catch {
    fs.writeFileSync(file, content); // e.g. file locked on Windows
    fs.rmSync(tmp, { force: true });
  }
}

/** The engine's file access, backed by Node's fs. */
export const nodeFs: Fsys = {
  async readText(p) {
    try {
      return fs.readFileSync(p, "utf8");
    } catch {
      return undefined;
    }
  },
  async writeText(p, text) {
    writeAtomic(p, text);
  },
  async info(p) {
    try {
      const st = fs.statSync(p);
      return { mtimeMs: st.mtimeMs, size: st.size, isDir: st.isDirectory() };
    } catch {
      return undefined;
    }
  },
  async listDir(p) {
    try {
      return fs.readdirSync(p);
    } catch {
      return [];
    }
  },
  join: (...parts) => path.join(...parts),
  dirname: (p) => path.dirname(p),
};

export function fileTodoIO(file: string): TodoIO {
  return fileTodoIOWith(nodeFs, file);
}

export function readState(file: string): State {
  try {
    return stateFromJSON(JSON.parse(fs.readFileSync(file, "utf8")));
  } catch {
    return { base: dict() };
  }
}

/** Finds WTF/Account/<name>/SavedVariables/SpicySideQuests.lua. Synchronous, for cheap change polling. */
export function findSavedVariables(cfg: Config): string | undefined {
  const accRoot = path.join(cfg.wowPath, "WTF", "Account");
  const file = (acc: string) => path.join(accRoot, acc, "SavedVariables", `${ADDON}.lua`);
  if (cfg.account && cfg.account !== "auto") return file(cfg.account);
  if (!fs.existsSync(accRoot)) return undefined;
  const found = fs
    .readdirSync(accRoot)
    .map(file)
    .filter((f) => fs.existsSync(f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return found[0];
}

export function readGame(svFile: string | undefined): GameData {
  return parseGame(svFile && fs.existsSync(svFile) ? fs.readFileSync(svFile, "utf8") : undefined);
}

/** Runs one sync pass against the local disk. */
export function syncOnce(cfg: Config, state: State, opts: SyncOptions): Promise<State | undefined> {
  return syncOnceWith(nodeFs, cfg, state, opts);
}
