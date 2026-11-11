// Spicy Side Quests desktop app. Runs the shared sync engine in the background and lets you
// view and edit your side quests (or the raw markdown). Settings and sync history are the
// same files the companion scripts use, so you can switch between them.
import { open, save } from "@tauri-apps/plugin-dialog";
import {
  addonDirWith,
  detectWowPathsWith,
  findSavedVariablesWith,
  isAddonInstalledWith,
  listAccountsWith,
  stateFromJSON,
  syncOnceWith,
  type Config,
  type State,
} from "../../companion/src/engine.ts";
import { dict, terminalSafe } from "../../companion/src/types.ts";
import { addTodo, deleteLine, editText, sections, StaleLine, toggleDone, type Row } from "./edit.ts";
import { envInfo, pathOps, tauriFs, type EnvInfo } from "./tauri-fs.ts";

const VERSION = "0.3.0";

// --- tiny DOM helper (text only, never HTML) -------------------------------------------
type Attrs = Record<string, string | boolean | ((e: Event) => void)>;
function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Attrs = {}, ...kids: (Node | string | null | undefined | false)[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (typeof v === "function") el.addEventListener(k.replace(/^on/, "").toLowerCase(), v);
    else if (typeof v === "boolean") (el as unknown as Record<string, boolean>)[k] = v;
    else el.setAttribute(k, v);
  }
  for (const kid of kids) if (kid !== null && kid !== undefined && kid !== false) el.append(kid);
  return el;
}
const $ = (id: string) => document.getElementById(id)!;

// --- app state ---------------------------------------------------------------------------
let env: EnvInfo;
let fs: ReturnType<typeof tauriFs>;
let paths: ReturnType<typeof pathOps>;
let configFile = "";
let stateFile = "";
let cfg: Config = { todoFile: "", wowPath: "", account: "auto", pollSeconds: 2 };
let state: State = { base: dict() };
let busy = false;
let again = false; // a sync was asked for while one was running
let lastSig = "";
let mdText = ""; // what's on disk, as last read
let editorDirty = false;
const activity: string[] = [];

function log(msg: string, warn = false) {
  activity.unshift(`${new Date().toTimeString().slice(0, 8)} ${warn ? "⚠ " : ""}${terminalSafe(msg)}`);
  activity.length = Math.min(activity.length, 200);
  if (currentTab === "activity") renderActivity();
}

function setStatus(text: string, kind: "ok" | "wait" | "bad" = "ok") {
  const el = $("status");
  el.textContent = text;
  el.className = `status ${kind}`;
}

// --- settings (shared with the companion scripts) --------------------------------------
async function loadSettings() {
  const dir = paths.join(env.configRoot, env.platform === "windows" ? "SpicySideQuests" : "spicysidequests");
  configFile = paths.join(dir, "config.json");
  stateFile = paths.join(dir, "state.json");
  try {
    const raw = JSON.parse((await fs.readText(configFile)) ?? "{}");
    cfg = {
      todoFile: String(raw.todoFile ?? ""),
      wowPath: String(raw.wowPath ?? ""),
      account: String(raw.account ?? "auto"),
      pollSeconds: Number(raw.pollSeconds) > 0 ? Number(raw.pollSeconds) : 2,
    };
  } catch {
    log("Couldn't read settings; starting fresh.", true);
  }
  try {
    state = stateFromJSON(JSON.parse((await fs.readText(stateFile)) ?? "{}"));
  } catch {
    state = { base: dict() };
  }
}

async function saveSettings() {
  await fs.writeText(configFile, JSON.stringify(cfg, null, 2) + "\n");
}

async function problem(): Promise<string | undefined> {
  if (!cfg.todoFile) return "Choose your markdown file in Settings";
  if (!cfg.wowPath) return "Choose your WoW folder in Settings";
  if (!(await fs.info(cfg.wowPath))) return "WoW folder not found";
  if (!(await isAddonInstalledWith(fs, cfg.wowPath))) return "The addon isn't installed in that WoW folder";
  return undefined;
}

