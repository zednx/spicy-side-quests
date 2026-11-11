import assert from "node:assert/strict";
import { test } from "node:test";
import { addTodo, deleteLine, editText, sections, StaleLine, toggleDone } from "../src/edit.ts";
import { pathOps } from "../src/tauri-fs.ts";

const SRC = `---
tags: [wow]
---
# Todo

## Professions
- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
- [x] Learn Alchemy ^d4e5f6

Some notes.

## Dungeons
- [ ] Run SM #group ^g7h8i9
`;

test("sections group todos by heading, with line numbers", () => {
  const s = sections(SRC);
  assert.deepEqual(s.map((x) => [x.category, x.rows.length]), [["Professions", 2], ["Dungeons", 1]]);
  assert.equal(s[0].rows[0].line, 6);
  assert.equal(s[0].rows[0].item.zone, "Winterspring");
});

test("toggle, delete and edit change only the target line", () => {
  const row = sections(SRC)[0].rows[0];
  const t = toggleDone(SRC, row.line, row.raw);
  assert.equal(t, SRC.replace("- [ ] Farm Arcanite", "- [x] Farm Arcanite"));
  assert.equal(deleteLine(SRC, row.line, row.raw), SRC.replace(row.raw + "\n", ""));
  const e = editText(SRC, row.line, row.raw, "Farm Thorium #mining");
  assert.equal(e.split("\n")[6], "- [ ] Farm Thorium #mining [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3");
});

test("edits refuse to touch a line that changed since it was shown", () => {
  const row = sections(SRC)[0].rows[0];
  assert.throws(() => toggleDone(SRC.replace("Farm", "Mine"), row.line, row.raw), StaleLine);
  assert.throws(() => deleteLine("short\n", row.line, row.raw), StaleLine);
});

test("add goes to the end of its section, or a new section", () => {
  const a = addTodo(SRC, "professions", "Buy vials #alchemy");
  assert.equal(a.split("\n")[8], "- [ ] Buy vials #alchemy");
  const b = addTodo(SRC, "Raids", "Molten Core");
  assert.ok(b.endsWith("## Raids\n- [ ] Molten Core\n"), b);
  // No headings at all: todos above any heading are "General", like the sync engine treats them.
  assert.equal(addTodo("# Just a title\n", "", "First one"), "# Just a title\n- [ ] First one\n");
  const d = addTodo("- [ ] loose\n", "General", "second");
  assert.equal(d, "- [ ] loose\n- [ ] second\n");
  assert.throws(() => addTodo(SRC, "X", "   "));
});

test("added text is a single safe line", () => {
  const a = addTodo(SRC, "Dungeons", "evil\n## Pwned\n- [x] injected");
  assert.ok(!a.includes("\n## Pwned"), a);
});

test("CRLF files stay CRLF", () => {
  const crlf = SRC.replace(/\n/g, "\r\n");
  const row = sections(crlf)[1].rows[0];
  assert.equal(toggleDone(crlf, row.line, row.raw), crlf.replace("- [ ] Run SM", "- [x] Run SM"));
  assert.ok(!addTodo(crlf, "Dungeons", "x").includes("\n- [ ] x\n"));
});

test("path helpers for Windows and Linux", () => {
  const w = pathOps("windows");
  assert.equal(w.join("C:\\Games\\", "\\WoW", "_forever_"), "C:\\Games\\WoW\\_forever_");
  assert.equal(w.join("C:\\", "x"), "C:\\x");
  assert.equal(w.dirname("C:\\Games\\WoW\\file.md"), "C:\\Games\\WoW");
  assert.equal(w.dirname("C:\\file.md"), "C:\\");
  assert.equal(w.dirname("D:/Notes/a.md"), "D:/Notes");
  const l = pathOps("linux");
  assert.equal(l.join("/home/me/", "/notes", "a.md"), "/home/me/notes/a.md");
  assert.equal(l.join("/", "etc"), "/etc");
  assert.equal(l.dirname("/home/me/a.md"), "/home/me");
  assert.equal(l.dirname("/a.md"), "/");
});
