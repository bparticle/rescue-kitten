// Drafts the Dustpaw campaign: nine kitten rescues that climb in size and difficulty, plus
// levels/outpost.json from sample-outpost.mjs as mission 9.
// Run once: node tools/level-builder/campaign.mjs [--force] [id...]
// It writes levels/<id>.json, the builder's own source format. After that, edit the levels in the
// builder and export there. Existing files are kept unless you pass --force, so builder edits survive.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { newLevel, randomTerrain, cellValue, materialMap, validate, TILE } from './format.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const materials = materialMap(JSON.parse(fs.readFileSync(path.join(root, 'sprites', 'tiles', 'materials.json'), 'utf8')));
const args = process.argv.slice(2);
const force = args.includes('--force');
const wanted = args.filter((a) => !a.startsWith('--'));

// Facings, as the builder stores them.
const N = 0, NE = 1, E = 2, SE = 3, S = 4, SW = 5, W = 6, NW = 7;
// Weapon ids, as in lib/range.lua.
const HANDGUN = 1, RIFLE = 2, SHOTGUN = 3, GRENADE = 4, ROCKET = 5, FLAMER = 6, TNT = 7, RAIL = 8;
const DISC = 10, ARC = 11, CRYO = 12, CHARGE = 13, ORB = 14, HAMMER = 15;

// The same painting helpers as sample-outpost.mjs, bound to one level.
function draft(id, width, height, seed, settings) {
  const level = newLevel(id, width, height, seed);
  Object.assign(level, settings);
  let state = seed * 7 + 1;
  const rand = () => { state = (state * 16807) % 2147483647; return state / 2147483647; };
  const at = (x, y) => y * width + x;
  const set = (layer, x, y, value) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const i = at(x, y), tile = value.split(':')[0];
    level[layer][i] = value && materials[tile] && !materials[tile].terrain ? cellValue(tile, level[layer][i], materials) : value;
  };
  const fill = (layer, x0, y0, x1, y1, value) => {
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(layer, x, y, typeof value === 'function' ? value(x, y) : value);
  };
  const outline = (layer, x0, y0, x1, y1, value) => {
    fill(layer, x0, y0, x1, y0, value); fill(layer, x0, y1, x1, y1, value);
    fill(layer, x0, y0, x0, y1, value); fill(layer, x1, y0, x1, y1, value);
  };
  const terrain = (x0, y0, x1, y1, kind) => fill('ground', x0, y0, x1, y1, () => randomTerrain(kind, rand));
  // Walls, floor and roof in one go, like the builder's House tool. doors: any of north/south/east/west.
  const house = (x0, y0, x1, y1, wall, floor, roof, doors = ['south'], windows = true) => {
    fill('ground', x0, y0, x1, y1, floor);
    if (roof) fill('roof', x0, y0, x1, y1, roof);
    outline('structure', x0, y0, x1, y1, wall);
    const mx = Math.floor((x0 + x1) / 2), my = Math.floor((y0 + y1) / 2);
    const spots = { south: [mx, y1], north: [mx, y0], west: [x0, my], east: [x1, my] };
    for (const door of doors) set('structure', ...spots[door], 'doorway');
    if (windows) {
      for (let x = x0 + 2; x < x1 - 1; x += 3) if (!(doors.includes('north') && Math.abs(x - mx) < 2)) set('structure', x, y0, 'window');
    }
  };
  const props = (id, ...cells) => { for (const [x, y] of cells) set('structure', x, y, id); };
  const c = (x) => x * TILE + 8;
  const place = (entity) => level.entities.push(entity);
  level.entities = [];
  const api = {
    level, rand, set, fill, outline, terrain, house, props,
    spawn: (x, y, dir) => place({ type: 'spawn', x: c(x), y: c(y), dir }),
    exit: (x, y) => place({ type: 'exit', x: c(x), y: c(y) }),
    kitten: (x, y) => place({ type: 'kitten', x: c(x), y: c(y) }),
    medkit: (...cells) => { for (const [x, y] of cells) place({ type: 'medkit', x: c(x), y: c(y) }); },
    pickup: (weapon, x, y) => place({ type: 'pickup', weapon, x: c(x), y: c(y) }),
    enemy: (kind, x, y, dir, wave = 1, rooftop = false) =>
      place({ type: 'enemy', kind, x: c(x), y: c(y), dir, wave, ...(rooftop ? { rooftop: true } : {}) }),
  };
  return api;
}

