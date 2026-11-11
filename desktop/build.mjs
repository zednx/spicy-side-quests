// Builds the app's web front end into dist/ (bundled with the shared sync engine).
import { copyFileSync, mkdirSync } from "node:fs";
import esbuild from "esbuild";

mkdirSync("dist", { recursive: true });
for (const f of ["index.html", "app.css", "chilli.png"]) copyFileSync(`src/${f}`, `dist/${f}`);
await esbuild.build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  outfile: "dist/app.js",
  format: "iife",
  platform: "browser",
  target: "es2022",
  legalComments: "none",
  logLevel: "info",
});
