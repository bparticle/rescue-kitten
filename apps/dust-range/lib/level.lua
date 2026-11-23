-- Tile levels built with tools/level-builder. Cells are 16 native pixels.
-- Implements the same queries as lib/cover.lua (entry, can_stand, slide, waypoint) on a grid,
-- plus tile damage, roofs, slow ground and hazards. Tile properties: sprites/tiles/materials.json.
local tiles = require("art.tiles")

local Level = {}
local floor, min, max, abs, sqrt, huge = math.floor, math.min, math.max, math.abs, math.sqrt, math.huge
local byte = string.byte

local WALK, SHOT, LOB, SIGHT, PIERCE = 1, 2, 4, 8, 16
local SIZE = 16
local ROOF_HEIGHT, AIM_HEIGHT = 24, 6
-- Actors are allowed through one-tile gaps whatever their hit radius.
local MAX_BODY = 6
local CODE_START, CODE_SKIP, CODE_BASE = 35, 93, 91
-- Loading runs inside the game's survey coroutine and yields so no single tick runs too long.
local LOAD_CELLS = 384
local yieldable = coroutine.isyieldable

local function pause(i)
  if i % LOAD_CELLS == 0 and yieldable and yieldable() then coroutine.yield() end
end

local function decode_char(c)
  c = c - CODE_START
  if c > CODE_SKIP - CODE_START then c = c - 1 end
  return c + 1
end

-- Narrow pieces share their footprint with the atlas. Coordinates are local, half-open.
local function footprint(def, variant)
  if def.bounds then return {def.bounds} end
  if not def.span then return end
  local mask = variant - 1
  if def.autotile == "orient" then mask = variant == 1 and 10 or 5 end
  local lo, hi = 8 - def.span, 8 + def.span
  local x0, x1 = mask & 8 ~= 0 and 0 or lo, mask & 2 ~= 0 and SIZE or hi
  local y0, y1 = mask & 1 ~= 0 and 0 or lo, mask & 4 ~= 0 and SIZE or hi
  if x0 == lo and x1 == hi then return {{lo, y0, hi, y1}} end
  local boxes = {{x0, lo, x1, hi}}
  if mask & 5 ~= 0 then boxes[2] = {lo, y0, hi, y1} end
  return boxes
end

local function record(level, key)
  local cached = level.records[key]
  if cached then return cached end
  local main, base, extra = key:match("^([^@]+)@([^@]*)@?(.*)$")
  main = main or key
  local id, variant = main:match("^(.-)/(%d+)$")
  local terrain = not id and tonumber(main:match("^T(%d+)$"))
  local entry
  if terrain then
    local material = terrain <= 16 and "dirt" or terrain <= 32 and "grass" or "mud"
    entry = {terrain=terrain, def=tiles.materials[material]}
  else
    id = id or main
    local def = assert(tiles.materials[id], "Unknown tile " .. key)
    variant = tonumber(variant) or 1
    local opaque = tiles.opaque[id]
    entry = {id=id, variant=variant, def=def, art=tiles.art[id] and tiles.art[id][variant],
      opaque=opaque and opaque:sub(variant,variant) == "1", boxes=footprint(def, variant)}
    if def.terrain then entry.terrain = 1 end
    if base and base ~= "" then entry.base = record(level, base) end
    if extra and extra ~= "" then
      if def.layer == "roof" then entry.detail = record(level, extra)
      else entry.footing = record(level, extra) end
    end
    -- Old exports have a single tile key and no explicit surface underneath.
    if not base and not entry.opaque and def.underlay then
      local underlay = tiles.materials[def.underlay]
      entry.base = record(level, underlay.terrain and "T1"
        or def.underlay .. (underlay.autotile == "area" and "/16" or "/1"))
    end
  end
  level.records[key] = entry
  return entry
end

local function decode_layer(level, data, legend, width, cells)
  local out = {}
  if not data then return out end
  local records = {}
  for index, key in ipairs(legend) do records[index] = record(level, key) end
  for i = 1, cells do
    local at = (i-1)*width + 1
    local c = byte(data, at)
    if c ~= 32 then
      local code = decode_char(c)
      if width == 2 then code = (code-1)*CODE_BASE + decode_char(byte(data, at+1)) end
      out[i] = records[code]
    end
    pause(i)
  end
  return out
