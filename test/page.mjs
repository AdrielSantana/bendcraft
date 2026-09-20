// mouse.mjs <url> <out-prefix>: opens Bendcraft, then: a left drag (look), a left click (break), a right click (place), space (jump, then land); hashes the canvas after each and reports fps
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const url = process.argv[2], out = process.argv[3], port = 9222 + Math.floor(Math.random() * 500);
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ["--headless=new", "--disable-gpu", "--no-sandbox", "--window-size=800,900", "--user-data-dir=" + mkdtempSync(join(tmpdir(), "cp-")), "--remote-debugging-port=" + port, "about:blank"], { stdio: "ignore", detached: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws, id = 0, waits = new Map(), errors = [];
const send = (method, params = {}) => new Promise((res) => { const i = ++id; waits.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
const grab = async (name) => { const r = await send("Runtime.evaluate", { expression: "document.getElementById('bend').toDataURL('image/png')", returnByValue: true }); writeFileSync(out + name + ".png", Buffer.from(r.result.value.split(",")[1], "base64"));
  const d = await send("Runtime.evaluate", { expression: "(() => { const c = document.getElementById('bend'); const x = c.getContext('2d').getImageData(0,0,c.width,c.height).data; let h = 0; for (let i = 0; i < x.length; i += 4) h = (h * 31 + x[i] + x[i+1] * 7 + x[i+2] * 13) >>> 0; return h; })()", returnByValue: true }); return d.result.value; };
const mouse = (type, x, y, button, extra = {}) => send("Input.dispatchMouseEvent", { type, x, y, button, clickCount: 1, ...extra });
try {
  let targets;
  for (let i = 0; i < 50 && !targets; i++) { await sleep(200); try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch {} }
  ws = new WebSocket(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await new Promise((r) => ws.onopen = r);
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && waits.has(d.id)) { waits.get(d.id)(d.result); waits.delete(d.id); }
    if (d.method === "Runtime.exceptionThrown") errors.push(d.params.exceptionDetails.exception?.description?.split("\n")[0]); };
  await send("Runtime.enable"); await send("Page.navigate", { url }); await sleep(6000);
  const rc = await send("Runtime.evaluate", { expression: "(() => { const r = document.getElementById('bend').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()", returnByValue: true });
  const [cx, cy] = rc.result.value;
  const h0 = await grab("0");
  // a drag of 120 px to the right: the camera turns, no block breaks
  await mouse("mousePressed", cx, cy, "left"); await sleep(50);
  for (let i = 1; i <= 6; i++) { await mouse("mouseMoved", cx + 20 * i, cy, "left", { buttons: 1 }); await sleep(40); }
  await mouse("mouseReleased", cx + 120, cy, "left"); await sleep(600);
  const h1 = await grab("1");
  // a left click: the block under the crosshair breaks
  await mouse("mousePressed", cx, cy, "left"); await sleep(50); await mouse("mouseReleased", cx, cy, "left"); await sleep(600);
  const h2 = await grab("2");
  // a right click: a block is placed
  await mouse("mousePressed", cx, cy, "right"); await sleep(50); await mouse("mouseReleased", cx, cy, "right"); await sleep(600);
  const h3 = await grab("3");
  // space: a jump, then the landing brings the same view back
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: " ", code: "Space", windowsVirtualKeyCode: 32 }); await sleep(60);
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: " ", code: "Space", windowsVirtualKeyCode: 32 }); await sleep(500);
  const h4 = await grab("4"); await sleep(3000); const h5 = await grab("5");
  const f = await send("Runtime.evaluate", { expression: "document.body.innerText.match(/\\d+ fps/)?.[0] || ''", returnByValue: true });
  console.log("hashes", h0, h1, h2, h3, h4, h5, "| drag turned:", h0 !== h1, "click broke:", h1 !== h2, "right placed:", h2 !== h3, "jump rose:", h3 !== h4, "landed back:", h5 === h3, "|", f.result.value, errors.length ? "ERRORS " + errors.join(" | ") : "");
} finally { try { process.kill(-chrome.pid, "SIGKILL"); } catch {} chrome.kill(); }
