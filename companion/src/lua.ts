// Tiny reader/writer for the Lua data files WoW uses (SavedVariables) and
// the Inbox.lua file we write. Only handles data literals, never executes code.

export type LuaValue = string | number | boolean | null | LuaValue[] | { [k: string]: LuaValue };

/** Parses `Name = value` assignments, e.g. a SavedVariables file. */
export function parseAssignments(src: string): Record<string, LuaValue> {
  const p = new Parser(src);
  const out: Record<string, LuaValue> = Object.create(null);
  p.skip();
  while (!p.eof()) {
    const name = p.ident();
    p.skip();
    p.expect("=");
    out[name] = p.value();
    p.skip();
    if (p.peek() === ";") p.i++;
    p.skip();
  }
  return out;
}

const MAX_DEPTH = 32;

class Parser {
  i = 0;
  depth = 0;
  src: string;
  constructor(src: string) {
    this.src = src;
  }

  eof() {
    return this.i >= this.src.length;
  }
  peek() {
    return this.src[this.i];
  }
  fail(msg: string): never {
    const line = this.src.slice(0, this.i).split("\n").length;
    throw new Error(`Lua parse error on line ${line}: ${msg}`);
  }
  expect(ch: string) {
    if (this.src[this.i] !== ch) this.fail(`expected '${ch}'`);
    this.i++;
  }

  /** Skips whitespace and comments (-- line and --[[ block ]]). */
  skip() {
    for (;;) {
      while (!this.eof() && /\s/.test(this.peek())) this.i++;
      if (this.src.startsWith("--[[", this.i)) {
        const end = this.src.indexOf("]]", this.i);
        this.i = end < 0 ? this.src.length : end + 2;
      } else if (this.src.startsWith("--", this.i)) {
        const end = this.src.indexOf("\n", this.i);
        this.i = end < 0 ? this.src.length : end + 1;
      } else return;
    }
  }

  ident(): string {
    const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(this.src.slice(this.i, this.i + 200));
    if (!m) this.fail("expected identifier");
    this.i += m[0].length;
    return m[0];
  }

  value(): LuaValue {
    this.skip();
    const ch = this.peek();
    if (ch === "{") return this.table();
    if (ch === '"' || ch === "'") return this.string();
    if (ch === "[" && (this.src[this.i + 1] === "[" || this.src[this.i + 1] === "=")) return this.longString();
    const rest = this.src.slice(this.i, this.i + 40);
    let m: RegExpExecArray | null;
    if ((m = /^(true|false|nil)\b/.exec(rest))) {
      this.i += m[0].length;
      return m[0] === "nil" ? null : m[0] === "true";
    }
    if ((m = /^-?(0x[0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?|inf|nan)/.exec(rest))) {
      this.i += m[0].length;
      return Number(m[0]);
    }
    this.fail(`unexpected '${ch}'`);
  }

  string(): string {
    const q = this.peek();
    this.i++;
    let out = "";
    while (!this.eof()) {
      const c = this.src[this.i++];
      if (c === q) return out;
      if (c !== "\\") {
        out += c;
        continue;
      }
      const e = this.src[this.i++];
      const map: Record<string, string> = { n: "\n", t: "\t", r: "\r", a: "\x07", b: "\b", f: "\f", v: "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n" };
      if (e in map) out += map[e];
      else if (/\d/.test(e)) {
        let digits = e;
        while (digits.length < 3 && /\d/.test(this.peek())) digits += this.src[this.i++];
        out += String.fromCharCode(Number(digits));
      } else out += e;
    }
    this.fail("unterminated string");
  }

  longString(): string {
    const m = /^\[(=*)\[/.exec(this.src.slice(this.i));
    if (!m) this.fail("bad long string");
    const close = "]" + m[1] + "]";
    const start = this.i + m[0].length;
    const end = this.src.indexOf(close, start);
    if (end < 0) this.fail("unterminated long string");
    this.i = end + close.length;
    return this.src.slice(start, end).replace(/^\r?\n/, "");
  }

  table(): LuaValue {
    this.expect("{");
    if (++this.depth > MAX_DEPTH) this.fail("tables nested too deeply");
    const keyed: Record<string, LuaValue> = Object.create(null); // no prototype: keys like "__proto__" stay plain keys
    const list: LuaValue[] = [];
    let hasKeys = false;
    for (;;) {
      this.skip();
      if (this.eof()) this.fail("unterminated table");
      if (this.peek() === "}") {
        this.i++;
        break;
      }
      let key: string | number | null = null;
      if (this.peek() === "[") {
        this.i++;
        const k = this.value();
        this.skip();
        this.expect("]");
        this.skip();
        this.expect("=");
        key = typeof k === "number" ? k : String(k);
      } else {
        const save = this.i;
        const m = /^[A-Za-z_][A-Za-z0-9_]*\s*=(?!=)/.exec(this.src.slice(this.i, this.i + 200));
        if (m && !/^(true|false|nil)\b/.test(m[0])) {
          key = this.ident();
          this.skip();
          this.expect("=");
        } else this.i = save;
      }
      const v = this.value();
      if (key === null) list.push(v);
      else if (typeof key === "number" && Number.isInteger(key) && key >= 1) list[key - 1] = v;
      else {
        keyed[String(key)] = v;
        hasKeys = true;
      }
      this.skip();
      if (this.peek() === "," || this.peek() === ";") this.i++;
    }
    this.depth--;
    if (!hasKeys) return list;
    list.forEach((v, idx) => (keyed[String(idx + 1)] = v));
    return keyed;
  }
}

/** Serialises a JS value as a Lua literal. */
export function toLua(v: unknown, indent = ""): string {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number") return Number.isFinite(v) ? String(v) : "0";
  if (typeof v === "string") return luaString(v);
  const inner = indent + "\t";
  if (Array.isArray(v)) {
    if (v.length === 0) return "{}";
    return "{\n" + v.map((x) => inner + toLua(x, inner) + ",\n").join("") + indent + "}";
  }
  const entries = Object.entries(v as Record<string, unknown>).filter(([, x]) => x !== undefined);
  if (entries.length === 0) return "{}";
  return (
    "{\n" +
    entries
      .map(([k, x]) => {
        const key = /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : `[${luaString(k)}]`;
        return `${inner}${key} = ${toLua(x, inner)},\n`;
      })
      .join("") +
    indent +
    "}"
  );
}

function luaString(s: string): string {
  return (
    '"' +
    s.replace(/[\\"\x00-\x1f\x7f]/g, (c) => {
      if (c === "\\") return "\\\\";
      if (c === '"') return '\\"';
      if (c === "\n") return "\\n";
      if (c === "\r") return "\\r";
      if (c === "\t") return "\\t";
      return "\\" + c.charCodeAt(0).toString().padStart(3, "0");
    }) +
    '"'
  );
}