end

local function cell_mask(ground, structure)
  local mask = 0
  for pass = 1, 2 do
    local tile = pass == 1 and ground or pass == 2 and structure
    local def = tile and tile.def
    if def then
      if def.walk then mask = mask | WALK end
      if def.shots then mask = mask | SHOT end
      if def.lobs then mask = mask | LOB end
      if def.sight then mask = mask | SIGHT end
    end
  end
  -- The rail rifle passes a cell only when everything that stops shots there is pierceable.
  local def = structure and structure.def
  if mask & SHOT ~= 0 and def and def.shots and def.pierce and not (ground and ground.def.shots) then
    mask = mask | PIERCE
  end
  return mask
end

local function label_roofs(level)
  local roof, region, w, h = level.roof, {}, level.w, level.h
  local count, visited, stack = 0, 0, {}
  for start = 1, w*h do
    pause(start)
    if roof[start] and not region[start] then
      count = count + 1
      region[start], stack[1] = count, start
      local top = 1
      while top > 0 do
        local i = stack[top]
        top = top - 1
        visited = visited + 1
        pause(visited)
        local x = (i-1) % w
        local neighbours = {x > 0 and i-1, x < w-1 and i+1, i > w and i-w, i <= w*(h-1) and i+w}
        for k = 1, 4 do
          local j = neighbours[k]
          if j and roof[j] and not region[j] then
            region[j] = count
            top = top + 1
            stack[top] = j
          end
        end
      end
    end
  end
  level.region = region
end

local function entrance_facing(roof, i, w, h, variant)
  -- A doorway crosses the wall at right angles. Exactly one side must lead under the roof.
  if variant == 1 then
    local north = i > w and roof[i-w] ~= nil
    local south = i <= w*(h-1) and roof[i+w] ~= nil
    if north ~= south then return north and "south" or "north" end
  else
    local west = (i-1) % w > 0 and roof[i-1] ~= nil
    local east = i % w ~= 0 and roof[i+1] ~= nil
    if west ~= east then return west and "east" or "west" end
  end
end

function Level.new(def)
  local w, h = def.w, def.h
  local level = {def=def, w=w, h=h, records={}, flow={}, version=0, roof_height=ROOF_HEIGHT}
  local legend, widths = def.legend, def.cell or {}
  level.ground = decode_layer(level, def.ground, legend.ground, widths.ground or 1, w*h)
  level.structure = decode_layer(level, def.structure, legend.structure, widths.structure or 1, w*h)
  level.roof = decode_layer(level, def.roof, legend.roof, widths.roof or 1, w*h)
  level.mask, level.hp, level.entrances = {}, {}, {}
  for i = 1, w*h do
    local structure = level.structure[i]
    level.mask[i] = cell_mask(level.ground[i], structure)
    if structure and structure.def.hp then level.hp[i] = structure.def.hp end
    if structure and level.roof[i] then
      if structure.id == "doorway" then
        level.entrances[i] = entrance_facing(level.roof, i, w, h, structure.variant)
      end
      if (structure.def.height or 0) > ROOF_HEIGHT then level.tall_roof_props = true end
    end
    pause(i)
  end
  label_roofs(level)
  return level
end

function Level.index(level, x, y)
  local cx, cy = floor(x/SIZE), floor(y/SIZE)
  if cx < 0 or cy < 0 or cx >= level.w or cy >= level.h then return end
  return cy*level.w + cx + 1, cx, cy
end

function Level.region_at(level, x, y)
  local i = Level.index(level, x, y)
  return i and level.region[i]
end

local function blocks(level, i, kind)
  local mask = level.mask[i]
  if kind == "shot" then return mask & SHOT ~= 0
  elseif kind == "rail" then return mask & SHOT ~= 0 and mask & PIERCE == 0
  elseif kind == "lob" then return mask & LOB ~= 0
  elseif kind == "sight" then return mask & SIGHT ~= 0
  elseif kind == "damage" then return level.hp[i] ~= nil
  elseif kind == "soft" then return level.hp[i] ~= nil and mask & SHOT == 0
  end
  return mask & WALK ~= 0
end

