// Assembles src/*.glsl into the Shadertoy export and a standalone viewer.
//   node tools/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const code = (f) => fs.readFileSync(path.join(root, 'src', f), 'utf8');
const A = { id: '4dXGR8', filepath: '/media/previz/buffer00.png' };

const shader = {
  ver: '0.1',
  info: {
    id: '', date: '0', viewed: 0,
    name: 'Ramanujan: The Crown and the Edge',
    description: 'The Hardy-Ramanujan circle method as a 3D crown of singularities over the unit disk, diving into an endless, exactly self-similar modular zoom at the golden point e^(2 pi i/phi). Drag horizontally to scrub.',
    likes: 0, published: 'Private', usePreview: 0,
    tags: ['ramanujan', 'modular', 'fordcircles', 'infinitezoom', 'raymarching'],
    hasliked: 0, parentid: '', parentname: '',
  },
  renderpass: [
    {
      inputs: [{ id: A.id, filepath: A.filepath, type: 'buffer', channel: 0,
        sampler: { filter: 'nearest', wrap: 'clamp', vflip: 'true', srgb: 'false', internal: 'byte' }, published: 1 }],
      outputs: [{ id: A.id, channel: 0 }],
      code: code('buffer_a.glsl'), name: 'Buffer A', description: '', type: 'buffer',
    },
    {
      inputs: [{ id: A.id, filepath: A.filepath, type: 'buffer', channel: 0,
        sampler: { filter: 'mipmap', wrap: 'clamp', vflip: 'true', srgb: 'false', internal: 'byte' }, published: 1 }],
      outputs: [{ id: '4dfGRr', channel: 0 }],
      code: code('image.glsl'), name: 'Image', description: '', type: 'image',
    },
  ],
};

const json = JSON.stringify(shader, null, 2);
JSON.parse(json);
fs.writeFileSync(path.join(root, 'ramanujan-edge.json'), json + '\n');
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => '{}'));
console.log('built ramanujan-edge.json + viewer.html');