const levels = {};

// 1. One guard, the kitten in plain sight, and the exit right behind you.
levels.backyard = () => {
  const L = draft('backyard', 18, 10, 101, {
    name: 'Backyard', objective: 'rescue-kitten', health: 100, loadout: [HANDGUN], order: 1,
    brief: 'A KITTEN WANDERED INTO THE YARD. ONE GUARD.',
  });
  L.terrain(0, 0, 17, 9, 'grass');
  L.outline('structure', 0, 0, 17, 9, 'wood-fence');
  L.set('structure', 0, 7, '');
  L.house(13, 1, 16, 3, 'wood-wall', 'wood-floor', 'roof-tin', ['south'], false);
  L.fill('ground', 3, 4, 12, 4, 'gravel');
  L.fill('ground', 14, 4, 14, 5, 'gravel');
  L.props('bush', [5, 2], [6, 7], [11, 7], [16, 8]);
  L.props('tree', [2, 1], [9, 1]);
  L.props('planter', [12, 3], [10, 3]);
  L.props('rock', [15, 7]);
  L.spawn(2, 4, E);
  L.exit(1, 7);
  L.kitten(9, 5);
  L.enemy('soldier', 7, 7, N);
  return L.level;
};

// 2. A rifle in the orchard, a runner that rushes, and the kitten behind the far hedge.
levels.orchard = () => {
  const L = draft('orchard', 26, 14, 202, {
    name: 'Orchard', objective: 'rescue-kitten', health: 100, loadout: [HANDGUN], order: 2,
    brief: 'THE KITTEN IS HIDING PAST THE ORCHARD HEDGE.',
  });
  L.terrain(0, 0, 25, 13, 'grass');
  L.terrain(1, 9, 4, 12, 'dirt');
  for (let x = 6; x <= 18; x += 3) for (const y of [2, 5, 8, 11]) L.set('structure', x, y, 'tree');
  L.fill('structure', 22, 0, 22, 9, 'hedge');
  L.fill('structure', 22, 12, 22, 13, 'hedge');
  L.props('hedge', [23, 9], [25, 9]);
  L.fill('ground', 23, 10, 25, 11, 'gravel');
  L.fill('ground', 23, 1, 25, 8, 'grass');
  L.props('bush', [24, 6], [2, 2], [4, 5], [20, 12]);
  L.props('planter', [23, 2], [25, 7]);
  L.terrain(13, 6, 15, 7, 'mud');
  L.spawn(2, 7, E);
  L.exit(1, 11);
  L.kitten(24, 3);
  L.pickup(RIFLE, 5, 10);
  L.medkit([14, 12]);
  L.enemy('soldier', 11, 4, W);
  L.enemy('soldier', 17, 9, W);
  L.enemy('runner', 20, 6, W);
  return L.level;
};

// 3. Roofs hide what is inside: the shotgun in the coop, a rifleman and the kitten in the house.
levels.farmhouse = () => {
  const L = draft('farmhouse', 30, 18, 303, {
    name: 'Farmhouse', objective: 'rescue-kitten', health: 100, loadout: [HANDGUN], order: 3,
    brief: 'FOLLOW THE MEOWING INTO THE FARMHOUSE.',
  });
  L.house(17, 3, 25, 10, 'brick-wall', 'wood-floor', 'roof-red', ['west']);
  L.fill('roof', 18, 6, 24, 6, 'roof-ridge-ew');
  L.fill('ground', 20, 7, 22, 8, 'rug');
  L.props('crate', [18, 4], [24, 9]);
  L.fill('structure', 21, 4, 21, 5, 'wood-wall');
  L.house(4, 12, 8, 15, 'wood-wall', 'wood-floor', 'roof-thatch', ['north'], false);
  L.fill('ground', 9, 6, 16, 6, 'gravel');
  L.fill('ground', 6, 7, 6, 11, 'gravel');
  L.outline('structure', 10, 11, 15, 16, 'wood-fence');
  L.set('structure', 12, 11, '');
  L.terrain(11, 12, 14, 15, 'mud');
  L.props('tree', [2, 2], [13, 2], [27, 3], [28, 12], [2, 16]);
  L.props('bush', [9, 3], [16, 13], [26, 15], [3, 5]);
  L.props('rock', [20, 14]);
  L.spawn(2, 8, E);
  L.exit(27, 15);
  L.kitten(23, 5);
  L.pickup(SHOTGUN, 6, 14);
  L.medkit([12, 9], [24, 7]);
  L.enemy('soldier', 12, 4, S);
  L.enemy('soldier', 13, 13, W);
  L.enemy('runner', 22, 14, W);
  L.enemy('runner', 27, 8, W);
  L.enemy('rifleman', 19, 8, W);
  return L.level;
};

