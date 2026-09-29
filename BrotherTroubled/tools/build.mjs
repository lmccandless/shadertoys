// Assembles src/*.glsl + src/project.json into the Shadertoy export and a standalone viewer.
//   node tools/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'src/project.json'), 'utf8'));

const shader = {
  ver: manifest.ver,
  info: manifest.info,
  renderpass: manifest.renderpass.map(({ file, ...pass }) => ({
    ...pass,
    code: fs.readFileSync(path.join(root, 'src', file), 'utf8'),
  })),
};
// Shadertoy wants `code` last-ish for readability; key order does not matter to the importer.
const json = JSON.stringify(shader, null, 2);
JSON.parse(json);
fs.writeFileSync(path.join(root, 'BrotherTroubled.json'), json + '\n');
const tpl = fs.readFileSync(path.join(here, 'viewer_template.html'), 'utf8');
fs.writeFileSync(path.join(root, 'viewer.html'), tpl
  .replace('/*__SHADER_JSON__*/null', () => JSON.stringify(shader).replace(/</g, '\\u003c'))
  .replace('/*__MEDIA__*/null', () => '{}'));
console.log('built BrotherTroubled.json + viewer.html');
