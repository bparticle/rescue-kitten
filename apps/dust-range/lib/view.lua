local Game = require("lib.game")
local Range = require("lib.range")
local Pixels = require("lib.pixels")
local effects = require("art.effects")
local palette = require("art.palette")
local terrain = require("art.terrain")
local icons = require("art.icons")

local W, HERO_SCALE, FIELD_W, FIELD_H, HUD_H = 320, 2, 160, 97, 24
local floor, min, max = math.floor, math.min, math.max
local byte = string.byte
local stamp, text = Pixels.stamp, Pixels.text
local INK, PANEL, BRASS, TEXT, DIM = 0x262320, 0x343029, 0xecd590, 0xf6e9d0, 0xbeb095
local SHADOW, PLATE = 0x7b6b57, 0x474841
local HP_GREEN, HP_AMBER, HP_RED = 0xb4cc92, 0xe4bd75, 0xff9278
local PICKUP_LIFT = {3,3,4,5,5,6,6,6,5,5,4,3}
local MEDKIT_MID, MEDKIT_DARK = 0x8fa375, 0x40563d
local BURGER_GOLD = 0xffc16a
local STAR_NEW, STAR_EMPTY = 0xfff1b8, 0x5c5442
local pickup_colors = {medkit=HP_GREEN, hamburger=BURGER_GOLD}
local function skin(light, shade, dark, hood)
  return setmetatable({[6]=light, [8]=shade, [9]=dark, [22]=hood}, {__index=palette.colors})
end
local skins = {
  soldier = skin(0xa45d5f, 0x663940, 0x422a33, 0x83474d),
  runner = skin(0xdc8f55, 0x885235, 0x583326, 0xbd7047),
  rifleman = skin(0x83bcb5, 0x366b6d, 0x24474d, 0x568c89),
  scatterguard = skin(0xab92cb, 0x665483, 0x463454, 0x8269a1),
  lobber = skin(0xadb877, 0x616741, 0x414732, 0x8a9858),
  warden = skin(0xa1a5b5, 0x64667a, 0x434858, 0x81859a),
  skirmisher = skin(0xdfb56d, 0x9d7442, 0x614428, 0xbd8f54),
  medic = skin(0xc7d6b8, 0x6e8c70, 0x3f5848, 0x9bb69a),
  bruiser = skin(0xcf8c82, 0x874c4c, 0x552f37, 0xaa625d),
  marksman = skin(0xce9db9, 0x7f526c, 0x58384e, 0xaa7696),
  cinder = skin(0xd58451, 0x7b4536, 0x503431, 0xaa6240),
  cryo = skin(0xa5cfe1, 0x50778c, 0x374d65, 0x7aa8c1),
}

local View = {}
View.__index = View

local function round(n) return floor(n + 0.5) end

local function health_bar(c, x, y, width, height, ratio, color)
  c:rect(x,y,width,height,INK)
  c:rect(x+1,y+1,width-2,height-2,PLATE)
  if ratio > 0 then c:rect(x+1,y+1,math.ceil((width-2)*ratio),height-2,color) end
end

local function health_color(game, ratio)
  if game.hurt_until then return 0xffb29c end
  if ratio <= 0.25 then return HP_RED end
  if ratio <= 0.5 then return HP_AMBER end
  return HP_GREEN
end

-- Effect sheets load on first use, one module per weapon.
local fx_modules = {}

local function sheet(name)
  local module = Range.effects[name][1]
  local loaded = fx_modules[module]
  if not loaded then
    loaded = require("art.fx-" .. module)
    fx_modules[module] = loaded
  end
  return loaded[name]
end

