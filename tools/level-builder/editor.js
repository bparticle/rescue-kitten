import {
  TILE, ROOF_HEIGHT, MIN_W, MIN_H, MAX_W, MAX_H, DIRECTIONS, WEAPONS, WEAPON_ART, ENEMIES, OBJECTIVES,
  materialMap, cellMaterial, cellValue, newLevel, resizeLevel, tileKeysAt, structureBounds, cellFlags, validate, generateTerrain,
  randomTerrain, cellOf,
} from '/format.mjs';

const $ = (id) => document.getElementById(id);
const LAYERS = ['ground', 'structure', 'roof'];
const TOOLS = [
  { id: 'paint', label: 'Paint', key: 'B' }, { id: 'rect', label: 'Rect', key: 'R' },
  { id: 'fill', label: 'Fill', key: 'F' }, { id: 'erase', label: 'Erase', key: 'E' },
  { id: 'pick', label: 'Pick', key: 'I' }, { id: 'house', label: 'House', key: 'H' },
  { id: 'entity', label: 'Entities', key: 'N' }, { id: 'pan', label: 'Pan', key: 'Space' },
];
const PROPS = [
  ['walk', 'Blocks movement', 'Player and enemies walk around it'],
  ['shots', 'Blocks gunfire', 'Bullets, beams, streams and rockets stop here'],
  ['lobs', 'Blocks grenades', 'Thrown and lobbed weapons stop here'],
  ['sight', 'Blocks sight', 'Idle enemies cannot spot you through it'],
  ['pierce', 'Rail pierces', 'Rail rifle shots pass through'],
  ['hp', 'Destructible', ''],
  ['explodes', 'Explodes', ''],
  ['slow', 'Slows movement', ''],
  ['hazard', 'Hurts player', ''],
  ['overhead', 'Rooftop surface', 'Covers ground-level actors and hides while the player is inside'],
];

const state = {
  spec: null, mats: {}, layout: null, img: {}, heroLayout: null,
  level: null, savedJson: '', exportedAt: null,
  undo: [], redo: [],
  tool: 'paint', brush: { ground: 'grass', structure: 'stone-wall', roof: 'roof-red' }, layer: 'structure',
  size: 1, entityType: 'enemy', selected: null,
  zoom: 3, panX: 40, panY: 60, overlay: 'none', roofMode: 'show', grid: true, frame: false,
  hover: null, drag: null, spaceDown: false,
};

// ------------------------------------------------------------ loading

async function loadImage(src) {
  const image = new Image();
  image.src = src;
  await image.decode();
  return image;
}

async function boot() {
  const [spec, layout, heroLayout] = await Promise.all([
    fetch('/assets/materials.json').then((r) => r.json()),
    fetch('/assets/tiles-layout.json').then((r) => r.json()),
    fetch('/assets/walk-layout.json').then((r) => r.json()),
  ]);
  state.spec = spec;
  state.mats = materialMap(spec);
  state.layout = layout;
  state.heroLayout = heroLayout;
  const [tileset, terrain, hero, kitten, ...weapons] = await Promise.all([
    loadImage('/assets/tileset.png'), loadImage('/assets/terrain.png'), loadImage('/assets/idle-hero.png'),
    loadImage('/assets/entities/kitten.png'),
    ...WEAPON_ART.slice(1).map((name) => loadImage(`/assets/weapons/${name}.png`)),
  ]);
  Object.assign(state.img, { tileset, terrain, hero, kitten, weapons: [null, ...weapons] });
  buildUi();
  const list = await refreshLevelList();
  const last = localStorage.getItem('dust-range-level');
  if (last && list.some((l) => l.id === last)) await openLevel(last);
  else if (list.length) await openLevel(list[0].id);
  else setLevel(newLevel('first-level'), true);
  resize();
}

// ------------------------------------------------------------ tile drawing

function drawTerrain(ctx, index, x, y) {
  const tile = Math.floor((index - 1) / 4), rotation = (index - 1) % 4;
  const sx = (tile % 4) * TILE, sy = Math.floor(tile / 4) * TILE;
  ctx.save();
  ctx.translate(x + TILE / 2, y + TILE / 2);
  ctx.rotate(-rotation * Math.PI / 2); // PIL ROTATE_90 turns counter-clockwise
  ctx.drawImage(state.img.terrain, sx, sy, TILE, TILE, -TILE / 2, -TILE / 2, TILE, TILE);
  ctx.restore();
}

function drawMaterial(ctx, id, variant, x, y) {
  const def = state.mats[id];
  if (!def) return;
  if (def.terrain) {
    const index = TERRAIN_DEFAULT[id] || 1;
    drawTerrain(ctx, index, x, y);
    return;
  }
  const entry = state.layout.materials[id];
  if (!entry) return;
  const columns = state.layout.columns;
  const sx = ((variant - 1) % columns) * TILE;
  const sy = (entry.row + Math.floor((variant - 1) / columns)) * TILE;
  ctx.drawImage(state.img.tileset, sx, sy, TILE, TILE, x, y, TILE, TILE);
}
const TERRAIN_DEFAULT = { dirt: 1, grass: 17, mud: 33 };

function preview(canvas, id) {
  canvas.width = TILE; canvas.height = TILE;
  const ctx = canvas.getContext('2d');
  const def = state.mats[id];
  const index = { area: 7, blob: 11, lane: 13 }[def.autotile] || 1;
  if (def.detail) drawMaterial(ctx, 'roof-slate', 16, 0, 0);
  if (def.autotile === 'lane') drawMaterial(ctx, 'road', 16, 0, 0);
  else if (def.underlay) drawMaterial(ctx, def.underlay, 16, 0, 0);
  drawMaterial(ctx, id, index, 0, 0);
}

// ------------------------------------------------------------ map buffers

const view = $('view');
const vctx = view.getContext('2d');
let base, roofs, bctx, rctx;

function allocateBuffers() {
  const { width, height } = state.level;
  base = new OffscreenCanvas(width * TILE, height * TILE);
  roofs = new OffscreenCanvas(width * TILE, height * TILE);
  bctx = base.getContext('2d');
  rctx = roofs.getContext('2d');
  for (let i = 0; i < width * height; i++) paintCell(i);
}

function drawKey(ctx, key, x, y) {
  if (!key) return;
  if (key.startsWith('T')) drawTerrain(ctx, Number(key.slice(1)), x, y);
  else {
    const [id, variant] = key.split('/');
    drawMaterial(ctx, id, Number(variant), x, y);
  }
}

function paintCell(i) {
  const level = state.level;
  const x = (i % level.width) * TILE, y = Math.floor(i / level.width) * TILE;
  bctx.clearRect(x, y, TILE, TILE);
  rctx.clearRect(x, y, TILE, TILE);
  for (const layer of LAYERS) {
    const ctx = layer === 'roof' ? rctx : bctx;
    const [key, base, extra] = tileKeysAt(level[layer], level.width, level.height, i, state.mats);
    if (layer === 'ground') drawKey(ctx, extra, x, y);
    drawKey(ctx, base, x, y);
    drawKey(ctx, key, x, y);
    if (layer === 'roof') drawKey(ctx, extra, x, y);
  }
  const structure = state.mats[cellMaterial(level.structure[i])];
  if (level.roof[i] && structure?.height > ROOF_HEIGHT) {
    const [key] = tileKeysAt(level.structure, level.width, level.height, i, state.mats);
    drawKey(rctx, key, x, y);
  }
}

