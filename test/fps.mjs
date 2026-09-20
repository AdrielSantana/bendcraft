// fps.mjs <url> [seconds]: opens the page in headless Chrome, reads #bend-fps
// through the DevTools protocol, prints it and the console errors.
import { spawn } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const url = process.argv[2], secs = Number(process.argv[3] || 8), port = 9222 + Math.floor(Math.random() * 500);
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ["--headless=new", "--disable-gpu", "--no-sandbox", "--user-data-dir=" + mkdtempSync(join(tmpdir(), "cp-")),
   "--remote-debugging-port=" + port, "about:blank"], { stdio: "ignore", detached: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0, waits = new Map(), errors = [];
const send = (method, params = {}) => new Promise((res) => { const i = ++id; waits.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
try {
  let targets;
  for (let i = 0; i < 50 && !targets; i++) { await sleep(200); try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch {} }
  const page = targets.find((t) => t.type === "page");
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.onopen = r);
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waits.has(d.id)) { waits.get(d.id)(d.result); waits.delete(d.id); }
    if (d.method === "Runtime.exceptionThrown") errors.push(d.params.exceptionDetails.exception?.description?.split("\n")[0] || "exception");
    if (d.method === "Runtime.consoleAPICalled" && d.params.type === "error") errors.push(d.params.args.map((a) => a.value || a.description).join(" ").slice(0, 160)); };
  await send("Runtime.enable"); await send("Page.enable");
  await send("Page.navigate", { url });
  await sleep(secs * 1000);
  if (process.argv[4]) {
    await send("Runtime.evaluate", { expression: "var s = document.getElementById('bend-threads'); s.value = '" + process.argv[4] + "'; s.dispatchEvent(new Event('change'));" });
    await sleep(secs * 1000);
  }
  const r = await send("Runtime.evaluate", { expression: "JSON.stringify({fps: (document.getElementById('bend-rate') || document.getElementById('bend-fps'))?.textContent, sel: document.getElementById('bend-threads')?.value, opts: document.getElementById('bend-threads')?.options.length, q: location.search, out: document.getElementById('bend-out')?.textContent.slice(0, 200), iso: crossOriginIsolated, hidden: document.hidden, title: document.title})", returnByValue: true });
  console.log(url.replace(/^.*\//, ""), r.result.value, errors.length ? "ERRORS: " + [...new Set(errors)].slice(0, 3).join(" | ") : "");
} finally { try { process.kill(-chrome.pid, "SIGKILL"); } catch {} chrome.kill(); }