// --- sync -------------------------------------------------------------------------------
async function signature(): Promise<string> {
  const sv = await findSavedVariablesWith(fs, cfg);
  const parts = await Promise.all([cfg.todoFile, sv ?? ""].map(async (p) => (p ? JSON.stringify(await fs.info(p)) : "-")));
  return parts.join("|");
}

async function sync(manual: boolean) {
  const p = await problem();
  if (p) {
    setStatus(p, "bad");
    if (manual) switchTab("settings");
    return;
  }
  if (editorDirty) {
    setStatus("Paused: save or discard your markdown edits", "wait");
    return;
  }
  if (busy) {
    again = true; // run once more when the current pass finishes
    return;
  }
  busy = true;
  try {
    const changes: string[] = [];
    const next = await syncOnceWith(fs, cfg, state, {
      log: (m) => {
        changes.push(m);
        log(m);
      },
      warn: (m) => log(m, true),
    });
    if (next) {
      state = next;
      await fs.writeText(stateFile, JSON.stringify({ base: state.base }, null, 2));
      setStatus(`Synced ${new Date().toTimeString().slice(0, 5)}`);
    } else {
      setStatus("Sync paused (see Activity)", "wait");
    }
    lastSig = await signature();
    if (manual && !changes.length) log("Already in sync.");
    await reloadNote();
  } catch (e) {
    setStatus("Sync failed (see Activity)", "bad");
    log(`Sync failed: ${e instanceof Error ? e.message : String(e)}`, true);
  } finally {
    busy = false;
    if (again) {
      again = false;
      void sync(false);
    }
  }
}

let timer: number | undefined;
function startTimer() {
  if (timer) clearInterval(timer);
  timer = window.setInterval(async () => {
    if (busy || (await problem())) return;
    if ((await signature()) !== lastSig) await sync(false);
  }, Math.max(1, cfg.pollSeconds) * 1000);
}

// --- tabs ---------------------------------------------------------------------------------
type Tab = "quests" | "markdown" | "settings" | "activity";
let currentTab: Tab = "quests";

function switchTab(tab: Tab) {
  if (currentTab === "markdown" && tab !== "markdown" && editorDirty && !confirm("Discard your unsaved markdown edits?")) return;
  if (currentTab === "markdown" && tab !== "markdown" && editorDirty) {
    editorDirty = false;
    void sync(false);
  }
  currentTab = tab;
  for (const b of document.querySelectorAll<HTMLButtonElement>(".tabs button")) b.classList.toggle("active", b.dataset.tab === tab);
  const view = $("view");
  view.replaceChildren();
  if (tab === "quests") renderQuests();
  if (tab === "markdown") renderMarkdownEditor();
  if (tab === "settings") void renderSettings();
  if (tab === "activity") renderActivity();
}

async function reloadNote() {
  mdText = cfg.todoFile ? ((await fs.readText(cfg.todoFile)) ?? "") : "";
  if (currentTab === "quests") renderQuests();
  if (currentTab === "markdown" && !editorDirty) renderMarkdownEditor();
}

// --- Side quests tab ----------------------------------------------------------------------
async function applyEdit(fn: (src: string) => string) {
  const current = (await fs.readText(cfg.todoFile)) ?? "";
  try {
    const next = fn(current);
    await fs.writeText(cfg.todoFile, next);
    mdText = next;
    renderQuests(true);
    void sync(false);
  } catch (e) {
    if (e instanceof StaleLine) {
      mdText = current;
      renderQuests(true);
    }
    alert(e instanceof Error ? e.message : String(e));
  }
}

