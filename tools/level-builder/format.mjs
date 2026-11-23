// Level format shared by the browser editor and the Node server.
// Source levels live in levels/<id>.json. Export writes apps/dust-range/levels/<id>.lua,
// which lib/level.lua decodes on the badge.

export const FORMAT = 1;
export const TILE = 16;
export const ROOF_HEIGHT = 24;
const BODY = 6;
export const MIN_W = 10, MIN_H = 7, MAX_W = 96, MAX_H = 96;
export const DIRECTIONS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

export const WEAPONS = [
  'Unarmed', 'Handgun', 'Assault rifle', 'Pump shotgun', 'Grenade', 'Rocket launcher', 'Flamethrower', 'TNT',
  'Rail rifle', 'Bankshot', 'Boomerang disc', 'Arc projector', 'Cryo sprayer', 'Charge cannon', 'Gravity orb',
  'Shock hammer',
];
export const WEAPON_ART = [
  'unarmed', 'handgun', 'assault-rifle', 'pump-shotgun', 'grenade', 'rocket-launcher', 'flamethrower', 'tnt',
  'rail-rifle', 'bankshot', 'boomerang-disc', 'arc-projector', 'cryo-sprayer', 'charge-cannon', 'gravity-orb',
  'shock-hammer',
];

// Mirrors lib/enemies.lua: weapon is the art the enemy carries, color is its skin tone.
export const ENEMIES = [
  { kind: 'soldier', name: 'Soldier', weapon: 1, color: '#a45d5f', role: 'Handgun' },
  { kind: 'runner', name: 'Runner', weapon: 0, color: '#dc8f55', role: 'Close strike' },
  { kind: 'rifleman', name: 'Rifleman', weapon: 2, color: '#83bcb5', role: 'Three-shot burst' },
  { kind: 'scatterguard', name: 'Scatterguard', weapon: 3, color: '#ab92cb', role: 'Short spread' },
  { kind: 'lobber', name: 'Lobber', weapon: 4, color: '#adb877', role: 'Lobs grenades over cover' },
  { kind: 'warden', name: 'Warden', weapon: 1, color: '#a1a5b5', role: 'Frontal shield' },
  { kind: 'skirmisher', name: 'Skirmisher', weapon: 9, color: '#dfb56d', role: 'Strafing pistol' },
  { kind: 'medic', name: 'Medic', weapon: 1, color: '#c7d6b8', role: 'Heals allies' },
  { kind: 'bruiser', name: 'Bruiser', weapon: 0, color: '#cf8c82', role: 'Charge' },
  { kind: 'marksman', name: 'Marksman', weapon: 8, color: '#ce9db9', role: 'Long beam' },
  { kind: 'cinder', name: 'Cinder', weapon: 6, color: '#d58451', role: 'Fire spray' },
  { kind: 'cryo', name: 'Cryo tech', weapon: 12, color: '#a5cfe1', role: 'Frost spray' },
];

// The badge font: letters, digits and a few symbols. The briefing screen wraps the text at spaces
// onto two lines of 27 characters beside the kitten (lib/menu.lua).
export const BRIEF_MAX = 56;
export const BRIEF_CHARS = /^[A-Za-z0-9 /.%<>+-]*$/;

export function briefLines(text, width = 27) {
  let lines = 0, line = 0;
  for (const word of text.split(/\s+/).filter(Boolean)) {
    if (line && line + 1 + word.length > width) { lines++; line = word.length; }
    else line = line ? line + 1 + word.length : word.length;
  }
  return lines + (line ? 1 : 0);
}

export const OBJECTIVES = {
  clear: 'Defeat every wave',
  exit: 'Reach the exit',
  'clear-exit': 'Defeat every wave, then reach the exit',
  'rescue-kitten': 'Rescue kitten and carry it to the exit',
};

// Terrain cells reuse the procedural range tiles: 12 tiles x 4 rotations = indexes 1..48.
export const TERRAIN = { dirt: [0, 4], grass: [4, 8], mud: [8, 12] };
export const TERRAIN_WEIGHTS = { dirt: [56, 18, 14, 12], grass: [34, 24, 25, 17], mud: [38, 23, 23, 16] };

