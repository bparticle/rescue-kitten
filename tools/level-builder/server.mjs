// Dustpaw level builder. Run: node tools/level-builder/server.mjs [port]
// Serves the editor on http://localhost:5178 and saves to levels/ (sources) and
// apps/dust-range/levels/ (exported Lua the badge loads). No npm packages needed.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { toLua, indexLua, summary, validate, materialMap } from './format.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const sources = path.join(root, 'levels');
const exported = path.join(root, 'apps', 'dust-range', 'levels');
const app = path.join(root, 'apps', 'dust-range');
const port = Number(process.argv[2] || process.env.PORT || 5178);
const ID = /^[a-z0-9_-]{1,40}$/;

const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png' };

// Only these files are served; everything else is a 404.
const assets = {
  '/': path.join(here, 'index.html'),
  '/editor.js': path.join(here, 'editor.js'),
  '/editor.css': path.join(here, 'editor.css'),
  '/format.mjs': path.join(here, 'format.mjs'),
  '/assets/materials.json': path.join(root, 'sprites', 'tiles', 'materials.json'),
  '/assets/tiles-layout.json': path.join(root, 'sprites', 'tiles', 'tiles-layout.json'),
  '/assets/tileset.png': path.join(root, 'sprites', 'tiles', 'tileset.png'),
  '/assets/terrain.png': path.join(root, 'sprites', 'terrain', 'barren-terrain.png'),
  '/assets/idle-hero.png': path.join(root, 'sprites', 'hero', 'idle-hero.png'),
  '/assets/entities/kitten.png': path.join(root, 'sprites', 'entities', 'kitten.png'),
  '/assets/walk-layout.json': path.join(root, 'sprites', 'hero', 'walk-layout.json'),
};
for (const file of fs.readdirSync(path.join(root, 'sprites', 'weapons'))) {
  if (file.endsWith('.png')) assets[`/assets/weapons/${file}`] = path.join(root, 'sprites', 'weapons', file);
}

const materials = () => materialMap(JSON.parse(fs.readFileSync(assets['/assets/materials.json'], 'utf8')));

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store' });
  res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 8 * 1024 * 1024) { reject(new Error('Body too large')); req.destroy(); }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function listSources() {
  fs.mkdirSync(sources, { recursive: true });
  return fs.readdirSync(sources).filter((f) => f.endsWith('.json')).map((file) => {
    try {
      const level = JSON.parse(fs.readFileSync(path.join(sources, file), 'utf8'));
      const id = file.slice(0, -5);
      const lua = path.join(exported, `${id}.lua`);
      return { id, name: level.name || id, width: level.width, height: level.height,
        modified: fs.statSync(path.join(sources, file)).mtimeMs,
        exported: fs.existsSync(lua) ? fs.statSync(lua).mtimeMs : null };
    } catch { return null; }
  }).filter(Boolean).sort((a, b) => a.name.localeCompare(b.name));
}

function exportedMetas() {
  if (!fs.existsSync(exported)) return [];
  return fs.readdirSync(exported).filter((f) => f.endsWith('.lua') && f !== 'index.lua').map((file) => {
    const first = fs.readFileSync(path.join(exported, file), 'utf8').split('\n', 1)[0];
    const match = first.match(/^-- meta: (.*)$/);
    return match ? JSON.parse(match[1]) : null;
  }).filter(Boolean);
}

function writeIndex() {
  const metas = exportedMetas();
  fs.mkdirSync(exported, { recursive: true });
  if (metas.length) fs.writeFileSync(path.join(exported, 'index.lua'), indexLua(metas));
  else if (fs.existsSync(path.join(exported, 'index.lua'))) fs.rmSync(path.join(exported, 'index.lua'));
  return metas;
}

// Bundled-file and size budget from tools/package.py.
function packageStats() {
  let files = 0, bytes = 0;
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name !== 'main.lua' && entry.name !== 'app.json' || dir !== app) {
        files++; bytes += fs.statSync(full).size;
      }
    }
  };
  walk(app);
  return { files, maxFiles: 64, bytes, maxBytes: 1024 * 1024 };
}

function exportLevel(level) {
  const defs = materials();
  const issues = validate(level, defs);
  const errors = issues.filter((i) => i.severity === 'error');
  if (errors.length) return { ok: false, issues };
  fs.mkdirSync(exported, { recursive: true });
  const lua = toLua(level, defs);
  if (Buffer.byteLength(lua) > 256 * 1024) return { ok: false, issues: [{ severity: 'error', message: 'Exported level exceeds 256 KiB.' }] };
  fs.writeFileSync(path.join(exported, `${level.id}.lua`), lua);
  writeIndex();
  return { ok: true, issues, bytes: Buffer.byteLength(lua), package: packageStats(), summary: summary(level) };
}

function runPackage() {
  return new Promise((resolve) => {
    const python = process.platform === 'win32' ? 'python' : 'python3';
    const child = spawn(python, [path.join(root, 'tools', 'package.py')], { cwd: root });
    let output = '';
    child.stdout.on('data', (d) => { output += d; });
    child.stderr.on('data', (d) => { output += d; });
    child.on('close', (code) => resolve({ ok: code === 0, output: output.trim() }));
    child.on('error', (error) => resolve({ ok: false, output: String(error) }));
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const route = url.pathname;
    if (req.method === 'GET' && assets[route]) {
      return send(res, 200, fs.readFileSync(assets[route]), types[path.extname(assets[route]) || '.html']);
    }
    if (route === '/api/levels' && req.method === 'GET') {
      return send(res, 200, { levels: listSources(), exported: exportedMetas(), package: packageStats() });
    }
    const match = route.match(/^\/api\/(levels|export)\/([^/]+)$/);
    if (match) {
      const [, kind, id] = match;
      if (!ID.test(id)) return send(res, 400, { error: 'Invalid level id' });
      const file = path.join(sources, `${id}.json`);
      if (kind === 'levels' && req.method === 'GET') {
        if (!fs.existsSync(file)) return send(res, 404, { error: 'No such level' });
        return send(res, 200, fs.readFileSync(file, 'utf8'));
      }
      if (kind === 'levels' && req.method === 'PUT') {
        const level = JSON.parse(await readBody(req));
        if (level.id !== id) return send(res, 400, { error: 'Level id does not match the URL' });
        fs.mkdirSync(sources, { recursive: true });
        fs.writeFileSync(file, JSON.stringify(level) + '\n');
        return send(res, 200, { ok: true });
      }
      if (kind === 'levels' && req.method === 'DELETE') {
        if (fs.existsSync(file)) fs.rmSync(file);
        return send(res, 200, { ok: true });
      }
      if (kind === 'export' && req.method === 'POST') {
        const level = JSON.parse(await readBody(req));
        if (level.id !== id) return send(res, 400, { error: 'Level id does not match the URL' });
        return send(res, 200, exportLevel(level));
      }
      if (kind === 'export' && req.method === 'DELETE') {
        if (id === 'index') return send(res, 400, { error: 'Index is reserved for the badge level menu' });
        const lua = path.join(exported, `${id}.lua`);
        if (fs.existsSync(lua)) fs.rmSync(lua);
        writeIndex();
        return send(res, 200, { ok: true, package: packageStats() });
      }
    }
    if (route === '/api/package' && req.method === 'POST') return send(res, 200, await runPackage());
    send(res, 404, { error: 'Not found' });
  } catch (error) {
    send(res, 500, { error: String(error.message || error) });
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Dustpaw level builder: http://localhost:${port}`);
  console.log(`Sources: ${path.relative(root, sources)}  Export: ${path.relative(root, exported)}`);
});
