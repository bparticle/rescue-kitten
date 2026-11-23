import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { installHeadlessClock } from './headless-clock.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const mosa = process.env.MOSA_BADGE_DIR ?? path.resolve(root, '..', 'mosa-badge');
const hostUrl = (name) => pathToFileURL(path.join(mosa, 'tools', 'lib', name));
const { SolanaOS } = await import(hostUrl('host.mjs'));
const { to565 } = await import(hostUrl('host-core.mjs'));
const app = process.env.DUST_RANGE_APP_DIR ?? path.join(root, 'apps', 'dust-range');
const tick = Number(process.env.DUST_RANGE_TICK_MS ?? 16);
const preview = process.argv[2];

// Model the badge's native RGB565 image path in the rectangle-only Mosa host.
function installImages(badge, images) {
  const lua = badge.engine.global;
  lua.set('__bench_load_image', (rows, palette) => {
    const image = rows.map(row => [...row].map(key => {
      assert.equal(typeof palette[key], 'number', `missing tile colour ${key}`);
      return to565(palette[key]);
    }));
    images.push(image);
    badge.px += image.length * image[0].length / 16;
    return images.length;
  });
  lua.set('__bench_blit_image', (id, token, x, y) => {
    const image = images[token - 1];
    for (const [iy, row] of image.entries()) {
      for (let ix = 0; ix < row.length;) {
        const color = row[ix];
        let end = ix + 1;
        while (end < row.length && row[end] === color) end++;
        badge.canvasRect(id, x + ix, y + iy, end - ix, 1, color);
        ix = end;
      }
    }
  });
  return `
    local create_canvas = ui.canvas
    local function image(c, token, x, y) __bench_blit_image(c.id, token, x, y) end
    function ui.canvas(...)
      local c = create_canvas(...)
      getmetatable(c).image = image
      return c
    end
    function ui.load(rows, options)
      return __bench_load_image(rows, options.palette)
    end
  `;
}

