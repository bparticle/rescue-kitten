// Checks that the LÖVE host (hosts/love) still runs the badge app in apps/dust-range.
//
//   node tools/love-check.mjs
//
// 1. API coverage: every badge API the game calls (ui.*, sys.*, led.*, storage.* …) and every
//    on_* callback it defines must be provided by hosts/love/main.lua.
// 2. Translation: every game file goes through hosts/love/compat/lua54.lua (run in Lua 5.4 via
//    the sibling mosa-badge's wasmoon). Line counts must not change, and no 5.4-only operator
//    may be left outside strings and comments.
// 3. Behaviour: smoke.mjs and levels-smoke.mjs run against the translated copy. Its operators
//    use shims that copy LuaJIT's 32-bit `bit` library and math.floor division, so integer
//    behaviour matches LÖVE. Instruction budgets are switched off here: the badge never runs
//    translated code, and `node tools/smoke.mjs` keeps checking the real budgets.
// 4. Boot: if LÖVE is installed, the game opens in LÖVE, goes from the map to Backyard, walks,
//    fires and quits. Screenshots go to dist/love-check/. Set LOVE to the lovec/love binary
//    when it isn't on PATH or in the default install folder. --skip-love skips this step.
//
// MOSA_BADGE_DIR selects a different headless host checkout, as for the smoke tests.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const app = path.join(root, 'apps', 'dust-range');
const host = path.join(root, 'hosts', 'love');
const mosa = process.env.MOSA_BADGE_DIR ?? path.resolve(root, '..', 'mosa-badge');
const skipLove = process.argv.includes('--skip-love');

const luaFiles = fs.readdirSync(app, { recursive: true })
  .map((rel) => rel.split(path.sep).join('/'))
  .filter((rel) => rel.endsWith('.lua'));
const stripLua = (src) => src
  .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, '')
  .replace(/\[(=*)\[[\s\S]*?\]\1\]/g, '""')
  .replace(/"(\\.|[^"\\\n])*"|'(\\.|[^'\\\n])*'/g, '""')
  .replace(/--.*$/gm, '');

// 1. API coverage ---------------------------------------------------------------
const hostSrc = fs.readFileSync(path.join(host, 'main.lua'), 'utf8');
const provided = new Set();
for (const m of hostSrc.matchAll(/^function (ui|sys|led|storage)\.(\w+)/gm)) provided.add(`${m[1]}.${m[2]}`);
for (const m of hostSrc.matchAll(/^(ui|sys|led|storage) = \{([^}]*)\}/gm)) {
  for (const f of m[2].matchAll(/(\w+)\s*=/g)) provided.add(`${m[1]}.${f[1]}`);
}
// APIs the game feature-tests and works without. Add one here only after checking the game's fallback.
const OPTIONAL = new Set([
  'ui.load', // lib/view.lua checks `ui.load and canvas.image` and stamps tiles from packed runs instead
]);
for (const api of OPTIONAL) provided.add(api);
const handledCallbacks = new Set(['on_key', 'on_tick', 'on_exit']);
const BADGE_GLOBALS = ['ui', 'sys', 'led', 'storage', 'badge', 'mesh', 'lamps', 'timer', 'cabinet', 'json', 'audio', 'sound'];
const missing = new Map();
for (const rel of luaFiles) {
  if (rel.startsWith('art/') || rel.startsWith('levels/')) continue; // generated data
  const code = stripLua(fs.readFileSync(path.join(app, rel), 'utf8'));
  for (const m of code.matchAll(new RegExp(`(?<![\\w.:])(${BADGE_GLOBALS.join('|')})\\.(\\w+)`, 'g'))) {
    const api = `${m[1]}.${m[2]}`;
    if (!provided.has(api)) missing.set(api, rel);
  }
  for (const m of code.matchAll(/^function (on_\w+)/gm)) {
    if (!handledCallbacks.has(m[1])) missing.set(m[1], rel);
  }
}
assert.equal(missing.size, 0, `hosts/love/main.lua lacks badge APIs the game uses: ${[...missing].map(([a, f]) => `${a} (${f})`).join(', ')}`);
console.log(`ok  API coverage: every badge API the game calls is in hosts/love (${provided.size} provided, ${OPTIONAL.size} optional)`);