export function terrainIndex(material, variant, rotation) {
  return (TERRAIN[material][0] + variant) * 4 + rotation + 1;
}

export function terrainOf(index) {
  const tile = Math.floor((index - 1) / 4);
  return tile < 4 ? 'dirt' : tile < 8 ? 'grass' : 'mud';
}

export function randomTerrain(material, random = Math.random) {
  const weights = TERRAIN_WEIGHTS[material];
  let roll = random() * 100, variant = 0;
  while (variant < 3 && roll > weights[variant]) { roll -= weights[variant]; variant++; }
  return `${material}:${terrainIndex(material, variant, Math.floor(random() * 4))}`;
}

// Port of terrain() in lib/game.lua so a level can start from the range's own ground.
export function generateTerrain(width, height, seed) {
  let state = seed;
  const rand = () => { state = (state * 75 + 74) % 65521; return state / 65521; };
  const span = 5, field = [];
  for (let y = 0; y <= Math.floor(height / span) + 1; y++) {
    field[y] = [];
    for (let x = 0; x <= Math.floor(width / span) + 1; x++) field[y][x] = rand();
  }
  const cumulative = { dirt: [56, 74, 88, 100], grass: [34, 58, 83, 100], mud: [38, 61, 84, 100] };
  const cells = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const gx = Math.floor(x / span), gy = Math.floor(y / span);
      const fx = (x % span) / span, fy = (y % span) / span;
      const a = field[gy], b = field[gy + 1];
      const top = a[gx] + (a[gx + 1] - a[gx]) * fx;
      const bottom = b[gx] + (b[gx + 1] - b[gx]) * fx;
      const wet = top + (bottom - top) * fy + (rand() - 0.5) * 0.13;
      const coverage = rand();
      let material = 'dirt';
      if (wet > 0.69 && coverage < 0.65) material = 'mud';
      else if (wet > 0.52 && coverage < 0.76) material = 'grass';
      const roll = rand() * 100;
      let variant = 0;
      while (roll > cumulative[material][variant]) variant++;
      cells.push(`${material}:${terrainIndex(material, variant, Math.floor(rand() * 4))}`);
    }
  }
  return cells;
}

export function materialMap(spec) {
  return Object.fromEntries(spec.materials.map((m) => [m.id, m]));
}

export function cellMaterial(value) {
  if (!value) return null;
  return value.split(/[:@]/, 1)[0];
}

export function newLevel(id = 'new-level', width = 40, height = 28, seed = 427) {
  return {
    format: FORMAT, id, name: 'New level', width, height, objective: 'clear', health: 100,
    loadout: [1], order: 0, seed,
    ground: generateTerrain(width, height, seed),
    structure: new Array(width * height).fill(''),
    roof: new Array(width * height).fill(''),
    entities: [{ type: 'spawn', x: 3 * TILE + 8, y: Math.floor(height / 2) * TILE + 8, dir: 3 }],
  };
}

export function resizeLevel(level, width, height, anchorX = 0, anchorY = 0) {
  const fresh = generateTerrain(width, height, level.seed || 427);
  const out = { ...level, width, height, ground: [], structure: [], roof: [] };
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const sx = x - anchorX, sy = y - anchorY;
      const inside = sx >= 0 && sy >= 0 && sx < level.width && sy < level.height;
      const from = sy * level.width + sx;
      out.ground.push(inside ? level.ground[from] : fresh[y * width + x]);
      out.structure.push(inside ? level.structure[from] : '');
      out.roof.push(inside ? level.roof[from] : '');
    }
  }
  out.entities = level.entities
    .map((e) => ({ ...e, x: e.x + anchorX * TILE, y: e.y + anchorY * TILE }))
    .filter((e) => e.x >= 0 && e.y >= 0 && e.x < width * TILE && e.y < height * TILE);
  return out;
}