function repaintAround(cells) {
  const { width, height } = state.level;
  const touched = new Set();
  for (const i of cells) {
    const x = i % width, y = Math.floor(i / width);
    for (let ny = Math.max(0, y - 1); ny <= Math.min(height - 1, y + 1); ny++) {
      for (let nx = Math.max(0, x - 1); nx <= Math.min(width - 1, x + 1); nx++) touched.add(ny * width + nx);
    }
  }
  for (const i of touched) paintCell(i);
}

// ------------------------------------------------------------ rendering

let frameQueued = false;
function render() {
  if (frameQueued) return;
  frameQueued = true;
  requestAnimationFrame(draw);
}

function draw() {
  frameQueued = false;
  const level = state.level;
  if (!level) return;
  const { zoom, panX, panY } = state;
  vctx.setTransform(1, 0, 0, 1, 0, 0);
  vctx.fillStyle = '#141210';
  vctx.fillRect(0, 0, view.width, view.height);
  vctx.imageSmoothingEnabled = false;
  vctx.setTransform(zoom, 0, 0, zoom, panX, panY);
  vctx.drawImage(base, 0, 0);
  const W = level.width * TILE, H = level.height * TILE;

  if (state.roofMode !== 'hide') {
    vctx.globalAlpha = state.roofMode === 'ghost' ? 0.35 : 1;
    vctx.drawImage(roofs, 0, 0);
    vctx.globalAlpha = 1;
  }
  if (state.overlay !== 'none') drawOverlay();
  if (state.grid && zoom >= 2) {
    vctx.strokeStyle = 'rgba(28,25,22,.28)';
    vctx.lineWidth = 1 / zoom;
    vctx.beginPath();
    for (let x = 0; x <= W; x += TILE) { vctx.moveTo(x, 0); vctx.lineTo(x, H); }
    for (let y = 0; y <= H; y += TILE) { vctx.moveTo(0, y); vctx.lineTo(W, y); }
    vctx.stroke();
  }
  vctx.strokeStyle = '#ecd590';
  vctx.lineWidth = 2 / zoom;
  vctx.strokeRect(0, 0, W, H);

  for (const entity of level.entities) if (!entity.rooftop) drawEntity(entity);
  for (const entity of level.entities) if (entity.rooftop) drawEntity(entity);
  drawPreview();
  if (state.frame) {
    const spawn = level.entities.find((e) => e.type === 'spawn');
    const center = state.hover ? state.hover.px : spawn ? { x: spawn.x, y: spawn.y } : null;
    if (center) {
      const left = Math.max(0, Math.min(W - 160, Math.round(center.x) - 80));
      const top = Math.max(0, Math.min(H - 97, Math.round(center.y) - 48));
      vctx.strokeStyle = '#ff9278';
      vctx.setLineDash([4 / zoom, 3 / zoom]);
      vctx.strokeRect(left, top, 160, 97);
      vctx.setLineDash([]);
    }
  }
}

const OVERLAY_COLORS = {
  walk: '255,84,64', shots: '255,196,40', lobs: '80,200,255', sight: '190,120,255', hp: '120,230,90', roof: '121,225,230',
};

function drawOverlay() {
  const level = state.level;
  const mode = state.overlay;
  vctx.fillStyle = 'rgba(16,14,12,.55)';
  vctx.fillRect(0, 0, level.width * TILE, level.height * TILE);
  for (let i = 0; i < level.width * level.height; i++) {
    const f = cellFlags(level, i, state.mats);
    const structure = state.mats[cellMaterial(level.structure[i])];
    const ground = state.mats[cellMaterial(level.ground[i])];
    if (mode === 'roof') {
      if (!f.overhead) continue;
      vctx.fillStyle = `rgba(${OVERLAY_COLORS.roof},.55)`;
      fillCell(i);
      if (structure?.walk && structure.height > ROOF_HEIGHT) {
        vctx.fillStyle = `rgba(${OVERLAY_COLORS.walk},.85)`;
        fillFootprint(level, i, structureBounds(level, i, state.mats));
      }
      continue;
    }
    if (mode === 'lobs' && f.roofLobs) {
      vctx.fillStyle = `rgba(${OVERLAY_COLORS.lobs},.35)`;
      fillCell(i);
    }
    let alpha = 0;
    if (mode === 'walk') alpha = f.walk ? 0.8 : f.slow < 1 ? 0.3 : 0;
    else if (mode === 'shots') alpha = f.shots ? (f.pierce ? 0.4 : 0.85) : 0;
    else if (mode === 'lobs') alpha = f.lobs ? 0.85 : 0;
    else if (mode === 'sight') alpha = f.sight ? 0.85 : 0;
    else if (mode === 'hp') alpha = f.explodes ? 0.9 : f.hp ? 0.35 + Math.min(0.5, f.hp / 640) : 0;
    if (mode === 'walk' && f.hazard) { vctx.fillStyle = 'rgba(255,60,40,.45)'; fillCell(i); }
    if (!alpha) continue;
    vctx.fillStyle = mode === 'hp' && f.explodes ? `rgba(255,120,60,${alpha})` : `rgba(${OVERLAY_COLORS[mode]},${alpha})`;
    const rectangles = structure?.[mode] && !ground?.[mode] ? structureBounds(level, i, state.mats) : null;
    fillFootprint(level, i, rectangles);
  }
}

function fillFootprint(level, i, rectangles) {
  if (!rectangles) { fillCell(i); return; }
  const x = (i % level.width) * TILE, y = Math.floor(i / level.width) * TILE;
  vctx.beginPath();
  for (const [x0, y0, x1, y1] of rectangles) vctx.rect(x + x0, y + y0, x1 - x0, y1 - y0);
  vctx.fill();
}

function fillCell(i) {
  const w = state.level.width;
  vctx.fillRect((i % w) * TILE, Math.floor(i / w) * TILE, TILE, TILE);
}

function heroFrame(weapon, dir) {
  const columns = state.heroLayout.idleSheet.columnsLeftToRight;
  const column = Math.max(0, columns.indexOf(WEAPON_ART[weapon] || 'unarmed'));
  return [column * 28, (dir ?? 4) * 28];
}