function questRow(row: Row) {
  const it = row.item;
  const text = h("span", { class: "text", title: "Click to edit" }, it.text);
  const li = h(
    "li",
    { class: it.done ? "done" : "" },
    h("input", { type: "checkbox", checked: it.done, "aria-label": "Done", onchange: () => applyEdit((s) => toggleDone(s, row.line, row.raw)) }),
    text,
    ...it.tags.map((t) => h("span", { class: "tag" }, "#" + t)),
    it.zone ? h("span", { class: "zone", title: "Location" }, it.x !== undefined ? `${it.zone} ${it.x}, ${it.y}` : it.zone) : null,
    h("button", { class: "icon", title: "Delete", "aria-label": "Delete", onclick: () => confirm(`Delete "${it.text}"?`) && applyEdit((s) => deleteLine(s, row.line, row.raw)) }, "✕"),
  );
  text.addEventListener("click", () => {
    const input = h("input", { class: "inline", value: [it.text, ...it.tags.map((t) => "#" + t)].join(" ") });
    let finished = false;
    const done = (saveIt: boolean) => {
      if (finished) return;
      finished = true;
      inlineEditing = false;
      if (saveIt && input.value.trim() && input.value !== input.defaultValue) void applyEdit((s) => editText(s, row.line, row.raw, input.value));
      else renderQuests(true);
    };
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") done(true);
      if (e.key === "Escape") done(false);
    });
    input.addEventListener("blur", () => done(true));
    inlineEditing = true;
    text.replaceWith(input);
    input.focus();
    input.select();
  });
  return li;
}

// The add box is built once per visit to the tab; syncs only redraw the list below it,
// so text you're typing (or an item you're editing) is never wiped by a background sync.
let questForm: { form: HTMLFormElement; cat: HTMLInputElement; text: HTMLInputElement; list: HTMLElement; datalist: HTMLDataListElement } | undefined;
let inlineEditing = false;
let renderedText: string | undefined;

function renderQuests(force = false) {
  if (currentTab !== "quests") return;
  const view = $("view");
  if (!cfg.todoFile) {
    questForm = undefined;
    view.replaceChildren(h("p", { class: "empty" }, "Choose your markdown file in Settings to get started."));
    return;
  }
  if (!questForm || !view.contains(questForm.form)) {
    const cat = h("input", { list: "cats", placeholder: "Category", class: "cat" });
    const text = h("input", { placeholder: "New side quest… #tag", class: "grow" });
    const add = () => {
      if (!text.value.trim()) return;
      const [c, t] = [cat.value, text.value];
      text.value = "";
      text.focus();
      void applyEdit((src) => addTodo(src, c, t));
    };
    const form = h("form", { class: "add", onsubmit: (e) => (e.preventDefault(), add()) }, cat, text, h("button", { type: "submit", class: "primary" }, "Add"));
    const datalist = h("datalist", { id: "cats" });
    const list = h("div", {});
    view.replaceChildren(form, datalist, list);
    questForm = { form, cat, text, list, datalist };
    renderedText = undefined;
  }
  if (inlineEditing || (!force && renderedText === mdText)) return;
  renderedText = mdText;

  const secs = sections(mdText);
  const cats = secs.map((x) => x.category);
  if (!questForm.cat.value) questForm.cat.value = cats[0] ?? "General";
  questForm.datalist.replaceChildren(...cats.map((c) => h("option", { value: c })));
  const list = questForm.list;
  if (!secs.some((x) => x.rows.length)) {
    list.replaceChildren(h("p", { class: "empty" }, "No side quests yet. Add one above, or in game with /ssq add."));
    return;
  }
  list.replaceChildren(
    ...secs
      .filter((x) => x.rows.length)
      .map((x) => {
        const open = x.rows.filter((r) => !r.item.done).length;
        return h("section", {}, h("h2", {}, x.category, h("span", { class: "count" }, ` ${open}/${x.rows.length}`)), h("ul", { class: "quests" }, ...x.rows.map(questRow)));
      }),
  );
}

