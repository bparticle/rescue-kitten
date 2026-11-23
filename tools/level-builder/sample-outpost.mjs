// Builds the "Outpost" sample level with the same helpers the editor uses.
// Run: node tools/level-builder/sample-outpost.mjs  (writes levels/outpost.json)
// Then open it in the builder and press Export, or run node tools/level-builder/export.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { newLevel, randomTerrain, cellValue, materialMap, TILE } from './format.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const materials = materialMap(JSON.parse(fs.readFileSync(path.join(root, 'sprites', 'tiles', 'materials.json'), 'utf8')));
const W = 48, H = 32;
const level = newLevel('outpost', W, H, 911);
Object.assign(level, {
  name: 'Outpost', objective: 'rescue-kitten', health: 130, loadout: [1, 2], order: 9, par: 80,
  brief: 'THE KITTEN CRAWLED INTO THE BARN ACROSS THE RIVER.',
});

let seed = 7;
const rand = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
const at = (x, y) => y * W + x;
// Paints like the editor brush: ground keeps the terrain under trimmed edges, roof details keep their roof.
const set = (layer, x, y, value) => {
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = at(x, y), id = value.split(':')[0];
  level[layer][i] = value && materials[id] && !materials[id].terrain ? cellValue(id, level[layer][i], materials) : value;
};
const fill = (layer, x0, y0, x1, y1, value) => {
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(layer, x, y, typeof value === 'function' ? value(x, y) : value);
};

function house(x0, y0, x1, y1, wall, floor, roof, door = 'south') {
  fill('ground', x0, y0, x1, y1, floor);
  fill('roof', x0, y0, x1, y1, roof);
  fill('structure', x0, y0, x1, y1, (x, y) => (x === x0 || x === x1 || y === y0 || y === y1 ? wall : ''));
  const mid = Math.floor((x0 + x1) / 2), midY = Math.floor((y0 + y1) / 2);
  if (door === 'south') set('structure', mid, y1, 'doorway');
  if (door === 'north') set('structure', mid, y0, 'doorway');
  if (door === 'west') set('structure', x0, midY, 'doorway');
  if (door === 'east') set('structure', x1, midY, 'doorway');
  for (let x = x0 + 2; x < x1 - 1; x += 3) {
    if (!(door === 'north' && Math.abs(x - mid) < 2)) set('structure', x, y0, 'window');
  }
}

// Road and river
fill('ground', 0, 15, W - 1, 16, 'road');
for (let x = 1; x < W; x += 3) set('ground', x, 15, 'road-line');
fill('ground', 29, 0, 29, H - 1, 'shallow-water');
fill('ground', 30, 0, 31, H - 1, 'deep-water');
fill('ground', 32, 0, 32, H - 1, 'shallow-water');
fill('ground', 28, 14, 33, 17, 'bridge-planks');
fill('structure', 28, 14, 33, 14, 'wood-fence');
fill('structure', 28, 17, 33, 17, 'wood-fence');
fill('ground', 0, 14, 27, 14, 'cobblestone');
fill('ground', 0, 17, 27, 17, 'cobblestone');
fill('ground', 34, 14, W - 1, 14, 'cobblestone');
fill('ground', 34, 17, W - 1, 17, 'cobblestone');

// Farmhouse, cottage and barn
house(5, 3, 13, 10, 'brick-wall', 'wood-floor', 'roof-red');
fill('ground', 7, 6, 9, 7, 'rug');
set('structure', 12, 4, 'crate');
set('structure', 6, 4, 'crate');
house(15, 20, 22, 26, 'stone-wall', 'tile-floor', 'roof-slate', 'north');
set('structure', 21, 25, 'crate');
house(36, 4, 45, 11, 'wood-wall', 'stone-floor', 'roof-tin', 'west');
set('structure', 43, 5, 'barrel'); set('structure', 44, 5, 'barrel'); set('structure', 44, 6, 'barrel');
set('structure', 38, 9, 'crate'); set('structure', 39, 9, 'crate');
house(3, 21, 8, 26, 'wood-wall', 'wood-floor', 'roof-thatch', 'east');

// Gravel path to the farmhouse door, planters either side
fill('ground', 9, 11, 9, 13, 'gravel');
set('structure', 8, 11, 'planter'); set('structure', 10, 11, 'planter');
// Roof details: ridges along the farmhouse and cottage, a vent on the barn, a skylight on the slate roof
fill('roof', 6, 6, 12, 6, 'roof-ridge-ew');
fill('roof', 5, 22, 5, 25, 'roof-ridge-ns');
set('roof', 40, 7, 'roof-vent'); set('roof', 42, 9, 'roof-vent');
set('roof', 18, 23, 'roof-skylight');
// Sandy east bank and worn asphalt toward the exit
fill('ground', 33, 0, 33, 13, 'sand');
fill('ground', 33, 18, 33, 31, 'sand');
fill('ground', 38, 15, 45, 16, 'road-worn');
for (let x = 40; x < 46; x += 3) set('ground', x, 15, 'road-line');

