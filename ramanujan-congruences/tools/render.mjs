// Headless frame capture for checking the shader without a GPU.
//
//   node tools/render.mjs --w 960 --h 540 --warm 2100 --t 5 --t 30 --out shots/x
//
// --warm N    : run N frames of Buffer A only (fills the exact p(n) table)
// --t SECONDS : jump there by scrubbing with the mouse (the shader's own
//               timeline control), let it settle, and save <out>_<t>.png
// --settle N  : full frames rendered after each jump (default 4)
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const args = process.argv.slice(2);
const opt = { w: 640, h: 360, warm: 0, settle: 4, out: 'shots/frame', times: [], dt: 1 / 60 };
for (let i = 0; i < args.length; i++) {
  const a = args[i], v = args[i + 1];
  if (a === '--w') opt.w = +v, i++;
  else if (a === '--h') opt.h = +v, i++;
  else if (a === '--warm') opt.warm = +v, i++;
  else if (a === '--settle') opt.settle = +v, i++;
  else if (a === '--out') opt.out = v, i++;
  else if (a === '--t') opt.times.push(+v), i++;
  else if (a === '--dt') opt.dt = +v, i++;
}
const common = fs.readFileSync(path.join(root, 'src/common.glsl'), 'utf8');
const T_TOTAL = +(/M_MAX = ([\d.]+)/.exec(common) || [0, 0])[1];

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: opt.w, height: opt.h } });
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
page.setDefaultTimeout(0);
await page.goto('file://' + path.join(root, `viewer.html?manual&w=${opt.w}&h=${opt.h}`));
await page.waitForFunction(() => window.ST);
await page.waitForFunction(() => ST.mediaReady());
const err = await page.evaluate(() => ST.errors());
if (err) { console.log(err); await browser.close(); process.exit(1); }

const t0 = Date.now();
if (opt.warm) {
  await page.evaluate(([n, dt]) => ST.renderFrames(n, dt, ['Buffer A']), [opt.warm, opt.dt]);
  console.log(`warmed ${opt.warm} frames of Buffer A in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
}
fs.mkdirSync(path.dirname(path.join(root, opt.out)), { recursive: true });
for (const t of opt.times) {
  const t1 = Date.now();
  const x = Math.min(opt.w - 0.5, (t / T_TOTAL) * opt.w);
  await page.evaluate(([x, h, dt, settle]) => {
    ST.setMouse(x, 3, true);
    ST.renderFrames(1, dt);
    ST.setMouse(x, 3, false);
    ST.renderFrames(settle, dt);
  }, [x, opt.h, opt.dt, opt.settle]);
  const url = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
  const file = path.join(root, `${opt.out}_${String(t).replace('.', 'p')}.png`);
  fs.writeFileSync(file, Buffer.from(url.split(',')[1], 'base64'));
  console.log(`t=${t} -> ${path.relative(root, file)} (${((Date.now() - t1) / 1000).toFixed(1)}s)`);
}
const e2 = await page.evaluate(() => ST.errors());
if (e2) console.log(e2);
await browser.close();
