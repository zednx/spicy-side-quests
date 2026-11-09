// Spicy Side Quests for Obsidian: keeps a note in this vault in sync with the
// Spicy Side Quests addon in WoW Forever. Uses the same sync engine as the
// companion scripts (../../companion/src), so behaviour and safety checks match.
import fs from "node:fs";
import {
  AbstractInputSuggest,
  type App,
  Notice,
  normalizePath,
  Plugin,
  PluginSettingTab,
  Setting,
  TFile,
} from "obsidian";
import { addonDir, detectWowPaths, isAddonInstalled, listAccounts, type Config } from "../../companion/src/config.ts";
import { findSavedVariables, stateFromJSON, syncOnce, type State } from "../../companion/src/sync.ts";
import { dict, terminalSafe } from "../../companion/src/types.ts";
import { ChangedWhileSyncing, vaultTodoIO, type VaultLike } from "./vault-io.ts";

interface Settings {
  todoFile: string; // path inside the vault
  wowPath: string;
  account: string;
  pollSeconds: number;
}

const DEFAULTS: Settings = { todoFile: "", wowPath: "", account: "auto", pollSeconds: 3 };
const MAX_LOG = 20;

export default class SpicySideQuestsPlugin extends Plugin {
  settings: Settings = { ...DEFAULTS };
  state: State = { base: dict() };
  activity: string[] = [];
  private statusEl!: HTMLElement;
  private busy = false;
  private again = false;
  private lastSig = "";
  private lastWarning = "";
  private debounce: number | undefined;
  private timer: number | undefined;
  onActivity: (() => void) | undefined;

  async onload() {
    const data = (await this.loadData()) ?? {};
    this.settings = { ...DEFAULTS, ...(data.settings ?? {}) };
    this.state = stateFromJSON(data.state);

    this.statusEl = this.addStatusBarItem();
    this.statusEl.addClass("ssq-status");
    this.statusEl.setAttr("aria-label", "Spicy Side Quests: click to sync now");
    this.registerDomEvent(this.statusEl, "click", () => void this.sync(true));
    this.setStatus(this.problem() ?? "Waiting…");

    this.addSettingTab(new SettingsTab(this.app, this));
    this.addCommand({ id: "sync-now", name: "Sync now", callback: () => void this.sync(true) });
    this.addCommand({ id: "open-note", name: "Open side quests note", callback: () => void this.openNote() });
    this.addRibbonIcon("flame", "Open side quests note", () => void this.openNote());

    // Note edited in Obsidian -> sync shortly after you stop typing.
    this.registerEvent(this.app.vault.on("modify", (f) => f.path === this.settings.todoFile && this.schedule()));
    // Note renamed or moved -> follow it.
    this.registerEvent(
      this.app.vault.on("rename", (f, old) => {
        if (old === this.settings.todoFile) {
          this.settings.todoFile = f.path;
          void this.save();
          this.note(`Following the renamed note: ${f.path}`);
        }
      }),
    );

    this.app.workspace.onLayoutReady(() => {
      this.restartTimer();
      void this.sync(false);
    });
  }

  onunload() {
    if (this.debounce) window.clearTimeout(this.debounce);
  }

  // --- helpers ---------------------------------------------------------------
  config(): Config {
    return { todoFile: this.settings.todoFile, wowPath: this.settings.wowPath, account: this.settings.account, pollSeconds: this.settings.pollSeconds };
  }

  /** Why syncing can't run yet, or undefined if everything is set up. */
  problem(): string | undefined {
    const s = this.settings;
    if (!s.todoFile) return "Choose a note in settings";
    if (!s.wowPath) return "Choose your WoW folder in settings";
    if (!fs.existsSync(s.wowPath)) return "WoW folder not found";
    if (!isAddonInstalled(s.wowPath)) return "Addon not installed in that WoW folder";
    return undefined;
  }

  async save() {
    await this.saveData({ settings: this.settings, state: this.state });
  }

  /** Changing to a different note: forget the old sync history so nothing gets deleted. */
  async setTodoFile(raw: string) {
    let p = normalizePath(raw.trim());
    if (p && !p.toLowerCase().endsWith(".md")) p += ".md";
    if (p === this.settings.todoFile) return;
    const hadOld = !!this.settings.todoFile;
    this.settings.todoFile = p;
    this.state = { base: dict() };
    await this.save();
    if (hadOld && p) this.note("Note changed: the next sync merges both sides and deletes nothing.");
    void this.sync(false);
  }

