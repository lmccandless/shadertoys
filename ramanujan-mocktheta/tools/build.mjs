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
    name: "Ramanujan's Mock Theta Function",
    description: 'The third-order mock theta function f(q) from Ramanujan\'s last letter (1920). Rays show where it erupts at roots of unity of even order; slide to f-b or f+b and a theta function cancels one family, never both.',
    likes: 0, published: 'Private', usePreview: 0,
    tags: ['ramanujan', 'mocktheta', 'modular', 'domaincoloring', 'interactive'],
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
fs.writeFileSync(path.join(root, 'ramanujan-mocktheta.json'), json + '\n');
const media = { [FONT.filepath]: 'data:image/png;base64,' + fs.readFileSync(path.join(here, 'font_standin.png')).toString('base64') };
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => JSON.stringify(media)));
console.log('built ramanujan-mocktheta.json + viewer.html');
