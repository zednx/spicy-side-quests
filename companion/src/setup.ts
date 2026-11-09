// Interactive terminal setup for the companion scripts (not used by the Obsidian plugin).
import fs from "node:fs";
import path from "node:path";
import { ADDON, addonDir, cleanPath, detectWowPaths, isAddonInstalled, listAccounts, saveConfig, type Config } from "./config.ts";
import { createPrompter } from "./prompt.ts";

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