function drawEntity(entity) {
  const { x, y } = entity;
  const selected = entity === state.selected;
  vctx.save();
  if (entity.type === 'spawn' || entity.type === 'enemy') {
    const enemy = entity.type === 'enemy' && ENEMIES.find((e) => e.kind === entity.kind);
    const [sx, sy] = heroFrame(enemy ? enemy.weapon : 1, entity.dir);
    vctx.fillStyle = 'rgba(0,0,0,.25)';
    vctx.fillRect(x - 4, y + 3, 9, 3);
    vctx.strokeStyle = entity.rooftop ? '#79e1e6' : enemy ? enemy.color : '#b4cc92';
    vctx.lineWidth = 1.5;
    vctx.beginPath(); vctx.arc(x, y, 9, 0, Math.PI * 2); vctx.stroke();
    vctx.drawImage(state.img.hero, sx, sy, 28, 28, x - 14, y - 14, 28, 28);
    if (enemy) {
      vctx.fillStyle = '#1c1916';
      vctx.fillRect(x + 5, y - 13, 7, 7);
      vctx.fillStyle = '#ecd590';
      vctx.font = 'bold 6px monospace';
      vctx.fillText(String(entity.wave || 1), x + 6.5, y - 7.5);
      if (entity.rooftop) {
        vctx.strokeStyle = '#79e1e6';
        vctx.beginPath();
        vctx.moveTo(x - 10, y - 8);
        vctx.lineTo(x - 6, y - 12);
        vctx.lineTo(x - 2, y - 8);
        vctx.stroke();
      }
    } else {
      vctx.fillStyle = '#b4cc92';
      vctx.font = 'bold 6px monospace';
      vctx.fillText('YOU', x - 6, y - 11);
    }
  } else if (['pickup', 'medkit', 'hamburger'].includes(entity.type)) {
    const icon = state.img.weapons[entity.weapon];
    const medkit = entity.type === 'medkit';
    const hamburger = entity.type === 'hamburger';
    const half = Math.max(4, Math.floor((icon?.width || 13) / 3));
    vctx.fillStyle = '#7b6b57';
    vctx.fillRect(x - half + 1, y + 4, 2 * half - 1, 3);
    vctx.fillStyle = '#625445';
    vctx.fillRect(x - half, y + 5, 2 * half + 1, 1);
    vctx.fillStyle = medkit ? '#b4cc92' : hamburger ? '#ffc16a' : '#ecd590';
    vctx.fillRect(x - half - 4, y + 5, 2, 1);
    vctx.fillRect(x + half + 3, y + 5, 2, 1);
    if (medkit) {
      vctx.fillStyle = '#262320';
      vctx.fillRect(x - 6, y - 9, 13, 11);
      vctx.fillStyle = '#f6e9d0';
      vctx.fillRect(x - 5, y - 8, 11, 8);
      vctx.fillStyle = '#b4cc92';
      vctx.fillRect(x - 3, y - 7, 7, 6);
      vctx.fillStyle = '#40563d';
      vctx.fillRect(x - 2, y - 5, 5, 1);
      vctx.fillRect(x, y - 7, 1, 5);
    } else if (hamburger) {
      vctx.fillStyle = '#262320';
      vctx.fillRect(x - 4, y - 10, 9, 11);
      vctx.fillRect(x - 6, y - 8, 13, 8);
      vctx.fillStyle = '#dc913e';
      vctx.fillRect(x - 5, y - 7, 11, 2);
      vctx.fillRect(x - 4, y - 3, 9, 2);
      vctx.fillStyle = '#ffc16a';
      vctx.fillRect(x - 3, y - 9, 7, 2);
      vctx.fillRect(x - 3, y - 3, 7, 1);
      vctx.fillStyle = '#b4cc92';
      vctx.fillRect(x - 5, y - 5, 11, 1);
      vctx.fillStyle = '#854635';
      vctx.fillRect(x - 4, y - 4, 9, 1);
      vctx.fillStyle = '#f6e9d0';
      vctx.fillRect(x + 2, y - 8, 1, 1);
    } else if (icon) {
      vctx.drawImage(icon, x - Math.floor(icon.width / 2), y - 4 - Math.floor(icon.height / 2));
    }
  } else if (entity.type === 'kitten') {
    const kitten = state.img.kitten;
    vctx.fillStyle = '#7b6b57';
    vctx.fillRect(x - 6, y + 3, 13, 2);
    vctx.fillStyle = '#b4cc92';
    vctx.fillRect(x - 9, y + 1, 2, 1);
    vctx.fillRect(x + 8, y + 1, 2, 1);
    vctx.drawImage(kitten, x - Math.floor(kitten.width / 2), y - 8);
  } else if (entity.type === 'exit') {
    vctx.strokeStyle = '#ecd590';
    vctx.lineWidth = 2;
    vctx.strokeRect(x - 7, y - 7, 14, 14);
    vctx.fillStyle = '#ecd590';
    vctx.font = 'bold 6px monospace';
    vctx.fillText('EXIT', x - 7, y + 2);
  }
  if (selected) {
    vctx.strokeStyle = '#ffffff';
    vctx.lineWidth = 1 / state.zoom * 2;
    vctx.setLineDash([2, 2]);
    vctx.strokeRect(x - 13, y - 14, 26, 28);
  }
  vctx.restore();
}

function drawPreview() {
  const hover = state.hover;
  if (!hover || hover.cell < 0) return;
  const level = state.level;
  vctx.lineWidth = 1.5 / state.zoom;
  if ((state.tool === 'rect' || state.tool === 'house') && state.drag && state.drag.kind === 'rect') {
    const [x0, y0, x1, y1] = rectCells(state.drag.start, hover.cell);
    vctx.strokeStyle = '#ecd590';
    vctx.fillStyle = 'rgba(236,213,144,.15)';
    vctx.fillRect(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE);
    vctx.strokeRect(x0 * TILE, y0 * TILE, (x1 - x0 + 1) * TILE, (y1 - y0 + 1) * TILE);
    return;
  }
  if (['paint', 'erase', 'rect', 'fill', 'house', 'pick'].includes(state.tool)) {
    const size = ['paint', 'erase'].includes(state.tool) ? state.size : 1;
    const cx = hover.cell % level.width - Math.floor((size - 1) / 2);
    const cy = Math.floor(hover.cell / level.width) - Math.floor((size - 1) / 2);
    vctx.strokeStyle = state.tool === 'erase' ? '#ff9278' : '#ffffff';
    vctx.strokeRect(cx * TILE, cy * TILE, size * TILE, size * TILE);
  }
}

// ------------------------------------------------------------ editing

function snapshot() {
  const l = state.level;
  return JSON.stringify(l);
}

function pushUndo() {
  state.undo.push(snapshot());
  if (state.undo.length > 120) state.undo.shift();
  state.redo = [];
}

function restore(json) {
  const sizeChanged = (() => { const next = JSON.parse(json); return next.width !== state.level.width || next.height !== state.level.height; })();
  state.level = JSON.parse(json);
  state.selected = null;
  if (sizeChanged) allocateBuffers();
  else for (let i = 0; i < state.level.width * state.level.height; i++) paintCell(i);
  changed();
  syncLevelForm();
}

function undo() {
  if (!state.undo.length) return;
  state.redo.push(snapshot());
  restore(state.undo.pop());
}