const CARDINALS = [[0, -1], [1, 0], [0, 1], [-1, 0]];
const CORNERS = [[1, -1, 3], [1, 1, 6], [-1, 1, 12], [-1, -1, 9]];
const AREA_MASKS = Array.from({ length: 16 }, (_, mask) => mask);
for (let mask = 0; mask < 16; mask++) {
  for (let cuts = 1; cuts < 16; cuts++) {
    if (CORNERS.every(([, , sides], bit) => !(cuts & (1 << bit)) || (mask & sides) === sides)) {
      AREA_MASKS.push(mask | (cuts << 4));
    }
  }
}
const AREA_VARIANT = new Map(AREA_MASKS.map((mask, i) => [mask, i + 1]));

function neighborhood(cells, width, height, index, materials, def, lane = false) {
  const x = index % width, y = Math.floor(index / width);
  const same = (dx, dy) => {
    const nx = x + dx, ny = y + dy;
    if (nx < 0 || ny < 0 || nx >= width || ny >= height) return false;
    const other = materials[cellMaterial(cells[ny * width + nx])];
    return lane ? other?.autotile === 'lane' : other && (other.group === def.group || other.joins === def.group);
  };
  const mask = CARDINALS.reduce((bits, [dx, dy], bit) => same(dx, dy) ? bits | (1 << bit) : bits, 0);
  if (lane || !['area', 'lane'].includes(def.autotile)) return mask;
  return CORNERS.reduce((bits, [dx, dy, sides], bit) =>
    (mask & sides) === sides && !same(dx, dy) ? bits | (16 << bit) : bits, mask);
}

// Structural blob and orientation numbering must match retile() in lib/level.lua.
export function variantAt(cells, width, height, index, materials) {
  const def = materials[cellMaterial(cells[index])];
  if (!def?.autotile) {
    const x = index % width, y = Math.floor(index / width);
    return 1 + (((Math.imul(x + 1, 374761393) ^ Math.imul(y + 1, 668265263)) >>> 0) % (def?.variants || 1));
  }
  const mask = neighborhood(cells, width, height, index, materials, def);
  if (def.autotile === 'area') return AREA_VARIANT.get(mask);
  if (def.autotile === 'blob') return mask + 1;
  if (def.autotile === 'orient') {
    const vertical = !!(mask & 1) + !!(mask & 4);
    const horizontal = !!(mask & 2) + !!(mask & 8);
    return vertical > horizontal ? 2 : 1;
  }
  const markings = neighborhood(cells, width, height, index, materials, def, true);
  if (markings) return markings + 3;
  const vertical = !!(mask & 1) + !!(mask & 4);
  const horizontal = !!(mask & 2) + !!(mask & 8);
  return (vertical > horizontal ? 5 : 10) + 3;
}

export function cellValue(id, previous, materials) {
  const def = materials[id];
  const previousId = cellMaterial(previous);
  if (def.detail) {
    return materials[previousId]?.layer === 'roof' ? `${previousId}@${id}` : previous;
  }
  if (def.layer !== 'ground' || !def.underlay) return id;
  const parts = (previous || '').split('@');
  const road = previousId === 'road-worn' || (previousId === 'road-line' && parts[1] === 'road-worn');
  const base = parts[road && previousId === 'road-line' ? 2 : 1] || previous;
  const substrate = materials[cellMaterial(base)];
  const valid = id === 'rug' ? substrate?.terrain || (substrate?.category === 'Interior' && !substrate.underlay)
    : id !== 'deep-water' && substrate?.terrain;
  const surface = id === 'road-line' && road ? 'road-line@road-worn' : id;
  return valid ? `${surface}@${base}` : surface;
}

function baseKey(value, materials, ordinaryVariant = 1) {
  const id = cellMaterial(value);
  const def = materials[id];
  if (def.terrain) {
    const index = Number(value.split(':')[1]) || terrainIndex(id, 0, 0);
    return `T${index}`;
  }
  return `${id}/${def.autotile === 'area' ? 16 : ordinaryVariant}`;
}