// --- Markdown tab ----------------------------------------------------------------------------
function renderMarkdownEditor() {
  if (currentTab !== "markdown") return;
  const view = $("view");
  view.replaceChildren();
  if (!cfg.todoFile) {
    view.append(h("p", { class: "empty" }, "Choose your markdown file in Settings first."));
    return;
  }
  const area = h("textarea", { class: "editor", spellcheck: false });
  area.value = mdText;
  const saveBtn = h("button", { class: "primary", disabled: true }, "Save");
  const discardBtn = h("button", { disabled: true }, "Discard");
  const note = h("span", { class: "muted" }, "Syncing pauses while you have unsaved edits.");
  const setDirty = (d: boolean) => {
    editorDirty = d;
    saveBtn.disabled = !d;
    discardBtn.disabled = !d;
    if (d) setStatus("Paused: save or discard your markdown edits", "wait");
  };
  area.addEventListener("input", () => setDirty(area.value !== mdText));
  saveBtn.addEventListener("click", async () => {
    const onDisk = (await fs.readText(cfg.todoFile)) ?? "";
    if (onDisk !== mdText && !confirm("The file changed on disk since you opened it. Overwrite it with your version?")) return;
    await fs.writeText(cfg.todoFile, area.value);
    mdText = area.value;
    setDirty(false);
    log("Saved the markdown file.");
    void sync(false);
  });
  discardBtn.addEventListener("click", async () => {
    setDirty(false);
    await reloadNote();
    renderMarkdownEditor();
  });
  area.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
      e.preventDefault();
      if (!saveBtn.disabled) saveBtn.click();
    }
  });
  view.append(h("div", { class: "toolbar" }, saveBtn, discardBtn, note), area);
}