// 4. Crate stacks and barrels. Grenades arc over cover; the kitten is boxed in by crates.
levels['crate-yard'] = () => {
  const L = draft('crate-yard', 32, 20, 404, {
    name: 'Crate Yard', objective: 'rescue-kitten', health: 100, loadout: [HANDGUN, SHOTGUN], order: 4,
    brief: 'BOXED IN BY CRATES. BLAST OR SHOOT A WAY IN.',
  });
  L.terrain(0, 0, 31, 19, 'dirt');
  L.fill('ground', 4, 2, 30, 18, 'road-worn');
  L.fill('ground', 8, 8, 26, 9, 'road');
  for (let x = 9; x <= 25; x += 3) L.set('ground', x, 8, 'road-line');
  L.house(10, 1, 17, 6, 'metal-wall', 'stone-floor', 'roof-tin', ['south']);
  L.set('roof', 13, 3, 'roof-vent');
  L.props('crate', [11, 2], [16, 2], [16, 5]);
  // The kitten's pen in the north-east corner.
  L.fill('structure', 26, 0, 26, 4, 'crate');
  L.fill('structure', 27, 4, 31, 4, 'crate');
  L.fill('ground', 27, 0, 31, 3, 'wood-floor');
  // Stacks and barrels around the yard.
  for (const [x, y] of [[6, 12], [13, 12], [20, 12], [20, 4], [7, 4]]) L.fill('structure', x, y, x + 1, y + 1, 'crate');
  L.props('barrel', [15, 14], [16, 14], [22, 6], [23, 6], [28, 10], [28, 11], [9, 15]);
  L.fill('structure', 23, 13, 26, 13, 'sandbags');
  L.fill('structure', 26, 14, 26, 15, 'sandbags');
  L.outline('structure', 0, 0, 31, 19, 'wood-fence');
  L.fill('structure', 0, 8, 0, 10, '');
  L.props('rock', [2, 2], [30, 17]);
  L.spawn(2, 16, NE);
  L.exit(1, 9);
  L.kitten(29, 1);
  L.pickup(GRENADE, 5, 10);
  L.medkit([12, 16], [24, 3]);
  L.enemy('soldier', 13, 4, S);
  L.enemy('soldier', 18, 10, W);
  L.enemy('scatterguard', 16, 15, W);
  L.enemy('scatterguard', 24, 7, SW);
  L.enemy('lobber', 25, 15, W);
  L.enemy('runner', 29, 13, W);
  return L.level;
};

// 5. A river with one bridge: wardens hold it, a marksman covers it, and the kitten waits on an island.
levels.riverside = () => {
  const L = draft('riverside', 36, 22, 505, {
    name: 'Riverside', objective: 'rescue-kitten', health: 110, loadout: [HANDGUN, RIFLE], order: 5,
    brief: 'STRANDED ON THE ISLAND. WADE ACROSS THE FORD.',
  });
  L.terrain(0, 0, 35, 21, 'grass');
  L.fill('ground', 15, 0, 15, 21, 'shallow-water');
  L.fill('ground', 16, 0, 20, 21, 'deep-water');
  L.fill('ground', 21, 0, 21, 21, 'shallow-water');
  L.fill('ground', 14, 0, 14, 21, 'sand');
  L.fill('ground', 22, 0, 22, 21, 'sand');
  // The island and the ford that reaches it from the west bank.
  L.fill('ground', 17, 2, 19, 7, 'sand');
  L.terrain(18, 3, 19, 6, 'grass');
  L.fill('ground', 16, 5, 16, 6, 'shallow-water');
  L.props('tree', [19, 2], [17, 7]);
  L.props('bush', [17, 3]);
  // The bridge.
  L.fill('ground', 14, 14, 22, 15, 'bridge-planks');
  L.fill('structure', 14, 13, 22, 13, 'wood-fence');
  L.fill('structure', 14, 16, 22, 16, 'wood-fence');
  L.fill('ground', 0, 14, 13, 15, 'road');
  L.fill('ground', 23, 14, 35, 15, 'road');
  L.fill('structure', 24, 12, 24, 13, 'sandbags');
  L.fill('structure', 24, 16, 24, 17, 'sandbags');
  L.fill('structure', 9, 11, 11, 11, 'sandbags');
  L.house(27, 4, 32, 9, 'wood-wall', 'wood-floor', 'roof-thatch', ['south']);
  L.props('tree', [3, 3], [7, 18], [11, 4], [26, 19], [33, 18], [30, 12], [5, 9]);
  L.props('rock', [12, 18], [25, 2], [34, 2]);
  L.props('bush', [8, 7], [2, 19], [26, 11], [33, 11]);
  L.spawn(2, 11, E);
  L.exit(34, 15);
  L.kitten(18, 4);
  L.pickup(RAIL, 6, 14);
  L.medkit([10, 18], [28, 17]);
  L.enemy('soldier', 10, 6, S);
  L.enemy('soldier', 12, 16, W);
  L.enemy('warden', 23, 14, W);
  L.enemy('warden', 23, 15, W);
  L.enemy('marksman', 29, 11, W);
  L.enemy('rifleman', 30, 16, W);
  L.enemy('runner', 33, 4, W, 2);
  L.enemy('runner', 33, 19, W, 2);
  L.enemy('skirmisher', 31, 14, W, 2);
  return L.level;
};

