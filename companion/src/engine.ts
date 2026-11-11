// The sync engine, independent of where it runs. It only touches files through an
// `Fsys`: Node's fs for the scripts and the Obsidian plugin, Rust commands for the
// desktop app. No Node imports here, so it also bundles for a browser/WebView.
import { parseAssignments, toLua, type LuaValue } from "./lua.ts";
import { cleanCategory, mdItems, parseMarkdown, renderMarkdown } from "./markdown.ts";
import { merge } from "./merge.ts";
import { DEFAULT_CATEGORY, dict, isValidId, now, oneLine, own, type Item } from "./types.ts";

export const ADDON = "SpicySideQuests";

export interface Config {
  /** Markdown file to sync, e.g. an Obsidian note. */
  todoFile: string;
  /** The WoW Forever client folder, e.g. C:/Program Files (x86)/World of Warcraft/_forever_ */
  wowPath: string;
  /** Folder name under WTF/Account, or "auto" to pick the one that has the addon's data. */
  account: string;
  /** How often to check the files for changes. */
  pollSeconds: number;
}

export interface FileInfo {
  mtimeMs: number;
  size: number;
  isDir: boolean;
}

/** The file operations the engine needs. */
export interface Fsys {
  /** File contents, or undefined if it doesn't exist. */
  readText(path: string): Promise<string | undefined>;
  /** Writes via a temp file + rename, creating parent folders. */
  writeText(path: string, text: string): Promise<void>;
  info(path: string): Promise<FileInfo | undefined>;
  /** Entry names in a folder ([] if it doesn't exist). */
  listDir(path: string): Promise<string[]>;
  join(...parts: string[]): string;
  dirname(path: string): string;
}

export interface State {
  base: Record<string, Item>;
}

/** Where the markdown file lives. The scripts use the disk; the Obsidian plugin uses the vault API. */
export interface TodoIO {
  /** Current text and modified time (unix seconds), or undefined if the file doesn't exist. */
  read(): Promise<{ text: string; mtime: number } | undefined>;
  /** Writes `text`. `expected` is what read() returned; an editor-backed implementation should
   *  throw if the file changed since, so a sync never overwrites edits made in the meantime. */
  write(text: string, expected?: string): Promise<void>;
  /** Shown in messages, e.g. the file path. */
  name: string;
}

export interface SyncOptions {
  dryRun?: boolean;
  force?: boolean;
  log: (msg: string) => void;
  warn: (msg: string) => void;
  /** Defaults to the file at cfg.todoFile. */
  todo?: TodoIO;
}

export const NEW_FILE = `---
tags: [wow, todo]
---

# WoW Todo

Synced with the Spicy Side Quests addon. Use \`## Headings\` for categories.

## ${DEFAULT_CATEGORY}
`;

export function fileTodoIOWith(fs: Fsys, file: string): TodoIO {
  return {
    name: file,
    async read() {
      const text = await fs.readText(file);
      if (text === undefined) return undefined;
      const info = await fs.info(file);
      return { text, mtime: Math.floor((info?.mtimeMs ?? Date.now()) / 1000) };
    },
    async write(text) {
      await fs.writeText(file, text);
    },
  };
}

/** Validates sync state loaded from JSON (a state file, or the Obsidian plugin's data). */
export function stateFromJSON(s: { base?: unknown } | null | undefined): State {
  try {
    if (!s || typeof s !== "object") return { base: dict() };
    const base = dict<Item>();
    for (const [id, raw] of Object.entries((s.base ?? {}) as Record<string, Record<string, unknown>>)) {
      if (!isValidId(id) || !raw || typeof raw !== "object" || typeof raw.text !== "string") continue;
      // tolerate nulls (e.g. a state file written by the PowerShell edition)
      for (const k of Object.keys(raw)) if (raw[k] === null) delete raw[k];
      if (!Array.isArray(raw.tags)) raw.tags = [];
      base[id] = { ...(raw as unknown as Item), id };
    }
    return { base };
  } catch {
    return { base: dict() };
  }
}

// --- WoW folder ------------------------------------------------------------------
export const addonDirWith = (fs: Fsys, wowPath: string) => fs.join(wowPath, "Interface", "AddOns", ADDON);

