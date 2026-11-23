// Re-export every level in levels/ to apps/dust-range/levels/ without the editor.
// Useful after changing sprites/tiles/materials.json. Run: node tools/level-builder/export.mjs [id...]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { toLua, indexLua, summary, validate, materialMap } from './format.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const sources = path.join(root, 'levels');
const out = path.join(root, 'apps', 'dust-range', 'levels');
const materials = materialMap(JSON.parse(fs.readFileSync(path.join(root, 'sprites', 'tiles', 'materials.json'), 'utf8')));
const wanted = process.argv.slice(2);

fs.mkdirSync(out, { recursive: true });
let failed = false;
for (const file of fs.readdirSync(sources).filter((f) => f.endsWith('.json'))) {
  const level = JSON.parse(fs.readFileSync(path.join(sources, file), 'utf8'));
  if (wanted.length && !wanted.includes(level.id)) continue;
  const issues = validate(level, materials);
  for (const issue of issues) console.log(`${level.id}: ${issue.severity}: ${issue.message}`);
  if (issues.some((i) => i.severity === 'error')) { failed = true; continue; }
  const lua = toLua(level, materials);
  fs.writeFileSync(path.join(out, `${level.id}.lua`), lua);
  console.log(`${level.id}: exported ${Buffer.byteLength(lua)} bytes`);
}
const metas = fs.readdirSync(out).filter((f) => f.endsWith('.lua') && f !== 'index.lua').map((f) => {
  const match = fs.readFileSync(path.join(out, f), 'utf8').split('\n', 1)[0].match(/^-- meta: (.*)$/);
  return match && JSON.parse(match[1]);
}).filter(Boolean);
fs.writeFileSync(path.join(out, 'index.lua'), indexLua(metas));
console.log(`index: ${metas.length} level(s)`);
process.exit(failed ? 1 : 0);
