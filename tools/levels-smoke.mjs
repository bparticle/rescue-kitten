// Checks level tiles, collision, destruction and the level menu with the sibling mosa-badge
// headless host. Run: node tools/levels-smoke.mjs [screenshot-dir]
import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { installHeadlessClock } from './headless-clock.mjs';
import { cellValue, materialMap, newLevel, tileKeysAt, toLua, validate, variantAt } from './level-builder/format.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const mosa = process.env.MOSA_BADGE_DIR ?? path.resolve(root, '..', 'mosa-badge');
const { SolanaOS } = await import(pathToFileURL(path.join(mosa, 'tools', 'lib', 'host.mjs')));
const app = process.env.DUST_RANGE_APP_DIR ?? path.join(root, 'apps', 'dust-range');
const shots = process.argv[2];
const readTiles = (file) => JSON.parse(fs.readFileSync(path.join(root, 'sprites', 'tiles', file), 'utf8'));
const materials = materialMap(readTiles('materials.json'));
const atlas = readTiles('tiles-layout.json');

const neighbors = [1, 5, 7, 3, 2, 8, 6, 0];
const areaVariants = new Set();
for (let mask = 0; mask < 256; mask++) {
  const cells = Array(9).fill('');
  cells[4] = 'roof-red';
  neighbors.forEach((i, bit) => { if (mask & (1 << bit)) cells[i] = 'roof-red'; });
  const variant = variantAt(cells, 3, 3, 4, materials);
  areaVariants.add(variant);
  const cardinal = mask & 15;
  const cuts = [3, 6, 12, 9].reduce((bits, pair, bit) =>
    (cardinal & pair) === pair && !(mask & (16 << bit)) ? bits | (16 << bit) : bits, 0);
  assert.equal(atlas.areaMasks[variant - 1], cardinal | cuts);
}
assert.equal(areaVariants.size, 47);
assert.equal(cellValue('roof-skylight', '', materials), '');
assert.equal(cellValue('roof-skylight', 'roof-tin@roof-vent', materials), 'roof-tin@roof-skylight');
assert.equal(cellValue('rug', 'stone-floor', materials), 'rug@stone-floor');
assert.equal(cellValue('road', 'grass:17', materials), 'road@grass:17');
const lanes = ['road', 'road-line', 'road-worn', 'road', 'road-line@grass:17', 'road-line', 'road', 'road', 'road'];
assert.deepEqual(tileKeysAt(lanes, 3, 3, 4, materials), ['road-line/6', 'road/16', '']);
const markedCrackedRoad = cellValue('road-line', 'road-worn@grass:17', materials);
assert.equal(markedCrackedRoad, 'road-line@road-worn@grass:17');
assert.deepEqual(tileKeysAt([markedCrackedRoad], 1, 1, 0, materials), ['road-line/13', 'road-worn/1', 'T17']);
console.log('ok  47 outlines, road turns, and surface details match the atlas');

const fixture = newLevel('tile-check', 10, 7);
const at = (x, y) => y * fixture.width + x;
for (let x = 2; x <= 4; x++) fixture.structure[at(x, 3)] = 'brick-wall';
for (let y = 0; y <= 2; y++) {
  for (let x = 0; x <= 2; x++) fixture.roof[at(x, y)] = 'roof-slate';
}
fixture.roof[at(2, 2)] = '';
fixture.roof[at(1, 1)] = 'roof-slate@roof-skylight';
fixture.ground[at(7, 3)] = 'road-line@grass:17';

const catalog = newLevel('material-catalog', 20, 12);
catalog.ground.fill('stone-floor');
const catalogEntries = Object.values(materials).map((def, entry) => {
  const x = 1 + 2 * (entry % 10), y = 1 + 2 * Math.floor(entry / 10);
  const i = y * catalog.width + x;
  catalog[def.layer][i] = def.detail ? 'roof-slate@' + def.id : def.id;
  return { def, x: x * 16 + 8, y: y * 16 + 8 };
});
assert.equal(validate(catalog, materials).filter((issue) => issue.severity === 'error').length, 0);

