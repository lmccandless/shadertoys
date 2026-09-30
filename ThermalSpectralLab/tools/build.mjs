// Assembles src/*.glsl into the Shadertoy export and a standalone viewer.
//   node tools/build.mjs
// Pass wiring (channels, samplers, media) is copied from the reference export,
// so the lite build binds exactly the same inputs as the original.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const ref = JSON.parse(fs.readFileSync(path.join(root, 'reference/Thermal_Spectral_Lab_Polished_24.json'), 'utf8'));
const files = { 'Common': 'common.glsl', 'Buffer A': 'buffer_a.glsl', 'Buffer B': 'buffer_b.glsl',
  'Buffer C': 'buffer_c.glsl', 'Buffer D': 'buffer_d.glsl', 'Image': 'image.glsl' };

const shader = structuredClone(ref);
shader.info.name = 'Thermal Spectral Lab (Lite)';
shader.info.description = fs.readFileSync(path.join(root, 'src/description.txt'), 'utf8').trim();
for (const rp of shader.renderpass) rp.code = fs.readFileSync(path.join(root, 'src', files[rp.name]), 'utf8');

const json = JSON.stringify(shader, null, 1);
JSON.parse(json);
fs.writeFileSync(path.join(root, 'ThermalSpectralLab.json'), json + '\n');

const font = 'data:image/png;base64,' + fs.readFileSync(path.join(here, 'font_standin.png')).toString('base64');
const media = { '/media/a/08b42b43ae9d3c0605da11d0eac86618ea888e62cdd9518ee8b9097488b31560.png': font };
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => JSON.stringify(media)));
console.log('built ThermalSpectralLab.json + viewer.html');
