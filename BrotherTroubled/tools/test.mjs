// Acceptance tests, mirroring the hand-off package's scenarios (SwiftShader, headless Chromium):
//   portrait : 800x668, 16 frames  -> every pass compiles, every buffer value is finite
//   left     : 400x300, 24 frames  -> drag to the far left: camera state clamps at -ORBIT_LIMIT
//   right    : 400x300, 24 frames  -> drag to the far right: camera state clamps at +ORBIT_LIMIT
//   reset    : 400x300, 48 frames  -> orbit, then double-click: camera returns to exactly zero
// Writes tests/report.json and exits non-zero on any failure.
//   node tools/test.mjs [--only portrait|left|right|reset]
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const only = process.argv.includes('--only') ? process.argv[process.argv.indexOf('--only') + 1] : null;
const LIMIT = 0.2617993877991494;
const sha = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'BrotherTroubled.json'))).digest('hex');
const NAMES = ['Buffer A', 'Buffer B', 'Buffer C', 'Buffer D'];

const scenarios = {
  portrait: { w: 800, h: 668, dt: 1 / 60, frames: 16, events: [], probes: [] },
  left: { w: 400, h: 300, dt: 0.05, frames: 24,
    events: [[1, 'down', 440, 247], [2, 'move', 40, 37], [3, 'up', 40, 37]],
    probes: [{ frame: 23, expect: [-LIMIT, -LIMIT, -LIMIT, -LIMIT] }] },
  right: { w: 400, h: 300, dt: 0.05, frames: 24,
    events: [[1, 'down', 440, 247], [2, 'move', 840, 457], [3, 'up', 840, 457]],
    probes: [{ frame: 23, expect: [LIMIT, LIMIT, LIMIT, LIMIT] }] },
  reset: { w: 400, h: 300, dt: 0.05, frames: 48,
    events: [[1, 'down', 440, 247], [2, 'move', 840, 457], [3, 'up', 840, 457],
             [29, 'down', 400, 220], [30, 'up', 400, 220], [32, 'down', 400, 220], [33, 'up', 400, 220]],
    probes: [{ frame: 47, expect: [0, 0, 0, 0] }] },
};

const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const report = { project_sha256: sha, started: new Date().toISOString(), results: [] };
let failed = false;
for (const [name, sc] of Object.entries(scenarios)) {
  if (only && only !== name) continue;
  const page = await browser.newPage({ viewport: { width: sc.w, height: sc.h } });
  page.setDefaultTimeout(0);
  const t0 = Date.now();
  await page.goto('file://' + path.join(root, `viewer.html?manual&w=${sc.w}&h=${sc.h}`));
  await page.waitForFunction(() => window.ST);
  const r = { test: name, size: [sc.w, sc.h], frames: sc.frames, errors: '', finite: {}, probes: [], passed: true };
  r.errors = await page.evaluate(() => ST.errors());
  if (r.errors) r.passed = false;
  else {
    for (let f = 0; f < sc.frames; f++) {
      const ev = sc.events.filter((e) => e[0] === f);
      const out = await page.evaluate(([evs, dt, w, h, scanFinite, doProbe]) => {
        for (const [, kind, x, y] of evs) ST.setMouse(x, y, kind !== 'up');
        ST.renderFrames(1, dt);
        const res = {};
        if (doProbe) res.cam = ST.readBuffer(0, 1, 0, 1, 1);
        if (scanFinite) {
          res.scan = [0, 1, 2, 3].map((b) => {
            const v = ST.readBuffer(b, 0, 0, w, h);
            let bad = 0, mn = Infinity, mx = -Infinity;
            for (const x of v) { if (!Number.isFinite(x)) bad++; else { if (x < mn) mn = x; if (x > mx) mx = x; } }
            return { bad, mn, mx, n: v.length };
          });
        }
        return res;
      }, [ev, sc.dt, sc.w, sc.h, name === 'portrait' && (f === 0 || f === sc.frames - 1), sc.probes.some((p) => p.frame === f)]);
      if (out.scan) out.scan.forEach((s, i) => {
        r.finite[`${NAMES[i]}@${f}`] = s;
        if (s.bad) r.passed = false;
      });
      for (const p of sc.probes.filter((p) => p.frame === f)) {
        const ok = p.expect.every((v, i) => Math.abs(v - out.cam[i]) < 1e-4);
        r.probes.push({ frame: f, expected: p.expect, actual: out.cam, passed: ok });
        if (!ok) r.passed = false;
      }
    }
    r.errors = await page.evaluate(() => ST.errors());
    if (r.errors) r.passed = false;
  }
  r.wall_seconds = +((Date.now() - t0) / 1000).toFixed(1);
  report.results.push(r);
  console.log(`${r.passed ? 'PASS' : 'FAIL'}  ${name}  (${sc.w}x${sc.h}, ${sc.frames} frames, ${r.wall_seconds}s)` +
    r.probes.map((p) => `  probe f${p.frame}: [${p.actual.map((v) => v.toFixed(4)).join(', ')}] ${p.passed ? 'ok' : 'MISMATCH'}`).join(''));
  if (!r.passed) { failed = true; if (r.errors) console.log(r.errors); }
  await page.close();
}
await browser.close();
fs.mkdirSync(path.join(root, 'tests'), { recursive: true });
fs.writeFileSync(path.join(root, 'tests/report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(failed ? 'FAILED' : 'all tests passed', `(project sha256 ${sha.slice(0, 12)}…)`);
process.exit(failed ? 1 : 0);