// 2. Translation ----------------------------------------------------------------
const require = createRequire(path.join(mosa, 'package.json'));
const { LuaFactory } = require('wasmoon');
const factory = new LuaFactory();
const translator = fs.readFileSync(path.join(host, 'compat', 'lua54.lua'), 'utf8');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'dustpaw-love-'));
const translated = path.join(work, 'app');
// LuaJIT semantics: bit.* returns signed 32-bit results and masks the shift count;
// __idiv is math.floor(a / b) as in compat/runtime.lua.
const LUAJIT_SHIMS = 'local function __tb(x) x = math.tointeger(x) or math.floor(x) x = x & 0xffffffff if x >= 0x80000000 then x = x - 0x100000000 end return x end '
  + '__idiv=function(a,b) return math.floor(a/b) end __band=function(a,b) return __tb(__tb(a)&__tb(b)) end '
  + '__bor=function(a,b) return __tb(__tb(a)|__tb(b)) end __bxor=function(a,b) return __tb(__tb(a)~__tb(b)) end '
  + '__shl=function(a,b) return __tb(__tb(a)<<(b&31)) end __shr=function(a,b) return __tb((__tb(a)&0xffffffff)>>(b&31)) end '
  + '__bnot=function(a) return __tb(~__tb(a)) end ';
let rewritten = 0;
for (const rel of fs.readdirSync(app, { recursive: true })) {
  const src = path.join(app, rel), dst = path.join(translated, rel);
  if (fs.statSync(src).isDirectory()) { fs.mkdirSync(dst, { recursive: true }); continue; }
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  if (!rel.endsWith('.lua')) { fs.copyFileSync(src, dst); continue; }
  const text = fs.readFileSync(src, 'utf8');
  // A fresh engine per file: one long-lived wasmoon engine runs out of memory on the art files.
  const lua = await factory.createEngine();
  lua.global.set('__src', translator);
  lua.global.set('__in', text);
  lua.global.set('__name', rel);
  let out;
  try {
    out = await lua.doString('local T = load(__src, "@lua54.lua")() return T.translate(__in, __name)');
  } finally {
    lua.global.close();
  }
  assert.equal(out.split('\n').length, text.split('\n').length, `translation changed the line count of ${rel}`);
  const ops54 = (code) => /\/\/|<<|>>|~|[&|]/.test(code.replace(/~=/g, ''));
  assert.ok(!ops54(stripLua(out)), `5.4 operator left in ${rel}`);
  if (ops54(stripLua(text))) rewritten++;
  fs.writeFileSync(dst, rel === 'main.lua' ? LUAJIT_SHIMS + out : out);
}
console.log(`ok  translated ${luaFiles.length} files for LuaJIT (${rewritten} used 5.4 operators), line numbers kept`);

// 3. Behaviour ------------------------------------------------------------------
// A copy of the headless host with the per-callback instruction cap lifted.
const hostCopy = path.join(work, 'mosa');
fs.mkdirSync(path.join(hostCopy, 'tools'), { recursive: true });
fs.cpSync(path.join(mosa, 'tools', 'lib'), path.join(hostCopy, 'tools', 'lib'), { recursive: true });
fs.copyFileSync(path.join(mosa, 'package.json'), path.join(hostCopy, 'package.json'));
fs.symlinkSync(path.join(mosa, 'node_modules'), path.join(hostCopy, 'node_modules'), 'junction');
const core = path.join(hostCopy, 'tools', 'lib', 'host-core.mjs');
const coreSrc = fs.readFileSync(core, 'utf8');
assert.ok(/^local BUDGET = \d+/m.test(coreSrc), 'host-core.mjs no longer defines BUDGET; update tools/love-check.mjs');
fs.writeFileSync(core, coreSrc.replace(/^local BUDGET = \d+/m, 'local BUDGET = 1e12'));

