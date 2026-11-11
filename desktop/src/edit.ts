// Small, safe edits to the markdown file for the Side quests tab: tick, add, rename,
// delete. Each edit checks the line still says what the UI showed, so an edit made
// against a stale view never touches the wrong line.
import { parseMarkdown, parseTaskText, type MdItem } from "../../companion/src/markdown.ts";
import { DEFAULT_CATEGORY, oneLine } from "../../companion/src/types.ts";

export interface Row {
  line: number; // index into the file's lines
  raw: string;
  item: MdItem;
}

export interface Section {
  category: string;
  rows: Row[];
}

export class StaleLine extends Error {
  constructor() {
    super("The file changed since it was shown. Refreshed; try again.");
  }
}

const TASK = /^([-*+]) \[(.)\] (.*)$/;
const eolOf = (src: string) => (src.includes("\r\n") ? "\r\n" : "\n");
const splitLines = (src: string) => src.split(/\r?\n/);

/** Todo lines grouped by category, in file order. */
export function sections(src: string): Section[] {
  const doc = parseMarkdown(src);
  const out: Section[] = [];
  const get = (cat: string) => {
    let s = out.find((x) => x.category.toLowerCase() === cat.toLowerCase());
    if (!s) out.push((s = { category: cat, rows: [] }));
    return s;
  };
  doc.lines.forEach((l, i) => {
    if (l.kind === "heading") get(l.category);
    if (l.kind === "item") get(l.item.category).rows.push({ line: i, raw: l.raw, item: l.item });
  });
  return out.filter((s) => s.rows.length > 0 || s.category !== DEFAULT_CATEGORY);
}

function lineAt(lines: string[], line: number, expected: string) {
  if (lines[line] !== expected) throw new StaleLine();
}

export function toggleDone(src: string, line: number, expected: string): string {
  const lines = splitLines(src);
  lineAt(lines, line, expected);
  const m = TASK.exec(lines[line]);
  if (!m) throw new StaleLine();
  lines[line] = `${m[1]} [${m[2] === " " ? "x" : " "}] ${m[3]}`;
  return lines.join(eolOf(src));
}

export function deleteLine(src: string, line: number, expected: string): string {
  const lines = splitLines(src);
  lineAt(lines, line, expected);
  lines.splice(line, 1);
  return lines.join(eolOf(src));
}

/** Replaces the text and #tags of a todo, keeping its tick, location fields and ^id. */
export function editText(src: string, line: number, expected: string, newText: string): string {
  const lines = splitLines(src);
  lineAt(lines, line, expected);
  const m = TASK.exec(lines[line]);
  if (!m) throw new StaleLine();
  const old = parseTaskText(m[3]);
  const next = parseTaskText(oneLine(newText));
  if (!next.text) throw new Error("A side quest needs some text.");
  const parts = [next.text, ...next.tags.map((t) => "#" + t)];
  if (old.zone) parts.push(`[zone:: ${old.zone}]`);
  if (old.x !== undefined && old.y !== undefined) parts.push(`[xy:: ${old.x}, ${old.y}]`);
  if (old.id) parts.push("^" + old.id);
  lines[line] = `${m[1]} [${m[2]}] ${parts.join(" ")}`;
  return lines.join(eolOf(src));
}

/** Adds "- [ ] text" at the end of the category's section (creating it if needed). */
export function addTodo(src: string, category: string, text: string): string {
  const clean = oneLine(text);
  if (!parseTaskText(clean).text) throw new Error("A side quest needs some text.");
  const cat = oneLine(category).replace(/^#+\s*/, "") || DEFAULT_CATEGORY;
  const eol = eolOf(src);
  const lines = splitLines(src);
  const doc = parseMarkdown(src);
  const newLine = `- [ ] ${clean}`;

  // Find the section: from its heading to the next heading.
  let start = -1;
  doc.lines.forEach((l, i) => {
    if (start === -1 && l.kind === "heading" && l.category.toLowerCase() === cat.toLowerCase()) start = i;
  });
  const hasHeadings = doc.lines.some((l) => l.kind === "heading");
  if (start === -1 && cat.toLowerCase() === DEFAULT_CATEGORY.toLowerCase() && !hasHeadings) start = -2; // no headings: top of file
  if (start === -1) {
    while (lines.length && lines[lines.length - 1].trim() === "") lines.pop();
    lines.push("", `## ${cat}`, newLine, "");
    return lines.join(eol);
  }
  const from = start === -2 ? 0 : start + 1;
  let end = doc.lines.length;
  for (let i = from; i < doc.lines.length; i++) if (doc.lines[i].kind === "heading") { end = i; break; }
  let insertAt = start + 1;
  if (start === -2) {
    // No headings: after the last line with text (keeps the file's trailing newline).
    insertAt = 0;
    for (let i = 0; i < end; i++) if (lines[i].trim() !== "") insertAt = i + 1;
  }
  for (let i = from; i < end; i++) if (doc.lines[i].kind === "item") insertAt = i + 1;
  lines.splice(insertAt, 0, newLine);
  return lines.join(eol);
}