// 6. A hedge maze: hedges hide you but let shots through. The kitten sits in the centre.
levels['hedge-maze'] = () => {
  const L = draft('hedge-maze', 34, 26, 606, {
    name: 'Hedge Maze', objective: 'rescue-kitten', health: 110, loadout: [HANDGUN, RIFLE], order: 6,
    brief: 'HEDGES HIDE YOU BUT DO NOT STOP BULLETS.',
  });
  L.terrain(0, 0, 33, 25, 'grass');
  // A 10 x 10 maze of one-tile corridors on odd tiles from (9, 3), carved by depth-first search.
  const X0 = 8, Y0 = 2, CELLS = 10;
  L.fill('structure', X0, Y0, X0 + CELLS * 2, Y0 + CELLS * 2, 'hedge');
  const seen = new Set();
  const open = (cx, cy) => L.set('structure', X0 + 1 + cx * 2, Y0 + 1 + cy * 2, '');
  const stack = [[0, 5]];
  seen.add('0,5'); open(0, 5);
  while (stack.length) {
    const [cx, cy] = stack[stack.length - 1];
    const next = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => [cx + dx, cy + dy, dx, dy])
      .filter(([nx, ny]) => nx >= 0 && ny >= 0 && nx < CELLS && ny < CELLS && !seen.has(`${nx},${ny}`));
    if (!next.length) { stack.pop(); continue; }
    const [nx, ny, dx, dy] = next[Math.floor(L.rand() * next.length)];
    L.set('structure', X0 + 1 + cx * 2 + dx, Y0 + 1 + cy * 2 + dy, '');
    open(nx, ny); seen.add(`${nx},${ny}`); stack.push([nx, ny]);
  }
  // Extra gaps make loops, so a dead end is never a trap.
  for (let i = 0; i < 18; i++) {
    const x = X0 + 1 + Math.floor(L.rand() * (CELLS * 2 - 1)), y = Y0 + 1 + Math.floor(L.rand() * (CELLS * 2 - 1));
    if ((x - X0) % 2 !== (y - Y0) % 2) L.set('structure', x, y, '');
  }
  // The centre garden, entrances west and east.
  L.fill('structure', X0 + 7, Y0 + 7, X0 + 13, Y0 + 13, '');
  L.fill('ground', X0 + 8, Y0 + 8, X0 + 12, Y0 + 12, 'cobblestone');
  L.props('planter', [X0 + 8, Y0 + 8], [X0 + 12, Y0 + 8], [X0 + 8, Y0 + 12], [X0 + 12, Y0 + 12]);
  L.set('structure', X0, Y0 + 11, '');
  L.set('structure', X0 + CELLS * 2, Y0 + 11, '');
  L.fill('ground', 0, 13, X0, 13, 'gravel');
  L.props('tree', [2, 2], [4, 22], [30, 3], [31, 22], [5, 7]);
  L.props('bush', [3, 17], [29, 13], [6, 3]);
  L.spawn(2, 13, E);
  L.exit(1, 10);
  L.kitten(X0 + 10, Y0 + 10);
  L.pickup(DISC, 5, 15);
  L.pickup(ARC, X0 + 1, Y0 + 1);
  L.medkit([X0 + 19, Y0 + 1], [X0 + 1, Y0 + 19], [X0 + 19, Y0 + 19]);
  L.enemy('skirmisher', X0 + 5, Y0 + 11, W);
  L.enemy('skirmisher', X0 + 15, Y0 + 5, S);
  L.enemy('skirmisher', X0 + 11, Y0 + 17, N);
  L.enemy('runner', X0 + 3, Y0 + 3, E);
  L.enemy('runner', X0 + 17, Y0 + 17, W);
  L.enemy('warden', X0 + 10, Y0 + 7, N);
  L.enemy('medic', X0 + 11, Y0 + 9, N);
  L.enemy('runner', 31, 13, W, 2);
  L.enemy('skirmisher', 31, 9, W, 2);
  return L.level;
};