const roofFixture = newLevel('roof-check', 10, 10);
const roofAt = (x, y) => y * roofFixture.width + x;
roofFixture.ground.fill('stone-floor');
for (let y = 2; y <= 4; y++) {
  for (let x = 3; x <= 6; x++) roofFixture.roof[roofAt(x, y)] = 'roof-tin';
}
for (let x = 3; x <= 6; x++) roofFixture.structure[roofAt(x, 5)] = 'brick-wall';
roofFixture.structure[roofAt(3, 6)] = 'tree';
roofFixture.structure[roofAt(1, 5)] = 'wood-fence';
roofFixture.structure[roofAt(1, 6)] = 'barbed-wire';
roofFixture.structure[roofAt(1, 3)] = 'wood-wall';
roofFixture.structure[roofAt(5, 6)] = 'crate';
roofFixture.structure[roofAt(5, 4)] = 'barrel';
roofFixture.entities = [
  { type: 'spawn', x: 72, y: 136, dir: 0 },
  { type: 'enemy', kind: 'soldier', x: 72, y: 72, dir: 4, rooftop: true },
  { type: 'enemy', kind: 'soldier', x: 72, y: 72, dir: 4 },
];
assert.equal(validate(roofFixture, materials).length, 0);
const roofGuard = roofFixture.entities[1];
assert.ok(validate({ ...roofFixture, entities: [roofFixture.entities[0], { ...roofGuard, y: 81 }] }, materials)
  .some((issue) => issue.severity === 'error' && issue.message.includes('clear roof')));
assert.ok(validate({ ...roofFixture, entities: [roofFixture.entities[0], { ...roofGuard, kind: 'runner' }] }, materials)
  .some((issue) => issue.severity === 'error' && issue.message.includes('ground position')));
assert.ok(validate({ ...roofFixture, entities: [{ ...roofFixture.entities[0], x: 2 }] }, materials)
  .some((issue) => issue.severity === 'error' && issue.message.includes('map edge')));
const mismatchedTerrain = { ...roofFixture, ground: ['mud:1', ...roofFixture.ground.slice(1)] };
assert.ok(validate(mismatchedTerrain, materials).some((issue) => issue.message.includes('Invalid tile')));
console.log('ok  builder validates roof footprints, enemy roles, map edges, and terrain indexes');

const badge = new SolanaOS({ dir: app });
const readApp = badge.options.read;
badge.options.read = (file) => file === 'levels/roof-check.lua' ? toLua(roofFixture, materials) : readApp(file);
await badge.launch();
installHeadlessClock(badge, 16);
let peak = 0;
const call = badge.call.bind(badge);
badge.call = (...args) => {
  const result = call(...args);
  peak = Math.max(peak, badge.lastInstructions());
  return result;
};
const lua = (code) => badge.lua(code);
const check = (name, code, expected) => {
  const value = lua(code);
  assert.equal(value, expected, `${name}: got ${value}`);
  console.log(`ok  ${name}`);
};

lua(`
  Game = require("lib.game")
  Level = require("lib.level")
  View = require("lib.view")
  function fresh(id)
    local game = Game.new(427, "level", nil, id or "outpost")
    while game.survey do game:prepare() end
    return game
  end
  function run(game, ms, keys)
    while ms > 0 do game:update(math.min(ms, 16), keys or {}); ms = ms - 16 end
  end
  function cell(game, x, y) return y*game.level.w + x + 1 end
  function centre(x) return x*16 + 8 end
`);

lua(`TileFixture = (function() ${toLua(fixture, materials)} end)()`);
lua(`Catalog = Level.new((function() ${toLua(catalog, materials)} end)())`);
for (const { def, x, y } of catalogEntries) {
  const expected = [
    !def.walk, !!def.shots, !!def.shots && !def.pierce, !!def.lobs || !!def.detail, !!def.sight,
    def.slow || 1, def.hazard || 0, def.hp || 0,
  ].join(' ');
  assert.equal(lua(`
    local l, x, y = Catalog, ${x}, ${y}
    local i = Level.index(l,x,y)
    local function blocks(kind) return tostring(Level.entry(l,x,y,1,0,1,0,kind) ~= nil) end
    return table.concat({tostring(Level.can_stand(l,x,y,6)), blocks("shot"), blocks("rail"),
      blocks("lob"), blocks("sight"), Level.speed(l,x,y), Level.hazard(l,x,y), l.hp[i] or 0}, " ")
  `), expected, def.id);
}
console.log(`ok  all ${catalogEntries.length} materials round-trip their tile interactions`);

