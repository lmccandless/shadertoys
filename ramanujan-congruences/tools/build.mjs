// Assembles src/*.glsl into the Shadertoy export and a standalone viewer.
//   node tools/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const code = (f) => fs.readFileSync(path.join(root, 'src', f), 'utf8');
const A = { id: '4dXGR8', filepath: '/media/previz/buffer00.png' };
// Shadertoy's SDF font texture, as in a reference export (ldfcDr).
const FONT = { id: '4dXGzr', filepath: '/media/a/08b42b43ae9d3c0605da11d0eac86618ea888e62cdd9518ee8b9097488b31560.png' };
const bufIn = (channel) => ({ id: A.id, filepath: A.filepath, type: 'buffer', channel,
  sampler: { filter: 'nearest', wrap: 'clamp', vflip: 'true', srgb: 'false', internal: 'byte' }, published: 1 });

const shader = {
  ver: '0.1',
  info: {
    id: '', date: '0', viewed: 0,
    name: "Ramanujan's Congruences",
    description: 'p(n) on a spiral with m tiles per turn, gold where m divides p(n). Slide m: at 5, 7 and 11 one residue class turns solid gold, p(5k+4), p(7k+5), p(11k+6). Exact p(n) mod lcm(1..16) computed on the GPU.',
    likes: 0, published: 'Private', usePreview: 0,
    tags: ['ramanujan', 'partitions', 'congruences', 'interactive', 'numbertheory'],
    hasliked: 0, parentid: '', parentname: '',
  },
  renderpass: [
    { inputs: [], outputs: [], code: code('common.glsl'), name: 'Common', description: '', type: 'common' },
    { inputs: [bufIn(0)], outputs: [{ id: A.id, channel: 0 }], code: code('buffer_a.glsl'), name: 'Buffer A', description: '', type: 'buffer' },
    {
      inputs: [bufIn(0), { id: FONT.id, filepath: FONT.filepath, type: 'texture', channel: 1,
        sampler: { filter: 'linear', wrap: 'clamp', vflip: 'false', srgb: 'false', internal: 'byte' }, published: 1 }],
      outputs: [{ id: '4dfGRr', channel: 0 }], code: code('image.glsl'), name: 'Image', description: '', type: 'image',
    },
  ],
};

const json = JSON.stringify(shader, null, 2);
JSON.parse(json);
fs.writeFileSync(path.join(root, 'ramanujan-congruences.json'), json + '\n');
const media = { [FONT.filepath]: 'data:image/png;base64,' + fs.readFileSync(path.join(here, 'font_standin.png')).toString('base64') };
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => JSON.stringify(media)));
console.log('built ramanujan-congruences.json + viewer.html');