function redo() {
  if (!state.redo.length) return;
  state.undo.push(snapshot());
  restore(state.redo.pop());
}

function changed() {
  render();
  scheduleChecks();
  updateStatusDirty();
}

function valueFor(id, previous) {
  const def = state.mats[id];
  if (def.terrain) return cellMaterial(previous) === id ? previous : randomTerrain(id);
  return cellValue(id, previous, state.mats);
}

function setCells(layer, cells, valueFn) {
  const level = state.level;
  const touched = [];
  for (const i of cells) {
    const value = valueFn(i, level[layer][i]);
    if (level[layer][i] === value) continue;
    level[layer][i] = value;
    touched.push(i);
  }
  if (touched.length) { repaintAround(touched); changed(); }
  return touched.length;
}

function brushCells(cell) {
  const level = state.level;
  const size = state.size;
  const cx = cell % level.width - Math.floor((size - 1) / 2);
  const cy = Math.floor(cell / level.width) - Math.floor((size - 1) / 2);
  const out = [];
  for (let y = cy; y < cy + size; y++) for (let x = cx; x < cx + size; x++) {
    if (x >= 0 && y >= 0 && x < level.width && y < level.height) out.push(y * level.width + x);
  }
  return out;
}

function lineCells(a, b, connected) {
  const w = state.level.width;
  let x0 = a % w, y0 = Math.floor(a / w);
  const x1 = b % w, y1 = Math.floor(b / w);
  const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  let err = dx + dy;
  const out = [];
  for (;;) {
    out.push(y0 * w + x0);
    if (x0 === x1 && y0 === y1) break;
    const e2 = 2 * err;
    if (e2 >= dy) {
      err += dy; x0 += sx;
      if (connected && e2 <= dx) out.push(y0 * w + x0);
    }
    if (e2 <= dx) { err += dx; y0 += sy; }
  }
  return out;
}

function rectCells(a, b) {
  const w = state.level.width;
  return [Math.min(a % w, b % w), Math.min(Math.floor(a / w), Math.floor(b / w)),
    Math.max(a % w, b % w), Math.max(Math.floor(a / w), Math.floor(b / w))];
}

function eraseValue(layer) {
  return layer === 'ground' ? (_, previous) => previous?.split('@')[1] || randomTerrain('dirt') : () => '';
}

function stroke(path) {
  const layer = state.layer;
  const cells = [];
  const seen = state.drag.seen;
  for (const step of path) {
    for (const cell of brushCells(step)) {
      if (seen.has(cell)) continue;
      seen.add(cell);
      cells.push(cell);
    }
  }
  if (state.tool === 'erase') setCells(layer, cells, eraseValue(layer));
  else setCells(layer, cells, (_, previous) => valueFor(state.brush[layer], previous));
}

function floodFill(cell) {
  const level = state.level, layer = state.layer;
  const target = cellMaterial(level[layer][cell]) || '';
  const want = state.brush[layer];
  if (target === want) return;
  const w = level.width, h = level.height;
  const seen = new Uint8Array(w * h), stack = [cell], cells = [];
  seen[cell] = 1;
  while (stack.length) {
    const i = stack.pop();
    cells.push(i);
    const x = i % w, y = Math.floor(i / w);
    for (const [nx, ny] of [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]) {
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      const j = ny * w + nx;
      if (!seen[j] && (cellMaterial(level[layer][j]) || '') === target) { seen[j] = 1; stack.push(j); }
    }
  }
  setCells(layer, cells, (_, previous) => valueFor(want, previous));
}

function fillRect(a, b, outline) {
  const [x0, y0, x1, y1] = rectCells(a, b);
  const w = state.level.width, cells = [];
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    if (!outline || x === x0 || x === x1 || y === y0 || y === y1) cells.push(y * w + x);
  }
  if (state.tool === 'erase') setCells(state.layer, cells, eraseValue(state.layer));
  else setCells(state.layer, cells, (_, previous) => valueFor(state.brush[state.layer], previous));
}

function buildHouse(a, b) {
  const [x0, y0, x1, y1] = rectCells(a, b);
  if (x1 - x0 < 2 || y1 - y0 < 2) { setStatus('Houses need at least 3 x 3 tiles.', 'err'); return; }
  const w = state.level.width;
  const wall = $('house-wall').value, floor = $('house-floor').value, roof = $('house-roof').value;
  const windows = $('house-windows').checked;
  const door = Math.floor((x0 + x1) / 2);
  const all = [], structure = new Map();
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    const i = y * w + x;
    all.push(i);
    const edge = x === x0 || x === x1 || y === y0 || y === y1;
    let value = '';
    if (edge) {
      value = wall;
      const corner = (x === x0 || x === x1) && (y === y0 || y === y1);
      if (y === y1 && x === door) value = 'doorway';
      else if (windows && !corner) {
        const horizontal = y === y0 || y === y1;
        const along = horizontal ? x - x0 : y - y0;
        const length = horizontal ? x1 - x0 : y1 - y0;
        if (length >= 4 && along % 3 === 2 && along < length - 1 && !(y === y1 && Math.abs(x - door) < 2)) value = 'window';
      }
    }
    structure.set(i, value);
  }
  setCells('ground', all, (_, previous) => valueFor(floor, previous));
  setCells('structure', all, (i) => structure.get(i));
  setCells('roof', all, () => roof);
}

function pick(cell) {
  const level = state.level;
  for (const layer of ['roof', 'structure', 'ground']) {
    if (layer === 'roof' && state.roofMode === 'hide') continue;
    const value = level[layer][cell];
    const id = layer === 'roof' && value?.includes('@') ? value.split('@')[1] : cellMaterial(value);
    if (id) { selectMaterial(id); return; }
  }
}

// ------------------------------------------------------------ entities

function entityAt(px, py, rooftop) {
  const list = state.level.entities;
  for (let i = list.length - 1; i >= 0; i--) {
    const e = list[i];
    if (rooftop !== undefined && !!e.rooftop !== rooftop) continue;
    if (Math.abs(e.x - px) <= 10 && Math.abs(e.y - py) <= 12) return e;
  }
  return null;
}

function snapPoint(px, py, free) {
  if (free) return [Math.round(px), Math.round(py)];
  return [Math.floor(px / TILE) * TILE + 8, Math.floor(py / TILE) * TILE + 8];
}

function placeEntity(px, py, free) {
  const level = state.level;
  const [x, y] = snapPoint(px, py, free);
  pushUndo();
  const type = state.entityType;
  let entity;
  if (type === 'spawn' || type === 'exit' || type === 'kitten') {
    level.entities = level.entities.filter((e) => e.type !== type);
    entity = type === 'spawn' ? { type, x, y, dir: Number($('ent-dir').value) } : { type, x, y };
  } else if (type === 'enemy') {
    entity = { type, kind: $('ent-kind').value, x, y, dir: Number($('ent-dir').value), wave: Number($('ent-wave').value) || 1 };
    if ($('ent-surface').value === 'roof') entity.rooftop = true;
  } else if (type === 'pickup') {
    entity = { type, weapon: Number($('ent-weapon').value), x, y };
  } else {
    entity = { type, x, y };
  }
  level.entities.push(entity);
  selectEntity(entity);
  changed();
}