check('narrow wall blocks only the visible strip', `local l = Level.new(TileFixture)
  local clear = Level.entry(l, 16, 50, 1, 0, 72) == nil
  local hit = Level.entry(l, 56, 49, 0, 1, 12)
  local x, y = Level.slide(l, 56, 46, 56, 58, 6)
  return tostring(clear) .. " " .. hit .. " " .. string.format("%.2f", y) .. " "
    .. tostring(Level.can_stand(l, x, y, 6))`, 'true 4.0 46.99 true');
check('compound tiles retain the road surface and roof detail', `local l = Level.new(TileFixture)
  local roof, road = l.roof[12], l.ground[38]
  return roof.variant .. " " .. roof.detail.id .. " " .. road.base.id .. " " .. road.footing.terrain
    .. " " .. tostring(Level.region_at(l, 40, 40) == nil)`,
  `${variantAt(fixture.roof, 10, 7, at(1, 1), materials)} roof-skylight road 17 true`);

check('roof sight and shots clear lower walls, with tall trees and roof decks still blocking', `local g = fresh("roof-check")
  local roof, indoor = g.enemies[1], g.enemies[2]
  assert(roof.roof and not indoor.roof and g:can_notice(roof,g) and g:attack_clear(roof,g))
  assert(not g:can_notice(indoor,g) and not g:attack_clear(indoor,g))
  assert(not g:can_notice(roof,indoor) and not g:attack_clear(roof,indoor))
  roof.x, g.x = 56, 56
  assert(not g:can_notice(roof,g) and not g:attack_clear(roof,g))
  return "ok"`, 'ok');
check('a rooftop guard wakes, fires over a wall, and stays on the roof', `local g = fresh("roof-check")
  local roof = g.enemies[1]
  run(g, 2500)
  assert(g.health < g.surface.health and not roof.dormant)
  g:nudge_enemy(roof, 0, 80)
  assert(roof.y < 74 and Level.can_stand(g.level,roof.x,roof.y,6,roof.roof))
  return "ok"`, 'ok');
check('a rooftop marksman beam reaches the player outside and stops at the deck indoors', `local g = fresh("roof-check")
  local marksman = g:spawn_enemy("marksman",72,72,5,true)
  g:fire_enemy(marksman,g.x,g.y)
  assert(g.health < g.surface.health)
  local hp = g.health
  g.x, g.y = 72, 65
  marksman.direction = 1
  g:fire_enemy(marksman,g.x,g.y)
  assert(g.health == hp)
  return "ok"`, 'ok');
check('the player can return fire at the rooftop guard, but cannot fire through the roof deck', `local g = fresh("roof-check")
  local roof, indoor = g.enemies[1], g.enemies[2]
  local hp = roof.health
  g:request_fire(); run(g, 200)
  assert(roof.health < hp and indoor.health == indoor.surface.health)
  hp = roof.health
  g.x, g.y = 72, 56
  g.direction = 5
  indoor.health = 0
  g:request_fire(); run(g, 200)
  assert(roof.health == hp)
  return "ok"`, 'ok');
check('a muzzle pressed against a narrow wall cannot fire through it', `local g = fresh("roof-check")
  local i = cell(g,4,5)
  local hp = g.level.hp[i]
  g.x, g.y, g.direction = 72, 97.02, 1
  g:request_fire(); run(g, 64)
  assert(g.level.hp[i] < hp and g.enemies[2].health == g.enemies[2].surface.health)
  return "ok"`, 'ok');
check('pass-through fixtures take damage once per projectile and rail shots damage pierced walls', `local g = fresh("roof-check")
  local fence, wire, wood = cell(g,1,5), cell(g,1,6), cell(g,1,3)
  g.x, g.y, g.direction = 21, 129, 1
  g:request_fire(); run(g, 280)
  assert(g.level.hp[fence] == 22 and g.level.hp[wire] == 12 and g.level.hp[wood] == 132)
  g.weapon = 8
  g:request_fire(); run(g, 32)
  return tostring(g.level.hp[wood]) .. " " .. g.level.structure[wire].id`, '92 splinters');
