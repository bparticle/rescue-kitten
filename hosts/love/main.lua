-- Dustpaw on LÖVE: runs the badge app in apps/dust-range unchanged.
--
-- This file recreates the small part of the Solana OS badge API the game uses
-- (ui.canvas, sys, led, storage, on_key/on_tick/on_exit) on top of LÖVE, and loads
-- the game's Lua 5.4 source through compat/lua54.lua so LuaJIT can run it.
--
-- Run from the repository root:  love hosts/love

local ffi = require("ffi")
local bit = require("bit")
local Lua54 = require("compat.lua54")
require("compat.runtime")

local APP_W, APP_H = 320, 218   -- the badge's app area
local LED_H = 22                -- a strip above it shows the badge LEDs
local FRAME_W, FRAME_H = APP_W, APP_H + LED_H
local REPEAT_DELAY, REPEAT_EVERY = 0.40, 0.08

---------------------------------------------------------------------------
-- Game files: packaged inside the .love under game/, or read from the repo.
---------------------------------------------------------------------------

local game_dir
local function read_game_file(path)
  if love.filesystem.getInfo("game/" .. path) then
    return love.filesystem.read("game/" .. path)
  end
  if not game_dir then
    game_dir = os.getenv("DUSTPAW_GAME_DIR")
      or (love.filesystem.getSource() .. "/../../apps/dust-range")
  end
  local file = io.open(game_dir .. "/" .. path, "rb")
  if not file then return nil end
  local src = file:read("*a")
  file:close()
  return src
end

local function load_game_chunk(path)
  local src = read_game_file(path)
  if not src then return nil end
  local ok, translated = pcall(Lua54.translate, src, path)
  if not ok then error(translated, 0) end
  local chunk, err = loadstring(translated, "@" .. path)
  if not chunk then error(err, 0) end
  return chunk
end

-- The game's require("lib.game") finds lib/game.lua in the game folder first.
table.insert(package.loaders, 2, function(name)
  local path = name:gsub("%.", "/") .. ".lua"
  local chunk = load_game_chunk(path)
  if not chunk then return "\n\tno game file '" .. path .. "'" end
  return chunk
end)

---------------------------------------------------------------------------
-- ui: canvases drawn in creation order, each a scaled pixel buffer.
---------------------------------------------------------------------------

local THEME = {bg = 0x000000, text = 0xffffff, dim = 0x888888, panel = 0x1a1a1a,
  border = 0x333333, green = 0x14f195, purple = 0x9945ff}
local objects = {}

-- 0xRRGGBB → the RGBA8 word ImageData stores (little-endian: R, G, B, A in memory).
local packed = {}
local function pack(c)
  if c == nil or c == false then return 0 end
  local v = packed[c]
  if v then return v end
  local rgb = type(c) == "string" and THEME[c] or c
  if type(rgb) ~= "number" then error("unknown colour " .. tostring(c), 3) end
  rgb = bit.band(rgb, 0xffffff)
  local r, g, b = bit.rshift(rgb, 16), bit.band(bit.rshift(rgb, 8), 255), bit.band(rgb, 255)
  v = 0xff000000 + b * 65536 + g * 256 + r
  packed[c] = v
  return v
end

local Canvas = {}
Canvas.__index = Canvas
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local function fill(self, x, y, w, h, v)
  local cw = self.w
  local x0, x1 = max(0, x), min(cw, x + w)
  local y0, y1 = max(0, y), min(self.h, y + h)
  if x0 >= x1 or y0 >= y1 then return end
  local px = self.px
  for row = y0, y1 - 1 do
    local base = row * cw
    for i = base + x0, base + x1 - 1 do px[i] = v end
  end
  self.dirty = true
end

function Canvas:rect(x, y, w, h, c)
  fill(self, floor(x), floor(y), floor(w), floor(h), pack(c))
end

function Canvas:pixel(x, y, c)
  x, y = floor(x), floor(y)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return end
  self.px[y * self.w + x] = pack(c)
  self.dirty = true
end

