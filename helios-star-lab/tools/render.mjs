// Headless frame capture (SwiftShader), driving the shader's own UI with the mouse.
//
//   node tools/render.mjs --w 960 --h 540 frames=20 shot=sun star=4 frames=20 shot=betelgeuse
//
// Steps run in order:
//   frames=N        render N frames at 60 fps
//   star=K          click star K in the picker (0 Sun .. 7 Sirius B)
//   click=ID        click a control: euv, visible, field, pause, zin, zout, hide
//   slider=K:V      drag slider K (0 T, 1 R, 2 rotation, 3 cycle) to V in 0..1
//   orbit=DX:DY     drag on the scene by DX, DY screen pixels
//   shot=NAME       save shots/NAME.png
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const args = process.argv.slice(2);
const opt = { w: 960, h: 540 };
const steps = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--w') opt.w = +args[++i];
  else if (args[i] === '--h') opt.h = +args[++i];
  else steps.push(args[i].split('='));
}
const s = Math.min(opt.w / 960, opt.h / 540);
const ui = (x, y) => [x * s + 0.5 * (opt.w - 960 * s), y * s];
const starX = [20, 57, 115, 180, 252, 338, 396, 447], starW = [3, 6, 7, 8, 10, 6, 5, 8].map((n) => 7 * n);
const controls = { visible: [575, 54], euv: [632, 54], field: [690, 54], pause: [757, 54], zout: [814, 54], zin: [875, 54], hide: [915, 54], show: [915, 18] };

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: opt.w, height: opt.h } });
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
page.setDefaultTimeout(0);
await page.goto('file://' + path.join(root, `viewer.html?manual&w=${opt.w}&h=${opt.h}`));
await page.waitForFunction(() => window.ST);
await page.waitForFunction(() => ST.mediaReady());
const err = await page.evaluate(() => ST.errors());
if (err) { console.log(err); await browser.close(); process.exit(1); }

const frames = (n) => page.evaluate((n) => ST.renderFrames(n, 1 / 60), n);
async function press(x, y, x2 = x, y2 = y, n = 6) {
  await page.evaluate(([x, y, x2, y2, n]) => {
    for (let i = 0; i <= n; i++) { ST.setMouse(x + (x2 - x) * i / n, y + (y2 - y) * i / n, true); ST.renderFrames(1, 1 / 60); }
    ST.setMouse(x2, y2, false); ST.renderFrames(1, 1 / 60);
  }, [x, y, x2, y2, n]);
}
fs.mkdirSync(path.join(root, 'shots'), { recursive: true });
for (const [k, v] of steps) {
  const t0 = Date.now();
  if (k === 'frames') await frames(+v);
  else if (k === 'star') await press(...ui(starX[+v] + starW[+v] / 2, 54));
  else if (k === 'click') await press(...ui(...controls[v]));
  else if (k === 'slider') {
    const [id, val] = v.split(':').map(Number), x0 = 20 + id * 235;
    const [ax, ay] = ui(x0 + 105, 12), [bx, by] = ui(x0 + 210 * val, 12);
    await press(ax, ay, bx, by, 8);
  } else if (k === 'orbit') {
    const [dx, dy] = v.split(':').map(Number);
    await press(opt.w / 2, opt.h / 2, opt.w / 2 + dx, opt.h / 2 + dy, 10);
  } else if (k === 'shot') {
    const url = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
    fs.writeFileSync(path.join(root, 'shots', v + '.png'), Buffer.from(url.split(',')[1], 'base64'));
  }
  console.log(`${k}=${v ?? ''} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}
const e2 = await page.evaluate(() => ST.errors());
if (e2) console.log(e2);
await browser.close();
