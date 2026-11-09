import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline/promises";

export interface Config {
  /** Markdown file to sync, e.g. an Obsidian note. */
  todoFile: string;
  /** The WoW Forever client folder, e.g. C:/Program Files (x86)/World of Warcraft/_forever_ */
  wowPath: string;
  /** Folder name under WTF/Account, or "auto" to pick the one that has the addon's data. */
  account: string;
  /** How often to check the files for changes. */
  pollSeconds: number;
}

export const ADDON = "SpicySideQuests";

export function defaultConfigDir(): string {
  if (process.platform === "win32" && process.env.APPDATA) return path.join(process.env.APPDATA, ADDON);
  const xdg = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
  return path.join(xdg, "spicysidequests");
}

/** Copies settings from the old "WoW Todo Sync" name, once. */
export function migrateOldConfigDir(newDir: string) {
  if (fs.existsSync(newDir)) return false;
  const xdg = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
  const old = process.platform === "win32" && process.env.APPDATA ? path.join(process.env.APPDATA, "WoWTodoSync") : path.join(xdg, "wowtodosync");
  if (!fs.existsSync(old)) return false;
  fs.cpSync(old, newDir, { recursive: true });
  return true;
}

/** Strips quotes (Windows "Copy as path") and expands ~. */
export function cleanPath(p: string): string {
  let s = p.trim().replace(/^["']|["']$/g, "");
  if (s.startsWith("~")) s = path.join(os.homedir(), s.slice(1));
  return path.normalize(s);
}

export function loadConfig(file: string): Config | undefined {
  if (!fs.existsSync(file)) return undefined;
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  return {
    todoFile: cleanPath(String(raw.todoFile ?? "")),
    wowPath: cleanPath(String(raw.wowPath ?? "")),
    account: String(raw.account ?? "auto"),
    pollSeconds: Number(raw.pollSeconds) > 0 ? Number(raw.pollSeconds) : 2,
  };
}

export function saveConfig(file: string, cfg: Config) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n");
}

export function addonDir(wowPath: string) {
  return path.join(wowPath, "Interface", "AddOns", ADDON);
}

export function isAddonInstalled(wowPath: string) {
  return fs.existsSync(path.join(addonDir(wowPath), `${ADDON}.toc`));
}

/** Common install locations. Only returns folders that have the addon installed. */
export function detectWowPaths(): string[] {
  const roots: string[] = [];
  if (process.platform === "win32") {
    for (const drive of ["C:", "D:", "E:"]) {
      roots.push(`${drive}\\Program Files (x86)\\World of Warcraft`, `${drive}\\Program Files\\World of Warcraft`, `${drive}\\World of Warcraft`, `${drive}\\Games\\World of Warcraft`);
    }
  } else {
    const home = os.homedir();
    for (const prefix of [path.join(home, "Games", "battlenet"), path.join(home, "Games", "battle-net"), path.join(home, ".wine")]) {
      roots.push(path.join(prefix, "drive_c", "Program Files (x86)", "World of Warcraft"));
    }
  }
  const flavours = ["_forever_", "_forever_beta_", "_classic_beta_"];
  return roots.flatMap((r) => flavours.map((f) => path.join(r, f))).filter(isAddonInstalled);
}

export async function runSetup(file: string, existing?: Config): Promise<Config> {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = async (q: string, def?: string) => {
    const a = (await rl.question(def ? `${q}\n  [${def}]: ` : `${q}\n  : `)).trim();
    return a || def || "";
  };
  try {
    console.log(`\nSpicy Side Quests setup — settings are saved to ${file}\n`);

    let todoFile = "";
    while (!todoFile) {
      todoFile = cleanPath(await ask("Path to your markdown todo file (it will be created if missing):", existing?.todoFile));
      if (!todoFile.toLowerCase().endsWith(".md")) {
        console.log("  Please give a .md file.");
        todoFile = "";
      }
    }

    const detected = detectWowPaths();
    let wowPath = "";
    while (!wowPath) {
      const def = existing?.wowPath || detected[0];
      wowPath = cleanPath(await ask("WoW Forever folder (the one that contains Interface and WTF):", def));
      if (!isAddonInstalled(wowPath)) {
        console.log(`  Couldn't find ${path.join(addonDir(wowPath), ADDON + ".toc")}.`);
        const keep = (await ask("  Use this folder anyway? (y/N)", "n")).toLowerCase();
        if (keep !== "y") wowPath = "";
      }
    }

    const cfg: Config = { todoFile, wowPath, account: existing?.account ?? "auto", pollSeconds: existing?.pollSeconds ?? 2 };
    saveConfig(file, cfg);
    console.log("\nSaved. Run again with --setup to change these.\n");
    return cfg;
  } finally {
    rl.close();
  }
}