local function ray_box(x, y, dx, dy, limit, x0, y0, x1, y1)
  local near, far = 0, limit
  if dx == 0 then
    if x < x0 or x >= x1 then return end
  else
    local t0, t1 = (x0-x)/dx, (x1-x)/dx
    near, far = max(near, min(t0,t1)), min(far, max(t0,t1))
  end
  if dy == 0 then
    if y < y0 or y >= y1 then return end
  else
    local t0, t1 = (y0-y)/dy, (y1-y)/dy
    near, far = max(near, min(t0,t1)), min(far, max(t0,t1))
  end
  if near <= far then return near, far end
end

local function impact(level, i, cx, cy, x, y, dx, dy, reach, entry, kind, z, dz)
  local structure = level.structure[i]
  local boxes = structure and structure.boxes
  if not boxes and not z then return entry end
  local ground = level.ground[i]
  local flag = (kind == "shot" or kind == "rail") and "shots"
    or kind == "lob" and "lobs" or kind == "sight" and "sight" or kind == "walk" and "walk"
  if ground and ground.def[flag] then return entry end
  local low, high = 0, reach
  if z then
    local height = structure and structure.def.height or 16
    if dz == 0 then
      if z > height or z < 0 then return end
    else
      local a, b = -z/dz, (height-z)/dz
      low, high = max(0, min(a,b)), min(reach, max(a,b))
      if low > high then return end
    end
  end
  local best
  x, y = x-cx*SIZE, y-cy*SIZE
  if not boxes then
    local near, far = ray_box(x, y, dx, dy, high, 0, 0, SIZE, SIZE)
    if near and max(near,low) <= far then return max(near,low) end
    return
  end
  for _, box in ipairs(boxes) do
    local near, far = ray_box(x, y, dx, dy, best or high, box[1], box[2], box[3], box[4])
    if near and max(near,low) <= far then best = max(near,low) end
  end
  return best
end

-- Grid walk along x + dx*t, y + dy*t for t in [0, reach]. Returns the entry t and cell index.
local function cast(level, x, y, dx, dy, reach, kind, region, z, dz, ignored)
  local w, h = level.w, level.h
  local cx, cy = floor(x/SIZE), floor(y/SIZE)
  local entry = 0
  if cx < 0 or cy < 0 or cx >= w or cy >= h then
    entry = ray_box(x,y,dx,dy,reach,0,0,w*SIZE,h*SIZE)
    if not entry then return end
    cx = max(0,min(w-1,floor((x+dx*entry)/SIZE)))
    cy = max(0,min(h-1,floor((y+dy*entry)/SIZE)))
  end
  local step_x = dx > 0 and 1 or dx < 0 and -1 or 0
  local step_y = dy > 0 and 1 or dy < 0 and -1 or 0
  local next_x = dx > 0 and ((cx+1)*SIZE - x)/dx or dx < 0 and (cx*SIZE - x)/dx or huge
  local next_y = dy > 0 and ((cy+1)*SIZE - y)/dy or dy < 0 and (cy*SIZE - y)/dy or huge
  local delta_x = dx ~= 0 and SIZE/abs(dx) or huge
  local delta_y = dy ~= 0 and SIZE/abs(dy) or huge
  local plane = z and dz ~= 0 and (ROOF_HEIGHT-z)/dz
  while entry <= reach and cx >= 0 and cy >= 0 and cx < w and cy < h do
    local i = cy*w + cx + 1
    local roof
    if level.region[i] and kind ~= "walk" then
      if plane and plane >= entry and plane <= min(next_x,next_y,reach) then
        roof = plane
      elseif kind == "lob" and not z and level.region[i] ~= region then
        roof = entry
      end
    end
    local hit
    if blocks(level, i, kind) and not (ignored and ignored[i]) then
      hit = impact(level, i, cx, cy, x, y, dx, dy, reach, entry, kind, z, dz)
    end
    if roof and (not hit or roof <= hit) then return roof end
    if hit then return hit, i end
    if next_x == next_y then
      entry, cx, cy = next_x, cx+step_x, cy+step_y
      next_x, next_y = next_x+delta_x, next_y+delta_y
    elseif next_x < next_y then
      entry, cx, next_x = next_x, cx + step_x, next_x + delta_x
    else
      entry, cy, next_y = next_y, cy + step_y, next_y + delta_y
    end
  end