async function measure(native) {
  // Nine clears open the Fortress, the busiest mission: three waves and rooftop marksmen.
  const clears = Object.fromEntries(['backyard', 'orchard', 'farmhouse', 'crate-yard', 'riverside',
    'hedge-maze', 'burning-barn', 'cold-storage', 'outpost'].map((id) => [id, true]));
  const badge = new SolanaOS({ dir: app, storageJson: JSON.stringify({ mission_clears: clears }) });
  const wait = (ms) => badge.frames(Math.ceil(ms / tick));
  const images = [];
  let readCost = 0;
  const read = badge.options.read;
  badge.options.read = (file) => {
    const source = read(file);
    if (source === undefined) return;
    readCost += 500 + Math.ceil(Buffer.byteLength(source) / 4);
    if (file !== 'main.lua') return source;
    const prelude = native ? installImages(badge, images) : '';
    return `${prelude}\n${source}\n
      function bench_finish_wave(restore)
        if restore then game.result, game.health = nil, game.surface.health end
        for _, enemy in ipairs(game.enemies) do enemy.health = 0 end
      end
      function bench_wound_pair()
        for index = 1, 2 do game:damage(game.enemies[index], 24, "impact") end
      end
      function bench_ready() return game.survey == nil end
      function bench_wake_all()
        game.health = game.surface.health
        for _, enemy in ipairs(game.enemies) do enemy.dormant, enemy.alerted = nil, true end
      end
      function bench_active_enemies() return #game.enemies end
    `;
  };

  try {
    await badge.launch();
    installHeadlessClock(badge, tick);
    const heap = badge.engine.global.get('__heap');
    const gc = badge.engine.global.get('__gc');
    const boot = Math.ceil(badge.lastInstructions());
    const bootWithReads = boot + readCost;
    let callback = boot;
    let combat = 0;
    let combatStage;
    let peakStage;
    let peakCombatReads = 0;
    let movingCost = 0;
    let movingTicks = 0;
    let peakHeap = heap();
    let peakObjects = badge.objects.size;
    const call = badge.call.bind(badge);
    badge.call = (...args) => {
      readCost = 0;
      const result = call(...args);
      const cost = Math.ceil(badge.lastInstructions()) + readCost;
      callback = Math.max(callback, cost);
      if (combatStage && cost > combat) {
        combat = cost;
        peakStage = combatStage;
        peakCombatReads = readCost;
      }
      if (combatStage === 'Fortress while moving' && args[0] === 'on_tick') {
        movingCost += cost;
        movingTicks++;
      }
      peakHeap = Math.max(peakHeap, heap());
      peakObjects = Math.max(peakObjects, badge.objects.size);
      assert.deepEqual(badge.errors, []);
      return result;
    };

    await badge.press('back');
    await badge.press('up');
    await badge.frames(12);
    assert.equal(images.length, native ? 48 : 0);
    const frame = () => createHash('sha256').update(badge.rgba()).digest('hex');
    const rangeFrame = frame();
    const wave = () => badge.lua('return select(16, range_status())');
    async function startFortress() {
      for (let attempt = 0; attempt < 200 && !badge.lua('return bench_ready()'); attempt++) await badge.frames(1);
      assert.equal(badge.lua('return select(13, range_status())'), 'level');
      assert.equal(badge.lua('return bench_ready()'), true, 'the Fortress finished loading');
      assert.equal(wave(), 1);
    }
    // Range menu: Resume, Mission Map, Weapon Specs, Exit. The map focuses the Fortress.
    await badge.hold('back', Math.ceil(1240 / tick));
    await badge.press('down');
    await badge.press('select');
    assert.equal(Number(badge.lua('return select(20, range_status())')), 10);
    await badge.press('select');
    await badge.press('select');
    await startFortress();
    combatStage = 'Fortress opening wave';
    badge.lua('bench_wake_all()');
    await wait(2500);
    badge.lua('bench_wound_pair()');
    await wait(900);
    const openingFrame = frame();
    await badge.press('select');
    await wait(2500);
    combatStage = null;

    // Clear each wave to reach the final assault with every remaining enemy hunting.
    combatStage = 'Fortress later waves';
    while (wave() < 3) {
      const previous = wave();
      badge.lua('bench_finish_wave(true)');
      await wait(1800);
      assert.equal(wave(), previous + 1);
      badge.lua('bench_wake_all()');
      await wait(1500);
    }
    assert.ok(badge.lua('return bench_active_enemies()') > 0);
    const lateFrame = frame();
    if (preview && native) badge.screenshot(preview);
    combatStage = 'Fortress while moving';
    badge.lua('bench_wake_all()');
    await badge.hold('left', Math.ceil(320 / tick));
    await badge.hold('up', Math.ceil(320 / tick));
    await badge.press('select');
    await wait(460);
    combatStage = null;

    // Mission menu: Resume, Retry Mission. Retry opens the briefing, and Select starts again.
    async function retry() {
      await badge.hold('back', Math.ceil(1240 / tick));
      await badge.press('down');
      await badge.press('select');
      await badge.press('select');
      await startFortress();
    }
    await retry();
    const retained = gc();
    for (let i = 0; i < 8; i++) await retry();
    const retainedGrowth = Math.max(0, gc() - retained);
    const imageKiB = images.reduce((total, image) => total + image.length * image[0].length * 2, 0) / 1024;

    console.log(`${native ? 'Image model' : 'Packed runs'} at ${tick} ms: boot ${boot} VM / ${bootWithReads} incl. file reads, `
      + `peak callback ${callback}, peak combat ${combat} (${peakStage}), ${Math.ceil(peakHeap)} KiB Lua heap, `
      + `${imageKiB} KiB tile pixels, ${retainedGrowth.toFixed(1)} KiB retained growth, ${peakObjects} UI objects.`);
    console.log(`Combat peak file-read estimate ${peakCombatReads}. Mean moving callback ${Math.ceil(movingCost/movingTicks)}.`);
    assert.ok(bootWithReads < 150_000 && callback < 150_000, 'keep at least 50k instructions of badge headroom');
    assert.ok(peakHeap + imageKiB < 4 * 1024, 'keep at least 2 MiB of badge heap headroom in the model');
    assert.ok(retainedGrowth < 24, `trial restarts retained ${retainedGrowth.toFixed(1)} KiB`);
    assert.equal(peakObjects, 3);
    return { rangeFrame, openingFrame, lateFrame, save: badge.storageJson() };
  } finally {
    badge.close();
  }
}

const packed = await measure(false);
const native = await measure(true);
assert.deepEqual(native, packed, 'both renderers should produce identical RGB565 frames and saves');