function surfaceBase(mask) {
  return (mask & 240) !== 0 || CORNERS.some(([, , sides]) => !(mask & sides));
}

// Export stores the same stack the editor renders. The first entry owns gameplay.
export function tileKeysAt(cells, width, height, index, materials) {
  const value = cells[index];
  if (!value) return [];
  const id = cellMaterial(value);
  const def = materials[id];
  if (!def) throw new Error(`Unknown tile "${id}"`);
  const variant = variantAt(cells, width, height, index, materials);
  const [, extra, footing] = value.split('@');
  if (def.terrain) return [baseKey(value, materials)];
  const main = `${id}/${variant}`;
  if (def.layer === 'roof') return extra ? [main, '', `${extra}/1`] : [main];
  const mask = def.autotile === 'area' ? AREA_MASKS[variant - 1]
    : def.autotile === 'lane' ? neighborhood(cells, width, height, index, materials, def) : null;
  if (mask === null) return [main];
  const worn = def.autotile === 'lane' && extra === 'road-worn';
  const base = def.underlay && surfaceBase(mask) ? baseKey((worn ? footing : extra) || def.underlay, materials) : '';
  if (def.autotile === 'lane') return [main, `${worn ? 'road-worn' : 'road'}/${AREA_VARIANT.get(mask)}`, base];
  return base ? [main, base] : [main];
}

export function structureBounds(level, index, materials) {
  const cells = level.structure;
  const def = materials[cellMaterial(cells[index])];
  if (def?.bounds) return [def.bounds];
  if (!def?.span) return null;
  const variant = variantAt(cells, level.width, level.height, index, materials);
  const mask = def.autotile === 'orient' ? (variant === 1 ? 10 : 5) : variant - 1;
  const lo = 8 - def.span, hi = 8 + def.span;
  const x0 = mask & 8 ? 0 : lo, x1 = mask & 2 ? TILE : hi;
  const y0 = mask & 1 ? 0 : lo, y1 = mask & 4 ? TILE : hi;
  if (x0 === lo && x1 === hi) return [[lo, y0, hi, y1]];
  return mask & 5 ? [[x0, lo, x1, hi], [lo, y0, hi, y1]] : [[x0, lo, x1, hi]];
}

export function cellFlags(level, index, materials) {
  const flags = { walk: false, shots: false, lobs: false, sight: false, pierce: false, slow: 1, hazard: 0,
    hp: 0, overhead: false, explodes: null };
  for (const layer of ['ground', 'structure']) {
    const def = materials[cellMaterial(level[layer][index])];
    if (!def) continue;
    for (const key of ['walk', 'shots', 'lobs', 'sight']) if (def[key]) flags[key] = true;
    if (def.slow) flags.slow *= def.slow;
    if (def.hazard) flags.hazard += def.hazard;
    if (layer === 'structure') {
      if (def.shots && def.pierce) flags.pierce = true;
      if (def.hp) flags.hp = def.hp;
      if (def.explodes) flags.explodes = def.explodes;
    }
  }
  const roof = materials[cellMaterial(level.roof[index])];
  if (roof?.overhead) { flags.overhead = true; if (roof.lobs) flags.roofLobs = true; }
  return flags;
}