check('the hammer can clear a wire hazard, and exposure costs the displayed health per second', `local g = fresh("roof-check")
  local wire = cell(g,1,6)
  g.x, g.y = 24, 104
  for _ = 1, 10 do g:hazard_tick(0.1) end
  assert(g.health == g.surface.health - 14)
  g.x, g.y, g.direction = 24, 118, 1
  g:swing(Game.weapons[15])
  assert(g.level.structure[wire].id == "splinters")
  return "ok"`, 'ok');
check('blasts shield destructibles and actors on the far side of a wall or roof', `local g = fresh("roof-check")
  local roof, indoor = g.enemies[1], g.enemies[2]
  local hp = g.level.hp[cell(g,5,6)]
  local weapon = {radius=65,damage=70,min_damage=0.25,direct=0,effect="blast"}
  g:explode(72,72,{kind="grenade",weapon=weapon,targets=g.enemies,contacts={}})
  assert(g.level.hp[cell(g,5,6)] == hp and indoor.health < indoor.surface.health and roof.health == roof.surface.health)
  assert(g.pending_blasts)
  run(g, 64)
  assert(not g.pending_blasts and roof.health == roof.surface.health)
  return "ok"`, 'ok');
check('a disc returning across a roof boundary stops and becomes usable again', `local g = fresh("roof-check")
  g.x, g.y = 72, 64
  local disc = g:spawn(g,Game.weapons[10],{},72,24,0,1)
  disc.region, disc.age = nil, disc.life
  g.disc_out = true
  g:update_shots(0.08)
  assert(not g.disc_out and #g.projectiles == 0 and g.enemies[2].health == g.enemies[2].surface.health)
  return "ok"`, 'ok');
check('gravity wells cannot pull or damage actors through walls', `local g = fresh("roof-check")
  local enemy = g.enemies[2]
  local orb = g:spawn(g,Game.weapons[14],{},72,94,0,-1)
  orb.well_at = g.time - 2
  g:update_shots(0.08)
  assert(enemy.y == 72 and enemy.health == enemy.surface.health)
  return "ok"`, 'ok');
check('view draws both exposed and hidden rooftop enemies and elevated fire', `local g = fresh("roof-check")
  local v = View.new()
  v.canvas:show(false); v.strip:show(false)
  g:fire_enemy(g.enemies[1],g.x,g.y)
  v:draw(g)
  g.x, g.y = 72, 64
  v:draw(g)
  return "ok"`, 'ok');

check('level loads at spawn', `local g = fresh(); return string.format("%d,%d,%d,%d,%d", g.x, g.y, g.width, g.height, g.health)`, '24,264,768,512,120');
check('Outpost medkit stays at full health, caps healing, and is consumed once', `local g = fresh()
  local kit
  for _, item in ipairs(g.pickups) do if item.kind == "medkit" then kit = item; break end end
  g.x, g.y = kit.x-5, kit.y
  run(g, 16, {right=true})
  assert(g.health == 120 and g:pickup_visible(kit))
  g.health = 115
  run(g, 16, {right=true})
  assert(g.health == 120 and not g:pickup_visible(kit) and g.notice == "MEDKIT  +5 HP")
  g.health = 90
  run(g, 16, {right=true})
  return g.health .. " " .. g.weapon .. " " .. g.found`, '90 1 0');
check('first wave is dormant', `local g = fresh(); local n = 0; for _, e in ipairs(g.enemies) do if e.dormant then n = n + 1 end end; return n .. "/" .. #g.enemies`, '8/8');
check('wave total in HUD state', `local g = fresh(); return g.squad.total .. " " .. g.squad.remaining`, '2 0');

// Farmhouse: brick wall row y=3, wall openings at x=7,10. Shots from outside (north, y=1) straight down.
check('brick wall stops shots', `local g = fresh(); return tostring(Level.entry(g.level, centre(6), centre(1), 0, 1, 40) ~= nil)`, 'true');
check('wall opening lets shots through', `local g = fresh(); local t = Level.entry(g.level, centre(7), centre(1), 0, 1, 40); return tostring(t ~= nil and t > 40 or t == nil)`, 'true');
check('wall opening blocks walking', `local g = fresh(); return tostring(Level.can_stand(g.level, centre(7), centre(3), 6))`, 'false');
check('doorway is walkable', `local g = fresh(); return tostring(Level.can_stand(g.level, centre(9), centre(10), 6))`, 'true');
check('deep water blocks walking', `local g = fresh(); return tostring(Level.can_stand(g.level, centre(30), centre(5), 6))`, 'false');
check('shots cross deep water', `local g = fresh(); return tostring(Level.entry(g.level, centre(28), centre(5), 1, 0, 70) == nil)`, 'true');
check('rail pierces wood wall but not brick', `local g = fresh()
  local wood = Level.entry(g.level, centre(34), centre(8), 1, 0, 60, 0, "rail")
  local brick = Level.entry(g.level, centre(4), centre(6), 1, 0, 40, 0, "rail")
  return tostring(wood == nil) .. " " .. tostring(brick ~= nil)`, 'true true');
