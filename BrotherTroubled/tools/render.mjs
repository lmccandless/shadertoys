// Headless frame capture (SwiftShader) for checking the shader without a GPU.
//
//   node tools/render.mjs --w 800 --h 668 --frames 16 --out shots/latest.png
//   node tools/render.mjs --drag 0.5 0 --frames 24 --out shots/right.png   # orbit test
//
// --frames N : total frames rendered (default 16; the 16-sample jitter converges by then)
// --drag X Y : drag from the canvas centre by (X, Y) fractions of the canvas, then release
// --dbl      : double-click first (orbit reset test)
// --probe    : print the camera-state texels of Buffer A after rendering
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const args = process.argv.slice(2);
const opt = { w: 800, h: 668, frames: 16, out: 'shots/latest.png', drag: null, dbl: false, probe: false, page: 'viewer.html' };
for (let i = 0; i < args.length; i++) {
  const a = args[i], v = args[i + 1];
  if (a === '--w') opt.w = +v, i++;
  else if (a === '--h') opt.h = +v, i++;
  else if (a === '--frames') opt.frames = +v, i++;
  else if (a === '--out') opt.out = v, i++;
  else if (a === '--page') opt.page = v, i++;
  else if (a === '--drag') opt.drag = [+v, +args[i + 2]], i += 2;
  else if (a === '--dbl') opt.dbl = true;
  else if (a === '--probe') opt.probe = true;
}
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: opt.w, height: opt.h } });
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
page.setDefaultTimeout(0);
await page.goto('file://' + path.join(root, `${opt.page}?manual&w=${opt.w}&h=${opt.h}`));
await page.waitForFunction(() => window.ST);
const err = await page.evaluate(() => ST.errors());
if (err) { console.log(err); await browser.close(); process.exit(1); }

const t0 = Date.now();
const dt = 1 / 60;
await page.evaluate(([n, dt]) => ST.renderFrames(n, dt), [3, dt]);            // atlas + first frames
if (opt.dbl) {
  await page.evaluate(([w, h, dt]) => {
    for (let k = 0; k < 2; k++) { ST.setMouse(w / 2, h / 2, true); ST.renderFrames(1, dt); ST.setMouse(w / 2, h / 2, false); ST.renderFrames(3, dt); }
  }, [opt.w, opt.h, dt]);
}
if (opt.drag) {
  await page.evaluate(([w, h, dx, dy, dt]) => {
    const x0 = w / 2, y0 = h / 2;
    ST.setMouse(x0, y0, true); ST.renderFrames(1, dt);
    for (let s = 1; s <= 8; s++) { ST.setMouse(x0 + dx * w * s / 8, y0 + dy * h * s / 8, true); ST.renderFrames(1, dt); }
    ST.setMouse(x0 + dx * w, y0 + dy * h, false);
  }, [opt.w, opt.h, opt.drag[0], opt.drag[1], dt]);
}
await page.evaluate(([n, dt]) => ST.renderFrames(n, dt), [opt.frames, dt]);
const url = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
const file = path.join(root, opt.out);
fs.mkdirSync(path.dirname(file), { recursive: true });
fs.writeFileSync(file, Buffer.from(url.split(',')[1], 'base64'));
console.log(`wrote ${opt.out}  (${opt.w}x${opt.h}, ${opt.frames} frames, ${((Date.now() - t0) / 1000).toFixed(1)}s)`);
if (opt.probe) console.log('camera', JSON.stringify(await page.evaluate(() => ST.readBuffer(0, 1, 0, 1, 1))));
const e2 = await page.evaluate(() => ST.errors());
if (e2) console.log(e2);
await browser.close();