-- Stamp one frame centred on x, y.
local function play(c, name, row, frame, x, y)
  local fx = sheet(name)
  local frames = fx[row] or fx[1]
  stamp(c, frames[min(#frames, frame)], x - fx.w//2, y - fx.h//2)
end

local function play_age(c, name, row, age, x, y, loop)
  local fps = Range.effects[name][3]
  local fx = sheet(name)
  local frames = fx[row] or fx[1]
  local frame = floor(age*fps)
  frame = loop and frame % #frames + 1 or min(#frames, frame + 1)
  stamp(c, frames[frame], x - fx.w//2, y - fx.h//2)
end

-- Repeat a tile sheet edge to edge along a facing for length pixels.
local tile_dirs = {{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}}
local function tile_count(row, length, whole)
  local d = tile_dirs[row]
  local step = (d[1] ~= 0 and d[2] ~= 0) and 22.6 or 16
  return whole and floor(length/step) or math.ceil(length/step)
end

local function tiles(c, name, row, frame, x, y, count)
  local fx = sheet(name)
  local data = fx[row][min(#fx[row], frame)]
  local dx, dy = tile_dirs[row][1], tile_dirs[row][2]
  local left = x - (dx > 0 and 0 or dx < 0 and 15 or 8)
  local top = y - (dy > 0 and 0 or dy < 0 and 15 or 8)
  for i = 0, count - 1 do stamp(c, data, left + dx*16*i, top + dy*16*i) end
end

-- A jagged electric link between two points that redraws differently every few frames.
local function bolt(c, x0, y0, x1, y1, seed, fade)
  local dx, dy = x1-x0, y1-y0
  local length = math.sqrt(dx*dx + dy*dy)
  if length < 1 then return end
  local nx, ny = -dy/length, dx/length
  local px, py = x0, y0
  local core = fade and 0x70c2c2 or 0xeefcf8
  local steps = max(2, floor(length/7))
  for i = 1, steps do
    local t = i/steps
    local wobble = i == steps and 0 or ((seed*7 + i*13) % 5 - 2)
    local qx, qy = round(x0 + dx*t + nx*wobble), round(y0 + dy*t + ny*wobble)
    if not fade then c:line(px+1, py, qx+1, qy, 0x70c2c2) end
    c:line(px, py, qx, qy, core)
    px, py = qx, qy
  end
end

-- Compile a few tiles per loading tick. Older hosts draw the same packed runs directly.
local tile_symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz123456789"
local blank_tile_row = string.rep("0", 16)
local TILES_PER_TICK = 6

function View:prepare_tiles()
  local loader = self.tile_loader
  if not loader then return end
  local images, options = loader.images, loader.options
  local last = min(#terrain, #images+TILES_PER_TICK)
  for index = #images + 1, last do
    local data = terrain[index]
    local rows = {}
    for y = 1, 16 do rows[y] = blank_tile_row end
    for i = 1, #data, 5 do
      local x, y, width, height, color = byte(data, i, i+4)
      local key = loader.keys[color]
      if not key then
        local count = loader.count + 1
        key = tile_symbols:sub(count,count)
        loader.count, loader.keys[color], options.palette[key] = count, key, palette.colors[color-35]
      end
      local fill = string.rep(key, width-35)
      local left, right = x-35, x+width-69
      for row = y-34, y+height-70 do
        rows[row] = rows[row]:sub(1,left) .. fill .. rows[row]:sub(right)
      end
    end
    images[index] = ui.load(rows, options)
  end
  if last == #terrain then self.tiles, self.tile_loader = images, nil end
end

function View.new()
  local canvas = ui.canvas(0,0,FIELD_W,FIELD_H,{scale=HERO_SCALE})
  local loader
  if ui.load and canvas.image then
    loader = {images={}, keys={}, count=0, options={palette={["0"]=palette.ground}}}
  end
  return setmetatable({
    canvas=canvas,
    strip=ui.canvas(0,FIELD_H*HERO_SCALE,W,HUD_H,{scale=1}),
    art={[0]=require("art.unarmed")},
    tile_loader=loader,
    pickup_motion=true,
  }, View)
end

function View:loading()
  self.canvas:rect(0,0,FIELD_W,FIELD_H,INK)
  self.strip:rect(0,0,W,HUD_H,INK)
  text(self.canvas,"DUSTPAW",59,45,BRASS)
end

function View:weapon_art(held)
  if not self.art[held] then self.art[held] = require("art." .. Game.weapons[held].art) end
  return self.art[held]
end

function View:enemy_portrait(profile)
  return self:weapon_art(profile.weapon)[7][1], skins[profile.skin]
end

local function ground(c, map, left, top, tiles)
  if not tiles then c:rect(0,0,FIELD_W,FIELD_H,palette.ground) end
  local draw_tile = tiles and c.image or stamp
  tiles = tiles or terrain
  for y = top//16, (top+FIELD_H-1)//16 do
    local row, py = map[y], y*16-top
    for x = left//16, (left+FIELD_W-1)//16 do
      draw_tile(c, tiles[row[x]], x*16-left, py)
    end
  end
end

-- Level tiles. Opaque tiles become native images on firmware that has ui.load; the rest
-- (and every tile on the headless host) are stamped from their packed runs.
local level_tiles

local function tile_image(self, tile)
  local images = self.tile_images
  if not images or not tile.opaque then return end
  local image = images[tile]
  if image ~= nil then return image or nil end
  local colors = level_tiles.colors
  local rows, keys, palette, count = {}, {}, {}, 0
  for y = 1, 16 do rows[y] = blank_tile_row end
  local data = tile.art
  for i = 1, #data, 5 do
    local x, y, width, height, color = byte(data, i, i+4)
    local key = keys[color]
    if not key then
      count = count + 1
      key = tile_symbols:sub(count,count)
      keys[color], palette[key] = key, colors[color-35]
    end
    local fill = string.rep(key, width-35)
    local left, right = x-35, x+width-69
    for row = y-34, y+height-70 do
      rows[row] = rows[row]:sub(1,left) .. fill .. rows[row]:sub(right)
    end
  end
  local ok, loaded = pcall(ui.load, rows, {palette=palette})
  images[tile] = ok and loaded or false
  return ok and loaded or nil
end

local function draw_tile_art(self, c, tile, x, y)
  if tile.terrain then
    if self.tiles then c:image(self.tiles[tile.terrain], x, y)
    else stamp(c, terrain[tile.terrain], x, y) end
    return
  end
  local image = tile_image(self, tile)
  if image then c:image(image, x, y)
  else stamp(c, tile.art, x, y, 1, level_tiles.colors) end
end

local function draw_tile(self, c, tile, x, y)
  -- An opaque tile hides whatever is underneath it.
  if not tile.opaque then
    if tile.footing then draw_tile_art(self, c, tile.footing, x, y) end
    if tile.base then draw_tile_art(self, c, tile.base, x, y) end
  end
  draw_tile_art(self, c, tile, x, y)
  if tile.detail then draw_tile_art(self, c, tile.detail, x, y) end
end

-- The entrance is a recessed opening in the eave. Depth is measured inward from the edge.
local entrance_rects = {
  {2,0,12,8,INK},
  {3,1,1,6,SHADOW}, {12,1,1,6,SHADOW},
  {3,6,10,1,BRASS},
  {4,0,8,2,SHADOW}, {4,0,8,1,DIM},
}

-- Resolve each facing once into flat x, y, w, h, color runs.
local entrance_runs = {}
for _, facing in ipairs({"north", "south", "west", "east"}) do
  local side = facing == "west" or facing == "east"
  local reverse = facing == "south" or facing == "east"
  local runs = {}
  for _, part in ipairs(entrance_rects) do
    local offset, depth, width, height, color = part[1], part[2], part[3], part[4], part[5]
    if reverse then depth = 16-depth-height end
    if side then runs[#runs+1] = {depth,offset,height,width,color}
    else runs[#runs+1] = {offset,depth,width,height,color} end
  end
  entrance_runs[facing] = runs
end

local function draw_entrance(c, x, y, facing)
  local runs = entrance_runs[facing]
  for i = 1, #runs do
    local r = runs[i]
    c:rect(x+r[1],y+r[2],r[3],r[4],r[5])
  end
end

-- Cells under an opaque tile in a later layer are skipped: structure covers ground, and a roof
-- that is showing covers both. hidden is the roof region the player stands under, which isn't drawn.
local function draw_level(self, c, level, left, top, layer, hidden, tall_only)
  local cells, w = level[layer], level.w
  local region = level.region
  local walls = layer == "ground" and level.structure
  local roofs = layer ~= "roof" and not tall_only and level.roof
  local entrances = layer == "roof" and level.entrances
  local x0, y0 = max(0, left//16), max(0, top//16)
  local x1, y1 = min(w-1, (left+FIELD_W-1)//16), min(level.h-1, (top+FIELD_H-1)//16)
  for y = y0, y1 do
    local row, py = y*w + 1, y*16-top
    for x = x0, x1 do
      local i = row+x
      local tile = cells[i]
      local covered = walls and walls[i] and walls[i].opaque
        or roofs and roofs[i] and roofs[i].opaque and not (hidden and region[i] == hidden)
      if tile and not covered and not ((layer == "roof" or tall_only) and hidden and region[i] == hidden)
        and (not tall_only or region[i] and (tile.def.height or 0) > level.roof_height) then
        local px = x*16-left
        draw_tile(self, c, tile, px, py)
        local facing = entrances and entrances[i]
        if facing then draw_entrance(c, px, py, facing) end
      end
    end
  end
end

local function draw_exit(c, exit, left, top, time, open)
  local x, y = round(exit.x)-left, round(exit.y)-top
  if x < -12 or x >= FIELD_W+12 or y < -12 or y >= FIELD_H+12 then return end
  local pulse = floor(time*4) % 2
  local color = open and BRASS or 0xa5ad7c
  c:rect(x-7-pulse,y-7-pulse,15+2*pulse,2,color)
  c:rect(x-7-pulse,y+6+pulse,15+2*pulse,2,color)
  c:rect(x-7-pulse,y-7-pulse,2,15+2*pulse,color)
  c:rect(x+6+pulse,y-7-pulse,2,15+2*pulse,color)
  text(c,"EXIT",x-11,y-3,color)
end

-- The kitten's head (rows 0-8) bobs a pixel over its body (rows 8-12). Row 8 sits
-- in both halves, so lifting the head stretches the neck instead of opening a gap.
local NECK = 8
local kitten_parts
local function kitten_halves()
  if kitten_parts then return kitten_parts end
  local art, head, body = require("art.kitten").art, {}, {}
  for i = 1, #art, 5 do
    local x, y, w, h, color = string.byte(art, i, i + 4)
    local top, bottom = y - 35, y - 35 + h - 35
    if top <= NECK then
      head[#head+1] = string.char(x, y, w, math.min(bottom, NECK+1) - top + 35, color)
    end
    if bottom > NECK then
      local from = math.max(top, NECK)
      body[#body+1] = string.char(x, from + 35, w, bottom - from + 35, color)
    end
  end
  kitten_parts = {table.concat(head), table.concat(body)}
  return kitten_parts
end

local function kitten_step(time)
  return floor(time*2) % 2
end

local function draw_kitten(c, x, y, carried, bob)
  local kitten = require("art.kitten")
  if x < -kitten.w or x >= FIELD_W+kitten.w or y < -kitten.h or y >= FIELD_H+kitten.h then return false end
  if not carried then
    c:rect(x-5,y+3,11,2,SHADOW)
    c:rect(x-6,y+4,13,1,SHADOW)
    c:rect(x-9,y+1,2,1,HP_GREEN)
    c:rect(x+8,y+1,2,1,HP_GREEN)
  end
  local halves, left = kitten_halves(), x-kitten.w//2
  stamp(c,halves[2],left,y-8,1,kitten.colors)
  stamp(c,halves[1],left,y-8-(bob or 0),1,kitten.colors)
  return true
end

local function pickup_step(time)
  return floor(time*8) % #PICKUP_LIFT
end

function View:needs_pickup_frame(game)
  if not self.pickup_motion or game.result then return false end
  return self.pickups_on_screen and self.pickup_step ~= pickup_step(game.time)
    or self.kitten_on_screen and self.kitten_step ~= kitten_step(game.time)
end

local function draw_medkit(c, x, y)
  c:rect(x-2,y-6,5,2,MEDKIT_DARK)
  c:rect(x-5,y-5,11,11,INK)
  c:rect(x-6,y-4,13,9,INK)
  c:rect(x-5,y-4,11,8,TEXT)
  c:rect(x-5,y+3,11,2,MEDKIT_MID)
  c:rect(x-3,y-3,7,6,HP_GREEN)
  c:rect(x-2,y-1,5,1,MEDKIT_DARK)
  c:rect(x,y-3,1,5,MEDKIT_DARK)
end

local function draw_hamburger(c, x, y)
  c:rect(x-4,y-6,9,11,INK)
  c:rect(x-6,y-4,13,8,INK)
  c:rect(x-3,y-5,7,2,BURGER_GOLD)
  c:rect(x-5,y-3,11,2,0xdc913e)
  c:pixel(x+2,y-4,TEXT)
  c:rect(x-5,y-1,11,1,HP_GREEN)
  c:rect(x-4,y,9,1,0x854635)
  c:rect(x-4,y+1,9,2,0xdc913e)
  c:rect(x-3,y+1,7,1,BURGER_GOLD)
end

local function draw_pickup(c, item, x, y, step, focused)
  local icon = icons[item.id]
  local lift = step and PICKUP_LIFT[(step+(item.x+item.y)//12) % #PICKUP_LIFT+1] or 4
  local half = max(4, (icon and icon[1] or 13)//3) - (lift >= 5 and 1 or 0)
  local accent = item.kind == "medkit" and (focused and HP_GREEN or MEDKIT_MID)
    or pickup_colors[item.kind] or (focused and BRASS or 0xc5ab76)
  c:rect(x-half+1,y+4,2*half-1,3,SHADOW)
  c:rect(x-half,y+5,2*half+1,1,0x625445)
  c:rect(x-half-4,y+5,2,1,accent)
  c:rect(x+half+3,y+5,2,1,accent)
  if icon then stamp(c,icon[3],x-icon[1]//2,y-lift-icon[2]//2)
  elseif item.kind == "hamburger" then draw_hamburger(c,x,y-lift)
  else draw_medkit(c,x,y-lift) end
end

local target_faces = {
  board   = {5, 5, 0xb37452, 0xf2cb87},
  steel   = {5, 5, 0x777e7b, 0xc5cbc1},
  pattern = {9, 7, 0xd0a76d, 0xf7dfaa},
  marker  = {3, 4, 0xa65a37, 0xf3b965},
  block   = {7, 6, 0x77716b, 0xbdb3a3},
  cloth   = {7, 5, 0x996951, 0xd1a36c},
  plank   = {3, 6, 0x9c6a45, 0xe0b27a},
  offset  = {5, 5, 0x6f7a6a, 0xd7dcc7},
  post    = {3, 6, 0x7d5a3c, 0xc89a62},
  node    = {4, 4, 0x44747c, 0x9fe3e0},
  dummy   = {6, 6, 0x8a7a63, 0xd8c9a4},
  bulwark = {9, 7, 0x5f5a55, 0xa59c8f},
  crate   = {5, 5, 0x8b6a3e, 0xd5a865},
  pad     = {5, 3, 0x5d6a74, 0xb5c6cc},
}

local function draw_target(c, target, x, y, time)
  local kind = target.kind
  if x < -23 or x >= FIELD_W+23 or y < -11 or y >= FIELD_H+24 then return end
  local half_w, half_h, base, light = table.unpack(target_faces[kind])
  local width = 2*half_w + 1
  c:rect(x-half_w-1,y+half_h,width+3,3,SHADOW)
  if target.health == 0 then
    c:rect(x-half_w,y+half_h-1,width,2,INK)
    c:rect(x-3,y+half_h-3,4,2,base)
    c:pixel(x+half_w,y+half_h-2,light)
  else
    c:rect(x-half_w-1,y-half_h-1,width+2,2*half_h+2,INK)
    c:rect(x-half_w,y-half_h,width,2*half_h,base)
    if kind == "board" or kind == "steel" then
      c:rect(x-3,y-3,7,6,light)
      c:rect(x-1,y-1,3,2,base)
    elseif kind == "pattern" then
      c:rect(x-7,y-5,15,10,light)
      c:rect(x-5,y-3,11,6,base)
      c:rect(x-3,y-2,7,4,light)
      c:pixel(x,y,INK)
    elseif kind == "marker" then
      c:rect(x-3,y-3,7,2,light)
      c:rect(x-3,y+1,7,1,light)
    elseif kind == "block" then
      c:rect(x-7,y-6,15,2,light)
      c:rect(x-7,y,15,1,INK)
      c:rect(x+2,y+1,1,5,light)
    elseif kind == "plank" or kind == "post" then
      c:rect(x-3,y-6,1,12,light)
      c:rect(x-1,y-4,3,1,INK)
      c:rect(x-1,y+2,3,1,INK)
    elseif kind == "offset" then
      c:rect(x-4,y-4,9,8,light)
      c:rect(x-2,y-2,5,4,base)
      c:pixel(x,y,0xdd964e)
    elseif kind == "node" then
      c:rect(x-2,y-3,5,6,light)
      c:rect(x-3,y-2,7,4,light)
      c:rect(x-1,y-1,3,2,0xeefcf8)
    elseif kind == "dummy" then
      c:rect(x-2,y-6,5,4,light)
      c:rect(x-5,y-1,11,2,light)
      c:rect(x-1,y+1,3,5,light)
    elseif kind == "bulwark" then
      c:rect(x-9,y-7,19,2,light)
      c:rect(x-9,y-1,19,1,INK)
      c:rect(x-4,y-5,1,4,INK)
      c:rect(x+4,y,1,7,INK)
    elseif kind == "crate" then
      c:rect(x-5,y-5,11,1,light)
      c:line(x-4,y-4,x+4,y+4,light)
      c:line(x+4,y-4,x-4,y+4,light)
    elseif kind == "pad" then
      c:rect(x-4,y-2,9,1,light)
      c:rect(x-1,y-1,3,2,0x70c2c2)
    else
      c:rect(x-8,y-6,17,2,light)
      c:line(x-6,y+2,x+6,y-3,light)
    end
    for _, mark in ipairs(target.marks) do
      local mx = x + max(1-half_w,min(half_w-1,round(mark.x)))
      local my = y + max(1-half_h,min(half_h-1,round(mark.y)))
      c:rect(mx,my,2,1,INK)
    end
    if target.cracked then
      c:line(x-2,y-half_h,x+1,y-1,INK)
      c:line(x+1,y-1,x-2,y+half_h-1,INK)
      c:line(x+1,y-1,x+half_w,y,INK)
    end
    if target.scorched then
      c:rect(x-half_w+1,y+half_h-3,width-2,2,0x503631)
      c:rect(x-2,y+half_h-5,5,3,0x503631)
    end
    if target.frost_until then
      local age = time - (target.frost_at or time)
      local frame = age < 0.12 and 1 or age < 0.25 and 2 or 3 + floor(age*8) % 2
      play(c,"frost-coat",1,frame,x,y)
    end
    if target.burn then
      c:rect(x-3,y-half_h-3,7,2,0xd4512e)
      c:rect(x-2,y-half_h-4,3,3,0xffab56)
      c:pixel(x+2,y-half_h-5,0xffd790)
    end
  end
  local ratio = target.health / target.surface.health
  local fill = math.ceil(width * ratio)
  c:rect(x-half_w-1,y+half_h+3,width+2,3,INK)
  if fill > 0 then
    local color = ratio > 0.55 and 0xa7b575 or ratio > 0.25 and BRASS or 0xe47c57
    c:rect(x-half_w,y+half_h+4,fill,1,color)
  end
  if target.label then
    local label = target.surface.name
    local left = x-3*#label
    c:rect(left-2,y-half_h-15,6*#label+3,9,INK)
    text(c,label,left,y-half_h-14,TEXT)
  end
end

local function locator(c, item, left, top, px, py, color)
  local x, y = item.x-left, item.y-top
  if x >= 19 and x < FIELD_W-19 and y >= 14 and y < FIELD_H-14 then return end
  local dx, dy = x-px, y-py
  local tx = dx > 0 and (FIELD_W-8-px)/dx or dx < 0 and (7-px)/dx or math.huge
  local ty = dy > 0 and (FIELD_H-8-py)/dy or dy < 0 and (7-py)/dy or math.huge
  local distance = max(0,min(tx,ty))
  local mx, my = round(px+dx*distance), round(py+dy*distance)
  c:rect(mx-4,my-4,9,9,INK)
  c:rect(mx-2,my-2,5,5,color or BRASS)
  if item.kind == "hamburger" then
    c:rect(mx-1,my-1,3,1,INK)
    c:rect(mx-1,my+1,3,1,INK)
  else
    if color then c:rect(mx,my-1,1,3,INK) else c:pixel(mx,my,INK) end
    if item.kind == "medkit" then c:rect(mx-1,my,3,1,INK) end
  end
end

local function draw_shot(c, shot, left, top, time)
  local x, y = round(shot.x)-left, round(shot.y)-top
  if x < -32 or x >= FIELD_W+32 or y < -32 or y >= FIELD_H+32 then return end
  local kind = shot.kind
  if kind == "bank" then
    play_age(c,"bank-round",Game.direction_of(shot.dx,shot.dy),shot.age,x,y,true)
  elseif kind == "disc" then
    c:rect(x-2,y+4,5,1,SHADOW)
    play_age(c,"disc-spin",1,shot.age,x,y,true)
  elseif kind == "charge" then
    play_age(c,shot.level >= 1 and "charge-bolt-full" or "charge-bolt-low",shot.direction,shot.age,x,y,true)
  elseif kind == "orb" then
    if shot.well_at then play_age(c,"gravity-well",1,time-shot.well_at,x,y,true)
    else play_age(c,"orb-shot",1,shot.age,x,y,true) end
  elseif kind == "frost" then
    local age = shot.age
    local frame = (floor(age*54) + shot.flame_phase)%3 + 1
    local drift = (frame-2) * age * 9
    x, y = x-round(shot.dy*drift), y+round(shot.dx*drift)
    play(c,"cryo-puff",age < 0.09 and 1 or age < 0.16 and 2 or 3,frame,x,y)
  elseif kind == "flame" then
    local age = shot.age
    local frame = (floor(age*54) + shot.flame_phase)%3 + 1
    if age < 0.038 then
      local reach = 2 + frame
      c:line(x,y,x+round(shot.dx*reach),y+round(shot.dy*reach),0xeb6e31)
      c:rect(x-1,y-1,3,3,0xffad50)
      c:pixel(x,y,0xffe6a4)
    else
      local drift = (frame-2) * age * 11
      x, y = x-round(shot.dy*drift), y+round(shot.dx*drift)
      local heat = age < 0.09 and 1 or age < 0.155 and 2 or 3
      effects.stamp(c,effects.flames[heat][frame],x,y)
      if frame == 2 then
        c:pixel(x+round(shot.dx*5-shot.dy*3),y+round(shot.dy*5+shot.dx*3),0xf79144)
      end
    end
  elseif kind == "grenade" then
    local lift = round(11 * math.sin(shot.age / shot.life * math.pi))
    c:rect(x-2,y,4,1,SHADOW)
    c:rect(x-2,y-lift-2,5,4,INK)
    c:rect(x-1,y-lift-1,3,2,0x738c64)
    c:pixel(x,y-lift-1,0xa5ad7c)
    c:pixel(x+floor(shot.age*21)%3-1,y-lift-2,0xd7cda4)
  elseif kind == "tnt" then
    local icon = icons[shot.weapon_id]
    local icon_left, icon_top = x-icon[1]//2, y-icon[2]//2
    local remaining = 1-shot.age/shot.life
    local urgent = remaining < 0.35
    local flare = floor(shot.age*(urgent and 22 or 10)) % 2 == 0
    local color = urgent and 0xf27b5b or BRASS
    c:rect(icon_left,y+4,icon[1],2,SHADOW)
    stamp(c,icon[3],icon_left,icon_top)
    if flare then
      local fuse_x, fuse_y = icon_left+7, icon_top+1
      c:line(fuse_x-2,fuse_y,fuse_x+2,fuse_y,0xffc155)
      c:line(fuse_x,fuse_y-2,fuse_x,fuse_y+1,0xffecae)
    end
    c:rect(x-6,y+7,12,3,INK)
    c:rect(x-5,y+8,math.ceil(10*remaining),1,color)
  elseif kind == "rocket" then
    local dx, dy = shot.dx, shot.dy
    x, y = x+round(dx*3), y+round(dy*3)
    local length = 10 + floor(shot.age*72)%4
    local tail_x, tail_y = x-round(dx*6), y-round(dy*6)
    local tip_x, tip_y = x-round(dx*length), y-round(dy*length)
    c:line(tail_x-round(dy*2),tail_y+round(dx*2),tip_x,tip_y,0xc8442b)
    c:line(tail_x+round(dy*2),tail_y-round(dx*2),tip_x,tip_y,0xee752e)
    c:line(tail_x,tail_y,x-round(dx*(length-2)),y-round(dy*(length-2)),0xffc155)
    c:pixel(x-round(dx*(length+2)),y-round(dy*(length+2)),0xe67439)
    effects.stamp(c,effects.rockets[shot.direction],x,y)
  else
    local tail = kind == "pellet" and 3 or 6
    local color = shot.owner.profile and 0xf28a6a or 0xffecae
    c:line(x,y,x-round(shot.dx*tail),y-round(shot.dy*tail),color)
    c:pixel(x,y,0xfff7d8)
  end
end

local function draw_smoke(c, p, left, top)
  local x, y = round(p.x)-left, round(p.y)-top
  if x < -8 or x >= FIELD_W+8 or y < -8 or y >= FIELD_H+8 then return end
  local progress = p.age/p.life
  if p.kind == "exhaust" then
    local size = 1 + floor(progress*2)
    local color = progress < 0.22 and 0xa26345 or progress < 0.65 and 0x645749 or 0x8a7a66
    c:rect(x-size,y,2*size+1,2,color)
    c:pixel(x,y-1,color)
    return
  end
  local size = 2 + floor(progress*3)
  if progress > 0.79 then
    c:rect(x-size,y-1,3,2,0x8d7c66)
    c:rect(x+1,y-2,3,2,0x95836e)
    return
  end
  local dark = progress < 0.45 and 0x493937 or 0x6c5d50
  local light = progress < 0.45 and 0x73554b or 0x857260
  c:rect(x-size,y-1,2*size+1,3,dark)
  c:rect(x-size+1,y-2,2*size-1,5,dark)
  c:rect(x-size+2,y-3,size+1,2,light)
  c:rect(x-size+1,y-1,size+1,2,light)
  c:pixel(x+size-1,y-1,light)
end

local blast_ring = {
  {-0.34,-1,0.34,-1}, {0.47,-0.94,0.94,-0.47}, {1,-0.34,1,0.34}, {0.94,0.47,0.47,0.94},
  {0.34,1,-0.34,1}, {-0.47,0.94,-0.94,0.47}, {-1,0.34,-1,-0.34}, {-0.94,-0.47,-0.47,-0.94},
}

local function draw_particle(c, p, left, top, game)
  local x, y = round(p.x)-left, round(p.y)-top
  local progress = p.age/p.life
  if p.kind == "fx" then
    if p.follow then x, y = round(game.x)-left, round(game.y)-top end
    play_age(c,p.name,p.row,p.age,x,y)
  elseif p.kind == "beam" then
    local whole = tile_count(p.row,p.length,game.level ~= nil)
    tiles(c,"rail-beam",p.row,floor(p.age*24)+1,x,y,whole)
    if game.level then
      local d = tile_dirs[p.row]
      local sx, sy = x+d[1]*16*whole, y+d[2]*16*whole
      local ex, ey = round(p.ex)-left, round(p.ey)-top
      c:line(sx,sy+1,ex,ey+1,0xb38bc9)
      c:line(sx,sy,ex,ey,0xf6e9f8)
    end
  elseif p.kind == "enemy_beam" then
    local ex, ey = round(p.ex)-left, round(p.ey)-top
    c:line(x,y+1,ex,ey+1,0xd27591)
    c:line(x,y,ex,ey,0xffc0cb)
  elseif p.kind == "arc" then
    local fade = progress > 0.55
    local ex, ey = round(p.ex)-left, round(p.ey)-top
    local d = tile_dirs[p.row]
    -- Whole tiles cover the straight run; a drawn bolt finishes on the struck point.
    local whole = tile_count(p.row, max(0, math.sqrt((ex-x)^2 + (ey-y)^2) - 8), true)
    tiles(c,"arc-bolt",p.row,fade and 3 or floor(p.age*20)%2+1,x,y,whole)
    local seed = p.seed + floor(p.age*20)
    bolt(c,x+d[1]*16*whole,y+d[2]*16*whole,ex,ey,seed,fade)
    for i, link in ipairs(p.links) do
      bolt(c,round(link[1])-left,round(link[2])-top,round(link[3])-left,round(link[4])-top,seed+i*3,fade)
    end
  elseif p.kind == "heal" then
    c:rect(x-3,y-1,7,3,0xabd495)
    c:rect(x-1,y-3,3,7,0xabd495)
  elseif p.kind == "flake" then
    c:pixel(x,y,progress < 0.5 and 0xeefcf8 or 0x95d6de)
    if progress < 0.3 then c:pixel(x+1,y,0xcdecff) end
  elseif p.kind == "water_blast" then
    local radius = max(3, round(p.radius*(0.15 + progress*0.65)))
    local color = progress < 0.5 and 0xa8e2e5 or 0x5f9eaa
    for _, edge in ipairs(blast_ring) do
      c:line(x+round(edge[1]*radius),y+round(edge[2]*radius),
        x+round(edge[3]*radius),y+round(edge[4]*radius),color)
    end
  elseif p.kind == "blast" or p.kind == "rocket_blast" or p.kind == "tnt_blast" then
    local frame = progress < 0.18 and 1 or progress < 0.42 and 2 or progress < 0.72 and 3 or 4
    if p.kind == "rocket_blast" then
      local radius = 8 + floor(progress*25)
      if frame <= 3 then
        local spread = radius//2
        local rim = frame == 1 and 0xffc480 or frame == 2 and 0xea753a or 0xa34133
        c:line(x-radius,y-1,x-spread,y-spread,rim)
        c:line(x+spread,y+spread,x+radius,y+1,rim)
        c:line(x-radius+1,y+2,x-spread-1,y+spread,rim)
        c:line(x+spread+1,y-spread,x+radius-1,y-2,rim)
      end
      effects.stamp(c,effects.blasts[min(frame+1,4)],x-6,y+3)
      effects.stamp(c,effects.blasts[min(frame+1,4)],x+5,y-4)
    elseif frame <= 3 then
      local tnt = p.kind == "tnt_blast"
      local radius = 7 + (p.radius-7) * (1-(1-progress)^4)
      local color = frame == 1 and 0xffcf88 or frame == 2 and 0xdf8d54 or 0xa06045
      local double_ring = tnt and frame <= 2
      local inner = radius * 0.75
      for _, segment in ipairs(blast_ring) do
        c:line(x+round(segment[1]*radius),y+round(segment[2]*radius),
          x+round(segment[3]*radius),y+round(segment[4]*radius),color)
        if double_ring then
          c:line(x+round(segment[1]*inner),y+round(segment[2]*inner),
            x+round(segment[3]*inner),y+round(segment[4]*inner),0xffe6ac)
        end
      end
      if double_ring then
        effects.stamp(c,effects.blasts[frame+1],x-9,y+3)
        effects.stamp(c,effects.blasts[frame+1],x+9,y-3)
      end
    end
    effects.stamp(c,effects.blasts[frame],x,y)
  elseif p.kind == "dust" then
    local size = progress < 0.5 and 2 or 3
    c:rect(x,y,size,2,progress < 0.7 and 0x83725e or 0xb5a484)
  elseif p.kind == "ember" then
    local color = progress < 0.25 and 0xffbe65 or progress < 0.60 and 0xe65d32 or 0xa1382d
    local tail = (1-progress)*0.06
    c:line(x,y,x-round(p.vx*tail),y-round(p.vy*tail),color)
    if progress < 0.25 then c:pixel(x,y,0xffedac) end
  else
    local color = progress < 0.4 and 0xffe2a0 or progress < 0.75 and 0xe39950 or 0xbd6e45
    c:rect(x,y,progress < 0.4 and 2 or 1,1,color)
  end
end

local function flash(c, actor, left, top)
  if actor.flash_fx then return end
  local x, y = round(actor.flash_x)-left, round(actor.flash_y)-top
  local dx, dy = actor.flash_dx, actor.flash_dy
  if actor.flash <= Game.flash_duration - Game.kick_duration then
    c:rect(x,y,2,2,0xffbd6d)
    return
  end
  local forward = actor.flash_kind == "pellet" and 6 or 4
  local a, b = round(dx*forward), round(dy*forward)
  local p, q = round(-dy*2), round(dx*2)
  c:line(x-p,y-q,x+a,y+b,0xffb45b)
  c:line(x+p,y+q,x+a,y+b,0xffb45b)
  c:line(x,y,x+a,y+b,0xfff6c7)
  c:rect(x-1,y-1,3,3,0xffe2a0)
end

function View:draw_actor(actor, weapon, x, y, colors)
  local c = self.canvas
  local art = self:weapon_art(weapon)
  c:rect(x-4,y+3,9,3,SHADOW)
  if actor.flash > Game.flash_duration - Game.kick_duration then
    x, y = x-round(actor.flash_dx), y-round(actor.flash_dy)
  end
  stamp(c, art[actor.direction][actor.pose], x-14, y-14, 1, colors)
end

function View:draw_enemy(enemy, left, top)
  local c = self.canvas
  local x, y = round(enemy.x)-left, round(enemy.y)-top
  if enemy.health == 0 or x < -14 or x >= FIELD_W+14 or y < -14 or y >= FIELD_H+22 then return end
  self:draw_actor(enemy, enemy.weapon, x, y, skins[enemy.profile.skin])
  if enemy.profile.frontal_damage and not enemy.fire_at then
    local d = tile_dirs[enemy.direction]
    local nx, ny = d[1], d[2]
    local sx, sy = x+nx*8, y+ny*8
    c:line(sx-ny*6,sy+nx*6,sx+ny*6,sy-nx*6,INK)
    c:line(sx+nx-ny*5,sy+ny+nx*5,sx+nx+ny*5,sy+ny-nx*5,0xa8cad4)
  end
  if enemy.flash > 0 then flash(c,enemy,left,top) end
  if x < 0 or x >= FIELD_W or y < 0 or y >= FIELD_H then return end
  local bar_x, bar_y = max(0,min(FIELD_W-17,x-8)), y < 24 and y+10 or y-13
  c:rect(bar_x,bar_y,17,4,INK)
  c:rect(bar_x+1,bar_y+1,math.ceil(15*enemy.health/enemy.surface.health),2,enemy.roof and 0x79e1e6 or 0xed906d)
  if enemy.fire_at then
    local cue = enemy.heal_target and 0xabd495 or BRASS
    local cue_x, cue_y = max(0,min(FIELD_W-5,x-2)), y < 24 and y+15 or y-23
    c:rect(cue_x,cue_y,5,9,INK)
    c:rect(cue_x+1,cue_y+1,3,4,cue)
    c:rect(cue_x+1,cue_y+6,3,2,cue)
  end
end

-- A body costs about 100 rects, so each floor draws only the newest few on screen.
local MAX_DRAWN_BODIES = 6
local body_art
local visible_bodies = {}
local function draw_bodies(c, bodies, left, top, on_roof, hidden_roof)
  if #bodies == 0 then return end
  body_art = body_art or require("art.enemy-bodies")
  local half_w, half_h = body_art.w//2, body_art.h//2
  local count = 0
  for index = #bodies, 1, -1 do
    local body = bodies[index]
    if (on_roof and body.roof and body.roof ~= hidden_roof) or (not on_roof and not body.roof) then
      local x, y = round(body.x)-left, round(body.y)-top
      if x >= -half_w and x < FIELD_W+half_w and y >= -half_h and y < FIELD_H+half_h then
        count = count + 1
        visible_bodies[count] = body
        if count == MAX_DRAWN_BODIES then break end
      end
    end
  end
  -- Oldest first, so newer bodies land on top.
  for index = count, 1, -1 do
    local body = visible_bodies[index]
    visible_bodies[index] = nil
    stamp(c,body_art[body.skin],round(body.x)-left-half_w,round(body.y)-top-half_h,1,body_art.colors)
  end
end

local function danger_ring(c, x, y, radius, color)
  if x < -radius or x >= FIELD_W+radius or y < -radius or y >= FIELD_H+radius then return end
  for _, edge in ipairs(blast_ring) do
    c:line(x+round(edge[1]*radius),y+round(edge[2]*radius),
      x+round(edge[3]*radius),y+round(edge[4]*radius),color)
  end
end

local function dashed_lane(c, x, y, ex, ey, left, top, color)
  local dx, dy = (ex-x)/7, (ey-y)/7
  for step = 1, 6, 2 do
    c:line(round(x+dx*step)-left,round(y+dy*step)-top,
      round(x+dx*(step+1))-left,round(y+dy*(step+1))-top,color)
  end
end

local function charge_lane(c, game, enemy, left, top)
  local dx, dy = enemy.aim_x-enemy.x, enemy.aim_y-enemy.y
  local length = math.sqrt(dx*dx + dy*dy)
  if length == 0 then return end
  dx, dy = dx/length, dy/length
  local reach = enemy.profile.dash_distance
  reach = game:cover_entry(enemy.x,enemy.y,dx,dy,reach,enemy.surface.radius) or reach
  local x, y = game:clamp_position(enemy.x+dx*reach, enemy.y+dy*reach)
  dashed_lane(c,enemy.x,enemy.y,x,y,left,top,0xf2a46e)
end

local function draw_threats(c, game, left, top, roof_pass, hidden_roof)
  local nearest, distance = nil, math.huge
  for _, enemy in ipairs(game.enemies) do
    if enemy.health > 0 then
      local dx, dy = enemy.x-game.x, enemy.y-game.y
      local x, y = round(enemy.x)-left, round(enemy.y)-top
      if not roof_pass and (x < 0 or x >= FIELD_W or y < 0 or y >= FIELD_H) then
        local range = dx*dx+dy*dy
        if range < distance then nearest, distance = enemy, range end
      end
      if enemy.fire_at and ((not roof_pass and not enemy.roof)
        or (roof_pass and enemy.roof and enemy.roof ~= hidden_roof)) then
        local profile = enemy.profile
        local lob = profile.shot and profile.shot.aimed_lob
        local radius = profile.hit_radius or (lob and profile.shot.radius)
        if radius then
          local x, y = enemy.aim_x, enemy.aim_y
          if lob then
            local level = game.level
            local region = level and level.region[floor(enemy.y/16)*level.w + floor(enemy.x/16) + 1]
            local mx, my, nx, ny, distance, z, dz = game:enemy_aim(enemy,profile.shot,x,y)
            local travel = max(profile.shot.speed*0.01,min(distance,profile.shot.speed*profile.shot.life))
            x, y = game:lob_landing(mx,my,nx,ny,travel,region,z,dz)
          end
          danger_ring(c,round(x)-left,round(y)-top,radius,lob and 0xdb8056 or 0xf29c72)
        end
        if profile.dash_distance then charge_lane(c,game,enemy,left,top) end
        if profile.beam_range then
          local mx, my, nx, ny, _, z, dz = game:enemy_aim(enemy,profile.shot,enemy.aim_x,enemy.aim_y)
          local reach = game:beam_reach(mx,my,nx,ny,profile.beam_range,z,dz)
          dashed_lane(c,mx,my,mx+nx*reach,my+ny*reach,left,top,0xe697ad)
        end
        local patient = enemy.heal_target
        if patient and patient.health > 0 then
          danger_ring(c,round(patient.x)-left,round(patient.y)-top,patient.surface.radius+3,0xabd495)
        end
      end
    end
  end
  for _, shot in ipairs(game.projectiles) do
    local elevated = game.level ~= nil and (shot.z or 0) >= game.level.roof_height
    if shot.weapon.aimed_lob and elevated == roof_pass then
      local travel = (shot.life-shot.age)*shot.weapon.speed
      local x, y = game:lob_landing(shot.x,shot.y,shot.dx,shot.dy,travel,shot.region,shot.z,shot.dz)
      danger_ring(c,round(x)-left,round(y)-top,shot.weapon.radius,0xf6ab70)
    end
  end
  return nearest
end

local function hud(c, game)
  local weapon = Game.weapons[game.weapon]
  local ratio = game.health/game.surface.health
  local color = health_color(game,ratio)
  c:rect(0, 0, W, HUD_H, INK)
  c:rect(0, 1, W, 12, PANEL)
  text(c, weapon and weapon.name:upper() or "UNARMED", 7, 4, weapon and BRASS or TEXT)
  health_bar(c,210,4,37,7,ratio,color)
  text(c,game.health .. "/" .. game.surface.health .. " HP",253,4,color)
  if game.drill then
    local squad = game.squad
    local status = "PRACTICE"
    if game.mission and game.mission.objective == "rescue-kitten" then
      status = game.result == "won" and "KITTEN SAFE" or game.mission.carrying and "REACH THE EXIT" or "FIND THE KITTEN"
    elseif game.mission and squad.total == 1 then status = string.format("%d LEFT", squad.remaining)
      if game.mission.objective ~= "clear" then status = status .. "  FIND EXIT" end
    elseif squad then status = string.format("WAVE %d/%d  %d LEFT", squad.wave, squad.total, squad.remaining) end
    text(c, status, 100, 4, TEXT)
    local condition, condition_color
    if game.burn and game.frost_speed then condition, condition_color = "BURN / CHILL", HP_AMBER
    elseif game.burn then condition, condition_color = "BURNING", HP_AMBER
    elseif game.frost_speed then condition, condition_color = "CHILLED", 0xa4cad8
    elseif ratio > 0 and ratio <= 0.25 and not game.result then condition, condition_color = "LOW HP", HP_RED end
    local right = W-7
    if game.score then
      local score = "SCORE " .. game.score
      right = right-6*#score
      text(c,score,right,16,BRASS)
      if game.score_boost then
        local boost = "2X " .. game.score_boost .. "S"
        right = right-6*#boost-7
        text(c,boost,right,16,BURGER_GOLD)
      end
    end
    if condition then
      right = right-6*#condition-(game.score and 7 or 0)
      text(c,condition,right,16,condition_color)
    end
    local hint = (game.score or condition) and "D-PAD MOVE  SELECT FIRE"
      or "D-PAD MOVE  SELECT FIRE  CANCEL GEAR / HOLD MENU"
    local notice = game.notice or hint
    text(c,notice:sub(1,max(0,(right-13)//6)),7,16,game.notice and BRASS or DIM)
    return
  end
  for slot = 1, #Game.weapons do
    local gear_color = slot == game.weapon and BRASS or game.owned[slot] and 0xa5ad7c or 0x645a48
    c:rect(100+4*(slot-1),5,3,5,gear_color)
  end
  text(c, game.found.."/"..#Game.weapons, 168, 4, TEXT)
  local hits = "HITS "..game.hits
  local hits_x = W-6*#hits-7
  text(c,hits,hits_x,16,TEXT)
  local notice = game.notice or "D-PAD MOVE  SELECT FIRE  HOLD CANCEL"
  text(c,notice:sub(1,(hits_x-13)//6),7,16,game.notice and BRASS or DIM)
end

local shake_steps = {{-1,0}, {0.7,0.55}, {0.5,-0.65}, {-0.8,0.35}, {0.7,0}, {-0.35,-0.5}, {0.3,0.35}}

local function camera_shake(game)
  local shake = game.camera_shake
  if not shake then return 0, 0 end
  local progress = (game.time-shake.started)/shake.duration
  local step = shake_steps[min(#shake_steps,1+floor(progress*#shake_steps))]
  local strength = shake.strength * (1-progress)^2
  return round(step[1]*strength), round(step[2]*strength)
end

function View:draw(game)
  local c = self.canvas
  local shake_x, shake_y = camera_shake(game)
  local left = max(0, min(game.width-FIELD_W, round(game.x)-FIELD_W//2+shake_x))
  local top = max(0, min(game.height-FIELD_H, round(game.y)-FIELD_H//2+shake_y))
  local px, py = round(game.x)-left, round(game.y)-top
  local level = game.level
  local roof_height = level and level.roof_height or math.huge
  local hidden_roof
  if level then
    level_tiles = level_tiles or require("art.tiles")
    if self.tile_images == nil then self.tile_images = (ui.load and c.image) and {} or false end
    if not self.tiles then c:rect(0,0,FIELD_W,FIELD_H,palette.ground) end
    hidden_roof = level.region[floor(game.y/16)*level.w + floor(game.x/16) + 1]
    draw_level(self, c, level, left, top, "ground", hidden_roof)
  else
    ground(c, game.ground, left, top, self.tiles)
  end
  for _, mark in ipairs(game.scorch_marks) do
    local x, y = round(mark.x)-left, round(mark.y)-top
    if (mark.z or 0) < roof_height and x >= -17 and x < FIELD_W+17 and y >= -11 and y < FIELD_H+11 then
      effects.stamp(c,effects.scorch,x,y)
    end
  end
  draw_bodies(c,game.bodies,left,top,false)
  if level then draw_level(self,c,level,left,top,"structure",hidden_roof) end
  local mission = game.mission
  local rescue = mission and mission.objective == "rescue-kitten"
  if game.exit then
    draw_exit(c,game.exit,left,top,game.time,mission.objective == "exit" or mission.exit_open)
  end
  self.kitten_step = kitten_step(game.time)
  local bob = self.pickup_motion and self.kitten_step or 0
  self.kitten_on_screen = rescue and mission.carrying or false
  if mission and mission.kitten and not mission.carrying then
    self.kitten_on_screen = draw_kitten(c,round(mission.kitten.x)-left,round(mission.kitten.y)-top,false,bob)
  end
  for _, plate in ipairs(game.reflectors) do
    local x, y = round(plate.x)-left, round(plate.y)-top
    if x >= -9 and x < FIELD_W+9 and y >= -9 and y < FIELD_H+9 then
      local age = game.time - (plate.struck_at or -1)
      play(c,"reflector",plate.slope == "/" and 1 or 2,age < 0.09 and 2 or age < 0.25 and 3 or 1,x,y)
    end
  end
  local closest = game:nearest_pickup()
  self.pickup_step, self.pickups_on_screen = pickup_step(game.time), false
  local step = self.pickup_motion and self.pickup_step
  for _, item in ipairs(game.pickups) do
    if game:pickup_visible(item) then
      local x, y = round(item.x)-left, round(item.y)-top
      if x >= -20 and x < FIELD_W+20 and y >= -7 and y < FIELD_H+14 then
        self.pickups_on_screen = true
        draw_pickup(c,item,x,y,step,item==closest)
      end
    end
  end
  for _, target in ipairs(game.targets) do
    if not target.profile then draw_target(c,target,round(target.x)-left,round(target.y)-top,game.time) end
  end
  for _, particle in ipairs(game.particles) do
    if (particle.z or 0) < roof_height and (particle.kind == "smoke" or particle.kind == "exhaust") then
      draw_smoke(c,particle,left,top)
    end
  end
  for _, shot in ipairs(game.projectiles) do
    if (shot.z or 0) < roof_height then draw_shot(c,shot,left,top,game.time) end
  end
  for _, enemy in ipairs(game.enemies) do
    if not enemy.roof then self:draw_enemy(enemy,left,top) end
  end
  local show_threats = (game.squad or game.practice) and not game.result
  local nearest_enemy = show_threats and draw_threats(c,game,left,top,false)
  if game.frost_speed then danger_ring(c,px,py+4,8,0xa4cad8) end
  self:draw_actor(game,game:held_weapon(),px,py)
  if rescue and mission.carrying then draw_kitten(c,px+8,py+4,true,bob) end
  for _, particle in ipairs(game.particles) do
    if max(particle.z or 0, particle.ez or 0) < roof_height and particle.kind ~= "smoke" and particle.kind ~= "exhaust" then
      draw_particle(c,particle,left,top,game)
    end
  end
  if game.charge_from then
    local weapon = Game.weapons[game.weapon]
    local mx, my = game:muzzle(weapon)
    local charge = game:charge_level(weapon)
    local frame = charge < 1 and 1 + floor(charge*4) or 5 + floor(game.time*12) % 2
    play(c,"charge-orb",1,frame,round(mx)-left,round(my)-top)
  end
  if game.flash > 0 then flash(c,game,left,top) end
  if level then
    draw_level(self,c,level,left,top,"roof",hidden_roof)
    if game.rooftop_enemies then
      for _, mark in ipairs(game.scorch_marks) do
        local x, y = round(mark.x)-left, round(mark.y)-top
        if (mark.z or 0) >= roof_height and x >= -17 and x < FIELD_W+17 and y >= -11 and y < FIELD_H+11 then
          effects.stamp(c,effects.scorch,x,y)
        end
      end
      draw_bodies(c,game.bodies,left,top,true,hidden_roof)
      for _, shot in ipairs(game.projectiles) do
        if (shot.z or 0) >= roof_height then draw_shot(c,shot,left,top,game.time) end
      end
      for _, enemy in ipairs(game.enemies) do
        if enemy.roof and enemy.roof ~= hidden_roof then self:draw_enemy(enemy,left,top) end
      end
      if show_threats then draw_threats(c,game,left,top,true,hidden_roof) end
      for _, particle in ipairs(game.particles) do
        if max(particle.z or 0, particle.ez or 0) >= roof_height then
          if particle.kind == "smoke" or particle.kind == "exhaust" then draw_smoke(c,particle,left,top)
          else draw_particle(c,particle,left,top,game) end
        end
      end
    end
    if level.tall_roof_props then draw_level(self,c,level,left,top,"structure",hidden_roof,true) end
  end
  if nearest_enemy then locator(c,nearest_enemy,left,top,px,py,0xed906d) end
  if game.drill and not game.result and game.health < game.surface.health then
    local ratio = game.health/game.surface.health
    health_bar(c,max(0,min(FIELD_W-19,px-9)),py < 14 and py+10 or py-14,19,4,ratio,health_color(game,ratio))
  end
  if closest then locator(c,closest,left,top,px,py,pickup_colors[closest.kind]) end
  if rescue and not game.result then
    local goal = mission.carrying and game.exit or mission.kitten
    if goal then locator(c,goal,left,top,px,py,0xf1a76e) end
  end
  if game.hurt_until then
    local color = 0xb66050
    c:rect(0,0,FIELD_W,1,color)
    c:rect(0,FIELD_H-1,FIELD_W,1,color)
    c:rect(0,0,1,FIELD_H,color)
    c:rect(FIELD_W-1,0,1,FIELD_H,color)
  end
  if game.result then
    local record = game.record
    local details = game.time_bonus and 22 or game.score and 11 or 0
    local news
    if record and record.best_score and record.best_time then news = "NEW BEST SCORE+TIME"
    elseif record and record.best_score then news = "NEW BEST SCORE"
    elseif record and record.best_time then news = "NEW BEST TIME" end
    if game.stars then details = details + 11 end
    if news then details = details + 11 end
    local y = game.practice and game.result == "won" and 4 or 31-details//2
    c:rect(19,y,122,34+details,INK)
    c:rect(19,y,122,1,BRASS)
    local result = "YOU ARE DOWN"
    if game.result == "won" then
      result = rescue and "KITTEN SAFE" or mission and "MISSION CLEAR" or "PRACTICE CLEARED"
    end
    local action = mission and game.result == "won" and "SELECT MISSIONS" or "SELECT RETRY"
    text(c,result,80-3*#result,y+7,BRASS)
    local line = y+18
    if game.score then
      local score = "SCORE " .. game.score
      text(c,score,80-3*#score,line,TEXT)
      line = line + 11
    end
    if game.time_bonus then
      local bonus = game.clear_time .. "S  BONUS +" .. game.time_bonus
      text(c,bonus,80-3*#bonus,line,BURGER_GOLD)
      line = line + 11
    end
    if game.stars then
      -- Stars earned for the first time on this run shine brighter.
      local gained = record and record.gained or 0
      for slot = 0, 2 do
        local bit = 1 << slot
        local color = game.stars & bit == 0 and STAR_EMPTY or gained & bit ~= 0 and STAR_NEW or BURGER_GOLD
        Pixels.star(c,65+slot*12,line,color)
      end
      line = line + 11
    end
    if news then text(c,news,80-3*#news,line,STAR_NEW) end
    text(c,action,80-3*#action,y+21+details,TEXT)
  end
  local wave, remaining
  if game.squad then wave, remaining = game.squad.wave, game.squad.remaining end
  local burning, chilled = game.burn ~= nil, game.frost_speed ~= nil
  if self.game ~= game or self.weapon ~= game.weapon or self.found ~= game.found
    or self.hits ~= game.hits or self.notice ~= game.notice or self.health ~= game.health
    or self.wave ~= wave or self.remaining ~= remaining or self.hurt_until ~= game.hurt_until
    or self.result ~= game.result or self.burning ~= burning or self.chilled ~= chilled
    or self.score ~= game.score or self.score_boost ~= game.score_boost
    or self.carrying ~= (mission and mission.carrying) then
    hud(self.strip,game)
    self.game, self.health = game, game.health
    self.weapon, self.found, self.hits, self.notice = game.weapon, game.found, game.hits, game.notice
    self.wave, self.remaining = wave, remaining
    self.hurt_until = game.hurt_until
    self.result, self.burning, self.chilled = game.result, burning, chilled
    self.score, self.score_boost = game.score, game.score_boost
    self.carrying = mission and mission.carrying
  end
end

return View
