import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import type { Config } from "../src/config.ts";
import { parseAssignments, toLua } from "../src/lua.ts";
import { mdItems, parseMarkdown, renderMarkdown } from "../src/markdown.ts";
import { merge } from "../src/merge.ts";
import { readGame, readState, syncOnce, type State } from "../src/sync.ts";
import { now, type Item } from "../src/types.ts";

let n = 0;
const newId = () => `new${++n}`;
const item = (over: Partial<Item>): Item => ({ id: "a", text: "x", tags: [], category: "General", done: false, created: 100, updated: 100, ...over });

// --- Lua -------------------------------------------------------------------
test("parses a WoW SavedVariables file", () => {
  const src = `
WoWTodoSyncDB = {
["items"] = {
["abc123"] = {
["text"] = "Farm \\"Arcanite\\"\\nnow",
["done"] = true,
["x"] = 52.1,
["tags"] = {
"farming", -- [1]
"alchemy", -- [2]
},
},
},
["order"] = {
"abc123", -- [1]
},
["settings"] = { ["collapsed"] = {}, },
}
Other = nil
`;
  const v = parseAssignments(src) as any;
  assert.equal(v.WoWTodoSyncDB.items.abc123.text, 'Farm "Arcanite"\nnow');
  assert.equal(v.WoWTodoSyncDB.items.abc123.done, true);
  assert.deepEqual(v.WoWTodoSyncDB.items.abc123.tags, ["farming", "alchemy"]);
  assert.deepEqual(v.WoWTodoSyncDB.order, ["abc123"]);
  assert.equal(v.Other, null);
});

test("Lua round trip", () => {
  const data = { a: "q\"uo\\te|", list: [1, 2.5, true], nested: { "odd key": "ü" } };
  const back = parseAssignments(`X = ${toLua(data)}`).X;
  assert.deepEqual(back, data);
});

// --- Markdown --------------------------------------------------------------
const SAMPLE = `---
tags: [wow]
---

# WoW Todo

Some notes stay put.

- [ ] Loose item ^loose1

## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Learn Alchemy
  - [ ] indented sub-task is ignored

\`\`\`
- [ ] in a code block is ignored
\`\`\`

## Dungeons
- [-] Cancelled counts as done ^d1
`;

test("parses categories, tags, zones and ids", () => {
  const items = mdItems(parseMarkdown(SAMPLE));
  assert.equal(items.length, 4);
  assert.deepEqual(items[0], { id: "loose1", text: "Loose item", tags: [], category: "General", done: false, zone: undefined, x: undefined, y: undefined });
  assert.equal(items[1].category, "Professions");
  assert.deepEqual(items[1].tags, ["farming"]);
  assert.equal(items[1].zone, "Winterspring");
  assert.equal(items[1].x, 63.2);
  assert.equal(items[2].id, undefined);
  assert.equal(items[2].done, true);
  assert.equal(items[3].done, true);
});

test("render keeps unchanged lines and non-todo content byte for byte", () => {
  const doc = parseMarkdown(SAMPLE);
  const md = mdItems(doc);
  const res = merge({ base: {}, md, mdTime: 500, game: {}, newId });
  const out = renderMarkdown(doc, res.items);
  // only change: Learn Alchemy gets an id
  assert.equal(out, SAMPLE.replace("- [x] Learn Alchemy", `- [x] Learn Alchemy ^${md[2].id}`));
  // second pass is a no-op
  const doc2 = parseMarkdown(out);
  const res2 = merge({ base: Object.fromEntries(res.items.map((i) => [i.id, i])), md: mdItems(doc2), mdTime: 600, game: {}, newId });
  assert.equal(renderMarkdown(doc2, res2.items), out);
  assert.equal(res2.log.length, 0);
});

test("render adds new items to their section and creates new sections", () => {
  const doc = parseMarkdown("# T\n\n## Professions\n- [ ] One ^p1\n\nNotes\n");
  const items = [
    item({ id: "p1", text: "One", category: "Professions" }),
    item({ id: "p2", text: "Two", category: "professions", tags: ["herb"] }),
    item({ id: "r1", text: "Raid", category: "Raids", done: true, zone: "Molten Core" }),
  ];
  assert.equal(
    renderMarkdown(doc, items),
    "# T\n\n## Professions\n- [ ] One ^p1\n- [ ] Two #herb ^p2\n\nNotes\n\n## Raids\n- [x] Raid [zone:: Molten Core] ^r1\n",
  );
});

test("CRLF files stay CRLF", () => {
  const doc = parseMarkdown("## A\r\n- [ ] One ^a1\r\n");
  const out = renderMarkdown(doc, [item({ id: "a1", text: "One", category: "A", done: true })]);
  assert.equal(out, "## A\r\n- [x] One ^a1\r\n");
});

