// Bundles src/main.ts (and the shared sync engine from ../companion/src) into main.js.
// The plugin manifest lives at the repo root (../manifest.json), where Obsidian looks for it.
import { builtinModules } from "node:module";
import esbuild from "esbuild";

const watch = process.argv.includes("--watch");
const ctx = await esbuild.context({
  entryPoints: ["src/main.ts"],
  bundle: true,
  outfile: "main.js",
  format: "cjs",
  platform: "node", // desktop only: Node's fs is used to reach the WoW folder
  target: "es2022",
  external: ["obsidian", "electron", ...builtinModules, ...builtinModules.map((m) => `node:${m}`)],
  sourcemap: watch ? "inline" : false,
  legalComments: "none",
  logLevel: "info",
  banner: { js: "/* Spicy Side Quests: https://github.com/zednx/spicy-side-quests (MIT) */" },
});
if (watch) await ctx.watch();
else {
  await ctx.rebuild();
  await ctx.dispose();
}