end

-- Same contract as Cover.entry. padding > 0 sweeps an actor body and only checks walking.
function Level.entry(level, x, y, dx, dy, reach, padding, kind, region, z, dz, ignored)
  dz = dz or 0
  if reach <= 0 or (dx == 0 and dy == 0 and dz == 0) then return end
  if not padding or padding <= 0 then return cast(level, x, y, dx, dy, reach, kind or "shot", region, z, dz, ignored) end
  local length = sqrt(dx*dx + dy*dy)
  local r = min(padding, MAX_BODY) - 0.01
  local px, py = -dy/length*r, dx/length*r
  local best, cell = huge, nil
  for side = -1, 1 do
    local t, i = cast(level, x + px*side, y + py*side, dx, dy, reach, "walk")
    if t and t < best then best, cell = t, i end
  end
  if cell then return max(0, best - 0.5/length), cell end
end

local FULL_TILE = {{0, 0, SIZE, SIZE}}

local function walking_boxes(level, i, roof)
  if roof then
    if level.region[i] ~= roof then return FULL_TILE end
    local structure = level.structure[i]
    if structure and structure.def.walk and (structure.def.height or 0) > ROOF_HEIGHT then return structure.boxes or FULL_TILE end
    return
  end
  if level.mask[i] & WALK == 0 then return end
  local ground, structure = level.ground[i], level.structure[i]
  if ground and ground.def.walk then return FULL_TILE end
  return structure and structure.boxes or FULL_TILE
end

function Level.can_stand(level, x, y, radius, roof)
  local r = min(radius or 0, MAX_BODY)
  local x0, x1 = floor((x-r)/SIZE), floor((x+r)/SIZE)
  local y0, y1 = floor((y-r)/SIZE), floor((y+r)/SIZE)
  if x0 < 0 or y0 < 0 or x+r > level.w*SIZE or y+r > level.h*SIZE then return false end
  for cy = y0, min(y1, level.h-1) do
    for cx = x0, min(x1, level.w-1) do
      local boxes = walking_boxes(level, cy*level.w + cx + 1, roof)
      if boxes then
        for _, box in ipairs(boxes) do
          if x+r >= cx*SIZE+box[1] and x-r < cx*SIZE+box[3]
            and y+r >= cy*SIZE+box[2] and y-r < cy*SIZE+box[4] then return false end
        end
      end
    end
  end
  return true
end

-- Sweep each axis against the visible structure footprint. The wide phase stays cell-based.
local function slide_axis(level, start, target, cross, r, vertical, roof)
  if start == target then return start end
  local along_cells, cross_cells = level.w, level.h
  local along_axis, cross_axis = 1, 2
  if vertical then along_cells, cross_cells, along_axis, cross_axis = level.h, level.w, 2, 1 end
  target = max(r, min(along_cells*SIZE-r, target))
  local a0 = max(0, floor((min(start,target)-r)/SIZE))
  local a1 = min(along_cells-1, floor((max(start,target)+r)/SIZE))
  local c0 = max(0, floor((cross-r)/SIZE))
  local c1 = min(cross_cells-1, floor((cross+r)/SIZE))
  local forward = target > start
  for c = c0, c1 do
    for a = a0, a1 do
      local i = vertical and a*level.w+c+1 or c*level.w+a+1
      local boxes = walking_boxes(level, i, roof)
      if boxes then
        for _, box in ipairs(boxes) do
          local cross_min, cross_max = c*SIZE+box[cross_axis], c*SIZE+box[cross_axis+2]
          if cross+r > cross_min and cross-r < cross_max then
            local lo, hi = a*SIZE+box[along_axis], a*SIZE+box[along_axis+2]
            if forward and start <= lo-r and target >= lo-r then target = lo-r-0.01
            elseif not forward and start >= hi+r and target <= hi+r then target = hi+r+0.01 end
          end
        end
      end
    end
  end
  return target
end

function Level.slide(level, x, y, next_x, next_y, radius, roof)
  local r = min(radius, MAX_BODY)
  x = slide_axis(level, x, next_x, y, r, false, roof)
  y = slide_axis(level, y, next_y, x, r, true, roof)
  return x, y
end