// Cover around the crossroads
fill('structure', 22, 11, 25, 11, 'sandbags');
fill('structure', 22, 12, 22, 12, 'sandbags');
fill('structure', 22, 19, 25, 19, 'sandbags');
fill('structure', 25, 20, 25, 20, 'sandbags');
fill('structure', 35, 19, 38, 19, 'sandbags');
set('structure', 18, 12, 'barrel'); set('structure', 26, 13, 'crate'); set('structure', 27, 13, 'crate');
set('structure', 34, 12, 'barrel');
fill('structure', 15, 1, 27, 1, 'hedge');
fill('structure', 15, 2, 15, 6, 'hedge');

// Fenced field with wire on the far bank
fill('structure', 36, 21, 46, 21, 'wood-fence');
fill('structure', 36, 29, 46, 29, 'wood-fence');
fill('structure', 36, 21, 36, 29, 'wood-fence');
fill('structure', 46, 21, 46, 29, 'wood-fence');
set('structure', 36, 25, '');
fill('ground', 37, 22, 45, 28, () => randomTerrain('grass', rand));
fill('structure', 40, 13, 44, 13, 'barbed-wire');
fill('structure', 39, 12, 39, 13, 'barbed-wire-ns');
// Metal checkpoint by the exit, and debris from an earlier fight
fill('structure', 44, 18, 46, 18, 'metal-wall');
set('structure', 44, 19, 'metal-wall');
set('structure', 23, 26, 'rubble'); set('structure', 24, 26, 'rubble'); set('structure', 17, 13, 'scorch');
set('structure', 13, 24, 'splinters');
set('structure', 10, 18, 'fire-pit');

// Nature
const props = [['tree', 2, 2], ['tree', 14, 12], ['tree', 26, 5], ['tree', 3, 12], ['tree', 19, 29], ['tree', 34, 26],
  ['tree', 46, 2], ['rock', 12, 28], ['rock', 25, 27], ['rock', 34, 2], ['rock', 45, 17], ['bush', 11, 12],
  ['bush', 20, 9], ['bush', 27, 23], ['bush', 33, 9], ['bush', 9, 29], ['bush', 2, 18], ['bush', 24, 2]];
for (const [id, x, y] of props) set('structure', x, y, id);
fill('ground', 9, 27, 13, 30, () => randomTerrain('mud', rand));

const c = (x, y) => [x * TILE + 8, y * TILE + 8];
const enemy = (kind, x, y, dir, wave = 1) => { const [px, py] = c(x, y); level.entities.push({ type: 'enemy', kind, x: px, y: py, dir, wave }); };
const pickup = (weapon, x, y) => { const [px, py] = c(x, y); level.entities.push({ type: 'pickup', weapon, x: px, y: py }); };
level.entities = [];
{ const [x, y] = c(1, 16); level.entities.push({ type: 'spawn', x, y, dir: 2 }); }
{ const [x, y] = c(46, 15); level.entities.push({ type: 'exit', x, y }); }
{ const [x, y] = c(42, 8); level.entities.push({ type: 'kitten', x, y }); }
enemy('soldier', 9, 8, 4); enemy('rifleman', 11, 6, 6);
enemy('lobber', 24, 10, 4); enemy('soldier', 24, 20, 0);
enemy('warden', 18, 23, 0); enemy('scatterguard', 20, 22, 6);
enemy('marksman', 37, 16, 6); enemy('soldier', 40, 8, 6);
enemy('runner', 42, 25, 6, 2); enemy('runner', 40, 26, 6, 2); enemy('bruiser', 43, 24, 6, 2);
enemy('medic', 41, 18, 6, 2); enemy('cinder', 38, 7, 6, 2);
pickup(3, 4, 14); pickup(4, 7, 24); pickup(5, 19, 13); pickup(8, 41, 7);
for (const [tx, ty] of [[12, 13], [27, 18], [38, 15]]) {
  const [x, y] = c(tx, ty);
  level.entities.push({ type: 'medkit', x, y });
}

fs.mkdirSync(path.join(root, 'levels'), { recursive: true });
fs.writeFileSync(path.join(root, 'levels', 'outpost.json'), JSON.stringify(level) + '\n');
console.log('wrote levels/outpost.json');