  restartTimer() {
    if (this.timer) window.clearInterval(this.timer);
    this.timer = window.setInterval(() => this.tick(), Math.max(2, this.settings.pollSeconds) * 1000);
    this.registerInterval(this.timer);
  }

  private signature(): string {
    if (this.problem()) return "";
    const sv = findSavedVariables(this.config());
    try {
      const st = sv ? fs.statSync(sv) : undefined;
      return st ? `${st.mtimeMs}:${st.size}` : "-";
    } catch {
      return "-";
    }
  }

  /** Polls the game's save file; WoW writes it on /reload and logout. */
  private tick() {
    const sig = this.signature();
    if (sig && sig !== this.lastSig) void this.sync(false);
  }

  private schedule() {
    if (this.debounce) window.clearTimeout(this.debounce);
    this.debounce = window.setTimeout(() => void this.sync(false), 1500);
  }

  private setStatus(text: string) {
    this.statusEl.setText(`🌶 ${text}`);
  }

  private note(msg: string) {
    const line = `${new Date().toTimeString().slice(0, 8)} ${terminalSafe(msg)}`;
    this.activity.unshift(line);
    this.activity.length = Math.min(this.activity.length, MAX_LOG);
    console.debug("[Spicy Side Quests]", msg);
    this.onActivity?.();
  }

  private warn(msg: string, manual: boolean) {
    this.note(msg);
    if (manual || msg !== this.lastWarning) new Notice(`Spicy Side Quests: ${msg}`, 8000);
    this.lastWarning = msg;
  }

  async openNote() {
    const p = this.settings.todoFile;
    if (!p) return new Notice("Spicy Side Quests: choose a note in the plugin settings first.");
    const f = this.app.vault.getAbstractFileByPath(p);
    if (f instanceof TFile) await this.app.workspace.getLeaf(false).openFile(f);
    else new Notice(`Spicy Side Quests: ${p} doesn't exist yet. It's created on the first sync.`);
  }

  private vaultLike(): VaultLike {
    const v = this.app.vault;
    return {
      getFile: (p) => {
        const f = v.getAbstractFileByPath(normalizePath(p));
        return f instanceof TFile ? f : null;
      },
      read: (f) => v.read(f as TFile),
      process: (f, fn) => v.process(f as TFile, fn),
      create: (p, d) => v.create(p, d),
      createFolder: (p) => v.createFolder(p),
      exists: (p) => v.adapter.exists(p),
    };
  }

  // --- sync ------------------------------------------------------------------
  async sync(manual: boolean) {
    const problem = this.problem();
    if (problem) {
      this.setStatus(problem);
      if (manual) new Notice(`Spicy Side Quests: ${problem}.`);
      return;
    }
    if (this.busy) {
      this.again = true;
      return;
    }
    this.busy = true;
    const changes: string[] = [];
    const sigBefore = this.signature();
    try {
      const next = await syncOnce(this.config(), this.state, {
        todo: vaultTodoIO(this.vaultLike(), this.settings.todoFile),
        log: (m) => {
          changes.push(m);
          this.note(m);
        },
        warn: (m) => this.warn(m, manual),
      });
      this.lastSig = sigBefore;
      if (next) {
        this.state = next;
        await this.save();
        this.setStatus(`Synced ${new Date().toTimeString().slice(0, 5)}`);
        this.lastWarning = "";
        if (changes.length) new Notice(`Spicy Side Quests\n${changes.slice(0, 6).join("\n")}`, 6000);
        else if (manual) new Notice("Spicy Side Quests: already in sync.");
      } else {
        this.setStatus("Sync paused (see settings)");
      }
    } catch (e) {
      if (e instanceof ChangedWhileSyncing) {
        this.schedule(); // you were typing; try again shortly
      } else {
        const msg = e instanceof Error ? e.message : String(e);
        this.setStatus("Sync failed (see settings)");
        this.warn(`Sync failed: ${msg}`, manual);
      }
    } finally {
      this.busy = false;
      if (this.again) {
        this.again = false;
        this.schedule();
      }
    }
  }
}

// --- settings ------------------------------------------------------------------
class NoteSuggest extends AbstractInputSuggest<TFile> {
  constructor(
    private readonly obsidian: App,
    private readonly input: HTMLInputElement,
    private readonly onPick: (path: string) => void,
  ) {
    super(obsidian, input);
  }
  getSuggestions(query: string): TFile[] {
    const q = query.toLowerCase();
    return this.obsidian.vault
      .getMarkdownFiles()
      .filter((f) => f.path.toLowerCase().includes(q))
      .slice(0, 30);
  }
  renderSuggestion(file: TFile, el: HTMLElement) {
    el.setText(file.path);
  }
  selectSuggestion(file: TFile) {
    this.input.value = file.path;
    this.onPick(file.path);
    this.close();
  }
}

