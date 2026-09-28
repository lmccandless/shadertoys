// Assembles src/*.glsl into the Shadertoy export and a standalone viewer.
//   node tools/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const code = (f) => fs.readFileSync(path.join(root, 'src', f), 'utf8');
const BUF = { A: { id: '4dXGR8', filepath: '/media/previz/buffer00.png' }, B: { id: 'XsXGR8', filepath: '/media/previz/buffer01.png' } };
const inp = (b, channel, filter) => ({ id: BUF[b].id, filepath: BUF[b].filepath, type: 'buffer', channel,
  sampler: { filter, wrap: 'clamp', vflip: 'true', srgb: 'false', internal: 'byte' }, published: 1 });

const shader = {
  ver: '0.1',
  info: {
    id: '', date: '0', viewed: 0,
    name: 'Mock Theta Field Lines',
    description: "Ramanujan's mock theta function f(q) on the unit disk as glowing field lines of phase and modulus. It erupts at every even-order root of unity: pan and zoom into the rim for ever finer flowers; morph f+b / f / f-b.",
    likes: 0, published: 'Private', usePreview: 0,
    tags: ['ramanujan', 'mocktheta', 'domaincoloring', 'fieldlines', 'interactive'],
    hasliked: 0, parentid: '', parentname: '',
  },
  renderpass: [
    { inputs: [], outputs: [], code: code('common.glsl'), name: 'Common', description: '', type: 'common' },
    { inputs: [inp('A', 0, 'nearest')], outputs: [{ id: BUF.A.id, channel: 0 }], code: code('buffer_a.glsl'), name: 'Buffer A', description: '', type: 'buffer' },
    { inputs: [inp('A', 0, 'nearest')], outputs: [{ id: BUF.B.id, channel: 0 }], code: code('buffer_b.glsl'), name: 'Buffer B', description: '', type: 'buffer' },
    { inputs: [inp('A', 0, 'nearest'), inp('B', 1, 'mipmap')], outputs: [{ id: '4dfGRr', channel: 0 }], code: code('image.glsl'), name: 'Image', description: '', type: 'image' },
  ],
};

const json = JSON.stringify(shader, null, 2);
JSON.parse(json);
fs.writeFileSync(path.join(root, 'mock-theta-field-lines.json'), json + '\n');
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => '{}'));
console.log('built mock-theta-field-lines.json + viewer.html');
