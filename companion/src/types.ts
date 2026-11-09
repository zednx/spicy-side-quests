export interface Item {
  id: string;
  text: string;
  tags: string[];
  category: string;
  done: boolean;
  deleted?: boolean;
  zone?: string;
  mapID?: number;
  x?: number;
  y?: number;
  created: number; // unix seconds
  updated: number; // unix seconds
}

export const DEFAULT_CATEGORY = "General";

export const now = (): number => Math.floor(Date.now() / 1000);

/** Same rule as Obsidian block IDs (and the addon): letters, digits and dashes. */
export const isValidId = (id: unknown): id is string => typeof id === "string" && /^[A-Za-z0-9-]{1,64}$/.test(id);

/** Own-property lookup, so ids like "constructor" never hit Object.prototype. */
export function own<T>(obj: Record<string, T>, key: string): T | undefined {
  return Object.prototype.hasOwnProperty.call(obj, key) ? obj[key] : undefined;
}

/** A plain dictionary with no prototype. */
export const dict = <T>(): Record<string, T> => Object.create(null);

/** Single-line text: control characters and line separators become spaces. */
export const oneLine = (s: string): string => s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, " ").replace(/ {2,}/g, " ").trim();

/** Text that is safe to print to a terminal (no escape sequences). */
export const terminalSafe = (s: string): string => s.replace(/[\x00-\x1f\x7f-\x9f]/g, "?");

/** True when two items have the same user-visible content. */
export function sameContent(a: Item, b: Item): boolean {
  return (
    a.text === b.text &&
    a.done === b.done &&
    !!a.deleted === !!b.deleted &&
    a.category.toLowerCase() === b.category.toLowerCase() &&
    a.tags.join(" ").toLowerCase() === b.tags.join(" ").toLowerCase() &&
    (a.zone ?? "") === (b.zone ?? "") &&
    round(a.x) === round(b.x) &&
    round(a.y) === round(b.y)
  );
}

const round = (v?: number) => (v === undefined ? undefined : Math.round(v * 10) / 10);