// 7. A farm on fire. Cinders spray flame, a bruiser charges, and the kitten is inside the barn.
levels['burning-barn'] = () => {
  const L = draft('burning-barn', 36, 26, 707, {
    name: 'Burning Barn', objective: 'rescue-kitten', health: 120, loadout: [HANDGUN, SHOTGUN], order: 7,
    brief: 'THE BARN IS BURNING. FREEZE THE FIRE CREW.',
  });
  L.terrain(0, 0, 35, 25, 'dirt');
  L.terrain(0, 0, 10, 8, 'grass');
  L.house(20, 6, 31, 15, 'wood-wall', 'wood-floor', 'roof-thatch', ['west', 'south']);
  L.fill('roof', 21, 10, 30, 10, 'roof-ridge-ew');
  L.fill('structure', 26, 7, 26, 11, 'wood-wall');
  L.props('crate', [21, 7], [22, 7], [30, 14], [29, 14]);
  L.props('fire-pit', [24, 13], [28, 8]);
  // The burned-out farmhouse.
  L.fill('ground', 4, 14, 11, 20, 'stone-floor');
  L.outline('structure', 4, 14, 11, 20, 'brick-wall');
  L.props('rubble', [7, 14], [8, 14], [11, 17], [11, 18], [4, 18]);
  L.props('scorch', [6, 16], [9, 19]);
  L.props('fire-pit', [8, 17]);
  // Fires across the yard and a fenced paddock.
  L.props('fire-pit', [15, 9], [17, 18], [13, 4], [33, 20], [24, 20]);
  L.props('scorch', [16, 9], [18, 18], [12, 4], [25, 19], [32, 4]);
  L.outline('structure', 13, 20, 21, 24, 'wood-fence');
  L.set('structure', 17, 20, '');
  L.props('splinters', [14, 20], [21, 22]);
  L.props('tree', [2, 3], [7, 2], [34, 1], [33, 24], [3, 24]);
  L.props('barrel', [18, 12], [33, 10], [33, 11]);
  L.fill('ground', 12, 11, 19, 11, 'gravel');
  L.spawn(2, 11, E);
  L.exit(2, 5);
  L.kitten(29, 8);
  L.pickup(CRYO, 6, 10);
  L.pickup(FLAMER, 15, 22);
  L.medkit([9, 3], [18, 15], [32, 17]);
  L.enemy('soldier', 14, 6, W);
  L.enemy('scatterguard', 17, 14, W);
  L.enemy('lobber', 22, 18, NW);
  L.enemy('soldier', 31, 18, W);
  L.enemy('cinder', 23, 9, W);
  L.enemy('cinder', 34, 6, W, 2);
  L.enemy('cinder', 34, 16, W, 2);
  L.enemy('bruiser', 27, 23, NW, 2);
  L.enemy('runner', 30, 2, SW, 2);
  return L.level;
};