function Canvas:line(x1, y1, x2, y2, c)
  x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
  local v = pack(c)
  local dx, dy = abs(x2 - x1), -abs(y2 - y1)
  local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    fill(self, x1, y1, 1, 1, v)
    if x1 == x2 and y1 == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x1 = x1 + sx end
    if e2 <= dx then err = err + dx; y1 = y1 + sy end
  end
end

function Canvas:show(visible) self.visible = visible ~= false end

function Canvas:remove()
  for i, obj in ipairs(objects) do
    if obj == self then table.remove(objects, i) break end
  end
end

ui = {}
function ui.canvas(x, y, w, h, opts)
  local data = love.image.newImageData(w, h)
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  local canvas = setmetatable({
    x = x, y = y, w = w, h = h, scale = opts and opts.scale or 1,
    data = data, image = nil, texture = image, visible = true, dirty = false,
    px = ffi.cast("uint32_t*", data:getFFIPointer()),
  }, Canvas)
  objects[#objects + 1] = canvas
  return canvas
end
-- No ui.load: the game then stamps tiles from packed runs, as on the headless host.

---------------------------------------------------------------------------
-- sys, led, storage
---------------------------------------------------------------------------

local tick_ms, start_time = 30, 0
local held = {}       -- key → {source = true}

sys = {}
function sys.millis() return floor((love.timer.getTime() - start_time) * 1000) end
function sys.tick(ms) tick_ms = max(1, floor(ms)) end
function sys.exit() love.event.quit() end
function sys.keys()
  local out = {}
  for key, sources in pairs(held) do
    if next(sources) then out[key] = true end
  end
  return out
end

local leds = {}
for i = 1, 8 do leds[i] = {0, 0, 0} end
led = {count = 8}
function led.set(i, r, g, b)
  if i < 1 or i > 8 then error("led.set: index 1..8", 2) end
  leds[i] = {r / 255, g / 255, b / 255}
end

local STORAGE_FILE = "storage.lua"
local store = {}

local function literal(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "table" then
    local out = {}
    for k, item in pairs(v) do out[#out + 1] = "[" .. literal(k) .. "]=" .. literal(item) end
    table.sort(out)
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("storage: can't keep a " .. t, 3)
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, item in pairs(v) do out[k] = copy(item) end
  return out
end

storage = {}
function storage.get(key) return copy(store[tostring(key)]) end
function storage.set(key, value)
  store[tostring(key)] = copy(value)
  love.filesystem.write(STORAGE_FILE, "return " .. literal(store))
end
function storage.remove(key)
  store[tostring(key)] = nil
  love.filesystem.write(STORAGE_FILE, "return " .. literal(store))
end

local function load_storage()
  local src = love.filesystem.getInfo(STORAGE_FILE) and love.filesystem.read(STORAGE_FILE)
  if not src then return end
  local chunk = loadstring(src, "=storage")
  if not chunk then return end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  if ok and type(value) == "table" then store = value end
end

---------------------------------------------------------------------------
-- Input: keyboard, gamepad buttons and the analog stick all feed the same keys.
---------------------------------------------------------------------------

local KEYBOARD = {
  up = "up", down = "down", left = "left", right = "right",
  z = "select", space = "select", ["return"] = "select", kpenter = "select",
  x = "back", backspace = "back",
}
-- SDL names the bottom face button "a". Set DUSTPAW_SWAP_AB=1 on devices whose
-- mapping puts the badge's Select on the other button.
local swap_ab = os.getenv("DUSTPAW_SWAP_AB") == "1"
local GAMEPAD = {
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  a = swap_ab and "back" or "select", b = swap_ab and "select" or "back",
}
local repeats = {}    -- key → {next = time, count = n}

local function call(name, ...)
  local fn = rawget(_G, name)
  if fn then return fn(...) end
end

local function press(key, source)
  local sources = held[key] or {}
  held[key] = sources
  local fresh = not next(sources)
  sources[source] = true
  if fresh then
    repeats[key] = {next = love.timer.getTime() + REPEAT_DELAY, count = 0}
    call("on_key", key, 0)
  end
end

local function release(key, source)
  local sources = held[key]
  if not sources then return end
  sources[source] = nil
  if not next(sources) then held[key], repeats[key] = nil, nil end
end

local function update_repeats(now)
  for key, r in pairs(repeats) do
    if now >= r.next then
      r.count, r.next = r.count + 1, now + REPEAT_EVERY
      call("on_key", key, r.count)
    end
  end
end

local stick = {}
local function update_stick(pad)
  local x, y = pad:getGamepadAxis("leftx"), pad:getGamepadAxis("lefty")
  local want = {left = x < -0.5, right = x > 0.5, up = y < -0.5, down = y > 0.5}
  for key, on in pairs(want) do
    if on and not stick[key] then press(key, "stick") end
    if not on and stick[key] then release(key, "stick") end
    stick[key] = on
  end
end

---------------------------------------------------------------------------
-- LÖVE callbacks
---------------------------------------------------------------------------

local accumulator = 0

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  start_time = love.timer.getTime()
  load_storage()
  if jit.arch == "arm64" or jit.arch == "arm" or os.getenv("DUSTPAW_FULLSCREEN") == "1" then
    love.window.setFullscreen(true)
    love.mouse.setVisible(false)
  end
  local chunk = load_game_chunk("main.lua")
  if not chunk then
    error("Dustpaw game files not found. Run `love hosts/love` from the repository root, "
      .. "or set DUSTPAW_GAME_DIR to apps/dust-range.", 0)
  end
  chunk()
end

function love.update(dt)
  local now = love.timer.getTime()
  for _, pad in ipairs(love.joystick.getJoysticks()) do
    if pad:isGamepad() then update_stick(pad) break end
  end
  update_repeats(now)
  accumulator = accumulator + dt * 1000
  local steps = 0
  while accumulator >= tick_ms and steps < 4 do
    call("on_tick", tick_ms)
    accumulator, steps = accumulator - tick_ms, steps + 1
  end
  if steps == 4 then accumulator = 0 end -- after a stall, skip ahead instead of racing
end

local function draw_leds()
  local spacing, y = 24, LED_H / 2
  local left = (FRAME_W - spacing * 5) / 2
  for i = 1, 8 do
    local c = leds[i]
    local lit = c[1] + c[2] + c[3] > 0
    local x = i <= 6 and left + (i - 1) * spacing or (i == 7 and 8 or FRAME_W - 8)
    if lit then
      love.graphics.setColor(c[1], c[2], c[3], 0.35)
      love.graphics.circle("fill", x, y, 7)
      love.graphics.setColor(c[1], c[2], c[3], 1)
    else
      love.graphics.setColor(0.16, 0.15, 0.14, 1)
    end
    love.graphics.circle("fill", x, y, 3.5)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  local w, h = love.graphics.getDimensions()
  local scale = min(w / FRAME_W, h / FRAME_H)
  if scale >= 1 then scale = floor(scale) end
  love.graphics.push()
  love.graphics.translate(floor((w - FRAME_W * scale) / 2), floor((h - FRAME_H * scale) / 2))
  love.graphics.scale(scale)
  draw_leds()
  for _, obj in ipairs(objects) do
    if obj.dirty then
      obj.texture:replacePixels(obj.data)
      obj.dirty = false
    end
    if obj.visible then
      love.graphics.draw(obj.texture, obj.x, LED_H + obj.y, 0, obj.scale, obj.scale)
    end
  end
  love.graphics.pop()
end

function love.keypressed(key)
  if key == "escape" then love.event.quit() return end
  if key == "f11" then love.window.setFullscreen(not love.window.getFullscreen()) return end
  local mapped = KEYBOARD[key]
  if mapped then press(mapped, "kb:" .. key) end
end

function love.keyreleased(key)
  local mapped = KEYBOARD[key]
  if mapped then release(mapped, "kb:" .. key) end
end

function love.gamepadpressed(pad, button)
  -- Guide, or Start + Back together, quits (the badge's Home button).
  if button == "guide" or (button == "start" and pad:isGamepadDown("back"))
    or (button == "back" and pad:isGamepadDown("start")) then
    love.event.quit()
    return
  end
  local mapped = GAMEPAD[button]
  if mapped then press(mapped, "pad:" .. button) end
end

function love.gamepadreleased(_, button)
  local mapped = GAMEPAD[button]
  if mapped then release(mapped, "pad:" .. button) end
end

function love.quit()
  call("on_exit")
  return false
end
