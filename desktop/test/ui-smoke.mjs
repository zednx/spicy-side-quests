// UI smoke test: runs the built front end (dist/) in headless Chromium with the Rust
// backend replaced by an in-memory file system, then clicks through the app.
//   node build.mjs && node test/ui-smoke.mjs [screenshot-dir]
import http from "node:http";
import fsp from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const dist = path.join(import.meta.dirname, "..", "dist");
const shots = process.argv[2];

const server = http.createServer(async (req, res) => {
  try {
    const file = path.join(dist, decodeURIComponent(new URL(req.url, "http://x").pathname).replace(/^\/$/, "/index.html"));
    if (!file.startsWith(dist)) throw new Error("outside dist");
    const type = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png" }[path.extname(file)] ?? "application/octet-stream";
    res.writeHead(200, { "content-type": type }).end(await fsp.readFile(file));
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = `http://127.0.0.1:${server.address().port}/`;

const now = Math.floor(Date.now() / 1000);
const files = {
  "/home/me/.config/spicysidequests/config.json": JSON.stringify({ todoFile: "/home/me/notes/Side Quests.md", wowPath: "/wow/_forever_", account: "auto", pollSeconds: 1 }),
  "/home/me/notes/Side Quests.md": "# Side Quests\n\n## Professions\n- [ ] Farm Arcanite #farming [zone:: Winterspring] [xy:: 63.2, 45.1] ^a1b2c3\n- [x] Learn Alchemy ^d4e5f6\n\n## Dungeons\n- [ ] Run SM Cathedral with the guild #group ^g7h8i9\n",
  "/wow/_forever_/Interface/AddOns/SpicySideQuests/SpicySideQuests.toc": "",
  "/wow/_forever_/WTF/Account/ME/SavedVariables/SpicySideQuests.lua": `SpicySideQuestsDB = { items = { ["k2x9aa"] = { id = "k2x9aa", text = "Find the Un'Goro pylons", category = "Exploring", tags = { "explore" }, zone = "Un'Goro Crater", x = 44.2, y = 11.8, done = false, created = ${now}, updated = ${now} } } }`,
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 960, height: 700 }, deviceScaleFactor: 2, colorScheme: "dark" });
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("dialog", (d) => d.accept());
await page.addInitScript((initial) => {
  const files = new Map(Object.entries(initial));
  const mtimes = new Map();
  const dirs = () => {
    const out = new Set();
    for (const f of files.keys()) {
      const parts = f.split("/");
      for (let i = 1; i < parts.length; i++) out.add(parts.slice(0, i).join("/") || "/");
    }
    return out;
  };
  window.__fakeFiles = files;
  window.__TAURI_INTERNALS__ = {
    transformCallback: () => 0,
    invoke: async (cmd, args) => {
      switch (cmd) {
        case "env_info":
          return { platform: "linux", home: "/home/me", configRoot: "/home/me/.config" };
        case "read_text":
          return files.has(args.path) ? files.get(args.path) : null;
        case "write_text":
          files.set(args.path, args.text);
          mtimes.set(args.path, Date.now());
          return null;
        case "file_info":
          if (files.has(args.path)) return { mtimeMs: mtimes.get(args.path) ?? 1000, size: files.get(args.path).length, isDir: false };
          return dirs().has(args.path) ? { mtimeMs: 0, size: 0, isDir: true } : null;
        case "list_dir": {
          const prefix = args.path.replace(/\/$/, "") + "/";
          const names = new Set();
          for (const p of [...files.keys(), ...dirs()]) if (p.startsWith(prefix)) names.add(p.slice(prefix.length).split("/")[0]);
          return [...names].filter(Boolean);
        }
        default:
          throw new Error(`unexpected command ${cmd}`);
      }
    },
  };
}, files);

const check = (cond, msg) => {
  if (!cond) throw new Error(`FAIL: ${msg}`);
  console.log(`ok   ${msg}`);
};
const md = () => page.evaluate(() => window.__fakeFiles.get("/home/me/notes/Side Quests.md"));
const inbox = () => page.evaluate(() => window.__fakeFiles.get("/wow/_forever_/Interface/AddOns/SpicySideQuests/Inbox.lua") ?? "");

try {
  await page.goto(url);
  await page.waitForFunction(() => document.getElementById("status")?.textContent?.startsWith("Synced"), null, { timeout: 10000 });
  check(true, "first sync completes");
  check((await md()).includes("## Exploring\n- [ ] Find the Un'Goro pylons #explore [zone:: Un'Goro Crater] [xy:: 44.2, 11.8] ^k2x9aa"), "game side quest written to the markdown file");
  check((await inbox()).includes('text = "Run SM Cathedral with the guild"'), "markdown side quests written to Inbox.lua");
  await page.waitForSelector("text=Find the Un'Goro pylons");
  check(true, "side quests tab shows the game's side quest");

  // add through the UI
  await page.fill(".add .cat", "Dungeons");
  await page.fill(".add .grow", "Clear Scarlet Library #group");
  await page.click(".add button");
  await page.waitForFunction(() => window.__fakeFiles.get("/home/me/notes/Side Quests.md").includes("Clear Scarlet Library #group ^"), null, { timeout: 5000 });
  check(true, "adding a side quest writes it to the file and gives it an id");
  await page.waitForFunction(() => (window.__fakeFiles.get("/wow/_forever_/Interface/AddOns/SpicySideQuests/Inbox.lua") ?? "").includes("Clear Scarlet Library"), null, { timeout: 5000 });
  check(true, "and syncs it to the game");

  // tick one off
  await page.locator("li", { hasText: "Farm Arcanite" }).locator("input[type=checkbox]").check();
  await page.waitForFunction(() => window.__fakeFiles.get("/home/me/notes/Side Quests.md").includes("- [x] Farm Arcanite"), null, { timeout: 5000 });
  check(true, "ticking a side quest marks it done in the file");

  // escaping: hostile text shows as text, not HTML
  await page.fill(".add .grow", '<img src=x onerror="window.__pwned=1"> sneaky');
  await page.click(".add button");
  await page.waitForSelector("text=sneaky");
  check(!(await page.evaluate(() => window.__pwned)), "user text is shown as text, never run as HTML");

  if (shots) await page.screenshot({ path: path.join(shots, "desktop-quests.png") });

  // markdown tab
  await page.click("button[data-tab=markdown]");
  const value = await page.inputValue("textarea.editor");
  check(value.includes("## Exploring"), "markdown tab shows the file");
  await page.fill("textarea.editor", value + "\n## Raids\n- [ ] Molten Core attunement\n");
  check((await page.textContent("#status")).startsWith("Paused"), "syncing pauses while there are unsaved edits");
  if (shots) await page.screenshot({ path: path.join(shots, "desktop-markdown.png") });
  await page.click(".toolbar button.primary");
  await page.waitForFunction(() => (window.__fakeFiles.get("/wow/_forever_/Interface/AddOns/SpicySideQuests/Inbox.lua") ?? "").includes("Molten Core attunement"), null, { timeout: 5000 });
  check(true, "saving the markdown syncs the new side quest to the game");

  // settings tab
  await page.click("button[data-tab=settings]");
  await page.waitForSelector("text=✓ Addon found.");
  check(true, "settings recognise the WoW folder");
  if (shots) await page.screenshot({ path: path.join(shots, "desktop-settings.png") });

  check(errors.length === 0, `no page errors ${errors.join("; ")}`);
  console.log("UI smoke test passed");
} finally {
  await browser.close();
  server.close();
}