export async function isAddonInstalledWith(fs: Fsys, wowPath: string): Promise<boolean> {
  if (!wowPath) return false;
  return !!(await fs.info(fs.join(addonDirWith(fs, wowPath), `${ADDON}.toc`)));
}

/** Account folders under WTF/Account (each has a SavedVariables folder). */
export async function listAccountsWith(fs: Fsys, wowPath: string): Promise<string[]> {
  if (!wowPath) return [];
  const root = fs.join(wowPath, "WTF", "Account");
  const out: string[] = [];
  for (const name of await fs.listDir(root)) {
    if ((await fs.info(fs.join(root, name)))?.isDir && (await fs.info(fs.join(root, name, "SavedVariables")))?.isDir) out.push(name);
  }
  return out.sort();
}

/** Where WoW Forever is usually installed. `home` is the user's home folder. */
export function wowPathCandidates(platform: string, home: string, join: (...p: string[]) => string): string[] {
  const roots: string[] = [];
  if (platform === "win32" || platform === "windows") {
    for (const drive of ["C:", "D:", "E:"]) {
      roots.push(`${drive}\\Program Files (x86)\\World of Warcraft`, `${drive}\\Program Files\\World of Warcraft`, `${drive}\\World of Warcraft`, `${drive}\\Games\\World of Warcraft`);
    }
  } else {
    for (const prefix of [join(home, "Games", "battlenet"), join(home, "Games", "battle-net"), join(home, ".wine")]) {
      roots.push(join(prefix, "drive_c", "Program Files (x86)", "World of Warcraft"));
    }
  }
  const flavours = ["_forever_", "_forever_beta_", "_classic_beta_"];
  return roots.flatMap((r) => flavours.map((f) => join(r, f)));
}

/** Install locations that have the addon. */
export async function detectWowPathsWith(fs: Fsys, platform: string, home: string): Promise<string[]> {
  const out: string[] = [];
  for (const p of wowPathCandidates(platform, home, fs.join)) if (await isAddonInstalledWith(fs, p)) out.push(p);
  return out;
}

/** Finds WTF/Account/<name>/SavedVariables/SpicySideQuests.lua (the newest, for "auto"). */
export async function findSavedVariablesWith(fs: Fsys, cfg: Config): Promise<string | undefined> {
  const accRoot = fs.join(cfg.wowPath, "WTF", "Account");
  const file = (acc: string) => fs.join(accRoot, acc, "SavedVariables", `${ADDON}.lua`);
  if (cfg.account && cfg.account !== "auto") return file(cfg.account);
  let best: { path: string; mtime: number } | undefined;
  for (const acc of await fs.listDir(accRoot)) {
    const info = await fs.info(file(acc));
    if (info && !info.isDir && (!best || info.mtimeMs > best.mtime)) best = { path: file(acc), mtime: info.mtimeMs };
  }
  return best?.path;
}

// --- Game data ---------------------------------------------------------------------
export interface GameData {
  items: Record<string, Item>;
  order: string[];
  categories: string[];
}

const str = (v: LuaValue | undefined) => (typeof v === "string" ? v : undefined);
const num = (v: LuaValue | undefined) => (typeof v === "number" ? v : undefined);

/** Parses the addon's SavedVariables file contents. */
export function parseGame(text: string | undefined): GameData {
  const empty: GameData = { items: dict(), order: [], categories: [] };
  if (text === undefined) return empty;
  const db = parseAssignments(text).SpicySideQuestsDB;
  if (!db || typeof db !== "object" || Array.isArray(db)) return empty;

  const items = dict<Item>();
  const rawItems = db.items;
  if (rawItems && typeof rawItems === "object") {
    for (const v of Object.values(rawItems)) {
      if (!v || typeof v !== "object" || Array.isArray(v)) continue;
      const id = str(v.id), itemText = str(v.text);
      if (!isValidId(id) || itemText === undefined || own(items, id)) continue;
      items[id] = {
        id,
        text: oneLine(itemText),
        tags: Array.isArray(v.tags) ? v.tags.filter((t): t is string => typeof t === "string") : [],
        category: cleanCategory(str(v.category) ?? ""),
        done: v.done === true,
        deleted: v.deleted === true || undefined,
        zone: str(v.zone),
        mapID: num(v.mapID),
        x: num(v.x),
        y: num(v.y),
        created: num(v.created) ?? 0,
        updated: num(v.updated) ?? 0,
      };
    }
  }
  const list = (v: LuaValue | undefined) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
  return { items, order: list(db.order), categories: list(db.categories) };
}

