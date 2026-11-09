import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createPrompter } from "./prompt.ts";

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

/** Account folders under WTF/Account (each has a SavedVariables folder). */
export function listAccounts(wowPath: string): string[] {
  const root = path.join(wowPath, "WTF", "Account");
  try {
    return fs
      .readdirSync(root, { withFileTypes: true })
      .filter((d) => d.isDirectory() && fs.existsSync(path.join(root, d.name, "SavedVariables")))
      .map((d) => d.name)
      .sort();
  } catch {
    return [];
  }
}

/** Problems with saved settings, e.g. after moving the vault or reinstalling WoW. */
export function configProblems(cfg: Config): string[] {
  const out: string[] = [];
  if (!cfg.todoFile) out.push("No markdown file is set.");
  else if (!fs.existsSync(path.dirname(cfg.todoFile))) out.push(`The markdown file's folder doesn't exist: ${path.dirname(cfg.todoFile)}`);
  else if (!fs.existsSync(cfg.todoFile)) out.push(`The markdown file doesn't exist: ${cfg.todoFile}`);
  if (!cfg.wowPath) out.push("No WoW folder is set.");
  else if (!fs.existsSync(cfg.wowPath)) out.push(`The WoW folder doesn't exist: ${cfg.wowPath}`);
  else if (!isAddonInstalled(cfg.wowPath)) out.push(`The addon isn't installed in: ${cfg.wowPath}`);
  if (cfg.account && cfg.account !== "auto" && cfg.wowPath && !listAccounts(cfg.wowPath).includes(cfg.account)) {
    out.push(`The WoW account folder "${cfg.account}" wasn't found.`);
  }
  return out;
}

/** Interactive setup. Press Enter to keep the value shown in [brackets]. */
export async function runSetup(file: string, existing?: Config): Promise<Config> {
  const prompt = createPrompter();
  const ask = prompt.ask;
  const yes = async (q: string, def: "y" | "n") => (await ask(`${q} (${def === "y" ? "Y/n" : "y/N"})`, def)).toLowerCase().startsWith("y");
  try {
    console.log(`\n=== Spicy Side Quests setup ===`);
    console.log(`Settings file: ${file}`);
    console.log("Press Enter to keep the value in [brackets]. You can paste or drag a path in.\n");

    // 1. Markdown file
    let todoFile = "";
    while (!todoFile) {
      todoFile = cleanPath(await ask("1) Markdown file to sync (any .md file, e.g. an Obsidian note):", existing?.todoFile));
      if (!todoFile.toLowerCase().endsWith(".md")) {
        console.log("   That needs to be a .md file.");
        todoFile = "";
      } else if (!fs.existsSync(path.dirname(todoFile))) {
        console.log(`   The folder ${path.dirname(todoFile)} doesn't exist.`);
        todoFile = "";
      } else if (!fs.existsSync(todoFile) && !(await yes("   That file doesn't exist yet. Create it there?", "y"))) {
        todoFile = "";
      }
    }

    // 2. WoW folder
    const detected = detectWowPaths().filter((p) => p !== existing?.wowPath);
    let wowPath = "";
    while (!wowPath) {
      console.log("\n2) WoW Forever folder (the one that contains Interface and WTF).");
      detected.forEach((p, i) => console.log(`   ${i + 1}. ${p}`));
      const def = existing?.wowPath || detected[0];
      const a = await ask(detected.length ? "   Type a number from the list, or a path:" : "   Path:", def);
      const n = Number(a);
      wowPath = Number.isInteger(n) && n >= 1 && n <= detected.length ? detected[n - 1] : cleanPath(a);
      if (!isAddonInstalled(wowPath)) {
        console.log(`   The addon isn't installed there (no ${path.join(addonDir(wowPath), ADDON + ".toc")}).`);
        if (!(await yes("   Use this folder anyway?", "n"))) wowPath = "";
      }
    }

    // 3. Account (only asked when there's a choice)
    let account = existing?.account ?? "auto";
    const accounts = listAccounts(wowPath);
    if (accounts.length > 1) {
      console.log("\n3) WoW account. \"auto\" picks the one you played most recently.");
      accounts.forEach((acc, i) => console.log(`   ${i + 1}. ${acc}`));
      const a = await ask("   Type a number, or auto:", accounts.includes(account) ? account : "auto");
      const n = Number(a);
      account = Number.isInteger(n) && n >= 1 && n <= accounts.length ? accounts[n - 1] : accounts.includes(a) ? a : "auto";
    } else if (!accounts.includes(account)) {
      account = "auto";
    }

    const cfg: Config = { todoFile, wowPath, account, pollSeconds: existing?.pollSeconds ?? 2 };
    console.log(`\n  markdown: ${cfg.todoFile}\n  game:     ${cfg.wowPath}\n  account:  ${cfg.account}`);
    saveConfig(file, cfg);
    console.log("\nSaved. Run setup again any time to change these.\n");
    return cfg;
  } finally {
    prompt.close();
  }
}
