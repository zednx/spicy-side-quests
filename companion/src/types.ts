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
