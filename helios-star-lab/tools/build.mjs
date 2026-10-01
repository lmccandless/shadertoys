// Assembles src/*.glsl into the Shadertoy export and a standalone viewer.
//   node tools/build.mjs
//
// Text: GLSL sources may write TXT("some text"); each becomes ivec2(offset, length) into one
// packed table, emitted at /*TEXT_DATA*/ (4 chars per uint, little-endian).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const NAME = 'helios-star-lab';

let table = '';
const offsets = new Map();
function expand(src) {
  return src.replace(/TXT\("((?:[^"\\]|\\.)*)"\)/g, (_, s) => {
    s = s.replace(/\\"/g, '"');
    for (const ch of s) if (ch.charCodeAt(0) > 255) throw new Error(`non-Latin-1 char in ${s}`);
    if (!offsets.has(s)) { offsets.set(s, table.length); table += s; }
    return `ivec2(${offsets.get(s)}, ${s.length})`;
  });
}
const raw = (f) => fs.readFileSync(path.join(root, 'src', f), 'utf8');
const files = Object.fromEntries(['common.glsl', 'buffer_a.glsl', 'buffer_b.glsl', 'buffer_c.glsl', 'buffer_d.glsl', 'image.glsl']
  .map((f) => [f, expand(raw(f))]));
const words = [];
for (let i = 0; i < table.length; i += 4) {
  let w = 0;
  for (let j = 0; j < 4 && i + j < table.length; j++) w += table.charCodeAt(i + j) * 2 ** (8 * j);
  words.push(w + 'u');
}
// A balanced if-tree rather than a const array: some compilers copy const arrays into every
// invocation, which costs far more than eight comparisons per lookup.
function tree(lo, hi) {
  if (hi - lo === 1) return words[lo];
  const mid = (lo + hi) >> 1;
  return `(i < ${mid} ? ${tree(lo, mid)} : ${tree(mid, hi)})`;
}
const data = `const int TEXT_LEN = ${table.length};\nuint textWord(int i) { return ${tree(0, words.length)}; }`;
for (const f in files) files[f] = files[f].replace('/*TEXT_DATA*/', data);

const BUF = [
  { id: '4dXGR8', filepath: '/media/previz/buffer00.png' },
  { id: 'XsXGR8', filepath: '/media/previz/buffer01.png' },
  { id: '4sXGR8', filepath: '/media/previz/buffer02.png' },
  { id: 'XdfGR8', filepath: '/media/previz/buffer03.png' },
];
// Shadertoy's SDF font texture.
const FONT = { id: '4dXGzr', filepath: '/media/a/08b42b43ae9d3c0605da11d0eac86618ea888e62cdd9518ee8b9097488b31560.png' };
const buf = (b, channel, filter = 'nearest') => ({ id: BUF[b].id, filepath: BUF[b].filepath, type: 'buffer', channel,
  sampler: { filter, wrap: 'clamp', vflip: 'true', srgb: 'false', internal: 'byte' }, published: 1 });
const pass = (name, type, file, inputs, out) => ({ inputs, outputs: out === undefined ? [] : [{ id: out, channel: 0 }],
  code: files[file], name, description: '', type });

const shader = {
  ver: '0.1',
  info: {
    id: '', date: '0', viewed: 0,
    name: 'Helios: Star Lab',
    description: 'Eight real stars from one physical model. Colour is the blackbody at each point\'s temperature with Eddington limb darkening; granule size follows the pressure scale height; spots, flares and the magnetic field follow rotation (Rossby number) and the activity cycle (butterfly diagram, Joy\'s and Hale\'s laws, dipole reversal); rapid rotators flatten and gravity-darken. Field lines are traced live through a potential field with a source surface. Drag to orbit.',
    likes: 0, published: 'Private', usePreview: 0,
    tags: ['sun', 'star', 'magnetic', 'blackbody', 'interactive', 'astrophysics'],
    hasliked: 0, parentid: '', parentname: '',
  },
  renderpass: [
    pass('Common', 'common', 'common.glsl', []),
    pass('Buffer A', 'buffer', 'buffer_a.glsl', [buf(0, 0)], BUF[0].id),
    pass('Buffer B', 'buffer', 'buffer_b.glsl', [buf(0, 0), buf(1, 1)], BUF[1].id),
    pass('Buffer C', 'buffer', 'buffer_c.glsl', [buf(0, 0), buf(1, 1)], BUF[2].id),
    pass('Buffer D', 'buffer', 'buffer_d.glsl', [buf(0, 0), buf(1, 1), buf(2, 2)], BUF[3].id),
    pass('Image', 'image', 'image.glsl', [buf(3, 0, 'mipmap'), buf(0, 1),
      { id: FONT.id, filepath: FONT.filepath, type: 'texture', channel: 2,
        sampler: { filter: 'linear', wrap: 'clamp', vflip: 'false', srgb: 'false', internal: 'byte' }, published: 1 }], '4dfGRr'),
  ],
};

const json = JSON.stringify(shader, null, 2);
JSON.parse(json);
fs.writeFileSync(path.join(root, `${NAME}.json`), json + '\n');
const media = { [FONT.filepath]: 'data:image/png;base64,' + fs.readFileSync(path.join(here, 'font_standin.png')).toString('base64') };
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => JSON.stringify(media)));
console.log(`built ${NAME}.json + viewer.html (${table.length} text chars)`);
