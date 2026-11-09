// One sync pass: read markdown + SavedVariables, merge, write markdown + Inbox.lua.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { ADDON, addonDir, type Config } from "./config.ts";
import { parseAssignments, toLua, type LuaValue } from "./lua.ts";
import { mdItems, parseMarkdown, renderMarkdown } from "./markdown.ts";
import { merge } from "./merge.ts";
import { DEFAULT_CATEGORY, now, type Item } from "./types.ts";

export interface State {
  base: Record<string, Item>;
}

export interface SyncOptions {
  dryRun?: boolean;
  force?: boolean;
  log: (msg: string) => void;
  warn: (msg: string) => void;
}

const NEW_FILE = `---
tags: [wow, todo]
---

# WoW Todo

Synced with the WoW Todo Sync addon. Use \`## Headings\` for categories.

## ${DEFAULT_CATEGORY}
`;

const sha = (s: string) => crypto.createHash("sha1").update(s).digest("hex");

export function readState(file: string): State {
  try {
    const s = JSON.parse(fs.readFileSync(file, "utf8"));
    const base: Record<string, Item> = s.base ?? {};
    // tolerate nulls (e.g. a state file written by another tool)
    for (const item of Object.values(base) as unknown as Record<string, unknown>[]) {
      for (const k of Object.keys(item)) if (item[k] === null) delete item[k];
      if (!Array.isArray(item.tags)) item.tags = [];
    }
    return { base };
  } catch {
    return { base: {} };
  }
}

function writeAtomic(file: string, content: string) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + ".tmp";
  fs.writeFileSync(tmp, content);
  try {
    fs.renameSync(tmp, file);
  } catch {
    fs.writeFileSync(file, content); // e.g. file locked on Windows
    fs.rmSync(tmp, { force: true });
  }
}

/** Finds WTF/Account/<name>/SavedVariables/WoWTodoSync.lua. */
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

const str = (v: LuaValue | undefined) => (typeof v === "string" ? v : undefined);
const num = (v: LuaValue | undefined) => (typeof v === "number" ? v : undefined);

export function readGame(svFile: string | undefined): { items: Record<string, Item>; order: string[]; categories: string[] } {
  const empty = { items: {}, order: [], categories: [] };
  if (!svFile || !fs.existsSync(svFile)) return empty;
  const db = parseAssignments(fs.readFileSync(svFile, "utf8")).WoWTodoSyncDB;
  if (!db || typeof db !== "object" || Array.isArray(db)) return empty;

  const items: Record<string, Item> = {};
  const rawItems = db.items;
  if (rawItems && typeof rawItems === "object") {
    for (const v of Object.values(rawItems)) {
      if (!v || typeof v !== "object" || Array.isArray(v)) continue;
      const id = str(v.id), text = str(v.text);
      if (!id || text === undefined) continue;
      items[id] = {
        id,
        text,
        tags: Array.isArray(v.tags) ? v.tags.filter((t): t is string => typeof t === "string") : [],
        category: str(v.category) || DEFAULT_CATEGORY,
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
    "-- Written by the WoW Todo Sync companion app. Changes here are overwritten.\n" +
    "-- Without the companion app this file stays empty and the addon works in-game only.\n" +
    `-- hash: ${hash}\n` +
    `WoWTodoSync_Inbox = ${toLua(payload)}\n`
  );
}

function newId(taken: Set<string>): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  for (;;) {
    let id = "";
    for (let i = 0; i < 6; i++) id += chars[crypto.randomInt(chars.length)];
    if (!taken.has(id)) return id;
  }
}

/** Runs one sync pass. Returns the new state, or undefined if nothing could be synced. */
export function syncOnce(cfg: Config, state: State, opts: SyncOptions): State | undefined {
  const liveBase = Object.values(state.base).filter((i) => !i.deleted).length;

  // Markdown
  let mdSrc: string;
  let mdTime: number;
  if (fs.existsSync(cfg.todoFile)) {
    mdSrc = fs.readFileSync(cfg.todoFile, "utf8");
    mdTime = Math.floor(fs.statSync(cfg.todoFile).mtimeMs / 1000);
  } else if (liveBase === 0) {
    mdSrc = NEW_FILE;
    mdTime = now();
    opts.log(`Creating ${cfg.todoFile}`);
  } else {
    opts.warn(`Markdown file not found: ${cfg.todoFile} — skipping so nothing gets deleted.`);
    return undefined;
  }
  const doc = parseMarkdown(mdSrc);
  const md = mdItems(doc);
  if (md.length === 0 && liveBase > 0 && !opts.force) {
    opts.warn(`The markdown file has no todos but ${liveBase} were synced before. Skipping so nothing gets deleted (use --force to accept).`);
    return undefined;
  }

  // Game
  const svFile = findSavedVariables(cfg);
  const game = readGame(svFile);

  // Merge
  const result = merge({ base: state.base, md, mdTime, game: game.items, gameOrder: game.order, newId });
  for (const line of result.log) opts.log(line);

  // Write markdown
  const newMd = renderMarkdown(doc, result.items);
  if (newMd !== mdSrc || !fs.existsSync(cfg.todoFile)) {
    if (!opts.dryRun) writeAtomic(cfg.todoFile, newMd);
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
  const inboxHash = sha(JSON.stringify([categories, result.items]));
  const inboxFile = path.join(addonDir(cfg.wowPath), "Inbox.lua");
  let current = "";
  try {
    current = fs.readFileSync(inboxFile, "utf8");
  } catch {}
  if (!current.includes(`-- hash: ${inboxHash}\n`)) {
    if (!opts.dryRun) writeAtomic(inboxFile, renderInbox(result.items, categories, now(), inboxHash));
    if (result.log.some((l) => l.startsWith("markdown"))) opts.log("Type /reload in game to see markdown changes.");
  }

  const base: Record<string, Item> = {};
  for (const i of result.items) base[i.id] = i;
  return { base };
}
