// Debug: render the cow SDF on a constant-z slice in painting-pixel space (800x668).
//   node tools/slice.mjs --z 0.0 --out shots/slice.png [--side]   (--side: slice x=const instead, plane x=--x)
// Inside = orange, outside = blue banded distance; material id tints.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const args = process.argv.slice(2);
let z = 0, out = 'shots/slice.png', mode = 'z', xval = 0;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--z') z = +args[++i];
  else if (args[i] === '--x') { xval = +args[++i]; mode = 'x'; }
  else if (args[i] === '--out') out = args[++i];
}
const common = fs.readFileSync(path.join(root, 'src/Common.glsl'), 'utf8');
const B = fs.readFileSync(path.join(root, 'src/Buffer_B.glsl'), 'utf8');
const cowPart = B.slice(0, B.indexOf('// ---- architecture'));
const img = `
${cowPart}
void mainImage(out vec4 O,in vec2 F) {
    vec3 p;
    ${mode === 'z' ? `p=P(F.x,668.0-F.y,${z.toFixed(4)});` : `p=vec3(${xval.toFixed(4)},P(400.0,668.0-F.y,0.0).y,(F.x-400.0)*0.011062*1.0);`}
    vec2 r=cow(p);
    float d=r.x;
    vec3 c=d<0.0?vec3(0.9,0.55,0.2)*(0.6+0.4*cos(d*60.0)):vec3(0.15,0.25,0.5)*(0.6+0.4*cos(d*40.0));
    if(d<0.0){ if(r.y>5.5&&r.y<6.5)c=vec3(0.1,0.1,0.1); if(r.y>6.5&&r.y<7.5)c=vec3(0.9,0.9,0.5); if(r.y>7.5&&r.y<8.5)c=vec3(0.2,0.1,0.1); if(r.y>15.5)c=vec3(0.9,0.2,0.9);if(r.y>9.5&&r.y<10.5)c=vec3(0.9,0.5,0.6);}
    if(abs(d)<0.004)c=vec3(1);
    O=vec4(c,1);
}`;
const shader = { info: { name: 'slice' }, renderpass: [
  { type: 'common', name: 'Common', code: common, inputs: [], outputs: [] },
  { type: 'image', name: 'Image', code: img, inputs: [], outputs: [{ id: '4dfGRr', channel: 0 }] } ] };
const html = fs.readFileSync(path.join(root, 'tools/viewer_template.html'), 'utf8')
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c')).replace('/*__MEDIA__*/null', () => '{}');
const tmp = path.join(root, 'shots/_slice.html');
fs.writeFileSync(tmp, html);
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 800, height: 668 } });
page.setDefaultTimeout(0);
await page.goto('file://' + tmp + '?manual&w=800&h=668');
await page.waitForFunction(() => window.ST);
const err = await page.evaluate(() => ST.errors());
if (err) { console.log(err); process.exit(1); }
await page.evaluate(() => ST.renderFrames(1, 1 / 60));
const url = await page.evaluate(() => document.getElementById('c').toDataURL('image/png'));
fs.writeFileSync(path.join(root, out), Buffer.from(url.split(',')[1], 'base64'));
fs.unlinkSync(tmp);
console.log('wrote', out);
await browser.close();