const env = { ...process.env, MOSA_BADGE_DIR: hostCopy, DUST_RANGE_APP_DIR: translated, DUST_RANGE_BUDGET: 'off' };
for (const test of ['smoke.mjs', 'levels-smoke.mjs']) {
  const run = spawnSync(process.execPath, [path.join(root, 'tools', test)], { env, encoding: 'utf8' });
  if (run.status !== 0) {
    process.stdout.write(run.stdout);
    process.stderr.write(run.stderr);
    assert.fail(`${test} failed on the LuaJIT translation`);
  }
  const last = run.stdout.trim().split('\n').filter((l) => !l.startsWith('Headless')).pop();
  console.log(`ok  ${test} on the LuaJIT translation: ${last}`);
}

// 4. Boot in LÖVE ---------------------------------------------------------------
function findLove() {
  if (process.env.LOVE) return process.env.LOVE;
  const candidates = process.platform === 'win32'
    ? ['C:/Program Files/LOVE/lovec.exe', 'C:/Program Files (x86)/LOVE/lovec.exe']
    : process.platform === 'darwin' ? ['/Applications/love.app/Contents/MacOS/love'] : [];
  for (const c of candidates) if (fs.existsSync(c)) return c;
  const which = spawnSync(process.platform === 'win32' ? 'where' : 'which', ['love'], { encoding: 'utf8' });
  return which.status === 0 ? which.stdout.trim().split(/\r?\n/)[0] : null;
}
const love = skipLove ? null : findLove();
if (!love) {
  console.log(skipLove ? 'skip LÖVE boot (--skip-love)' : 'skip LÖVE boot: LÖVE not found (set LOVE=path/to/lovec)');
} else {
  const saveRoot = process.platform === 'win32' ? path.join(process.env.APPDATA, 'LOVE')
    : process.platform === 'darwin' ? path.join(os.homedir(), 'Library', 'Application Support', 'LOVE')
    : path.join(process.env.XDG_DATA_HOME ?? path.join(os.homedir(), '.local', 'share'), 'love');
  const saves = path.join(saveRoot, 'dustpaw-check');
  fs.rmSync(saves, { recursive: true, force: true });
  // Map → Backyard briefing → mission; walk up and right, fire, then quit.
  const script = '2.5:shot-1-map 3:down-z 3.1:up-z 4:shot-2-briefing 4.5:down-z 4.6:up-z 7:shot-3-mission '
    + '7.2:down-up 8.2:up-up 8.3:down-right 9:up-right 9.1:down-z 10:up-z 10.2:shot-4-combat 10.5:quit';
  const run = spawnSync(love, [path.join(root, 'tools', 'love-driver')], {
    env: { ...process.env, DUSTPAW_HOST: host, DUSTPAW_GAME_DIR: app, DUSTPAW_SCRIPT: script },
    encoding: 'utf8', timeout: 60_000,
  });
  if (run.status !== 0) {
    process.stdout.write(run.stdout ?? '');
    process.stderr.write(run.stderr ?? '');
    assert.fail(`LÖVE boot failed (status ${run.status}${run.error ? `, ${run.error.message}` : ''})`);
  }
  const shotsDir = path.join(root, 'dist', 'love-check');
  fs.rmSync(shotsDir, { recursive: true, force: true });
  fs.mkdirSync(shotsDir, { recursive: true });
  const shots = fs.existsSync(saves) ? fs.readdirSync(saves).filter((f) => f.endsWith('.png')) : [];
  for (const f of shots) fs.copyFileSync(path.join(saves, f), path.join(shotsDir, f));
  assert.equal(shots.length, 4, `expected 4 screenshots from LÖVE, got ${shots.length}`);
  const fps = /fps: (\d+)/.exec(run.stdout)?.[1];
  console.log(`ok  LÖVE boot: map → briefing → Backyard, walked and fired at ${fps} fps; screenshots in dist/love-check/`);
}

// Remove the node_modules junction first so cleanup can never reach the real mosa-badge modules.
fs.unlinkSync(path.join(hostCopy, 'node_modules'));
fs.rmSync(work, { recursive: true, force: true });
console.log('LÖVE host in sync with the badge app.');
