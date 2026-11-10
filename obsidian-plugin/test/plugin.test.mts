import assert from "node:assert/strict";
import fs from "node:fs";
import Module, { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { parseAssignments } from "../../companion/src/lua.ts";
import { ChangedWhileSyncing, vaultTodoIO, type FileLike, type VaultLike } from "../src/vault-io.ts";

// --- A tiny in-memory vault ---------------------------------------------------
class FakeVault implements VaultLike {
  files = new Map<string, { text: string; mtime: number }>();
  folders = new Set<string>();
  beforeProcess?: () => void;
  getFile(p: string): FileLike | null {
    const f = this.files.get(p);
    return f ? { path: p, stat: { mtime: f.mtime } } : null;
  }
  async read(f: FileLike) {
    return this.files.get(f.path)!.text;
  }
  async process(f: FileLike, fn: (d: string) => string) {
    this.beforeProcess?.();
    const cur = this.files.get(f.path)!;
    const next = fn(cur.text);
    this.files.set(f.path, { text: next, mtime: Date.now() });
    return next;
  }
  async create(p: string, d: string) {
    this.files.set(p, { text: d, mtime: Date.now() });
  }
  async createFolder(p: string) {
    this.folders.add(p);
  }
  async exists(p: string) {
    return this.folders.has(p) || this.files.has(p);
  }
}

test("vault IO reads, creates (with folders) and writes", async () => {
  const v = new FakeVault();
  const io = vaultTodoIO(v, "Games/WoW/Todo.md");
  assert.equal(await io.read(), undefined);
  await io.write("hello");
  assert.ok(v.folders.has("Games/WoW"));
  assert.equal((await io.read())!.text, "hello");
  await io.write("world", "hello");
  assert.equal((await io.read())!.text, "world");
});

test("vault IO never overwrites edits made during a sync", async () => {
  const v = new FakeVault();
  v.files.set("T.md", { text: "original", mtime: 1 });
  const io = vaultTodoIO(v, "T.md");
  v.beforeProcess = () => v.files.set("T.md", { text: "you typed this", mtime: 2 });
  await assert.rejects(io.write("merged", "original"), ChangedWhileSyncing);
  assert.equal(v.files.get("T.md")!.text, "you typed this");
});

// --- The built plugin against a minimal fake Obsidian -----------------------------
function fakeObsidian(vault: FakeVault) {
  const el = (): Record<string, unknown> => {
    const e: Record<string, unknown> = { text: "" };
    e.setText = (t: string) => (e.text = t);
    e.addClass = () => {};
    e.setAttr = () => {};
    return e;
  };
  class TFile {
    path: string;
    stat: { mtime: number };
    constructor(p: string, stat: { mtime: number }) {
      this.path = p;
      this.stat = stat;
    }
  }
  const notices: string[] = [];
  const handlers: Record<string, ((...a: unknown[]) => void)[]> = {};
  const app = {
    vault: {
      on: (name: string, fn: (...a: unknown[]) => void) => ((handlers[name] ??= []).push(fn), {}),
      getAbstractFileByPath: (p: string) => {
        const f = vault.getFile(p);
        return f ? new TFile(f.path, f.stat) : null;
      },
      read: (f: FileLike) => vault.read(f),
      process: (f: FileLike, fn: (d: string) => string) => vault.process(f, fn),
      create: (p: string, d: string) => vault.create(p, d),
      createFolder: (p: string) => vault.createFolder(p),
      adapter: { exists: (p: string) => vault.exists(p) },
      getMarkdownFiles: () => [],
    },
    workspace: {
      onLayoutReady: () => {},
      getLeaf: () => ({ openFile: async () => {} }),
      on: (name: string, fn: (...a: unknown[]) => void) => ((handlers["ws:" + name] ??= []).push(fn), {}),
      getActiveFile: () => null,
    },
  };
  let stored: unknown = null;
  class Plugin {
    app = app;
    async loadData() {
      return stored;
    }
    async saveData(d: unknown) {
      stored = JSON.parse(JSON.stringify(d));
    }
    addStatusBarItem() {
      return el();
    }
    addSettingTab() {}
    addCommand() {}
    addRibbonIcon() {}
    registerEvent() {}
    registerDomEvent() {}
    registerInterval(n: number) {
      return n;
    }
  }
  const mod = {
    Plugin,
    PluginSettingTab: class {},
    Setting: class {},
    AbstractInputSuggest: class {},
    TFile,
    Notice: class {
      constructor(m: string) {
        notices.push(m);
      }
    },
    normalizePath: (p: string) => p.replace(/\\/g, "/").replace(/\/+/g, "/"),
  };
  return { mod, app, notices, handlers, getStored: () => stored };
}

// The plugin uses window.setTimeout etc.; Node has them on globalThis.
(globalThis as unknown as { window: typeof globalThis }).window = globalThis;

test("built plugin: syncs the game and a vault note end to end", async () => {
  const main = path.join(import.meta.dirname, "..", "main.js");
  if (!fs.existsSync(main)) return assert.fail("run `npm run build` first");

  // fake WoW folder with one in-game side quest
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ssq-plugin-"));
  const wow = path.join(dir, "_forever_");
  const addon = path.join(wow, "Interface", "AddOns", "SpicySideQuests");
  const sv = path.join(wow, "WTF", "Account", "ME", "SavedVariables");
  fs.mkdirSync(addon, { recursive: true });
  fs.mkdirSync(sv, { recursive: true });
  fs.writeFileSync(path.join(addon, "SpicySideQuests.toc"), "");
  const t = Math.floor(Date.now() / 1000);
  fs.writeFileSync(
    path.join(sv, "SpicySideQuests.lua"),
    `SpicySideQuestsDB = { items = { g1 = { id = "g1", text = "From game", category = "Quests", tags = { "q" }, done = false, created = ${t}, updated = ${t} } } }`,
  );

  // load main.js with "obsidian" resolved to the fake
  const vault = new FakeVault();
  const fake = fakeObsidian(vault);
  // Obsidian loads main.js as CommonJS; a .cjs copy makes Node do the same.
  const cjs = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "ssq-main-")), "main.cjs");
  fs.copyFileSync(main, cjs);
  const req = createRequire(cjs);
  const origLoad = (Module as unknown as { _load: (...a: unknown[]) => unknown })._load;
  (Module as unknown as { _load: (...a: unknown[]) => unknown })._load = function (request: unknown, ...rest: unknown[]) {
    return request === "obsidian" ? fake.mod : origLoad.call(this, request, ...rest);
  };
  let Plugin: new () => {
    onload(): Promise<void>;
    onunload(): void;
    sync(manual: boolean): Promise<void>;
    markEdited(): void;
    flush(): void;
    isTyping(): boolean;
    pending: boolean;
    setTodoFile(p: string): Promise<void>;
    settings: { todoFile: string; wowPath: string };
    save(): Promise<void>;
    problem(): string | undefined;
  };
  try {
    Plugin = req(cjs).default;
  } finally {
    (Module as unknown as { _load: unknown })._load = origLoad;
  }

  const plugin = new Plugin();
  await plugin.onload();
  assert.equal(plugin.problem(), "Choose a note in settings");

  plugin.settings.wowPath = wow;
  await plugin.setTodoFile("Games/Side Quests"); // ".md" is added
  await new Promise((r) => setTimeout(r, 50));
  assert.equal(plugin.settings.todoFile, "Games/Side Quests.md");
  assert.equal(plugin.problem(), undefined);

  // first sync creates the note with the in-game item
  await plugin.sync(true);
  const note = vault.files.get("Games/Side Quests.md")!.text;
  assert.match(note, /## Quests\n- \[ \] From game #q \^g1/);

  // add a side quest in the note -> appears in Inbox.lua; state is persisted in plugin data
  vault.files.set("Games/Side Quests.md", { text: note.replace("## Quests", "## Quests\n- [ ] From Obsidian #o"), mtime: Date.now() + 5000 });
  await plugin.sync(false);
  const inbox = parseAssignments(fs.readFileSync(path.join(addon, "Inbox.lua"), "utf8")).SpicySideQuests_Inbox as { items: { text: string }[] };
  assert.deepEqual(inbox.items.map((i) => i.text).sort(), ["From Obsidian", "From game"]);
  const stored = fake.getStored() as { settings: { todoFile: string }; state: { base: Record<string, unknown> } };
  assert.equal(stored.settings.todoFile, "Games/Side Quests.md");
  assert.equal(Object.keys(stored.state.base).length, 2);
  assert.ok(fake.notices.some((n) => n.includes("markdown → game: added \"From Obsidian\"")), fake.notices.join(" | "));

  // While you're typing, automatic syncs wait: a half-written line gets no ^id and isn't sent.
  const before = vault.files.get("Games/Side Quests.md")!.text;
  const typing = before.replace("## Quests", "## Quests\n- [ ] Half writ");
  vault.files.set("Games/Side Quests.md", { text: typing, mtime: Date.now() + 10000 });
  plugin.markEdited();
  assert.ok(plugin.isTyping());
  await plugin.sync(false); // e.g. the game saved meanwhile
  assert.equal(vault.files.get("Games/Side Quests.md")!.text, typing, "no write while typing");
  assert.ok(plugin.pending);

  // Leaving the note (or switching to WoW) syncs straight away.
  plugin.flush();
  await new Promise((r) => setTimeout(r, 100));
  assert.match(vault.files.get("Games/Side Quests.md")!.text, /- \[ \] Half writ \^\w+/);
  assert.equal(plugin.pending, false);

  // "Sync now" doesn't wait.
  plugin.markEdited();
  vault.files.set("Games/Side Quests.md", { text: vault.files.get("Games/Side Quests.md")!.text.replace("Half writ", "Half written"), mtime: Date.now() + 20000 });
  await plugin.sync(true);
  assert.match(vault.files.get("Games/Side Quests.md")!.text, /Half written \^\w+/);
  plugin.onunload(); // clears the pending timer

  fs.rmSync(dir, { recursive: true, force: true });
});