// 8. A frozen depot. Cryo techs slow you, a marksman watches from the roof, and the kitten is
// sealed in a brick vault with no door.
levels['cold-storage'] = () => {
  const L = draft('cold-storage', 38, 28, 808, {
    name: 'Cold Storage', objective: 'rescue-kitten', health: 120, loadout: [HANDGUN, RIFLE, SHOTGUN], order: 8,
    brief: 'THE KITTEN IS SEALED IN THE VAULT. BREAK IN.',
  });
  L.terrain(0, 0, 37, 27, 'dirt');
  L.fill('ground', 2, 2, 35, 25, 'road');
  L.fill('ground', 2, 13, 35, 14, 'road-worn');
  for (let x = 3; x <= 34; x += 3) L.set('ground', x, 13, 'road-line');
  L.house(4, 3, 14, 10, 'metal-wall', 'tile-floor', 'roof-tin', ['south', 'east']);
  L.set('roof', 7, 5, 'roof-vent'); L.set('roof', 11, 7, 'roof-vent');
  L.props('crate', [5, 4], [6, 4], [13, 9], [5, 9]);
  L.house(21, 2, 33, 10, 'metal-wall', 'stone-floor', 'roof-tin', ['south', 'west']);
  L.set('roof', 24, 4, 'roof-skylight');
  L.props('barrel', [32, 3], [32, 4], [22, 9]);
  // The vault: brick walls all round, no door.
  L.house(25, 17, 32, 23, 'brick-wall', 'tile-floor', 'roof-slate', [], false);
  L.props('crate', [26, 18], [31, 22]);
  // Yard cover.
  L.fill('structure', 16, 16, 19, 16, 'sandbags');
  L.fill('structure', 8, 19, 8, 22, 'sandbags');
  for (const [x, y] of [[13, 18], [20, 21], [17, 6]]) L.fill('structure', x, y, x + 1, y, 'crate');
  L.props('barrel', [22, 16], [23, 16], [11, 23]);
  L.outline('structure', 0, 0, 37, 27, 'metal-wall');
  L.fill('structure', 0, 24, 0, 26, '');
  L.fill('structure', 36, 0, 37, 0, '');
  L.fill('structure', 37, 1, 37, 2, '');
  L.spawn(2, 24, NE);
  L.exit(35, 2);
  L.kitten(28, 20);
  L.pickup(TNT, 5, 17);
  L.pickup(ROCKET, 9, 7);
  L.pickup(CHARGE, 18, 24);
  L.medkit([12, 15], [28, 6], [34, 22]);
  L.enemy('cryo', 11, 17, W);
  L.enemy('warden', 17, 15, S);
  L.enemy('rifleman', 10, 12, S);
  L.enemy('soldier', 7, 7, E);
  L.enemy('medic', 20, 18, W);
  L.enemy('warden', 24, 12, S);
  L.enemy('marksman', 27, 6, S, 1, true);
  L.enemy('rifleman', 34, 16, W);
  L.enemy('cryo', 30, 12, SW);
  L.enemy('cryo', 34, 24, W, 2);
  L.enemy('bruiser', 34, 19, W, 2);
  L.enemy('runner', 20, 25, N, 2);
  L.enemy('runner', 35, 9, S, 2);
  return L.level;
};

