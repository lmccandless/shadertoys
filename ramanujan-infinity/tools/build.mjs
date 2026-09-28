// Assembles the GLSL passes in ../src into a Shadertoy JSON export and a
// self-contained viewer page.
//
//   node tools/build.mjs
//
// Outputs (in the project folder):
//   ramanujan-infinity.json  - Shadertoy export (import via the bridge)
//   viewer.html              - standalone WebGL2 viewer with the JSON embedded

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const src = (f) => path.join(root, 'src', f);

const BUFFERS = {
  A: { id: '4dXGR8', filepath: '/media/previz/buffer00.png' },
  B: { id: 'XsXGR8', filepath: '/media/previz/buffer01.png' },
  C: { id: '4sXGR8', filepath: '/media/previz/buffer02.png' },
  D: { id: 'XdfGR8', filepath: '/media/previz/buffer03.png' },
};

// Shadertoy's SDF font texture, exactly as it appears in a reference export
// (ldfcDr "SDF Font Texture Adventures").
const FONT = {
  id: '4dXGzr',
  filepath: '/media/a/08b42b43ae9d3c0605da11d0eac86618ea888e62cdd9518ee8b9097488b31560.png',
  type: 'texture',
  sampler: { filter: 'linear', wrap: 'clamp', vflip: 'false', srgb: 'false', internal: 'byte' },
};
// Offline stand-in for that texture, used only by viewer.html.
const FONT_STANDIN = path.join(here, 'font_standin.png');

const PASSES = [
  { name: 'Common', type: 'common', file: 'common.glsl', inputs: [] },
  {
    name: 'Buffer A', type: 'buffer', file: 'buffer_a.glsl', out: 'A',
    inputs: [{ buf: 'A', channel: 0, filter: 'nearest' }, { font: true, channel: 1 }],
  },
  {
    name: 'Buffer B', type: 'buffer', file: 'buffer_b.glsl', out: 'B',
    inputs: [{ buf: 'A', channel: 0, filter: 'nearest' }],
  },
  {
    name: 'Buffer C', type: 'buffer', file: 'buffer_c.glsl', out: 'C',
    inputs: [{ buf: 'A', channel: 0, filter: 'nearest' }, { font: true, channel: 1 }],
  },
  {
    name: 'Buffer D', type: 'buffer', file: 'buffer_d.glsl', out: 'D',
    inputs: [{ buf: 'B', channel: 0, filter: 'mipmap' }],
  },
  {
    name: 'Image', type: 'image', file: 'image.glsl',
    inputs: [
      { buf: 'B', channel: 0, filter: 'linear' },
      { buf: 'C', channel: 1, filter: 'linear' },
      { buf: 'D', channel: 2, filter: 'linear' },
      { buf: 'A', channel: 3, filter: 'nearest' },
    ],
  },
];

// `#include "file"` lines are resolved at build time so the exported code is
// plain, self-contained Shadertoy GLSL.
function load(file, seen = new Set()) {
  if (seen.has(file)) throw new Error(`include cycle at ${file}`);
  seen.add(file);
  const text = fs.readFileSync(src(file), 'utf8');
  return text.replace(/^[ \t]*#include\s+"([^"]+)"[ \t]*$/gm, (_, f) => load(f, new Set(seen)).trimEnd());
}

function input({ buf, channel, filter, wrap = 'clamp', font }) {
  if (font) return { id: FONT.id, filepath: FONT.filepath, type: FONT.type, channel, sampler: FONT.sampler, published: 1 };
  return {
    id: BUFFERS[buf].id,
    filepath: BUFFERS[buf].filepath,
    type: 'buffer',
    channel,
    sampler: { filter, wrap, vflip: 'true', srgb: 'false', internal: 'byte' },
    published: 1,
  };
}

const shader = {
  ver: '0.1',
  info: {
    id: '',
    date: '0',
    viewed: 0,
    name: 'Ramanujan: Notes from the Edge of Infinity',
    description:
      'Six movements on Ramanujan: exact partition numbers p(n) computed on the GPU, ' +
      'the congruences p(5k+4)=0 mod 5 / 7 / 11, the Hardy-Ramanujan circle method as a crown of ' +
      'singularities, an infinite modular zoom into the golden boundary point, 1+2+3+...=-1/12, ' +
      'and the mock theta functions of his last letter. Drag horizontally to scrub the timeline.',
    likes: 0,
    published: 'Private',
    usePreview: 0,
    tags: ['ramanujan', 'partitions', 'modular', 'mocktheta', 'infinity', 'multipass'],
    hasliked: 0,
    parentid: '',
    parentname: '',
  },
  renderpass: PASSES.map((p) => ({
    inputs: p.inputs.map(input),
    outputs: p.out ? [{ id: BUFFERS[p.out].id, channel: 0 }] : p.type === 'image' ? [{ id: '4dfGRr', channel: 0 }] : [],
    code: load(p.file),
    name: p.name,
    description: '',
    type: p.type,
  })),
};

const json = JSON.stringify(shader, null, 2);
JSON.parse(json);
fs.writeFileSync(path.join(root, 'ramanujan-infinity.json'), json + '\n');

const template = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
const embedded = JSON.stringify(shader).replace(/</g, '\\u003c');
const media = { [FONT.filepath]: 'data:image/png;base64,' + fs.readFileSync(FONT_STANDIN).toString('base64') };
fs.writeFileSync(path.join(root, 'viewer.html'), template
  .replace('/*__SHADER_JSON__*/null', () => embedded)
  .replace('/*__MEDIA__*/null', () => JSON.stringify(media)));

const sizes = shader.renderpass.map((r) => `${r.name}: ${r.code.length} chars`).join(', ');
console.log(`built ramanujan-infinity.json + viewer.html (${sizes})`);
