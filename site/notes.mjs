// notes.mjs <index.html>: after `bun main.ts main.bend -o site/index.html`,
// gives the page its title, the service worker that adds the COOP/COEP
// headers GitHub Pages lacks, and a note with the controls. Idempotent.
import { readFileSync, writeFileSync } from "node:fs";
const path = process.argv[2];
let s = readFileSync(path, "utf8");
const MARK = "<!-- bendcraft notes -->";
if (s.includes(MARK)) { console.log("kept " + path); process.exit(0); }
s = s.replace("<title>main</title>", "<title>Bendcraft</title>");
s = s.replace('<script src="index.js"></script>', '<script src="coi-serviceworker.js"></script>\n<script src="index.js"></script>');
s = s.replace('<pre id="bend-out"></pre>', `<pre id="bend-out"></pre>
${MARK}
<p style="max-width: 512px">
  <b>Bendcraft</b>: an endless voxel world written in <a href="https://github.com/bendlang/bend">Bend</a>,
  rendered by one parallel call on every core of your machine.
  <b>WASD</b> walk · <b>space</b> jumps · drag the mouse to look (or arrows) · click breaks ·
  right click places (or J/L) · Esc quits. The world is seeded noise; what you build is kept
  when you walk away and come back.
  Source and the native GPU build: <a href="https://github.com/AdrielSantana/bendcraft">AdrielSantana/bendcraft</a>.
</p>
<p style="max-width: 512px; color: #888">
  Needs a browser with SharedArrayBuffer and wasm tail calls: Chrome 112+, Firefox 121+, Safari 18.2+.
  GitHub Pages sends no COOP/COEP headers, so a small service worker adds them and reloads the page once on your first visit.
</p>`);
writeFileSync(path, s);
console.log("edited " + path);