function Level.speed(level, x, y)
  local i = Level.index(level, x, y)
  if not i then return 1 end
  local ground, structure = level.ground[i], level.structure[i]
  return (ground and ground.def.slow or 1) * (structure and structure.def.slow or 1)
end

function Level.hazard(level, x, y)
  local i = Level.index(level, x, y)
  if not i then return 0 end
  local ground, structure = level.ground[i], level.structure[i]
  return (ground and ground.def.hazard or 0) + (structure and structure.def.hazard or 0)
end

function Level.water_at(level, x, y)
  local i = Level.index(level, x, y)
  local ground = i and level.ground[i]
  return ground and (ground.id == "shallow-water" or ground.id == "deep-water")
end

-- Breadth-first distances to the player's cell, eight ways without cutting blocked corners.
-- A full search is too slow for one badge tick, so it runs FLOW_CELLS cells per Level.update
-- and enemies follow the last finished field until the new one is ready.
local FLOW_CELLS = 100

local function request_flow(level, goal)
  local flow, job = level.flow, level.flow_job
  if flow.goal == goal and flow.version == level.version then return end
  if job and job.version == level.version then return end
  local queue = job and job.queue or level.spare_queue or {}
  level.flow_job = {goal=goal, version=level.version, dist={[goal]=0}, queue=queue, head=1, tail=1}
  queue[1] = goal
end

function Level.update(level)
  local job = level.flow_job
  if not job then return end
  local w, h, mask = level.w, level.h, level.mask
  local dist, queue, head, tail = job.dist, job.queue, job.head, job.tail
  local stop = head + FLOW_CELLS
  while head <= tail and head < stop do
    local i = queue[head]
    head = head + 1
    local x, y = (i-1) % w, (i-1) // w
    local d = dist[i] + 1
    for oy = -1, 1 do
      local ny = y + oy
      if ny >= 0 and ny < h then
        for ox = -1, 1 do
          local nx = x + ox
          if nx >= 0 and nx < w and (ox ~= 0 or oy ~= 0) then
            local j = ny*w + nx + 1
            if not dist[j] and mask[j] & WALK == 0
              and (ox == 0 or oy == 0 or (mask[y*w+nx+1] & WALK == 0 and mask[ny*w+x+1] & WALK == 0)) then
              dist[j] = d
              tail = tail + 1
              queue[tail] = j
            end
          end
        end
      end
    end
  end
  job.head, job.tail = head, tail
  if head > tail then
    level.flow = {goal=job.goal, version=job.version, dist=dist}
    level.flow_job, level.spare_queue = nil, queue
  end
end

local function walk_clear(level, x, y, tx, ty, radius)
  return not Level.entry(level, x, y, tx-x, ty-y, 1, radius)
end