check('grenades arc over sandbags, not walls', `local g = fresh()
  local bags = Level.entry(g.level, centre(23), centre(13), 0, -1, 40, 0, "lob")
  local shot = Level.entry(g.level, centre(23), centre(13), 0, -1, 40, 0, "shot")
  local wall = Level.entry(g.level, centre(9), centre(1), 0, 1, 40, 0, "lob")
  return tostring(bags == nil) .. " " .. tostring(shot ~= nil) .. " " .. tostring(wall ~= nil)`, 'true true true');
check('roof stops grenades from outside only', `local g = fresh()
  local inside = Level.region_at(g.level, centre(9), centre(6))
  local outside = Level.entry(g.level, centre(9), centre(13), 0, -1, 60, 0, "lob")
  local within = Level.entry(g.level, centre(7), centre(5), 1, 0, 60, 0, "lob", inside)
  return tostring(inside ~= nil) .. " " .. tostring(outside ~= nil) .. " " .. tostring(within == nil)`, 'true true true');
check('hedge blocks sight but not shots', `local g = fresh()
  return tostring(Level.entry(g.level, centre(20), centre(0), 0, 1, 30, 0, "sight") ~= nil) .. " "
    .. tostring(Level.entry(g.level, centre(20), centre(0), 0, 1, 30, 0, "shot") == nil)`, 'true true');
check('shallow water slows', `local g = fresh(); return string.format("%.2f %.2f", Level.speed(g.level, centre(29), centre(5)), Level.speed(g.level, centre(2), centre(16)))`, '0.60 1.00');
check('explosions in deep water splash without scorching the river', `local g = fresh()
  g:explode(centre(30),centre(5),{kind="grenade",weapon=Game.weapons[4],targets=g.enemies,contacts={}})
  assert(#g.scorch_marks == 0 and g.particles[1].kind == "water_blast")
  return "ok"`, 'ok');

check('player cannot walk through a wall', `local g = fresh()
  g.x, g.y = centre(9), centre(1) + 4
  run(g, 800, {down=true})
  return tostring(g.y < 3*16)`, 'true');
check('player slides along the river bank', `local g = fresh()
  g.x, g.y = centre(28), centre(4)
  run(g, 600, {right=true})
  return tostring(g.x < 30*16 and g.x > 29*16)`, 'true');
check('barrel shot chains into an explosion', `local g = fresh()
  g.owned[1], g.weapon = true, 1
  g.x, g.y, g.direction = centre(18) - 30, centre(12), 3
  local before = g.level.structure[cell(g, 18, 12)].id
  g:request_fire(); run(g, 400)
  local after = g.level.structure[cell(g, 18, 12)]
  return before .. " " .. (after and after.id or "none") .. " " .. #g.scorch_marks`, 'barrel scorch 1');
check('crate breaks after enough damage', `local g = fresh()
  local i = cell(g, 26, 13)
  g:strike_tile(i, 100)
  local after = g.level.structure[i]
  return (after and after.id or "none") .. " " .. tostring(Level.can_stand(g.level, centre(26), centre(13), 6))`, 'splinters true');
check('broken wall retiles neighbours', `local g = fresh()
  local i = cell(g, 6, 3)
  local before = g.level.structure[cell(g, 5, 3)].variant
  g:strike_tile(i, 999)
  return before .. " " .. g.level.structure[i].id .. " " .. g.level.structure[cell(g, 5, 3)].variant`, '7 rubble 5');
check('barbed wire hurts the player', `local g = fresh()
  g.x, g.y = centre(42), centre(13)
  for _, e in ipairs(g.enemies) do e.health = 0 end
  local hp = g.health
  run(g, 1100)
  return tostring(g.health < hp)`, 'true');