export function renderInbox(items: Item[], categories: string[], generated: number, hash = ""): string {
  const payload = {
    generated,
    categories,
    items: items.map((i) => ({ ...i, deleted: i.deleted || undefined })),
  };
  return (
    "-- Written by the Spicy Side Quests companion app. Changes here are overwritten.\n" +
    "-- Without the companion app this file stays empty and the addon works in-game only.\n" +
    `-- hash: ${hash}\n` +
    `SpicySideQuests_Inbox = ${toLua(payload)}\n`
  );
}

// --- Helpers that work in Node and in a WebView ------------------------------------------
async function sha1(s: string): Promise<string> {
  const bytes = new Uint8Array(await globalThis.crypto.subtle.digest("SHA-1", new TextEncoder().encode(s)));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function newId(taken: Set<string>): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  for (;;) {
    const rnd = globalThis.crypto.getRandomValues(new Uint8Array(6));
    const id = Array.from(rnd, (b) => chars[b % chars.length]).join("");
    if (!taken.has(id)) return id;
  }
}

// --- One sync pass -------------------------------------------------------------------
/** Runs one sync pass. Returns the new state, or undefined if nothing could be synced. */
export async function syncOnceWith(fs: Fsys, cfg: Config, state: State, opts: SyncOptions): Promise<State | undefined> {
  const liveBase = Object.values(state.base).filter((i) => !i.deleted).length;
  const todo = opts.todo ?? fileTodoIOWith(fs, cfg.todoFile);

  // Markdown
  let mdSrc: string;
  let mdTime: number;
  const existing = await todo.read();
  if (existing) {
    mdSrc = existing.text;
    mdTime = existing.mtime;
  } else if (liveBase === 0) {
    mdSrc = NEW_FILE;
    mdTime = now();
    opts.log(`Creating ${todo.name}`);
  } else {
    opts.warn(`Markdown file not found: ${todo.name} — skipping so nothing gets deleted.`);
    return undefined;
  }
  const doc = parseMarkdown(mdSrc);
  const md = mdItems(doc);
  if (md.length === 0 && liveBase > 0 && !opts.force) {
    opts.warn(`The markdown file has no todos but ${liveBase} were synced before. Skipping so nothing gets deleted (use --force to accept).`);
    return undefined;
  }

  // Game
  const svFile = await findSavedVariablesWith(fs, cfg);
  const game = parseGame(svFile ? await fs.readText(svFile) : undefined);

  // Merge
  const result = merge({ base: state.base, md, mdTime, game: game.items, gameOrder: game.order, newId });
  for (const line of result.log) opts.log(line);

  // Write markdown
  const newMd = renderMarkdown(doc, result.items);
  if (newMd !== mdSrc || !existing) {
    if (!opts.dryRun) await todo.write(newMd, existing?.text);
  }

  // Write Inbox.lua (only when the content changed)
  const categories: string[] = [];
  const addCat = (c: string) => {
    if (!categories.some((x) => x.toLowerCase() === c.toLowerCase())) categories.push(c);
  };
  doc.lines.forEach((l) => l.kind === "heading" && result.items.some((i) => i.category.toLowerCase() === l.category.toLowerCase()) && addCat(l.category));
  game.categories.forEach(addCat);
  result.items.forEach((i) => addCat(i.category));

  // Compared against the file itself, so an addon update that resets Inbox.lua gets rewritten.
  const inboxHash = await sha1(JSON.stringify([categories, result.items]));
  const inboxFile = fs.join(addonDirWith(fs, cfg.wowPath), "Inbox.lua");
  const current = (await fs.readText(inboxFile)) ?? "";
  if (!current.includes(`-- hash: ${inboxHash}\n`)) {
    if (!opts.dryRun) await fs.writeText(inboxFile, renderInbox(result.items, categories, now(), inboxHash));
    if (result.log.some((l) => l.startsWith("markdown"))) opts.log("Type /reload in game to see markdown changes.");
  }

  const base = dict<Item>();
  for (const i of result.items) base[i.id] = i;
  return { base };
}