// --- Settings tab ----------------------------------------------------------------------------
async function renderSettings() {
  const view = $("view");
  const fileInput = h("input", { value: cfg.todoFile, placeholder: "C:\\Users\\you\\Documents\\Side Quests.md", class: "grow" });
  const wowInput = h("input", { value: cfg.wowPath, placeholder: "C:\\Program Files (x86)\\World of Warcraft\\_forever_", class: "grow" });
  const wowState = h("p", { class: "hint" });
  const accountSel = h("select", {});
  const pollInput = h("input", { type: "number", min: "1", max: "60", value: String(cfg.pollSeconds), class: "small" });

  const refreshWow = async () => {
    const ok = await isAddonInstalledWith(fs, cfg.wowPath);
    wowState.textContent = !cfg.wowPath ? "The folder that contains Interface and WTF." : ok ? "✓ Addon found." : `⚠ The addon isn't installed here (no ${addonDirWith(fs, cfg.wowPath)}).`;
    wowState.className = `hint ${cfg.wowPath ? (ok ? "good" : "bad") : ""}`;
    const accounts = await listAccountsWith(fs, cfg.wowPath);
    accountSel.replaceChildren(h("option", { value: "auto" }, "Auto (the one you played last)"), ...accounts.map((a) => h("option", { value: a }, a)));
    accountSel.value = accounts.includes(cfg.account) ? cfg.account : "auto";
    accountSel.disabled = accounts.length < 2;
  };

  const setFile = async (p: string) => {
    p = p.trim().replace(/^["']|["']$/g, "");
    if (p && !p.toLowerCase().endsWith(".md")) p += ".md";
    if (p === cfg.todoFile) return;
    const changed = !!cfg.todoFile;
    cfg.todoFile = p;
    fileInput.value = p;
    // A different file has different todos: forget the old sync history so nothing gets deleted.
    state = { base: dict() };
    await fs.writeText(stateFile, JSON.stringify({ base: {} }));
    await saveSettings();
    if (changed) log("Markdown file changed: the next sync merges both sides and deletes nothing.");
    await reloadNote();
    void sync(false);
  };
  const setWow = async (p: string) => {
    cfg.wowPath = p.trim().replace(/^["']|["']$/g, "");
    wowInput.value = cfg.wowPath;
    await saveSettings();
    await refreshWow();
    void sync(false);
  };

  fileInput.addEventListener("change", () => setFile(fileInput.value));
  wowInput.addEventListener("change", () => setWow(wowInput.value));
  accountSel.addEventListener("change", async () => {
    cfg.account = accountSel.value;
    await saveSettings();
    void sync(false);
  });
  pollInput.addEventListener("change", async () => {
    cfg.pollSeconds = Math.min(60, Math.max(1, Number(pollInput.value) || 2));
    pollInput.value = String(cfg.pollSeconds);
    await saveSettings();
    startTimer();
  });

  const browseFile = async () => {
    const p = await open({ multiple: false, directory: false, filters: [{ name: "Markdown", extensions: ["md"] }] });
    if (typeof p === "string") await setFile(p);
  };
  const newFile = async () => {
    const p = await save({ defaultPath: "Side Quests.md", filters: [{ name: "Markdown", extensions: ["md"] }] });
    if (typeof p === "string") await setFile(p);
  };
  const browseWow = async () => {
    const p = await open({ multiple: false, directory: true });
    if (typeof p === "string") await setWow(p);
  };
  const findWow = async () => {
    const found = await detectWowPathsWith(fs, env.platform, env.home);
    if (found.length) await setWow(found[0]);
    else alert("Couldn't find WoW Forever with the addon in the usual places. Use Browse to pick the folder that contains Interface and WTF.");
  };

  const welcome = !cfg.todoFile || !cfg.wowPath ? [h("p", { class: "welcome" }, "Welcome! Pick your markdown file (any .md file, e.g. an Obsidian note) and your WoW Forever folder. Syncing starts straight away.")] : [];
  view.replaceChildren(
    ...welcome,
    h("label", {}, "Markdown file"),
    h("div", { class: "row" }, fileInput, h("button", { onclick: browseFile }, "Browse…"), h("button", { onclick: newFile }, "New file…")),
    h("p", { class: "hint" }, "Your side quests are kept here. Headings are categories; anything else in the file is left alone."),
    h("label", {}, "WoW Forever folder"),
    h("div", { class: "row" }, wowInput, h("button", { onclick: browseWow }, "Browse…"), h("button", { onclick: findWow }, "Find")),
    wowState,
    h("label", {}, "WoW account"),
    h("div", { class: "row" }, accountSel),
    h("label", {}, "Check for changes every (seconds)"),
    h("div", { class: "row" }, pollInput),
    h("p", { class: "hint" }, `Settings are shared with the sync scripts: ${configFile}`),
  );
  await refreshWow();
}

// --- Activity tab ------------------------------------------------------------------------------
function renderActivity() {
  if (currentTab !== "activity") return;
  const view = $("view");
  view.replaceChildren(
    activity.length ? h("ul", { class: "log" }, ...activity.map((l) => h("li", { class: l.includes("⚠") ? "warn" : "" }, l))) : h("p", { class: "empty" }, "Nothing yet."),
  );
}

// --- start -------------------------------------------------------------------------------------
async function main() {
  env = await envInfo();
  fs = tauriFs(env.platform);
  paths = pathOps(env.platform);
  $("version").textContent = `v${VERSION}`;
  for (const b of document.querySelectorAll<HTMLButtonElement>(".tabs button")) b.addEventListener("click", () => switchTab(b.dataset.tab as Tab));
  $("sync").addEventListener("click", () => void sync(true));
  await loadSettings();
  await reloadNote();
  const p = await problem();
  switchTab(p ? "settings" : "quests");
  setStatus(p ?? "Starting…", p ? "bad" : "wait");
  await sync(false);
  startTimer();
  window.addEventListener("focus", () => void reloadNote());
}

main().catch((e) => {
  document.body.textContent = `Spicy Side Quests couldn't start: ${e instanceof Error ? e.message : String(e)}`;
});
