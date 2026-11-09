// Three-way merge between the markdown file, the game and the last synced state.
// When both sides changed the same item, the most recent change wins.
import { toItem, type MdItem } from "./markdown.ts";
import { now, sameContent, type Item } from "./types.ts";

export interface MergeInput {
  base: Record<string, Item>; // state after the previous sync
  md: MdItem[]; // items parsed from markdown (ids may be missing)
  mdTime: number; // markdown file mtime, unix seconds
  game: Record<string, Item>; // items from the addon's SavedVariables
  gameOrder?: string[];
  newId: (taken: Set<string>) => string;
  tombstoneDays?: number;
}

export interface MergeResult {
  items: Item[];
  log: string[];
}

export function merge(input: MergeInput): MergeResult {
  const { base, md, mdTime, game } = input;
  const log: string[] = [];
  const taken = new Set<string>([...Object.keys(base), ...Object.keys(game)]);

  // 1. Give new markdown items an id (and fix duplicate ids).
  const mdMap = new Map<string, MdItem>();
  for (const item of md) {
    if (!item.id || mdMap.has(item.id)) {
      item.id = input.newId(taken);
    }
    taken.add(item.id);
    mdMap.set(item.id, item);
  }

  // 2. Stable order: markdown first, then game, then anything left in base.
  const ids: string[] = [];
  const seen = new Set<string>();
  const push = (id: string) => {
    if (!seen.has(id)) {
      seen.add(id);
      ids.push(id);
    }
  };
  mdMap.forEach((_, id) => push(id));
  (input.gameOrder ?? []).forEach((id) => game[id] && push(id));
  Object.keys(game).forEach(push);
  Object.keys(base).forEach(push);

  const items: Item[] = [];
  for (const id of ids) {
    const b = base[id];
    const g = game[id];
    const m = mdMap.get(id);

    let fromMd: Item | undefined;
    if (m) {
      const ref = b ?? g;
      const asItem = toItem(m, { ...ref, id });
      if (!ref) {
        asItem.created = asItem.updated = mdTime;
      }
      const changed = b ? b.deleted || !sameContent(asItem, b) : !(g && sameContent(asItem, g));
      if (changed) fromMd = { ...asItem, updated: Math.max(mdTime, (b?.updated ?? 0) + 1) };
    } else if (b && !b.deleted) {
      // was in the file last time, now gone -> deleted in markdown
      fromMd = { ...b, deleted: true, updated: Math.max(mdTime, b.updated + 1) };
    }

    const gameChanged = !!g && (!b || g.updated > b.updated);
    const fromGame = gameChanged ? g : undefined;

    let final: Item | undefined;
    let source = "";
    if (fromMd && fromGame) {
      if (fromGame.updated > fromMd.updated) {
        final = fromGame;
        source = "game";
      } else {
        final = fromMd;
        source = "markdown";
      }
    } else if (fromMd) {
      final = fromMd;
      source = "markdown";
    } else if (fromGame) {
      final = fromGame;
      source = "game";
    } else {
      final = b ?? g;
    }
    if (!final) continue;

    if (source) log.push(describe(b, final, source));
    items.push(final);
  }

  // 3. Forget old tombstones.
  const cutoff = now() - (input.tombstoneDays ?? 30) * 86400;
  return {
    items: items.filter((i) => !(i.deleted && i.updated < cutoff)),
    log: log.filter(Boolean),
  };
}

function describe(prev: Item | undefined, next: Item, source: string): string {
  const arrow = source === "game" ? "game → markdown" : "markdown → game";
  const name = `"${next.text}"`;
  if (next.deleted) return prev && !prev.deleted ? `${arrow}: removed ${name}` : "";
  if (!prev || prev.deleted) return `${arrow}: added ${name} (${next.category})`;
  if (prev.done !== next.done) return `${arrow}: ${next.done ? "completed" : "reopened"} ${name}`;
  if (sameContent(prev, next)) return "";
  return `${arrow}: updated ${name}`;
}
