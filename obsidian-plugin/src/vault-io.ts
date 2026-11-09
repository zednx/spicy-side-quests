// Reads and writes the todo note through Obsidian's vault API (so the open editor stays in
// step). Written against a tiny interface so it can be tested without Obsidian.
import type { TodoIO } from "../../companion/src/sync.ts";

export interface FileLike {
  path: string;
  stat: { mtime: number };
}

export interface VaultLike {
  getFile(path: string): FileLike | null;
  read(file: FileLike): Promise<string>;
  /** Atomically transform the file's current contents (Obsidian's vault.process). */
  process(file: FileLike, fn: (data: string) => string): Promise<string>;
  create(path: string, data: string): Promise<unknown>;
  createFolder(path: string): Promise<unknown>;
  exists(path: string): Promise<boolean>;
}

export class ChangedWhileSyncing extends Error {
  constructor(path: string) {
    super(`${path} changed while syncing; will retry`);
  }
}

export function vaultTodoIO(vault: VaultLike, path: string): TodoIO {
  return {
    name: path,
    async read() {
      const f = vault.getFile(path);
      if (!f) return undefined;
      return { text: await vault.read(f), mtime: Math.floor(f.stat.mtime / 1000) };
    },
    async write(text, expected) {
      const f = vault.getFile(path);
      if (!f) {
        const dir = path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
        if (dir && !(await vault.exists(dir))) await vault.createFolder(dir);
        await vault.create(path, text);
        return;
      }
      let changed = false;
      await vault.process(f, (data) => {
        // Only replace the text we merged from; if you typed in between, leave it and retry.
        if (expected !== undefined && data !== expected) {
          changed = true;
          return data;
        }
        return text;
      });
      if (changed) throw new ChangedWhileSyncing(path);
    },
  };
}
