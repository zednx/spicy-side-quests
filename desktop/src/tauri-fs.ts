// The engine's file access, backed by the app's Rust commands.
import { invoke } from "@tauri-apps/api/core";
import type { FileInfo, Fsys } from "../../companion/src/engine.ts";

export interface EnvInfo {
  platform: string; // "windows" | "linux" | "macos"
  home: string;
  configRoot: string;
}

/** Path helpers for the given platform (the web view has no `path` module). */
export function pathOps(platform: string) {
  const win = platform === "windows";
  const sep = win ? "\\" : "/";
  const trailing = win ? /[\\/]+$/ : /\/+$/;
  const leading = win ? /^[\\/]+/ : /^\/+/;
  const join = (...parts: string[]) => {
    let out = "";
    for (const p of parts) {
      if (!p) continue;
      out = out ? out.replace(trailing, "") + sep + p.replace(leading, "") : p;
    }
    return out;
  };
  const dirname = (p: string) => {
    const s = p.length > 1 ? p.replace(trailing, "") || p[0] : p;
    const i = Math.max(s.lastIndexOf("/"), win ? s.lastIndexOf("\\") : -1);
    if (i < 0) return ".";
    if (i === 0) return s[0];
    if (win && i === 2 && s[1] === ":") return s.slice(0, 3);
    return s.slice(0, i);
  };
  return { join, dirname, sep };
}

export function tauriFs(platform: string): Fsys {
  const { join, dirname } = pathOps(platform);
  return {
    readText: async (path) => (await invoke<string | null>("read_text", { path })) ?? undefined,
    writeText: (path, text) => invoke<void>("write_text", { path, text }),
    info: async (path) => (await invoke<FileInfo | null>("file_info", { path })) ?? undefined,
    listDir: (path) => invoke<string[]>("list_dir", { path }),
    join,
    dirname,
  };
}

export const envInfo = () => invoke<EnvInfo>("env_info");