function selectEntity(entity) {
  state.selected = entity;
  if (entity) {
    setEntityType(entity.type, false);
    if (entity.kind) $('ent-kind').value = entity.kind;
    if (entity.dir !== undefined) $('ent-dir').value = entity.dir;
    if (entity.wave) $('ent-wave').value = entity.wave;
    if (entity.type === 'enemy') $('ent-surface').value = entity.rooftop ? 'roof' : 'ground';
    if (entity.weapon !== undefined) $('ent-weapon').value = entity.weapon;
  }
  render();
}

function deleteSelected() {
  if (!state.selected) return;
  pushUndo();
  state.level.entities = state.level.entities.filter((e) => e !== state.selected);
  state.selected = null;
  changed();
}

function setEntityType(type, deselect = true) {
  state.entityType = type;
  for (const b of $('entity-buttons').children) b.classList.toggle('on', b.dataset.type === type);
  for (const label of $('entity-form').children) {
    label.classList.toggle('hidden', !label.dataset.for.split(' ').includes(type));
  }
  if (deselect && state.selected && state.selected.type !== type) state.selected = null;
  render();
}

function editSelected(apply) {
  if (!state.selected) return;
  pushUndo();
  apply(state.selected);
  changed();
}

// ------------------------------------------------------------ input

function toWorld(event) {
  const rect = view.getBoundingClientRect();
  const sx = (event.clientX - rect.left) * devicePixelRatio, sy = (event.clientY - rect.top) * devicePixelRatio;
  const px = (sx - state.panX) / state.zoom, py = (sy - state.panY) / state.zoom;
  return { px: { x: px, y: py }, cell: cellOf(state.level, px, py) };
}

view.addEventListener('contextmenu', (e) => e.preventDefault());
view.addEventListener('pointerdown', (event) => {
  view.setPointerCapture(event.pointerId);
  const at = toWorld(event);
  state.hover = at;
  const panning = event.button === 1 || event.button === 2 || state.spaceDown || state.tool === 'pan';
  if (panning) {
    state.drag = { kind: 'pan', x: event.clientX, y: event.clientY, panX: state.panX, panY: state.panY };
    return;
  }
  if (event.button !== 0) return;
  if (event.altKey && at.cell >= 0) { pick(at.cell); return; }
  if (state.tool === 'entity') {
    const rooftop = state.entityType === 'enemy' ? $('ent-surface').value === 'roof' : undefined;
    const hit = entityAt(at.px.x, at.px.y, rooftop);
    if (hit) {
      selectEntity(hit);
      pushUndo();
      state.drag = { kind: 'entity', entity: hit, moved: false };
    } else if (at.cell >= 0) placeEntity(at.px.x, at.px.y, event.shiftKey);
    return;
  }
  if (at.cell < 0) return;
  if (state.tool === 'pick') { pick(at.cell); return; }
  if (state.tool === 'fill') { pushUndo(); floodFill(at.cell); return; }
  if (state.tool === 'rect' || state.tool === 'house') { state.drag = { kind: 'rect', start: at.cell }; render(); return; }
  pushUndo();
  state.drag = { kind: 'paint', last: at.cell, seen: new Set() };
  stroke([at.cell]);
});

view.addEventListener('pointermove', (event) => {
  const at = toWorld(event);
  state.hover = at;
  const drag = state.drag;
  if (drag && drag.kind === 'pan') {
    state.panX = drag.panX + (event.clientX - drag.x) * devicePixelRatio;
    state.panY = drag.panY + (event.clientY - drag.y) * devicePixelRatio;
  } else if (drag && drag.kind === 'paint' && at.cell >= 0 && at.cell !== drag.last) {
    const brush = state.mats[state.brush[state.layer]];
    const connected = state.tool === 'paint' && ['blob', 'lane'].includes(brush.autotile);
    stroke(lineCells(drag.last, at.cell, connected));
    drag.last = at.cell;
  } else if (drag && drag.kind === 'entity') {
    const [x, y] = snapPoint(at.px.x, at.px.y, event.shiftKey);
    const level = state.level;
    if (x >= 0 && y >= 0 && x < level.width * TILE && y < level.height * TILE) {
      drag.entity.x = x; drag.entity.y = y; drag.moved = true;
      scheduleChecks();
    }
  }
  showCellInfo(at.cell);
  render();
});

view.addEventListener('pointerup', (event) => {
  const drag = state.drag;
  state.drag = null;
  if (!drag) return;
  if (drag.kind === 'rect') {
    const at = toWorld(event);
    const end = at.cell >= 0 ? at.cell : drag.start;
    pushUndo();
    if (state.tool === 'house') buildHouse(drag.start, end);
    else fillRect(drag.start, end, event.shiftKey);
  } else if (drag.kind === 'entity') {
    if (!drag.moved) state.undo.pop();
    else changed();
  }
  render();
});

view.addEventListener('pointerleave', () => { state.hover = null; render(); });

view.addEventListener('wheel', (event) => {
  event.preventDefault();
  const rect = view.getBoundingClientRect();
  const sx = (event.clientX - rect.left) * devicePixelRatio, sy = (event.clientY - rect.top) * devicePixelRatio;
  const before = state.zoom;
  const next = Math.max(1, Math.min(10, before * (event.deltaY < 0 ? 1.25 : 0.8)));
  state.zoom = Math.round(next * 4) / 4;
  state.panX = sx - (sx - state.panX) * (state.zoom / before);
  state.panY = sy - (sy - state.panY) * (state.zoom / before);
  $('zoom-label').textContent = `${Math.round(state.zoom * 100)}%`;
  render();
}, { passive: false });

