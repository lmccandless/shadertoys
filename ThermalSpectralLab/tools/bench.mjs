// Headless compile + cost check (SwiftShader, so absolute numbers are CPU-bound;
// compare ratios between builds).
//   node tools/bench.mjs [--json path] [--w 960 --h 540] [--warm 30] [--n 10] [--shot out.png]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const args = process.argv.slice(2);
const opt = { w: 960, h: 540, warm: 30, n: 10, json: null, shot: null, keys: '', t: 0 };
for (let i = 0; i < args.length; i += 2) opt[args[i].replace(/^--/, '')] = isNaN(+args[i + 1]) ? args[i + 1] : +args[i + 1];

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: opt.w, height: opt.h } });
page.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
page.setDefaultTimeout(0);
await page.goto('file://' + path.join(root, `viewer.html?manual&w=${opt.w}&h=${opt.h}`));
await page.waitForFunction(() => window.ST);
let t0 = Date.now();
if (opt.json || opt.def) {
  const sh = JSON.parse(fs.readFileSync(path.resolve(opt.json || path.join(root, 'ThermalSpectralLab.json')), 'utf8'));
  // --def NAME=VALUE[,NAME=VALUE] overrides #defines in Common.
  for (const d of String(opt.def || '').split(',').filter(Boolean)) {
    const [k, v] = d.split('=');
    const c = sh.renderpass.find((r) => r.type === 'common');
    c.code = c.code.replace(new RegExp(`#define ${k} .*`), `#define ${k} ${v}`);
  }
  await page.evaluate((sh) => ST.load(sh), sh);
}
await page.evaluate(() => ST.renderFrames(1));
console.log(`compile + first frame: ${Date.now() - t0} ms`);
await page.waitForFunction(() => ST.mediaReady());
const err = await page.evaluate(() => ST.errors());
if (err) { console.log(err); await browser.close(); process.exit(1); }
t0 = Date.now();
await page.evaluate((n) => ST.renderFrames(n), opt.warm);
if (opt.t) await page.evaluate((n) => ST.renderFrames(n, 0.1), Math.round(opt.t * 10));
for (const k of String(opt.keys || '').split(',').filter(Boolean)) {
  await page.evaluate((k) => { ST.keyEvent(k, true); ST.renderFrames(1); ST.keyEvent(k, false); ST.renderFrames(3); }, +k);
}
console.log(`warm ${opt.warm} frames: ${Date.now() - t0} ms`);
const ms = await page.evaluate((n) => ST.bench(n, 1 / 60), opt.n);
console.log(`steady: ${ms.toFixed(1)} ms/frame at ${opt.w}x${opt.h}`);
if (opt.passes) for (const name of ['Buffer A', 'Buffer B', 'Buffer C', 'Buffer D', 'Image']) {
  const t = await page.evaluate(([n, name]) => ST.bench(n, 0, [name]), [opt.n, name]);
  console.log(`  ${name}: ${t.toFixed(1)} ms`);
}
if (opt.shot) {
  const url = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
  fs.writeFileSync(path.resolve(opt.shot), Buffer.from(url.split(',')[1], 'base64'));
  console.log('wrote', opt.shot);
}
await browser.close();