// Walking distance field from a cell, eight ways without cutting blocked corners (as in lib/level.lua).
export function reachable(level, materials, startIndex) {
  const { width, height } = level;
  const blocked = new Uint8Array(width * height);
  for (let i = 0; i < blocked.length; i++) blocked[i] = cellFlags(level, i, materials).walk ? 1 : 0;
  const seen = new Uint8Array(width * height);
  if (startIndex < 0 || blocked[startIndex]) return seen;
  const queue = [startIndex];
  seen[startIndex] = 1;
  while (queue.length) {
    const i = queue.pop();
    const x = i % width, y = Math.floor(i / width);
    for (let oy = -1; oy <= 1; oy++) {
      for (let ox = -1; ox <= 1; ox++) {
        const nx = x + ox, ny = y + oy;
        if ((!ox && !oy) || nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        const j = ny * width + nx;
        if (seen[j] || blocked[j]) continue;
        if (ox && oy && (blocked[y * width + nx] || blocked[ny * width + x])) continue;
        seen[j] = 1;
        queue.push(j);
      }
    }
  }
  return seen;
}

export function cellOf(level, x, y) {
  if (!Number.isFinite(x) || !Number.isFinite(y)) return -1;
  const cx = Math.floor(x / TILE), cy = Math.floor(y / TILE);
  if (cx < 0 || cy < 0 || cx >= level.width || cy >= level.height) return -1;
  return cy * level.width + cx;
}

function canStand(level, materials, x, y, rooftop) {
  if (x < BODY || y < BODY || x + BODY > level.width * TILE || y + BODY > level.height * TILE) return false;
  for (let cy = Math.floor((y - BODY) / TILE); cy <= Math.min(level.height - 1, Math.floor((y + BODY) / TILE)); cy++) {
    for (let cx = Math.floor((x - BODY) / TILE); cx <= Math.min(level.width - 1, Math.floor((x + BODY) / TILE)); cx++) {
      const i = cy * level.width + cx;
      const structure = materials[cellMaterial(level.structure[i])];
      const ground = materials[cellMaterial(level.ground[i])];
      const roof = materials[cellMaterial(level.roof[i])];
      const solid = rooftop ? !roof?.overhead : ground.walk;
      if (!solid && (!structure?.walk || (rooftop && (structure.height || 0) <= ROOF_HEIGHT))) continue;
      const boxes = (!solid && structureBounds(level, i, materials)) || [[0, 0, TILE, TILE]];
      for (const [x0, y0, x1, y1] of boxes) {
        if (x + BODY >= cx * TILE + x0 && x - BODY < cx * TILE + x1
          && y + BODY >= cy * TILE + y0 && y - BODY < cy * TILE + y1) return false;
      }
    }
  }
  return true;
}

function routeCell(level, materials, x, y, field) {
  const cx = Math.floor(x / TILE), cy = Math.floor(y / TILE);
  for (let oy = -1; oy <= 1; oy++) {
    for (let ox = -1; ox <= 1; ox++) {
      const nx = cx + ox, ny = cy + oy;
      if (nx < 0 || ny < 0 || nx >= level.width || ny >= level.height) continue;
      const i = ny * level.width + nx;
      if (field ? !field[i] : cellFlags(level, i, materials).walk) continue;
      const dx = nx * TILE + TILE / 2 - x, dy = ny * TILE + TILE / 2 - y;
      const steps = Math.ceil(Math.hypot(dx, dy));
      let clear = true;
      for (let step = 1; step <= steps && clear; step++) {
        clear = canStand(level, materials, x + dx * step / steps, y + dy * step / steps, false);
      }
      if (clear) return i;
    }
  }
  return -1;
}

function validTile(value, materials, layer) {
  if (typeof value !== 'string') return false;
  const [main, ...extras] = value.split('@');
  const id = cellMaterial(main);
  const def = materials[id];
  if (!def || def.layer !== layer || def.detail) return false;
  const terrainMatches = (part, material) => part === material.id ||
    (material.terrain && /^\d+$/.test(part.split(':')[1] || '') && part.split(':').length === 2
      && terrainOf(Number(part.split(':')[1])) === material.terrain
      && Number(part.split(':')[1]) >= 1 && Number(part.split(':')[1]) <= 48);
  if (!terrainMatches(main, def)) return false;
  if (id === 'road-line' && extras[0] === 'road-worn') extras.shift();
  if (!extras.length) return true;
  if (extras.length !== 1) return false;
  const extra = extras[0], base = materials[cellMaterial(extra)];
  if (layer === 'roof') return !!base?.detail && extra === base.id;
  return !!def.underlay && base?.layer === 'ground' && !base.underlay && terrainMatches(extra, base);
}

export function validate(level, materials) {
  const issues = [];
  const add = (severity, message, entity) => issues.push({ severity, message, entity });
  if (!/^[a-z0-9_-]{1,40}$/.test(level.id || '')) add('error', 'Level id must be 1-40 characters of a-z, 0-9, - or _.');
  if (level.id === 'index') add('error', 'Choose a different level id. Index is reserved for the badge level menu.');
  if (!Number.isInteger(level.width) || !Number.isInteger(level.height)
    || level.width < MIN_W || level.height < MIN_H || level.width > MAX_W || level.height > MAX_H) {
    add('error', `Use whole dimensions between ${MIN_W} × ${MIN_H} and ${MAX_W} × ${MAX_H} tiles.`);
    return issues;
  }
  for (const layer of ['ground', 'structure', 'roof']) {
    const cells = level[layer];
    if (!Array.isArray(cells) || cells.length !== level.width * level.height) {
      add('error', `Invalid ${layer} layer size.`);
      return issues;
    }
    for (const value of cells) {
      if (!value && layer !== 'ground') continue;
      if (!validTile(value, materials, layer)) {
        add('error', `Invalid tile "${value}" in the ${layer} layer.`);
        return issues;
      }
    }
  }
  if (!Array.isArray(level.entities) || level.entities.some((e) => !e || typeof e !== 'object')) {
    add('error', 'Invalid entity list.');
    return issues;
  }
  if (level.objective !== undefined && !Object.hasOwn(OBJECTIVES, level.objective)) add('error', 'Unknown objective.');
  if (level.brief !== undefined && (typeof level.brief !== 'string' || level.brief.length > BRIEF_MAX)) {
    add('error', `Keep the briefing under ${BRIEF_MAX + 1} characters.`);
  } else if (level.brief && briefLines(level.brief) > 2) {
    add('warn', 'The briefing wraps past two lines on the badge. Shorten it.');
  } else if (level.brief && !BRIEF_CHARS.test(level.brief)) {
    add('warn', 'The badge font has letters, digits, spaces and / . % < > + - only. Other characters show as gaps.');
  }
  if (level.health !== undefined && (!Number.isInteger(level.health) || level.health < 1 || level.health > 999)) {
    add('error', 'Starting health must be a whole number from 1 to 999.');
  }
  if (level.par !== undefined && (!Number.isInteger(level.par) || level.par < 1 || level.par > 3599)) {
    add('error', 'Par time must be a whole number of seconds from 1 to 3599.');
  }
  const validWeapon = (id) => Number.isInteger(id) && id > 0 && id < WEAPONS.length;
  if (level.loadout !== undefined && (!Array.isArray(level.loadout) || !level.loadout.every(validWeapon))) {
    add('error', 'Starting loadout contains an unknown weapon.');
  }
  const spawns = level.entities.filter((e) => e.type === 'spawn');
  const enemies = level.entities.filter((e) => e.type === 'enemy');
  const exits = level.entities.filter((e) => e.type === 'exit');
  const kittens = level.entities.filter((e) => e.type === 'kitten');
  const pickups = level.entities.filter((e) => e.type === 'pickup');
  const rescue = level.objective === 'rescue-kitten';
  const clear = level.objective === undefined || ['clear', 'clear-exit'].includes(level.objective);
  if (spawns.length !== 1) add('error', spawns.length ? 'Only one player spawn is allowed.' : 'Place a player spawn.');
  if (exits.length > 1) add('error', 'Only one exit is allowed.');
  if (kittens.length > 1) add('error', 'Only one kitten is allowed.');
  if (rescue && !kittens.length) add('error', 'This objective needs a kitten.');
  if ((rescue || ['exit', 'clear-exit'].includes(level.objective)) && !exits.length) add('error', 'This objective needs an exit.');
  if (clear && !enemies.length) add('warn', 'No enemies to clear.');
  if ((!rescue || enemies.length) && !(level.loadout || []).length && !pickups.length) {
    add('warn', 'The player starts unarmed and there are no weapon pickups.');
  }
  const weaponIds = [...(Array.isArray(level.loadout) ? level.loadout : []), ...pickups.map((pickup) => pickup.weapon)];
  if (clear && enemies.some((enemy) => enemy.rooftop)
    && !weaponIds.some((id) => validWeapon(id) && ![4, 7, 10, 14, 15].includes(id))) {
    add('warn', 'Add a direct-fire weapon so the player can hit rooftop enemies.');
  }

  const spawn = spawns[0];
  let field = null;
  const sx = Math.round(spawn?.x), sy = Math.round(spawn?.y);
  if (cellOf(level, sx, sy) >= 0 && canStand(level, materials, sx, sy, false)) {
    const start = routeCell(level, materials, sx, sy);
    field = reachable(level, materials, start);
  }
  for (const entity of level.entities) {
    const x = Math.round(entity.x), y = Math.round(entity.y);
    const cell = Number.isFinite(entity.x) && Number.isFinite(entity.y) ? cellOf(level, x, y) : -1;
    const label = entity.type === 'enemy' ? `${entity.kind} (wave ${entity.wave || 1})`
      : entity.type === 'pickup' ? `${WEAPONS[entity.weapon] || 'Unknown weapon'} pickup` : entity.type;
    if (!['spawn', 'enemy', 'pickup', 'medkit', 'hamburger', 'kitten', 'exit'].includes(entity.type)) {
      add('error', 'Unknown entity type.', entity);
      continue;
    }
    if (entity.dir !== undefined && (!Number.isInteger(entity.dir) || entity.dir < 0 || entity.dir >= DIRECTIONS.length)) {
      add('error', `${label} has an invalid facing.`, entity);
    }
    if (entity.type === 'enemy') {
      const enemy = ENEMIES.find((entry) => entry.kind === entity.kind);
      if (!enemy) add('error', 'Unknown enemy kind.', entity);
      if (entity.wave !== undefined && (!Number.isInteger(entity.wave) || entity.wave < 1 || entity.wave > 9)) {
        add('error', 'Enemy wave must be a whole number from 1 to 9.', entity);
      }
      if (entity.rooftop && enemy?.weapon === 0) add('error', `${enemy.name} needs a ground position to attack.`, entity);
    }
    if (entity.rooftop !== undefined && (entity.type !== 'enemy' || typeof entity.rooftop !== 'boolean')) {
      add('error', `${label} has an invalid surface.`, entity);
    }
    if (entity.type === 'pickup' && !validWeapon(entity.weapon)) add('error', 'Invalid pickup weapon.', entity);
    if (cell < 0) { add('error', `${label} is outside the map.`, entity); continue; }
    if (!canStand(level, materials, x, y, entity.rooftop)) {
      add('error', entity.rooftop ? `${label} needs a clear roof under its whole body.`
        : `${label} overlaps a blocker or the map edge.`, entity);
    } else if (entity !== spawn && !entity.rooftop && field && !field[cell]
      && routeCell(level, materials, x, y, field) < 0) {
      add('warn', `${label} cannot be reached on foot from the spawn.`, entity);
    }
    if (spawn && entity.type === 'enemy' && Math.hypot(entity.x - spawn.x, entity.y - spawn.y) < 56) {
      add('warn', `${label} starts within 56 px of the spawn.`, entity);
    }
  }
  return issues;
}

// ------------------------------------------------------------------ Lua export

const CODE_START = 35, CODE_SKIP = 93, CODE_BASE = 91;

function codeChar(value) {
  let code = CODE_START + value - 1;
  if (code >= CODE_SKIP) code++;
  return String.fromCharCode(code);
}

function encode(value, width) {
  if (width === 1) return codeChar(value);
  return codeChar(Math.floor((value - 1) / CODE_BASE) + 1) + codeChar(((value - 1) % CODE_BASE) + 1);
}

function luaString(value) {
  return '"' + String(value).replace(/[\x00-\x1f"\\]/g, (char) => char === '"' || char === '\\'
    ? '\\' + char : '\\' + String(char.charCodeAt(0)).padStart(3, '0')) + '"';
}

function encodeLayer(level, layer, materials) {
  const cells = level[layer];
  const legend = [], lookup = new Map(), keys = [];
  for (let i = 0; i < cells.length; i++) {
    const parts = tileKeysAt(cells, level.width, level.height, i, materials);
    if (!parts.length) { keys.push(null); continue; }
    const key = parts.join('@');
    if (!lookup.has(key)) { legend.push(key); lookup.set(key, legend.length); }
    keys.push(lookup.get(key));
  }
  const width = legend.length <= CODE_BASE ? 1 : 2;
  if (legend.length > CODE_BASE * CODE_BASE) throw new Error(`Too many different tiles in the ${layer} layer`);
  const empty = width === 1 ? ' ' : '  ';
  const data = keys.map((k) => (k ? encode(k, width) : empty)).join('');
  return { legend, width, data };
}

export function summary(level) {
  const enemies = level.entities.filter((e) => e.type === 'enemy');
  const waves = new Set(enemies.map((e) => e.wave || 1));
  return {
    id: level.id, name: level.name || level.id, w: level.width, h: level.height,
    objective: level.objective || 'clear', enemies: enemies.length, waves: Math.max(1, waves.size),
    health: level.health || 100, order: level.order || 0, ...(level.par ? { par: level.par } : {}),
    ...(level.brief ? { brief: level.brief } : {}),
  };
}

export function toLua(level, materials) {
  const layers = {};
  for (const layer of ['ground', 'structure', 'roof']) layers[layer] = encodeLayer(level, layer, materials);
  const entity = (e) => {
    const x = Math.round(e.x), y = Math.round(e.y);
    if (e.type === 'spawn') return `{"spawn",${x},${y},${(e.dir ?? 4) + 1}}`;
    if (e.type === 'enemy') return `{"enemy",${luaString(e.kind)},${x},${y},${(e.dir ?? 4) + 1},${e.wave || 1}${e.rooftop ? ',true' : ''}}`;
    if (e.type === 'pickup') return `{"pickup",${e.weapon},${x},${y}}`;
    return `{${luaString(e.type)},${x},${y}}`;
  };
  const meta = summary(level);
  const lines = [
    `-- meta: ${JSON.stringify(meta)}`,
    `-- Generated by tools/level-builder from levels/${level.id}.json. Edit the level there.`,
    'return {',
    `  id=${luaString(level.id)}, name=${luaString(level.name || level.id)}, w=${level.width}, h=${level.height},`,
    `  objective=${luaString(level.objective || 'clear')}, health=${Math.round(level.health || 100)},`
      + (level.par ? ` par=${level.par},` : ''),
    `  loadout={${(level.loadout || []).join(',')}},`,
    `  cell={ground=${layers.ground.width},structure=${layers.structure.width},roof=${layers.roof.width}},`,
    '  legend={',
    ...['ground', 'structure', 'roof'].map((l) => `    ${l}={${layers[l].legend.map(luaString).join(',')}},`),
    '  },',
    ...['ground', 'structure', 'roof'].map((l) => `  ${l}=[=[${layers[l].data}]=],`),
    '  entities={',
    ...level.entities.map((e) => `    ${entity(e)},`),
    '  },',
    '}',
    '',
  ];
  return lines.join('\n');
}

export function indexLua(metas) {
  const sorted = [...metas].sort((a, b) => (a.order || 0) - (b.order || 0) || a.name.localeCompare(b.name));
  const row = (m) => `  {id=${luaString(m.id)}, name=${luaString(m.name)}, w=${m.w}, h=${m.h}, objective=${luaString(m.objective)}, `
    + `enemies=${m.enemies}, waves=${m.waves}, health=${m.health}${m.par ? `, par=${m.par}` : ''}${m.brief ? `, brief=${luaString(m.brief.toUpperCase())}` : ''}},`;
  return ['-- Generated by tools/level-builder. Lists the exported levels in menu order.', 'return {',
    ...sorted.map(row), '}', ''].join('\n');
}
