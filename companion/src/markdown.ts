// Reads and writes the markdown todo file while keeping everything that is not
// a todo (frontmatter, notes, links) exactly as the user wrote it.
//
//   ## Category
//   - [ ] Text #tag [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3
import { DEFAULT_CATEGORY, oneLine, sameContent, type Item } from "./types.ts";

const TASK = /^([-*+]) \[(.)\] (.*)$/; // top-level tasks only; indented ones are left alone
const HEADING = /^#{2,6}[ \t]+(.*)$/;
const HEADING_CLOSE = /(?:^|[ \t])#+$/; // optional closing "##"
// Lines longer than this are kept as plain text and never parsed (guards against pathological input).
export const MAX_LINE = 1000;
const FENCE = /^\s*(```|~~~)/;
const BLOCK_ID = /\s+\^([A-Za-z0-9-]+)\s*$/;
const ZONE = /\[zone::([^\]]*)\]/i;
const XY = /\[xy::\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*\]/i;
const TAG = /(^|\s)#([\p{L}\p{N}_/-]+)/gu;

export interface MdItem {
  id?: string; // undefined until we assign one
  text: string;
  tags: string[];
  category: string;
  done: boolean;
  zone?: string;
  x?: number;
  y?: number;
}

type Line =
  | { kind: "text"; raw: string }
  | { kind: "heading"; raw: string; category: string }
  | { kind: "item"; raw: string; item: MdItem };

export interface MdDoc {
  lines: Line[];
  eol: string;
}

export function parseTaskText(body: string): Omit<MdItem, "category" | "done"> {
  let rest = body;
  let id: string | undefined;
  const idm = BLOCK_ID.exec(rest);
  if (idm) {
    id = idm[1];
    rest = rest.slice(0, idm.index);
  }
  let zone: string | undefined, x: number | undefined, y: number | undefined;
  const zm = ZONE.exec(rest);
  if (zm) {
    zone = zm[1].trim() || undefined;
    rest = rest.replace(ZONE, " ");
  }
  const xym = XY.exec(rest);
  if (xym) {
    x = Number(xym[1]);
    y = Number(xym[2]);
    rest = rest.replace(XY, " ");
  }
  const tags: string[] = [];
  rest = rest.replace(TAG, (_m, pre: string, tag: string) => {
    if (!/\p{L}/u.test(tag)) return _m; // "#1" is not a tag in Obsidian
    if (!tags.some((t) => t.toLowerCase() === tag.toLowerCase())) tags.push(tag);
    return pre;
  });
  const text = rest.replace(/\s+/g, " ").trim();
  return { id, text, tags, zone, x, y };
}

export function parseMarkdown(src: string): MdDoc {
  const eol = src.includes("\r\n") ? "\r\n" : "\n";
  const raw = src.split(/\r?\n/);
  const lines: Line[] = [];
  let category = DEFAULT_CATEGORY;
  let inFence = false;
  let inFrontmatter = raw[0] === "---";

  raw.forEach((line, idx) => {
    if (inFrontmatter) {
      lines.push({ kind: "text", raw: line });
      if (idx > 0 && line === "---") inFrontmatter = false;
      return;
    }
    if (FENCE.test(line)) inFence = !inFence;
    if (inFence || FENCE.test(line) || line.length > MAX_LINE) {
      lines.push({ kind: "text", raw: line });
      return;
    }
    const h = HEADING.exec(line);
    if (h && h[1].trim()) {
      category = h[1].trimEnd().replace(HEADING_CLOSE, "").trim() || DEFAULT_CATEGORY;
      lines.push({ kind: "heading", raw: line, category });
      return;
    }
    const t = TASK.exec(line);
    if (t) {
      const parsed = parseTaskText(t[3]);
      if (parsed.text !== "") {
        lines.push({ kind: "item", raw: line, item: { ...parsed, category, done: t[2] !== " " } });
        return;
      }
    }
    lines.push({ kind: "text", raw: line });
  });
  return { lines, eol };
}

export function mdItems(doc: MdDoc): MdItem[] {
  return doc.lines.flatMap((l) => (l.kind === "item" ? [l.item] : []));
}

const fmt = (n: number) => (Math.round(n * 10) / 10).toString();

// Values written into the file are reduced to one safe line each, so data from the
// game can never add extra lines, headings or todos to your notes.
const cleanTag = (t: string) => t.replace(/[^\p{L}\p{N}_/-]/gu, "");
const cleanZone = (z: string) => oneLine(z).replace(/[\[\]]/g, "");
export const cleanCategory = (c: string) => oneLine(c).replace(/^#+\s*/, "") || DEFAULT_CATEGORY;

export function renderItem(item: Item): string {
  const parts = [oneLine(item.text) || "(untitled)"];
  for (const t of item.tags.map(cleanTag)) if (/\p{L}/u.test(t)) parts.push("#" + t);
  const zone = item.zone ? cleanZone(item.zone) : "";
  if (zone) parts.push(`[zone:: ${zone}]`);
  if (Number.isFinite(item.x) && Number.isFinite(item.y)) parts.push(`[xy:: ${fmt(item.x!)}, ${fmt(item.y!)}]`);
  parts.push("^" + item.id);
  return `- [${item.done ? "x" : " "}] ${parts.join(" ")}`;
}

const lc = (s: string) => s.toLowerCase();

/**
 * Re-renders the document with the final item list. Unchanged item lines keep
 * their original text; deleted items are removed; new or moved items are added
 * at the end of their category's section (a new section is created if needed).
 */
export function renderMarkdown(doc: MdDoc, items: Item[]): string {
  const live = items.filter((i) => !i.deleted);
  const byId = new Map(live.map((i) => [i.id, i]));

  // Sections: index range of each category in the line list.
  type Section = { category: string; out: string[]; lastItem: number; headed: boolean };
  const sections: Section[] = [{ category: DEFAULT_CATEGORY, out: [], lastItem: -1, headed: false }];
  const placed = new Set<string>();

  for (const line of doc.lines) {
    let sec = sections[sections.length - 1];
    if (line.kind === "heading") {
      sec = { category: line.category, out: [line.raw], lastItem: 0, headed: true };
      sections.push(sec);
      continue;
    }
    if (line.kind === "item") {
      const id = line.item.id;
      const final = id ? byId.get(id) : undefined;
      if (!final || lc(final.category) !== lc(sec.category) || placed.has(final.id)) continue;
      const asMd = toItem(line.item, final);
      const keepRaw = sameContent(asMd, final) && BLOCK_ID.exec(line.raw)?.[1] === final.id;
      sec.out.push(keepRaw ? line.raw : renderItem(final));
      sec.lastItem = sec.out.length - 1;
      placed.add(final.id);
      continue;
    }
    sec.out.push(line.raw);
  }

  // Place new/moved items.
  const pending = live.filter((i) => !placed.has(i.id));
  for (const item of pending) {
    let sec =
      sections.find((s) => s.headed && lc(s.category) === lc(item.category)) ??
      (lc(item.category) === lc(DEFAULT_CATEGORY) && sections.length === 1 ? sections[0] : undefined);
    if (!sec) {
      const last = sections[sections.length - 1];
      while (last.out.length && last.out[last.out.length - 1].trim() === "") last.out.pop();
      if (last.out.length) last.out.push("");
      sec = { category: item.category, out: [`## ${cleanCategory(item.category)}`], lastItem: 0, headed: true };
      sections.push(sec);
    }
    const at = sec.lastItem >= 0 ? sec.lastItem + 1 : sec.out.length;
    sec.out.splice(at, 0, renderItem(item));
    sec.lastItem = at;
  }

  let out = sections.flatMap((s) => s.out);
  if (out.length && out[out.length - 1] !== "") out.push("");
  return out.join(doc.eol);
}

/** Converts a parsed markdown item into a full Item, borrowing ids/timestamps. */
export function toItem(md: MdItem, base: Partial<Item> & { id: string }): Item {
  return {
    id: base.id,
    text: md.text,
    tags: md.tags,
    category: md.category,
    done: md.done,
    zone: md.zone,
    mapID: md.zone && base.zone === md.zone ? base.mapID : undefined,
    x: md.x,
    y: md.y,
    created: base.created ?? 0,
    updated: base.updated ?? 0,
  };
}