class SettingsTab extends PluginSettingTab {
  constructor(
    app: App,
    private readonly plugin: SpicySideQuestsPlugin,
  ) {
    super(app, plugin);
  }

  hide() {
    this.plugin.onActivity = undefined;
  }

  display() {
    const { containerEl } = this;
    const s = this.plugin.settings;
    containerEl.empty();

    containerEl.createEl("p", {
      text: "Keeps a note in this vault in sync with the Spicy Side Quests addon in WoW Forever. Changes go both ways every time you /reload or log out in game.",
    });

    new Setting(containerEl)
      .setName("Side quests note")
      .setDesc("Any note in this vault. It's created on the first sync if it doesn't exist. Headings are categories.")
      .addText((t) => {
        t.setPlaceholder("Games/Side Quests.md").setValue(s.todoFile);
        const pick = (p: string) => void this.plugin.setTodoFile(p).then(() => this.display());
        new NoteSuggest(this.app, t.inputEl, pick);
        t.inputEl.addEventListener("change", () => pick(t.getValue()));
      });

    const wowOk = s.wowPath && isAddonInstalled(s.wowPath);
    new Setting(containerEl)
      .setName("WoW Forever folder")
      .setDesc(
        !s.wowPath
          ? "The folder that contains Interface and WTF, e.g. C:\\Program Files (x86)\\World of Warcraft\\_forever_"
          : wowOk
            ? "✓ Addon found."
            : `⚠ The addon isn't installed here (no ${addonDir(s.wowPath)}).`,
      )
      .addText((t) => {
        t.setPlaceholder("…\\World of Warcraft\\_forever_").setValue(s.wowPath);
        t.inputEl.addEventListener("change", async () => {
          s.wowPath = t.getValue().trim().replace(/^["']|["']$/g, "");
          await this.plugin.save();
          this.display();
          void this.plugin.sync(false);
        });
      })
      .addButton((b) =>
        b.setButtonText("Find").onClick(async () => {
          const found = detectWowPaths();
          if (!found.length) {
            new Notice("No WoW Forever install with the addon found in the usual places. Paste the folder path instead.");
            return;
          }
          s.wowPath = found[0];
          await this.plugin.save();
          this.display();
          void this.plugin.sync(false);
        }),
      );

    const accounts = s.wowPath ? listAccounts(s.wowPath) : [];
    if (accounts.length > 1) {
      new Setting(containerEl)
        .setName("WoW account")
        .setDesc("Auto picks the account you played most recently.")
        .addDropdown((d) => {
          d.addOption("auto", "Auto");
          for (const a of accounts) d.addOption(a, a);
          d.setValue(accounts.includes(s.account) ? s.account : "auto").onChange(async (v) => {
            s.account = v;
            await this.plugin.save();
            void this.plugin.sync(false);
          });
        });
    }

    new Setting(containerEl)
      .setName("Check for game changes every")
      .setDesc(`${s.pollSeconds} seconds`)
      .addSlider((sl) =>
        sl
          .setLimits(2, 30, 1)
          .setValue(s.pollSeconds)
          .onChange(async (v) => {
            s.pollSeconds = v;
            await this.plugin.save();
            this.plugin.restartTimer();
          }),
      );

    new Setting(containerEl)
      .setName("Sync now")
      .setDesc(this.plugin.problem() ?? "Also available from the command palette and by clicking 🌶 in the status bar.")
      .addButton((b) => b.setButtonText("Sync now").setCta().onClick(() => void this.plugin.sync(true)));

    containerEl.createEl("h3", { text: "Recent activity" });
    const log = containerEl.createDiv({ cls: "ssq-activity" });
    const render = () => {
      log.empty();
      if (!this.plugin.activity.length) log.createDiv({ text: "Nothing yet.", cls: "ssq-muted" });
      for (const line of this.plugin.activity) log.createDiv({ text: line });
    };
    render();
    this.plugin.onActivity = render;

    containerEl.createEl("p", {
      cls: "ssq-muted",
      text: "Safety: only todo lines in the note are ever rewritten. If the note goes missing or suddenly has no todos, syncing pauses instead of deleting anything in game.",
    });
  }
}