// --- Merge -----------------------------------------------------------------
const md = (over: object) => ({ id: "a", text: "x", tags: [], category: "General", done: false, ...over });

test("game completion flows to markdown", () => {
  const base = { a: item({}) };
  const res = merge({ base, md: [md({})], mdTime: 100, game: { a: item({ done: true, updated: 200 }) }, newId });
  assert.equal(res.items[0].done, true);
  assert.match(res.log[0], /game → markdown: completed/);
});

test("markdown edit flows to game with a newer timestamp", () => {
  const base = { a: item({}) };
  const res = merge({ base, md: [md({ text: "y" })], mdTime: 300, game: { a: item({}) }, newId });
  assert.equal(res.items[0].text, "y");
  assert.equal(res.items[0].updated, 300);
});

test("conflict: newest change wins", () => {
  const base = { a: item({}) };
  const game = { a: item({ done: true, updated: 400 }) };
  assert.equal(merge({ base, md: [md({ text: "md" })], mdTime: 300, game, newId }).items[0].done, true);
  assert.equal(merge({ base, md: [md({ text: "md" })], mdTime: 500, game, newId }).items[0].text, "md");
});

test("deleting a line in markdown deletes in game, and vice versa", () => {
  const base = { a: item({}), b: item({ id: "b" }) };
  const res = merge({ base, md: [md({ id: "b" })], mdTime: 300, game: { a: item({}), b: item({ id: "b", deleted: true, updated: 200 }) }, newId, tombstoneDays: 1e9 });
  const a = res.items.find((i) => i.id === "a")!;
  const b = res.items.find((i) => i.id === "b")!;
  assert.equal(a.deleted, true);
  assert.equal(b.deleted, true);
});

test("first sync with identical items on both sides changes nothing", () => {
  const res = merge({ base: {}, md: [md({})], mdTime: 999, game: { a: item({}) }, newId });
  assert.equal(res.items[0].updated, 100);
});

// --- End to end ------------------------------------------------------------
test("full sync against a fake WoW folder", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wts-"));
  const wow = path.join(dir, "_forever_");
  const addon = path.join(wow, "Interface", "AddOns", "WoWTodoSync");
  const svDir = path.join(wow, "WTF", "Account", "ME", "SavedVariables");
  fs.mkdirSync(addon, { recursive: true });
  fs.mkdirSync(svDir, { recursive: true });
  fs.writeFileSync(path.join(addon, "WoWTodoSync.toc"), "");
  const t = now();
  fs.writeFileSync(
    path.join(svDir, "WoWTodoSync.lua"),
    `WoWTodoSyncDB = { ["items"] = { ["g1"] = { ["id"] = "g1", ["text"] = "From game", ["category"] = "Quests", ["tags"] = { "q" }, ["done"] = false, ["created"] = ${t}, ["updated"] = ${t} } }, ["order"] = { "g1" }, ["categories"] = { "General", "Quests" } }`,
  );
  const todo = path.join(dir, "vault", "Todo.md");
  const cfg: Config = { todoFile: todo, wowPath: wow, account: "auto", pollSeconds: 2 };
  const logs: string[] = [];
  const opts = { log: (m: string) => logs.push(m), warn: (m: string) => logs.push("WARN " + m) };

  let state: State | undefined = syncOnce(cfg, readState(path.join(dir, "none.json")), opts);
  assert.ok(state);
  const written = fs.readFileSync(todo, "utf8");
  assert.match(written, /## Quests\n- \[ \] From game #q \^g1/);

  // add a todo in markdown -> appears in Inbox.lua
  fs.writeFileSync(todo, written.replace("## Quests", "## Quests\n- [ ] Added in Obsidian #md"));
  state = syncOnce(cfg, state, opts)!;
  const inbox = parseAssignments(fs.readFileSync(path.join(addon, "Inbox.lua"), "utf8")).WoWTodoSync_Inbox as any;
  const texts = inbox.items.map((i: any) => i.text);
  assert.deepEqual(texts.sort(), ["Added in Obsidian", "From game"]);
  assert.match(fs.readFileSync(todo, "utf8"), /Added in Obsidian #md \^\w+/);

  // emptying the file is refused
  fs.writeFileSync(todo, "# nothing\n");
  assert.equal(syncOnce(cfg, state, opts), undefined);
  assert.ok(logs.some((l) => l.startsWith("WARN")));
  fs.rmSync(dir, { recursive: true, force: true });
});

test("readGame tolerates a missing file", () => {
  assert.deepEqual(readGame(undefined).items, {});
});