// 10. The finale: a walled fortress with towers, three waves, and the kitten in the keep.
levels.fortress = () => {
  const L = draft('fortress', 48, 40, 1010, {
    name: 'Fortress', objective: 'rescue-kitten', health: 150, loadout: [HANDGUN, RIFLE, SHOTGUN, GRENADE], order: 10,
    brief: 'STORM THE FORTRESS. THE KITTEN IS IN THE KEEP.',
  });
  L.terrain(0, 0, 47, 39, 'grass');
  L.terrain(0, 33, 47, 39, 'dirt');
  // Moat along the south wall with a bridge to the gate.
  L.fill('ground', 6, 32, 41, 32, 'shallow-water');
  L.fill('ground', 6, 33, 41, 33, 'deep-water');
  L.fill('ground', 6, 34, 41, 34, 'shallow-water');
  L.fill('ground', 22, 32, 25, 34, 'bridge-planks');
  L.fill('ground', 23, 35, 24, 39, 'gravel');
  // Curtain wall, gate and courtyard.
  L.fill('ground', 9, 5, 38, 29, 'cobblestone');
  L.outline('structure', 8, 4, 39, 30, 'stone-wall');
  L.fill('structure', 23, 30, 24, 30, 'doorway');
  L.fill('structure', 8, 17, 8, 18, 'window');
  L.fill('structure', 39, 17, 39, 18, 'window');
  // Corner towers with roofs for rooftop marksmen.
  for (const [x, y] of [[8, 4], [36, 4], [8, 27], [36, 27]]) {
    L.fill('roof', x, y, x + 3, y + 3, 'roof-slate');
  }
  // Keep, barracks and armoury.
  L.house(19, 6, 28, 15, 'stone-wall', 'stone-floor', 'roof-slate', ['south']);
  L.fill('structure', 20, 10, 22, 10, 'stone-wall');
  L.fill('structure', 25, 10, 27, 10, 'stone-wall');
  L.fill('ground', 22, 7, 25, 9, 'rug');
  L.set('roof', 23, 12, 'roof-skylight');
  L.house(11, 8, 16, 14, 'brick-wall', 'wood-floor', 'roof-red', ['east']);
  L.house(31, 8, 36, 14, 'brick-wall', 'tile-floor', 'roof-red', ['west']);
  L.props('crate', [34, 9], [35, 9], [12, 13]);
  // Courtyard cover.
  L.fill('structure', 13, 21, 17, 21, 'sandbags');
  L.fill('structure', 30, 21, 34, 21, 'sandbags');
  L.fill('structure', 21, 19, 26, 19, 'sandbags');
  L.props('barrel', [18, 24], [19, 24], [29, 24], [28, 25], [21, 17], [26, 17]);
  for (const [x, y] of [[11, 25], [35, 24], [15, 17], [32, 17]]) L.fill('structure', x, y, x + 1, y + 1, 'crate');
  L.props('fire-pit', [23, 23]);
  // Outside the walls.
  L.props('tree', [2, 3], [4, 12], [3, 24], [44, 4], [45, 14], [43, 25], [10, 37], [37, 37], [16, 36], [31, 38]);
  L.props('rock', [6, 18], [42, 20], [19, 37]);
  L.fill('structure', 18, 36, 20, 36, 'barbed-wire');
  L.fill('structure', 27, 36, 29, 36, 'barbed-wire');
  L.spawn(24, 38, N);
  L.exit(21, 38);
  L.kitten(23, 8);
  L.pickup(ARC, 14, 36);
  L.pickup(ORB, 13, 11);
  L.pickup(HAMMER, 33, 11);
  L.pickup(ROCKET, 12, 27);
  L.medkit([33, 37], [10, 22], [37, 22], [23, 26], [34, 13]);
  // Wave 1: the gate, the courtyard and the towers.
  L.enemy('warden', 22, 28, S);
  L.enemy('warden', 25, 28, S);
  L.enemy('soldier', 15, 23, S);
  L.enemy('soldier', 32, 23, S);
  L.enemy('rifleman', 23, 20, S);
  L.enemy('scatterguard', 13, 19, E);
  L.enemy('lobber', 31, 19, W);
  L.enemy('marksman', 9, 28, E, 1, true);
  L.enemy('marksman', 38, 28, W, 1, true);
  L.enemy('medic', 24, 22, S);
  // Wave 2: the barracks empty out.
  L.enemy('runner', 17, 11, S, 2);
  L.enemy('runner', 30, 11, S, 2);
  L.enemy('skirmisher', 14, 16, S, 2);
  L.enemy('skirmisher', 33, 16, S, 2);
  L.enemy('cinder', 11, 6, S, 2);
  L.enemy('cryo', 36, 6, S, 2);
  // Wave 3: the keep's guard.
  L.enemy('bruiser', 23, 13, S, 3);
  L.enemy('warden', 21, 12, S, 3);
  L.enemy('warden', 26, 12, S, 3);
  L.enemy('marksman', 37, 6, S, 3, true);
  L.enemy('medic', 24, 17, S, 3);
  return L.level;
};

fs.mkdirSync(path.join(root, 'levels'), { recursive: true });
let failed = false;
for (const [id, build] of Object.entries(levels)) {
  if (wanted.length && !wanted.includes(id)) continue;
  const file = path.join(root, 'levels', `${id}.json`);
  if (fs.existsSync(file) && !force) { console.log(`${id}: kept existing levels/${id}.json (pass --force to redraft)`); continue; }
  const level = build();
  const issues = validate(level, materials);
  for (const issue of issues) console.log(`${id}: ${issue.severity}: ${issue.message}${issue.entity ? ` at ${Math.floor(issue.entity.x / TILE)},${Math.floor(issue.entity.y / TILE)}` : ''}`);
  if (issues.some((i) => i.severity === 'error')) { failed = true; continue; }
  fs.writeFileSync(file, JSON.stringify(level) + '\n');
  console.log(`${id}: wrote levels/${id}.json`);
}
process.exit(failed ? 1 : 0);