window.addEventListener('keydown', (event) => {
  const typing = ['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement.tagName);
  const mod = event.ctrlKey || event.metaKey;
  if (mod && event.key.toLowerCase() === 's') { event.preventDefault(); save(); return; }
  if (typing) return;
  if (mod && event.key.toLowerCase() === 'z') { event.preventDefault(); event.shiftKey ? redo() : undo(); return; }
  if (mod && event.key.toLowerCase() === 'y') { event.preventDefault(); redo(); return; }
  if (event.key === ' ') { state.spaceDown = true; event.preventDefault(); return; }
  if (event.key === 'Delete' || event.key === 'Backspace') { deleteSelected(); return; }
  if (event.key === 'Escape') { state.drag = null; state.selected = null; render(); return; }
  const tool = TOOLS.find((t) => t.key.toLowerCase() === event.key.toLowerCase());
  if (tool && !mod) { setTool(tool.id); return; }
  const k = event.key.toLowerCase();
  if (k === 'g') { $('opt-grid').checked = state.grid = !state.grid; render(); }
  if (k === 'o') cycle('overlay-mode', 'overlay');
  if (k === 't') cycle('roof-mode', 'roofMode');
  if (k === '[') setSize(Math.max(1, state.size - 1));
  if (k === ']') setSize(Math.min(3, state.size + 1));
  if (k === '1') setLayer('ground');
  if (k === '2') setLayer('structure');
  if (k === '3') setLayer('roof');
  const pan = 48;
  if (event.key === 'ArrowLeft') { state.panX += pan; render(); }
  if (event.key === 'ArrowRight') { state.panX -= pan; render(); }
  if (event.key === 'ArrowUp') { state.panY += pan; render(); }
  if (event.key === 'ArrowDown') { state.panY -= pan; render(); }
});
window.addEventListener('keyup', (event) => { if (event.key === ' ') state.spaceDown = false; });
window.addEventListener('beforeunload', (event) => {
  if (isDirty()) { event.preventDefault(); event.returnValue = ''; }
});

function cycle(groupId, key) {
  const buttons = [...$(groupId).children];
  const index = buttons.findIndex((b) => b.dataset.mode === state[key]);
  const next = buttons[(index + 1) % buttons.length];
  next.click();
}

// ------------------------------------------------------------ ui

function setTool(id) {
  state.tool = id;
  for (const b of $('tools').children) b.classList.toggle('on', b.dataset.tool === id);
  $('house-options').classList.toggle('hidden', id !== 'house');
  $('brush-row').classList.toggle('hidden', !['paint', 'erase'].includes(id));
  view.style.cursor = id === 'pan' ? 'grab' : id === 'entity' ? 'default' : 'crosshair';
  render();
}

function setSize(size) {
  state.size = size;
  for (const b of $('brush-size').children) b.classList.toggle('on', Number(b.dataset.size) === size);
  render();
}

function setLayer(layer) {
  state.layer = layer;
  $('layer-pill').textContent = layer;
  for (const el of document.querySelectorAll('.swatch')) {
    el.classList.toggle('on', el.dataset.id === state.brush[layer] && state.mats[el.dataset.id].layer === layer);
  }
  showTileInfo(state.brush[layer]);
}

function selectMaterial(id) {
  const def = state.mats[id];
  state.brush[def.layer] = id;
  if (['entity', 'pick', 'pan', 'house'].includes(state.tool)) setTool('paint');
  setLayer(def.layer);
}

function flagsHtml(def) {
  return ['walk', 'shots', 'lobs', 'sight', 'hp'].filter((k) => def[k])
    .map((k) => `<span class="flag f-${k}"></span>`).join('');
}

function describe(def, key) {
  const value = def[key];
  if (key === 'hp') return value ? `Destructible: ${value} HP${def.breaksTo ? `, leaves ${state.mats[def.breaksTo].name.toLowerCase()}` : ''}` : 'Indestructible';
  if (key === 'explodes') return value ? `Explodes: ${value.damage} damage, ${value.radius} px radius` : 'Does not explode';
  if (key === 'slow') return value ? `Movement at ${Math.round(value * 100)}% speed` : 'Normal speed';
  if (key === 'hazard') return value ? `Hurts the player ${value} HP per second` : 'Harmless';
  return null;
}

function showTileInfo(id) {
  const def = state.mats[id];
  if (!def) { $('tile-info').textContent = ''; return; }
  const canvas = document.createElement('canvas');
  preview(canvas, id);
  const rows = (def.detail ? [] : PROPS).map(([key, label, note]) => {
    const yes = key === 'slow' ? def.slow && def.slow < 1 : !!def[key];
    const text = describe(def, key) || (yes ? label : `${label.replace('Blocks', 'Does not block').replace('Rail pierces', 'Rail does not pierce')}`);
    if (key === 'overhead' && !yes) return '';
    if (key === 'pierce' && !def.shots) return '';
    return `<li class="${yes ? 'yes' : 'no'}" title="${note}"><span class="mark">${yes ? '✓' : '–'}</span><span>${key === 'overhead' ? label : text}</span></li>`;
  }).join('');
  const auto = { area: 'Edges and corners follow the outline', blob: 'Joins adjacent pieces',
    orient: 'Turns to follow walls', lane: 'Follows the road and adjacent markings' }[def.autotile];
  const info = def.detail ? 'Paint over an existing roof'
    : def.terrain || def.variants ? 'Texture varies across the map' : auto || 'Single tile';
  const height = def.overhead ? ROOF_HEIGHT : def.height;
  $('tile-info').innerHTML = `<div class="title"><div></div><div><b>${def.name}</b><span>${def.layer} · ${info}${height ? ` · ${height} px high` : ''}</span></div></div><ul class="props">${rows}</ul>`;
  $('tile-info').querySelector('.title > div').replaceWith(canvas);
}

function buildPalette() {
  const container = $('palette');
  container.innerHTML = '';
  const groups = new Map();
  for (const def of state.spec.materials) {
    const key = `${def.layer}|${def.category}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(def);
  }
  for (const [key, defs] of groups) {
    const [layer, category] = key.split('|');
    const h = document.createElement('h3');
    h.textContent = `${category} · ${layer}`;
    container.append(h);
    const grid = document.createElement('div');
    grid.className = 'grid';
    for (const def of defs) {
      const el = document.createElement('button');
      el.className = 'swatch';
      el.dataset.id = def.id;
      el.title = def.name;
      const canvas = document.createElement('canvas');
      preview(canvas, def.id);
      el.innerHTML = `<span class="flags">${flagsHtml(def)}</span>`;
      el.append(canvas);
      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = def.name;
      el.append(name);
      el.addEventListener('click', () => selectMaterial(def.id));
      grid.append(el);
    }
    container.append(grid);
  }
}

function options(select, entries) {
  select.innerHTML = entries.map(([value, label]) => `<option value="${value}">${label}</option>`).join('');
}

function buildUi() {
  $('tools').innerHTML = TOOLS.map((t) => `<button data-tool="${t.id}">${t.label}<kbd>${t.key}</kbd></button>`).join('');
  for (const b of $('tools').children) b.addEventListener('click', () => setTool(b.dataset.tool));
  for (const b of $('brush-size').children) b.addEventListener('click', () => setSize(Number(b.dataset.size)));
  buildPalette();
  const of = (layer, filter = () => true) => state.spec.materials.filter((m) => m.layer === layer && filter(m)).map((m) => [m.id, m.name]);
  options($('house-wall'), of('structure', (m) => m.category === 'Walls' && m.autotile === 'blob'));
  options($('house-floor'), of('ground', (m) => !m.walk && !m.slow && m.autotile !== 'lane'));
  $('house-floor').value = 'wood-floor';
  options($('house-roof'), of('roof', (m) => m.overhead));
  options($('ent-kind'), ENEMIES.map((e) => [e.kind, `${e.name} – ${e.role}`]));
  options($('ent-dir'), DIRECTIONS.map((d, i) => [i, d]));
  $('ent-dir').value = 4;
  options($('ent-weapon'), WEAPONS.slice(1).map((w, i) => [i + 1, w]));
  options($('lvl-objective'), Object.entries(OBJECTIVES));
  $('lvl-loadout').innerHTML = WEAPONS.slice(1).map((w, i) => `<label><input type="checkbox" value="${i + 1}">${w}</label>`).join('');

  for (const b of $('entity-buttons').children) b.addEventListener('click', () => { setEntityType(b.dataset.type); setTool('entity'); });
  $('ent-kind').addEventListener('change', () => editSelected((e) => { if (e.type === 'enemy') e.kind = $('ent-kind').value; }));
  $('ent-wave').addEventListener('change', () => {
    $('ent-wave').value = Math.min(9, Math.max(1, Math.round(Number($('ent-wave').value)) || 1));
    editSelected((e) => { if (e.type === 'enemy') e.wave = Number($('ent-wave').value); });
  });
  $('ent-surface').addEventListener('change', () => editSelected((e) => {
    if (e.type === 'enemy') e.rooftop = $('ent-surface').value === 'roof';
  }));
  $('ent-dir').addEventListener('change', () => editSelected((e) => {
    if (e.type === 'spawn' || e.type === 'enemy') e.dir = Number($('ent-dir').value);
  }));
  $('ent-weapon').addEventListener('change', () => editSelected((e) => { if (e.type === 'pickup') e.weapon = Number($('ent-weapon').value); }));

  const field = (id, apply) => $(id).addEventListener('change', () => { pushUndo(); apply($(id).value); changed(); });
  field('lvl-name', (v) => { state.level.name = v.trim() || 'Untitled'; });
  field('lvl-id', (v) => { state.level.id = v.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '-'); $('lvl-id').value = state.level.id; });
  field('lvl-objective', (v) => { state.level.objective = v; });
  field('lvl-brief', (v) => {
    const brief = v.trim().replace(/\s+/g, ' ');
    if (brief) state.level.brief = brief; else delete state.level.brief;
  });
  field('lvl-health', (v) => {
    state.level.health = Math.max(10, Math.min(999, Math.round(Number(v)) || 100));
    $('lvl-health').value = state.level.health;
  });
  field('lvl-par', (v) => {
    const par = Math.round(Number(v));
    if (par >= 1) state.level.par = Math.min(3599, par); else delete state.level.par;
    $('lvl-par').value = state.level.par || '';
  });
  field('lvl-order', (v) => { state.level.order = Number(v) || 0; });
  field('lvl-seed', (v) => { state.level.seed = Number(v) || 1; });
  $('lvl-loadout').addEventListener('change', () => {
    pushUndo();
    state.level.loadout = [...$('lvl-loadout').querySelectorAll('input:checked')].map((i) => Number(i.value));
    changed();
  });
  $('btn-resize').addEventListener('click', () => {
    const w = Number($('lvl-w').value), h = Number($('lvl-h').value);
    if (!Number.isInteger(w) || !Number.isInteger(h) || w < MIN_W || h < MIN_H || w > MAX_W || h > MAX_H) {
      setStatus(`Use whole dimensions from ${MIN_W} × ${MIN_H} to ${MAX_W} × ${MAX_H}.`, 'err');
      return;
    }
    pushUndo();
    state.level = resizeLevel(state.level, w, h, Math.round(Number($('lvl-ax').value)) || 0, Math.round(Number($('lvl-ay').value)) || 0);
    selectEntity(null);
    $('lvl-ax').value = 0; $('lvl-ay').value = 0;
    allocateBuffers();
    changed();
    syncLevelForm();
  });
  $('btn-terrain').addEventListener('click', () => {
    pushUndo();
    const fresh = generateTerrain(state.level.width, state.level.height, state.level.seed || 427);
    setCells('ground', state.level.ground.map((_, i) => i), (i) => {
      const id = cellMaterial(state.level.ground[i]);
      return state.mats[id] && state.mats[id].terrain ? fresh[i] : state.level.ground[i];
    });
  });

  for (const b of $('overlay-mode').children) b.addEventListener('click', () => {
    state.overlay = b.dataset.mode;
    for (const o of $('overlay-mode').children) o.classList.toggle('on', o === b);
    render();
  });
  for (const b of $('roof-mode').children) b.addEventListener('click', () => {
    state.roofMode = b.dataset.mode;
    for (const o of $('roof-mode').children) o.classList.toggle('on', o === b);
    render();
  });
  $('opt-grid').addEventListener('change', (e) => { state.grid = e.target.checked; render(); });
  $('opt-frame').addEventListener('change', (e) => { state.frame = e.target.checked; render(); });

  $('btn-new').addEventListener('click', newLevelPrompt);
  $('btn-save').addEventListener('click', save);
  $('btn-export').addEventListener('click', exportLevel);
  $('btn-package').addEventListener('click', buildZip);
  $('btn-undo').addEventListener('click', undo);
  $('btn-redo').addEventListener('click', redo);
  $('level-select').addEventListener('change', async (e) => {
    if (isDirty() && !confirm('Discard unsaved changes?')) { e.target.value = state.level.id; return; }
    await openLevel(e.target.value);
  });
  $('issues').addEventListener('click', (e) => {
    const li = e.target.closest('li[data-jump]');
    if (!li) return;
    const [x, y] = li.dataset.jump.split(',').map(Number);
    centerOn(x, y);
  });

  setTool('paint');
  setEntityType('enemy');
  setLayer('structure');
  window.addEventListener('resize', resize);
}

function syncLevelForm() {
  const l = state.level;
  $('lvl-name').value = l.name || '';
  $('lvl-id').value = l.id;
  $('lvl-objective').value = l.objective || 'clear';
  $('lvl-brief').value = l.brief || '';
  $('lvl-health').value = l.health || 100;
  $('lvl-par').value = l.par || '';
  $('lvl-order').value = l.order || 0;
  $('lvl-w').value = l.width;
  $('lvl-h').value = l.height;
  $('lvl-seed').value = l.seed || 427;
  for (const input of $('lvl-loadout').querySelectorAll('input')) input.checked = (l.loadout || []).includes(Number(input.value));
}

function showCellInfo(cell) {
  const info = $('cell-info');
  if (cell < 0 || !state.level) { info.textContent = 'Outside the map.'; return; }
  const l = state.level;
  const x = cell % l.width, y = Math.floor(cell / l.width);
  const name = (layer) => {
    const id = cellMaterial(l[layer][cell]);
    if (!id) return '—';
    const detail = layer === 'roof' && state.mats[l[layer][cell].split('@')[1]];
    return state.mats[id].name + (detail ? ` + ${detail.name}` : '');
  };
  const f = cellFlags(l, cell, state.mats);
  const blocks = ['walk', 'shots', 'lobs', 'sight'].filter((k) => f[k]).map((k) => ({ walk: 'movement', shots: 'gunfire', lobs: 'grenades', sight: 'sight' })[k]);
  const extra = [];
  if (f.pierce) extra.push('rail pierces');
  if (f.hp) extra.push(`${f.hp} HP`);
  if (f.explodes) extra.push('explosive');
  if (f.slow < 1) extra.push(`${Math.round(f.slow * 100)}% speed`);
  if (f.hazard) extra.push(`${f.hazard} dmg/s`);
  const structure = state.mats[cellMaterial(l.structure[cell])];
  if (structure?.height) extra.push(`${structure.height} px obstacle height`);
  if (f.roofLobs) extra.push(`roof deck at ${ROOF_HEIGHT} px`);
  info.innerHTML = `<b>${x},${y}</b> (${x * TILE + 8},${y * TILE + 8} px) · ground <b>${name('ground')}</b> · structure <b>${name('structure')}</b> · roof <b>${name('roof')}</b>`
    + ` · blocks <b>${blocks.join(', ') || 'nothing'}</b>${extra.length ? ' · ' + extra.join(', ') : ''}`;
}

let checkTimer = 0;
function scheduleChecks() {
  clearTimeout(checkTimer);
  checkTimer = setTimeout(runChecks, 150);
}

function runChecks() {
  const issues = validate(state.level, state.mats);
  const errors = issues.filter((i) => i.severity === 'error').length;
  const enemies = state.level.entities.filter((e) => e.type === 'enemy');
  const waves = new Set(enemies.map((e) => e.wave || 1)).size;
  $('issue-count').textContent = `${errors} errors · ${issues.length - errors} warnings · ${enemies.length} enemies in ${Math.max(1, waves)} wave${waves > 1 ? 's' : ''}`;
  $('issues').replaceChildren(...(issues.length ? issues : [{ severity: 'ok', message: 'Ready to export.' }]).map((issue) => {
    const item = document.createElement('li');
    item.className = issue.severity;
    item.textContent = issue.message;
    if (Number.isFinite(issue.entity?.x) && Number.isFinite(issue.entity?.y)) item.dataset.jump = `${issue.entity.x},${issue.entity.y}`;
    return item;
  }));
  $('btn-export').disabled = errors > 0;
}

function centerOn(x, y) {
  state.panX = view.width / 2 - x * state.zoom;
  state.panY = view.height / 2 - y * state.zoom;
  const hit = state.level.entities.find((e) => e.x === x && e.y === y);
  if (hit) { setTool('entity'); selectEntity(hit); }
  render();
}

function resize() {
  const rect = view.getBoundingClientRect();
  view.width = Math.round(rect.width * devicePixelRatio);
  view.height = Math.round(rect.height * devicePixelRatio);
  $('zoom-label').textContent = `${Math.round(state.zoom * 100)}%`;
  render();
}

function fitView() {
  const l = state.level;
  const rect = view.getBoundingClientRect();
  const w = rect.width * devicePixelRatio, h = (rect.height - 80) * devicePixelRatio;
  state.zoom = Math.max(1, Math.min(6, Math.floor(Math.min(w / (l.width * TILE), h / (l.height * TILE)) * 4) / 4));
  state.panX = (w - l.width * TILE * state.zoom) / 2;
  state.panY = 44 * devicePixelRatio + (h - l.height * TILE * state.zoom) / 2;
  $('zoom-label').textContent = `${Math.round(state.zoom * 100)}%`;
}

// ------------------------------------------------------------ files

function setStatus(text, kind = '') {
  const el = $('status');
  el.textContent = text;
  el.className = `status ${kind}`;
}

function isDirty() {
  return state.level && JSON.stringify(state.level) !== state.savedJson;
}

function updateStatusDirty() {
  document.title = `${isDirty() ? '• ' : ''}${state.level.name} – Dustpaw Level Builder`;
}

function setLevel(level, unsaved = false) {
  state.level = level;
  state.savedJson = unsaved ? '' : JSON.stringify(level);
  state.undo = []; state.redo = []; state.selected = null;
  allocateBuffers();
  syncLevelForm();
  resize();
  fitView();
  changed();
  localStorage.setItem('dust-range-level', level.id);
}

async function refreshLevelList() {
  const data = await fetch('/api/levels').then((r) => r.json());
  const select = $('level-select');
  select.innerHTML = data.levels.map((l) => `<option value="${l.id}">${l.name}${l.exported ? '' : ' (not exported)'}</option>`).join('')
    || '<option value="">No saved levels</option>';
  if (state.level) select.value = state.level.id;
  state.package = data.package;
  return data.levels;
}

async function openLevel(id) {
  const level = await fetch(`/api/levels/${id}`).then((r) => r.json());
  setLevel(level);
  $('level-select').value = id;
  setStatus(`Opened ${level.name}`);
}

function newLevelPrompt() {
  if (isDirty() && !confirm('Discard unsaved changes?')) return;
  const name = prompt('Level name', 'New level');
  if (!name) return;
  const id = name.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-|-$/g, '') || 'level';
  const level = newLevel(id, 40, 28, Math.floor(Math.random() * 60000) + 1);
  level.name = name;
  setLevel(level, true);
  setStatus('New level – save to keep it');
}

async function save() {
  const level = state.level;
  const { id } = level;
  if (!/^[a-z0-9_-]{1,40}$/.test(id)) { setStatus('Fix the level id before saving.', 'err'); return null; }
  const body = JSON.stringify(level);
  try {
    const response = await fetch(`/api/levels/${id}`, { method: 'PUT', body });
    if (!response.ok) { setStatus((await response.json()).error, 'err'); return null; }
    if (state.level === level) {
      state.savedJson = body;
      updateStatusDirty();
      localStorage.setItem('dust-range-level', id);
    }
    await refreshLevelList();
    setStatus(`Saved levels/${id}.json`, 'ok');
    return { id, body };
  } catch (error) {
    setStatus(`Save failed: ${error.message}`, 'err');
    return null;
  }
}

async function exportLevel() {
  const saved = await save();
  if (!saved) return;
  try {
    const response = await fetch(`/api/export/${saved.id}`, { method: 'POST', body: saved.body });
    const result = await response.json();
    if (!result.ok) {
      setStatus(result.error || result.issues?.find((i) => i.severity === 'error')?.message || 'Export blocked – see Checks', 'err');
      runChecks();
      return;
    }
    await refreshLevelList();
    const p = result.package;
    setStatus(`Exported ${(result.bytes / 1024).toFixed(1)} KB · package ${p.files}/${p.maxFiles} files, ${(p.bytes / 1024).toFixed(0)}/${p.maxBytes / 1024} KB`, 'ok');
  } catch (error) {
    setStatus(`Export failed: ${error.message}`, 'err');
  }
}

async function buildZip() {
  setStatus('Building dist/dustpaw.zip…');
  const result = await fetch('/api/package', { method: 'POST' }).then((r) => r.json());
  setStatus(result.ok ? 'ZIP built' : 'ZIP build failed', result.ok ? 'ok' : 'err');
  $('dialog-text').textContent = result.output || '(no output)';
  $('dialog').showModal();
}

boot().catch((error) => {
  setStatus(`Failed to load: ${error.message}`, 'err');
  console.error(error);
});