function Level.waypoint(level, x, y, tx, ty, radius, previous_x, previous_y)
  if walk_clear(level, x, y, tx, ty, radius) then return end
  if previous_x then
    local dx, dy = previous_x-x, previous_y-y
    if dx*dx+dy*dy > 1 and walk_clear(level, x, y, previous_x, previous_y, radius) then return previous_x, previous_y end
  end
  local goal = Level.index(level, tx, ty)
  local here = Level.index(level, x, y)
  if not goal or not here then return end
  request_flow(level, goal)
  local dist = level.flow.dist
  if not dist or not dist[here] then return end
  local w, cur = level.w, here
  local best_x, best_y
  for _ = 1, 6 do
    local cx, cy = (cur-1) % w, (cur-1) // w
    local next_cell, next_d = nil, dist[cur]
    for oy = -1, 1 do
      for ox = -1, 1 do
        local nx, ny = cx+ox, cy+oy
        if nx >= 0 and ny >= 0 and nx < w and ny < level.h then
          local j = ny*w + nx + 1
          local d = dist[j]
          if d and d < next_d and (ox == 0 or oy == 0
            or (level.mask[cy*w+nx+1] & WALK == 0 and level.mask[ny*w+cx+1] & WALK == 0)) then
            next_cell, next_d = j, d
          end
        end
      end
    end
    if not next_cell then break end
    cur = next_cell
    local px, py = ((cur-1) % w)*SIZE + SIZE/2, ((cur-1) // w)*SIZE + SIZE/2
    if not walk_clear(level, x, y, px, py, radius) then break end
    best_x, best_y = px, py
    if cur == goal then break end
  end
  return best_x, best_y
end

-- Neighbour-aware variants, matching the level builder.
local function retile(level, i)
  local tile = level.structure[i]
  if not tile or not tile.def.autotile then return end
  local w, group = level.w, tile.def.group
  local x = (i-1) % w
  local function same(j)
    local other = j and level.structure[j]
    return other and other.def.group == group
  end
  local n, e = same(i > w and i-w), same(x < w-1 and i+1)
  local s, west = same(i <= w*(level.h-1) and i+w), same(x > 0 and i-1)
  local variant
  if tile.def.autotile == "blob" then
    variant = (n and 1 or 0) + (e and 2 or 0) + (s and 4 or 0) + (west and 8 or 0) + 1
  else
    local vertical, horizontal = (n and 1 or 0) + (s and 1 or 0), (e and 1 or 0) + (west and 1 or 0)
    variant = vertical > horizontal and 2 or 1
  end
  level.structure[i] = record(level, tile.id .. "/" .. variant)
end

-- Same per-cell texture pick as variantAt() in tools/level-builder/format.mjs.
local function texture_variant(level, i, def)
  local x, y = (i-1) % level.w, (i-1) // level.w
  local count = def.variants or 1
  local hash = (((x+1)*374761393) & 0xffffffff) ~ (((y+1)*668265263) & 0xffffffff)
  -- Unsigned remainder, also on the badge's 32-bit integers where hash can be negative.
  return 1 + (((hash >> 1) % count) * 2 + (hash & 1)) % count
end

-- Destroy the structure in a cell. Returns the explosion spec if it was explosive.
function Level.destroy(level, i)
  local tile = level.structure[i]
  if not tile then return end
  local def = tile.def
  local leftover = def.breaksTo
  level.structure[i] = leftover
    and record(level, leftover .. "/" .. texture_variant(level, i, tiles.materials[leftover])) or nil
  level.hp[i] = leftover and tiles.materials[leftover].hp or nil
  level.mask[i] = cell_mask(level.ground[i], level.structure[i])
  level.version = level.version + 1
  local w = level.w
  local x = (i-1) % w
  if i > w then retile(level, i-w) end
  if i <= w*(level.h-1) then retile(level, i+w) end
  if x > 0 then retile(level, i-1) end
  if x < w-1 then retile(level, i+1) end
  return def.explodes, ((i-1) % w)*SIZE + SIZE/2, ((i-1) // w)*SIZE + SIZE/2
end

-- Drain a destructible cell. Returns true and an explosion spec when it breaks.
function Level.damage(level, i, amount)
  local hp = level.hp[i]
  if not hp then return false end
  hp = hp - amount
  if hp > 0 then
    level.hp[i] = hp
    return false
  end
  return true, Level.destroy(level, i)
end

-- Cells whose centres lie inside a blast, with the falloff the blast applies there.
function Level.blast_cells(level, x, y, radius, z)
  local hits = {}
  local reach = radius + SIZE/2
  local x0, x1 = max(0, floor((x-reach)/SIZE)), min(level.w-1, floor((x+reach)/SIZE))
  local y0, y1 = max(0, floor((y-reach)/SIZE)), min(level.h-1, floor((y+reach)/SIZE))
  for cy = y0, y1 do
    for cx = x0, x1 do
      local i = cy*level.w + cx + 1
      if level.hp[i] then
        local dx, dy = cx*SIZE + SIZE/2 - x, cy*SIZE + SIZE/2 - y
        local dz = z and min(AIM_HEIGHT, level.structure[i].def.height or AIM_HEIGHT)-z
        local distance = sqrt(dx*dx + dy*dy + (dz or 0)^2)
        if distance <= reach then
          local stop, blocker = Level.entry(level,x,y,dx,dy,1,0,"shot",nil,z,dz)
          if not stop or blocker == i then hits[#hits+1] = {i, 1 - distance/reach} end
        end
      end
    end
  end
  return hits
end

Level.SIZE = SIZE
Level.ROOF_HEIGHT, Level.AIM_HEIGHT = ROOF_HEIGHT, AIM_HEIGHT
return Level