check('blast does not pass through walls', `local g = fresh()
  local soldier = g.enemies[1]
  soldier.x, soldier.y = centre(9), centre(5)
  local hp = soldier.health
  g:explode(centre(9), centre(1), {kind="grenade", targets=g.enemies, contacts={},
    weapon={radius=60, damage=70, min_damage=0.25, direct=0, effect="blast"}})
  return tostring(soldier.health == hp)`, 'true');
check('enemies route around buildings', `local g = fresh()
  for _, e in ipairs(g.enemies) do e.health = 0 end
  run(g, 50)
  local runner = g:spawn_enemy("runner", centre(9), centre(1), 5)
  runner.alerted, runner.ready_at = true, 0
  g.x, g.y, g.health = centre(9), centre(13), 9999
  run(g, 6000)
  return tostring(runner.y > 11*16 and math.abs(runner.x - g.x) + math.abs(runner.y - g.y) < 40)`, 'true');
check('enemy fire hits the player in the open', `local g = fresh()
  for _, e in ipairs(g.enemies) do e.health = 0 end
  run(g, 50)
  local soldier = g:spawn_enemy("soldier", centre(4), centre(12), 3)
  soldier.alerted, soldier.ready_at = true, 0
  g.x, g.y = centre(7), centre(12)
  local hp = g.health
  run(g, 3000)
  return tostring(g.health < hp)`, 'true');
check('a wall shelters the player from enemy fire', `local g = fresh()
  for _, e in ipairs(g.enemies) do e.health = 0 end
  run(g, 50)
  -- Soldier outside the farmhouse west wall, player inside: the soldier must walk round to the door.
  local soldier = g:spawn_enemy("soldier", centre(3), centre(6), 3)
  soldier.alerted, soldier.ready_at = true, 0
  g.x, g.y = centre(6), centre(6)
  local hp = g.health
  run(g, 900)
  return tostring(g.health == hp)`, 'true');
check('spotting the player wakes the guard', `local g = fresh()
  g.x, g.y = centre(9), centre(8)
  run(g, 100)
  return tostring(g.enemies[1].dormant == nil)`, 'true');
check('clearing waves opens the exit', `local g = fresh()
  for _, e in ipairs(g.enemies) do e.health = 0 end
  run(g, 100)
  local wave = g.squad.wave
  run(g, 1800)
  for _, e in ipairs(g.enemies) do e.health = 0 end
  run(g, 100)
  g.x, g.y = g.exit.x, g.exit.y
  run(g, 50)
  return wave .. " " .. g.squad.wave .. " " .. tostring(g.result)`, '1 2 won');
check('view draws a level frame', `local g = fresh(); local v = View.new(); v.canvas:show(false); v.strip:show(false); v:draw(g); g.x, g.y = centre(9), centre(6); v:draw(g); return "drawn"`, 'drawn');

// Menu flow: hold Cancel to open the menu, pick LEVELS, start the first level.
await badge.frames(30);
const status = () => lua('return table.concat({range_status()}, ",")').split(',');
await badge.hold('back', 90);
await badge.frames(5);
assert.equal(status()[9], 'menu');
for (let i = 0; i < 3; i++) await badge.press('down');
await badge.press('select');
await badge.frames(3);
assert.equal(status()[9], 'levels', `expected the level list, got ${status()[9]}`);
if (shots) badge.screenshot(path.join(shots, 'levels-menu.png'));
await badge.press('select');
for (let i = 0; i < 120 && status()[12] !== 'level'; i++) await badge.frames(1);
assert.equal(status()[9], 'range');
assert.equal(status()[12], 'level');
if (shots) badge.screenshot(path.join(shots, 'level-start.png'));
console.log('ok  level menu starts the level');
// Walk into the crossroads firefight and keep shooting.
for (let i = 0; i < 12; i++) { await badge.hold('right', 25); await badge.press('select'); }
for (let i = 0; i < 6; i++) { await badge.hold('up', 15); await badge.press('select'); }
if (shots) badge.screenshot(path.join(shots, 'level-fight.png'));
assert.ok(peak < 160_000, `level callback budget regressed: ${peak}`);
console.log(`ok  firefight within budget (${peak} / 200000 instructions)`);
assert.deepEqual(badge.errors, []);
console.log('all level checks passed');
