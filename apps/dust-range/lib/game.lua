local Range = require("lib.range")
local Enemies = require("lib.enemies")
local Squad = require("lib.squad")
local Cover, Level, Mission

local Game = {}
Game.__index = Game

local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt
local sin, cos, abs, exp = math.sin, math.cos, math.abs, math.exp
local MOVE_SPEED, STEP_DISTANCE, FIRE_BUFFER = 104, 6, 0.10
local PICKUP_RADIUS, MEDKIT_HP = 11, 30
local HURT_DURATION, ROUTE_DURATION, ROUTE_TOLERANCE = 0.18, 0.16, 8
local MAX_SCORCH_MARKS, SCORCH_MERGE_DISTANCE = 8, 8
local MAX_PARTICLES, MAX_PROJECTILES, PLAYER_PROJECTILE_RESERVE = 76, 32, 8
local KNOCK_DECAY, RECOVER_AFTER = 12, 3
local PLAYER_SURFACE = {name="PLAYER", health=100, radius=6, scale={}}
local diagonal = 1 / sqrt(2)
local directions = {
  {0,-1}, {diagonal,-diagonal}, {1,0}, {diagonal,diagonal},
  {0,1}, {-diagonal,diagonal}, {-1,0}, {-diagonal,-diagonal},
}
local facing = {{8,1,2}, {7,0,3}, {6,5,4}}

Game.weapons = Range.weapons
Game.flash_duration = 0.062
Game.kick_duration = 0.028
local dirt_weights  = {56,74,88,100}
local grass_weights = {34,58,83,100}
local mud_weights   = {38,61,84,100}

local function clamp(value, low, high) return min(high, max(low, value)) end

-- Facing index (1 = N, clockwise) nearest to a heading.
function Game.direction_of(dx, dy)
  return floor((math.atan(dy, dx) + math.pi/2) / (math.pi/4) + 0.5) % 8 + 1
end

local function random(seed)
  return function()
    seed = (seed * 75 + 74) % 65521
    return seed / 65521
  end
end

local function terrain(cells, columns, rows, seed)
  local rand, field = random(seed), {}
  local span = 5
  for y = 0, rows // span + 1 do
    field[y] = {}
    for x = 0, columns // span + 1 do field[y][x] = rand() end
  end
  for y = 0, rows - 1 do
    local line = {}
    cells[y] = line
    for x = 0, columns - 1 do
      local gx, gy = x // span, y // span
      local fx, fy = x % span / span, y % span / span
      local a, b = field[gy], field[gy + 1]
      local top = a[gx] + (a[gx + 1] - a[gx]) * fx
      local bottom = b[gx] + (b[gx + 1] - b[gx]) * fx
      local wet = top + (bottom - top) * fy + (rand() - 0.5) * 0.13
      local coverage = rand()
      local base, weights = 0, dirt_weights
      if wet > 0.69 and coverage < 0.65 then
        base, weights = 8, mud_weights
      elseif wet > 0.52 and coverage < 0.76 then
        base, weights = 4, grass_weights
      end
      local roll, variant = rand() * 100, 1
      while roll > weights[variant] do variant = variant + 1 end
      line[x] = (base + variant - 1) * 4 + floor(rand() * 4) + 1
    end
    if (y+1) % 5 == 0 and y+1 < rows then coroutine.yield() end
  end
end

function Game.new(seed, drill, surveyed_ground, practice)
  local x, y = 448, 320
  local ground = surveyed_ground or {}
  local game = setmetatable({
    x=x, y=y, direction=3, pose=1, walk=0, weapon=drill and 1 or 0,
    health=PLAYER_SURFACE.health, surface=PLAYER_SURFACE, found=0, shots=0, hits=0,
    width=896, height=640, ground=ground, random=random(seed + 1),
    pickups=drill and {} or Range.pickups(x, y), targets=drill and {} or Range.targets(x, y),
    reflectors=drill and {} or Range.reflectors(x, y), enemies={}, dt=0,
    owned={[0]=true}, projectiles={}, particles={}, scorch_marks={}, time=0, cooldown=0,
    flash=0, message_until=0, dirty=true, drill=drill,
  }, Game)
  if drill == "level" then
    Level, Mission = require("lib.level"), require("lib.mission")
    game.enemy_targets, game.level_id = {game}, practice
    game.survey = coroutine.create(function() Mission.start(game, practice) end)
    return game
  end
  if not surveyed_ground then
    game.survey = coroutine.create(function() terrain(ground, 56, 40, seed) end)
  end
  game.enemy_targets = {game}
  if drill == "endless" then
    Cover = Cover or require("lib.cover")
    game.cover, game.cover_phase = Cover.layout(0, nil, x, y, PLAYER_SURFACE.radius), 0
  end
  if drill then
    game.owned[1] = true
    if drill == "endless" then Squad.start(game, random(seed+801))
    elseif practice then
      game.practice = practice
      game.owned[0], game.owned[2], game.owned[11], game.weapon = nil, true, true, 2
      local enemy = game:spawn_enemy(practice, x+79, y+3, 7)
      enemy.ready_at = 0.62
      if practice == "medic" then
        local patient = game:spawn_enemy("soldier", x+61, y-16, 7)
        patient.health, patient.ready_at = 30, 0.9
      end
    end
  end
  return game
end

function Game:spawn_enemy(kind, x, y, direction, rooftop)
  local enemy = Enemies.new(kind, x, y, direction)
  if rooftop then
    enemy.roof = Level.region_at(self.level, x, y)
    self.rooftop_enemies = true
  end
  if enemy.profile.strafe_speed or enemy.profile.circle_speed then enemy.strafe_side = #self.enemies % 2 == 0 and 1 or -1 end
  self.enemies[#self.enemies+1] = enemy
  if self.targets ~= self.enemies then self.targets[#self.targets+1] = enemy end
  self.dirty = true
  return enemy
end

function Game:prepare()
  local ok, message = coroutine.resume(self.survey)
  if not ok then error(message) end
  if coroutine.status(self.survey) == "dead" then self.survey = nil end
end

function Game:cycle()
  if self.result then return end
  for shift = 1, #Game.weapons + 1 do
    local id = (self.weapon + shift) % (#Game.weapons + 1)
    if self.owned[id] then
      self.weapon, self.flash, self.cooldown, self.dirty = id, 0, 0, true
      self.fire_until, self.charge_from = nil, nil
      return
    end
  end
end

function Game:pickup_visible(item)
  return not item.collected and not self.owned[item.id]
end

function Game:nearest_pickup(collecting)
  local best, closest = math.huge, nil
  local wounded = self.health < self.surface.health
  for _, item in ipairs(self.pickups) do
    if self:pickup_visible(item) and (item.id or wounded) then
      local dx, dy = item.x - self.x, item.y - self.y
      local range = dx * dx + dy * dy
      if range < best and (not collecting or range <= PICKUP_RADIUS^2 and (not self.level
        or not self:cover_entry(self.x,self.y,dx,dy,1,0,"walk"))) then best, closest = range, item end
    end
  end
  return closest, best
end

function Game:message(text)
  self.notice, self.message_until, self.dirty = text, self.time + 1.4, true
end

function Game:request_fire()
  self.fire_until = self.time + FIRE_BUFFER
end

function Game:held_weapon()
  if self.weapon == 4 and self.grenade_ready_at then return 0 end
  if self.disc_out and self.weapon > 0 and Game.weapons[self.weapon].kind == "disc" then return 0 end
  return self.weapon
end

function Game:collect()
  if self.health == 0 then return end
  local item = self:nearest_pickup(true)
  if not item then return end
  if item.id then
    self:collect_weapon(item.id)
  else
    local restored = min(MEDKIT_HP, self.surface.health-self.health)
    item.collected, self.health = true, self.health+restored
    self:particle(self.x, self.y-20, 0, -12, 0.4, "heal")
    self:message("MEDKIT  +" .. restored .. " HP")
  end
end

function Game:collect_weapon(id)
  if self.owned[id] then return end
  self.owned[id] = true
  self.found, self.weapon, self.flash, self.cooldown = self.found + 1, id, 0, 0
  self.charge_from = nil
  local weapon = Game.weapons[id]
  local name = weapon.name:upper()
  self:message(self.squad and "EQUIPPED " .. name or "FOUND " .. name .. "  TARGET " .. weapon.lane)
end

function Game:add_medkit(x, y)
  self.pickups[#self.pickups+1] = {kind="medkit", x=x, y=y}
  self.dirty = true
end

function Game:drop_weapon(id, x, y)
  if self.owned[id] then return end
  for _, item in ipairs(self.pickups) do
    if item.id == id then return end
  end
  self.pickups[#self.pickups+1] = {id=id, x=x, y=y}
  self.dirty = true
end

function Game:clamp_position(x, y)
  local arena = self.arena
  if arena then return clamp(x, arena.left, arena.right), clamp(y, arena.top, arena.bottom) end
  local margin = self.level and 6 or 16
  return clamp(x, margin, self.width-margin), clamp(y, margin, self.height-margin)
end

-- kind picks what a level cell must block: "shot" (default), "rail", "lob", "sight" or "walk".
function Game:cover_entry(x, y, dx, dy, reach, padding, kind, region, z, dz)
  if self.level then return Level.entry(self.level, x, y, dx, dy, reach, padding, kind, region, z, dz) end
  if self.cover then return Cover.entry(self.cover, x, y, dx, dy, reach, padding or 0) end
end

function Game:obstructed()
  return self.cover ~= nil or self.level ~= nil
end

local function shot_height(actor, target)
  if actor.roof or target and target.roof then
    local from = Level.AIM_HEIGHT + (actor.roof and Level.ROOF_HEIGHT or 0)
    local to = Level.AIM_HEIGHT + (target and target.roof and Level.ROOF_HEIGHT or 0)
    return from, to-from
  end
end

function Game:line_clear(x, y, tx, ty, z, dz)
  return not self:cover_entry(x, y, tx-x, ty-y, 1, 0, "shot", nil, z, dz)
end

function Game:attack_clear(actor, target)
  local z, dz = shot_height(actor, target)
  return self:line_clear(actor.x, actor.y, target.x, target.y, z, dz)
end

function Game:can_notice(actor, target)
  local z, dz = shot_height(actor, target)
  return not self:cover_entry(actor.x, actor.y, target.x-actor.x, target.y-actor.y, 1,
    0, "sight", nil, z, dz)
end

function Game:can_lob(actor, target)
  if not self.level then return true end
  local region = Level.region_at(self.level, actor.x, actor.y)
  local z, dz = shot_height(actor, target)
  return not self:cover_entry(actor.x, actor.y, target.x-actor.x, target.y-actor.y, 1,
    0, "lob", region, z, dz)
end

function Game:can_stand(x, y, radius)
  if self.level then return Level.can_stand(self.level, x, y, radius) end
  return not self.cover or Cover.can_stand(self.cover, x, y, radius)
end

function Game:rotate_cover(wave)
  if not self.cover then return false end
  local phase = (wave-1)//3
  if phase == self.cover_phase then return false end
  local previous = self.cover
  self.cover, self.cover_phase = Cover.layout(phase,previous,self.x,self.y,self.surface.radius), phase
  return self.cover ~= previous
end

function Game:detour(enemy, tx, ty)
  if enemy.roof or not self.cover and not self.level then return false end
  local previous_x, previous_y
  if enemy.route_until and self.time < enemy.route_until
    and (tx-enemy.route_goal_x)^2 + (ty-enemy.route_goal_y)^2 <= ROUTE_TOLERANCE^2 then
    previous_x, previous_y = enemy.route_x, enemy.route_y
  end
  local x, y = (self.level and Level or Cover).waypoint(self.level or self.cover, enemy.x, enemy.y, tx, ty,
    enemy.surface.radius, previous_x, previous_y)
  if not x then
    enemy.route_until = nil
    return false
  end
  if x ~= previous_x or y ~= previous_y then
    enemy.route_x, enemy.route_y = x, y
    enemy.route_goal_x, enemy.route_goal_y = tx, ty
    enemy.route_until = self.time+ROUTE_DURATION
  end
  local dx, dy = x-enemy.x, y-enemy.y
  local distance = sqrt(dx*dx + dy*dy)
  if distance < 0.01 then return false end
  local step = min(1, enemy.profile.speed*self.dt / distance)
  self:move_actor(enemy, dx*step, dy*step, self.direction_of(dx,dy))
  return true
end

local function actor_position(game, actor, x, y)
  x, y = game:clamp_position(x, y)
  if game.level then return Level.slide(game.level, actor.x, actor.y, x, y, actor.surface.radius, actor.roof) end
  if game.cover then return Cover.slide(game.cover, actor.x, actor.y, x, y, actor.surface.radius) end
  return x, y
end

function Game:move_actor(actor, dx, dy, direction)
  if self.level and not actor.roof and (dx ~= 0 or dy ~= 0) then
    local speed = Level.speed(self.level, actor.x, actor.y)
    dx, dy = dx*speed, dy*speed
  end
  local x, y = actor_position(self, actor, actor.x + dx, actor.y + dy)
  local vx, vy = x-actor.x, y-actor.y
  local moving = vx ~= 0 or vy ~= 0
  actor.walk = moving and (actor.walk + sqrt(vx*vx + vy*vy) / STEP_DISTANCE) % 8 or 0
  local pose = moving and floor(actor.walk) + 2 or 1
  if direction ~= actor.direction or pose ~= actor.pose
    or floor(x+0.5) ~= floor(actor.x+0.5) or floor(y+0.5) ~= floor(actor.y+0.5) then
    self.dirty = true
  end
  actor.x, actor.y, actor.direction, actor.pose = x, y, direction, pose
  return moving
end

function Game:nudge_enemy(enemy, dx, dy)
  local x, y = actor_position(self, enemy, enemy.x + dx, enemy.y + dy)
  if floor(x+0.5) ~= floor(enemy.x+0.5) or floor(y+0.5) ~= floor(enemy.y+0.5) then self.dirty = true end
  enemy.x, enemy.y = x, y
end

local lobbed = {grenade=true, disc=true, orb=true}

function Game:muzzle(weapon, actor)
  actor = actor or self
  local d = directions[actor.direction]
  local forward = weapon.muzzle
  if actor.pose == 3 or actor.pose == 4 or actor.pose == 7 or actor.pose == 8 then forward = forward - 1 end
  local dx, dy = d[1]*forward-d[2]*weapon.offset, d[2]*forward+d[1]*weapon.offset
  if self.level then
    local kind = lobbed[weapon.kind] and "lob" or weapon.kind == "rail" and "rail" or "shot"
    local region = kind == "lob" and Level.region_at(self.level, actor.x, actor.y)
    local z = actor.roof and Level.ROOF_HEIGHT + Level.AIM_HEIGHT
    local stop = Level.entry(self.level, actor.x, actor.y, dx, dy, 1, 0, kind, region, z)
    if stop then
      local scale = max(0, stop-0.005)
      dx, dy = dx*scale, dy*scale
    end
  end
  return actor.x+dx, actor.y+dy, d[1], d[2]
end

function Game:particle(x, y, vx, vy, duration, kind, radius, z)
  local particles = self.particles
  if #particles >= MAX_PARTICLES then return end
  local p = {x=x, y=y, vx=vx, vy=vy, age=0, life=duration, kind=kind, radius=radius, z=z}
  particles[#particles + 1] = p
  return p
end

-- One play of an animated effect sheet. Row is the facing for directional sheets.
function Game:fx(name, x, y, row, z)
  local spec = Range.effects[name]
  local p = self:particle(x, y, 0, 0, spec[2] / spec[3], "fx", nil, z)
  if p then p.name, p.row = name, row or 1 end
  return p
end

function Game:burst(x, y, amount, kind, z)
  for index = 1, min(amount, MAX_PARTICLES - #self.particles) do
    local angle = self.random() * 2 * math.pi
    local velocity = 12 + self.random() * 44
    self:particle(x, y, cos(angle)*velocity, sin(angle)*velocity, 0.18+self.random()*0.36, kind, nil, z)
  end
end

function Game:spawn(actor, weapon, contacts, x, y, dx, dy, flame_phase, z, dz)
  local projectiles = self.projectiles
  local limit = actor == self and MAX_PROJECTILES or MAX_PROJECTILES - PLAYER_PROJECTILE_RESERVE
  if #projectiles >= limit then return end
  local life = weapon.life
  if z and dz < 0 then life = min(life, z/(-dz*weapon.speed)) end
  projectiles[#projectiles + 1] = {
    x=x, y=y, dx=dx, dy=dy, age=0, life=life, kind=weapon.kind,
    weapon=weapon, contacts=contacts, targets=actor == self and self.targets or self.enemy_targets,
    direction=actor.direction, flame_phase=flame_phase, weapon_id=actor.weapon, owner=actor,
    region=self.level and lobbed[weapon.kind] and Level.region_at(self.level, actor.x, actor.y),
    z=z, dz=dz,
  }
  return projectiles[#projectiles]
end

local no_kick = {grenade=true, flame=true, frost=true, disc=true, orb=true, hammer=true}

function Game:muzzle_flash(actor, kind, x, y, dx, dy)
  actor.flash = no_kick[kind] and 0 or Game.flash_duration
  actor.flash_x, actor.flash_y, actor.flash_dx, actor.flash_dy, actor.flash_kind = x, y, dx, dy, kind
  local muzzle_fx = Range.muzzle_effects[kind]
  actor.flash_fx = muzzle_fx ~= nil
  if muzzle_fx then self:fx(muzzle_fx, x, y, actor.direction, shot_height(actor)) end
end

function Game:spawn_spread(actor, weapon, x, y, dx, dy, z, dz)
  local contacts = {}
  local stream = weapon.kind == "flame" or weapon.kind == "frost"
  local phase_seed = stream and (actor == self and self.shots*2 or floor(self.time*60))
  for index = 1, weapon.count do
    local angle = (index - (weapon.count + 1) / 2) * weapon.spread
    local sine, cosine = sin(angle), cos(angle)
    local phase = phase_seed and phase_seed+index
    self:spawn(actor, weapon, contacts, x, y, dx*cosine-dy*sine, dy*cosine+dx*sine, phase, z, dz)
  end
end

function Game:enemy_aim(enemy, weapon, target_x, target_y)
  local x, y, dx, dy = self:muzzle(weapon, enemy)
  local ax, ay = target_x-x, target_y-y
  local distance = sqrt(ax*ax + ay*ay)
  if distance > 0 then dx, dy = ax/distance, ay/distance end
  local z, dz = shot_height(enemy, self)
  return x, y, dx, dy, distance, z, z and (distance > 0 and dz/distance or 0)
end

function Game:beam_reach(x, y, dx, dy, reach, z, dz)
  if z and dz < 0 then reach = min(reach, -z/dz) end
  local stop, cell = self:cover_entry(x,y,dx,dy,reach,0,"shot",nil,z,dz)
  return stop or reach, cell
end

function Game:lob_landing(x, y, dx, dy, reach, region, z, dz)
  if self.level then
    local stop = self:cover_entry(x,y,dx,dy,reach,0,"lob",region,z,dz)
    if stop then reach = max(0, stop-0.01) end
  end
  return x+dx*reach, y+dy*reach
end

-- Intersect the projected hit interval with the actor's vertical hit box.
local function body_entry(target, first, last, z, dz)
  if not z then return not target.roof and first or nil end
  local bottom = target.roof and Level.ROOF_HEIGHT or 0
  local top = bottom + Level.AIM_HEIGHT*2
  if dz == 0 then return z >= bottom and z <= top and first or nil end
  local a, b = (bottom-z)/dz, (top-z)/dz
  first = max(first, min(a,b))
  if first <= min(last, max(a,b)) then return first end
end

function Game:fire_enemy(enemy, target_x, target_y)
  local profile = enemy.profile
  local weapon = profile.shot or Game.weapons[enemy.weapon]
  local x, y, dx, dy, distance, z, dz = self:enemy_aim(enemy,weapon,target_x,target_y)
  self:muzzle_flash(enemy, weapon.kind, x, y, dx, dy)
  if profile.beam_range then
    local reach, cell = self:beam_reach(x,y,dx,dy,profile.beam_range,z,dz)
    local beam = self:particle(x, y, 0, 0, 0.16, "enemy_beam", nil, z)
    if beam then beam.ex, beam.ey, beam.ez = x+dx*reach, y+dy*reach, z and z+dz*reach end
    local px, py = self.x-x, self.y-y
    local along, across = px*dx + py*dy, px*dy - py*dx
    if along >= 0 and along <= reach and abs(across) <= self.surface.radius and body_entry(self, along, along, z, dz) then
      self:enemy_hit(weapon.damage, weapon.effect)
    end
    self:damage_along(x,y,dx,dy,reach-0.001,weapon.damage,"soft",z,dz)
    self:strike_tile(cell, weapon.damage)
  elseif weapon.count then
    self:spawn_spread(enemy, weapon, x, y, dx, dy, z, dz)
  else
    local shot = self:spawn(enemy, weapon, {}, x, y, dx, dy, nil, z, dz)
    if shot and weapon.aimed_lob then shot.life = clamp(distance / weapon.speed, 0.01, shot.life) end
  end
end

Game.reserve_enemy_attack = Squad.reserve_attack

function Game:enemy_hit(amount, effect)
  local damage = self:damage(self, amount, effect)
  self:report(self, effect, damage)
end

function Game:enemy_strike(enemy)
  local profile = enemy.profile
  local dx, dy = self.x - enemy.aim_x, self.y - enemy.aim_y
  local reach_x, reach_y = enemy.aim_x - enemy.x, enemy.aim_y - enemy.y
  self:burst(enemy.aim_x, enemy.aim_y, 4, "dust")
  if dx*dx + dy*dy > profile.hit_radius^2 or reach_x*reach_x + reach_y*reach_y > (profile.fire_range + 1)^2 then return end
  if not self:melee_clear(enemy.x, enemy.y, self.x, self.y) then return end
  self:enemy_hit(profile.damage, "smash")
end

function Game:melee_clear(x, y, tx, ty)
  return self:line_clear(x, y, tx, ty) and (not self.level
    or not self:cover_entry(x, y, tx-x, ty-y, 1, 0, "walk"))
end

function Game:fire(weapon, level)
  local kind = weapon.kind
  self.cooldown, self.shots = weapon.delay, self.shots + 1
  self.fire_until = nil
  self.dirty = true
  if kind == "tnt" then
    self.flash = 0
    self:spawn(self, weapon, {}, self.x, self.y, 0, 0)
    self:message(string.format("TNT PLANTED   FUSE %.1fS", weapon.life))
    return
  end
  if kind == "hammer" then
    self.flash = 0
    return self:swing(weapon)
  end
  local x, y, dx, dy = self:muzzle(weapon)
  local z, dz
  if self.level and self.rooftop_enemies and not lobbed[kind] then
    z, dz = self:aim_elevation(x, y, dx, dy, weapon.speed*weapon.life, kind == "rail" and "rail" or "shot")
  end
  self:muzzle_flash(self, kind, x, y, dx, dy)
  if kind == "rail" then return self:rail(weapon, x, y, dx, dy, z, dz) end
  if kind == "arc" then return self:arc(weapon, x, y, dx, dy, z, dz) end
  if kind == "grenade" then self.grenade_ready_at = self.time + weapon.delay end
  if kind == "disc" then self.disc_out = true end
  if kind == "orb" then self.orb_out = true end
  if weapon.count then
    self:spawn_spread(self, weapon, x, y, dx, dy, z, dz)
  else
    local shot = self:spawn(self, weapon, {}, x, y, dx, dy, nil, z, dz)
    if shot and kind == "charge" then shot.level = level or 0 end
    if not shot and kind == "disc" then self.disc_out = nil end
    if not shot and kind == "orb" then self.orb_out = nil end
  end
end

-- Every living target a straight line crosses within reach, nearest first.
function Game:ray(x, y, dx, dy, reach, z, dz)
  local hits = {}
  for _, target in ipairs(self.targets) do
    if target.health > 0 then
      local tx, ty = target.x-x, target.y-y
      local forward = tx*dx + ty*dy
      local across = tx*dy - ty*dx
      local chord = target.surface.radius^2 - across^2
      if chord >= 0 then
        local half = sqrt(chord)
        local first, last = max(0, forward-half), min(reach, forward+half)
        local entry = first <= last and body_entry(target, first, last, z, dz)
        if entry then
          hits[#hits+1] = {target=target, along=entry}
        end
      end
    end
  end
  table.sort(hits, function(a, b) return a.along < b.along end)
  return hits
end

-- Directional aiming still chooses a lane in screen space. A clear ground
-- target takes precedence over a rooftop target farther down that lane.
function Game:aim_elevation(x, y, dx, dy, reach, kind)
  local stop = self:cover_entry(x,y,dx,dy,reach,0,kind) or reach
  local ground = self:ray(x,y,dx,dy,stop)[1]
  local best = ground and ground.along or reach
  local slope
  for _, target in ipairs(self.enemies) do
    if target.roof and target.health > 0 then
      local tx, ty = target.x-x, target.y-y
      local along, across = tx*dx+ty*dy, tx*dy-ty*dx
      if along > 0 and along <= best and abs(across) <= target.surface.radius then
        local dz = Level.ROOF_HEIGHT/along
        if not self:cover_entry(x,y,dx,dy,along,0,kind,nil,Level.AIM_HEIGHT,dz) then
          best, slope = along, dz
        end
      end
    end
  end
  if slope then return Level.AIM_HEIGHT, slope end
end

function Game:mark(target, x, y)
  local marks = target.marks
  if not marks then return end
  if #marks == 6 then table.remove(marks, 1) end
  marks[#marks+1] = {x=x-target.x, y=y-target.y}
end

function Game:summary(label, contacts, last, count, total)
  if count == 1 then
    self:report(last, label, contacts[last])
  elseif count > 1 then
    self:message(string.format("%s  %d TARGETS  %d DMG", label:upper(), count, total))
  end
end

-- The rail slug crosses its whole reach at once and damages every target on the line.
function Game:rail(weapon, x, y, dx, dy, z, dz)
  local reach = weapon.speed * weapon.life
  local stop, cell = self:cover_entry(x,y,dx,dy,reach,0,"rail",nil,z,dz)
  if stop then reach = stop end
  self:damage_along(x,y,dx,dy,reach-0.001,weapon.damage,"damage",z,dz)
  if stop then
    self:strike_tile(cell, weapon.damage)
  end
  local contacts, scale, total, last = {}, 1, 0, nil
  local hits = self:ray(x, y, dx, dy, reach, z, dz)
  for _, hit in ipairs(hits) do
    local target = hit.target
    local hx, hy = x+dx*hit.along, y+dy*hit.along
    total = total + self:damage(target, weapon.damage*scale, weapon.effect, contacts)
    self:mark(target, hx, hy)
    self:fx("rail-pierce", hx, hy, self.direction, z and z+dz*hit.along)
    scale, last = scale * weapon.pierce, target
  end
  local beam = self:fx("rail-beam", x, y, self.direction, z)
  if beam then
    beam.kind, beam.length, beam.ez = "beam", reach, z and z+dz*reach
    beam.ex, beam.ey = x+dx*reach, y+dy*reach
  end
  if #hits == 0 then self:burst(x+dx*reach, y+dy*reach, 2, "dust", z and z+dz*reach) end
  self:summary(weapon.effect, contacts, last, #hits, total)
end

-- The arc strikes the first target on the line, then forks to its nearest neighbours.
function Game:arc(weapon, x, y, dx, dy, z, dz)
  local reach = weapon.speed * weapon.life
  local stop, cell = self:cover_entry(x,y,dx,dy,reach,0,"shot",nil,z,dz)
  if stop then reach = stop end
  local first = self:ray(x, y, dx, dy, reach, z, dz)[1]
  if first then reach = first.along end
  self:damage_along(x,y,dx,dy,reach-0.001,weapon.damage,"soft",z,dz)
  if cell and not first then self:strike_tile(cell, weapon.damage) end
  local bolt = self:particle(x, y, 0, 0, 0.22, "arc", nil, z)
  if bolt then
    bolt.ex, bolt.ey, bolt.row, bolt.links, bolt.seed = x+dx*reach, y+dy*reach, self.direction, {}, self.shots
    bolt.ez = z and z+dz*reach
  end
  if not first then
    self:burst(x+dx*reach, y+dy*reach, 2, "dust", z and z+dz*reach)
    return
  end
  local origin = first.target
  local hx, hy = x+dx*first.along, y+dy*first.along
  if bolt then bolt.ex, bolt.ey = hx, hy end
  local contacts = {}
  local total, count = self:damage(origin, weapon.damage, weapon.effect, contacts), 1
  self:fx("arc-zap", hx, hy, nil, shot_height(origin))
  local chained = {[origin]=true}
  for _ = 1, weapon.chain do
    local best, nearest = weapon.chain_range^2, nil
    for _, target in ipairs(self.targets) do
      if target.health > 0 and not chained[target] then
        local ox, oy = target.x-origin.x, target.y-origin.y
        local range = ox*ox + oy*oy
        if range <= best and self:attack_clear(origin,target) then
          best, nearest = range, target
        end
      end
    end
    if not nearest then break end
    chained[nearest] = true
    total, count = total + self:damage(nearest, weapon.damage*weapon.chain_damage, weapon.effect, contacts), count + 1
    local nz = shot_height(nearest)
    self:fx("arc-zap", nearest.x, nearest.y, nil, nz)
    if bolt then bolt.links[#bolt.links+1] = {hx, hy, nearest.x, nearest.y} end
    if bolt and nz then bolt.ez = nz end
  end
  self:summary(count > 1 and "chain" or weapon.effect, contacts, origin, count, total)
end

-- The hammer sweeps a cone in front of the hero and shoves light targets away.
local function in_swing(dx, dy, distance, reach, direction, cone)
  return distance <= reach and (distance < 1 or (dx*direction[1]+dy*direction[2])/distance >= cone)
end

function Game:swing(weapon)
  local d = directions[self.direction]
  local swing = self:fx("hammer-swing", self.x, self.y, self.direction)
  if swing then swing.follow = true end
  local cone = cos(math.rad(weapon.arc))
  local contacts, total, count, last = {}, 0, 0, nil
  for _, target in ipairs(self.targets) do
    if target.health > 0 then
      local dx, dy = target.x-self.x, target.y-self.y
      local distance = sqrt(dx*dx + dy*dy)
      if not target.roof and in_swing(dx,dy,distance,weapon.reach+target.surface.radius,d,cone)
        and self:line_clear(self.x,self.y,target.x,target.y) then
        total, count, last = total + self:damage(target, weapon.damage, weapon.effect, contacts), count + 1, target
        self:fx("hammer-shock", target.x, target.y)
        if target.surface.light and target.health > 0 then
          local nx, ny = d[1], d[2]
          if distance >= 1 then nx, ny = dx/distance, dy/distance end
          target.vx, target.vy = nx*weapon.knockback*KNOCK_DECAY, ny*weapon.knockback*KNOCK_DECAY
          self:fx("knock-skid", target.x, target.y, Game.direction_of(nx, ny))
        end
      end
    end
  end
  local struck_tile = false
  if self.level then
    local tiles = Level.blast_cells(self.level,self.x,self.y,weapon.reach)
    for _, hit in ipairs(tiles) do
      local i = hit[1]-1
      local x, y = (i % self.level.w + 0.5)*Level.SIZE, (i // self.level.w + 0.5)*Level.SIZE
      local dx, dy = x-self.x, y-self.y
      if in_swing(dx,dy,sqrt(dx*dx+dy*dy),weapon.reach+Level.SIZE/2,d,cone) then
        self:strike_tile(i+1, weapon.damage)
        if not struck_tile then self:fx("hammer-shock",x,y) end
        struck_tile = true
      end
    end
  end
  if count > 0 or struck_tile then self:shake(self.x, self.y, 1.6, 0.12)
  else self:burst(self.x+d[1]*14, self.y+d[2]*14, 3, "dust") end
  self:summary(weapon.effect, contacts, last, count, total)
end

function Game:clear_frost(target)
  target.frost_until, target.frost_at, target.frost_bonus, target.frost_speed = nil, nil, nil, nil
end

function Game:damage(target, amount, effect, contacts)
  local scale = target.surface.scale[effect] or 1
  local damage = min(target.health, max(1, floor(amount * scale + 0.5)))
  target.health = target.health - damage
  if target == self and damage > 0 then self.hurt_until = self.time + HURT_DURATION end
  if target.dormant then target.dormant, target.alerted = nil, true end
  local on_hit = target.profile and target.profile.on_hit
  if on_hit and damage > 0 then on_hit(self, target, effect) end
  if target.home_x then target.reset_at = self.time + (target.health == 0 and 1.65 or 3) end
  if target.health == 0 then target.burn = nil end
  if contacts then
    local previous = contacts[target]
    if not previous and target ~= self then self.hits = self.hits + 1 end
    contacts[target] = (previous or 0) + damage
  end
  self.dirty = true
  -- Any follow-up hit except frost and burn shatters a frost coat for bonus damage.
  if target.frost_until and effect ~= "frost" and effect ~= "burn" and effect ~= "shatter" then
    local bonus = target.frost_bonus
    self:clear_frost(target)
    self:fx("frost-shatter", target.x, target.y, nil, shot_height(target))
    if target.health > 0 then
      target.shatter_at = self.time
      damage = damage + self:damage(target, bonus, "shatter", contacts)
    end
  end
  return damage
end

function Game:report(target, effect, damage)
  if target.shatter_at == self.time then effect = "shatter" end
  if target == self then
    self:message(string.format("HIT  -%d HP  %s", damage, effect:upper()))
    return
  end
  self:message(string.format("%s  %s %d  HP %d/%d", target.surface.name, effect:upper(),
    damage, target.health, target.surface.health))
end

local impact_fx = {bank="bank-impact", disc="disc-hit", charge="charge-impact"}

local function shield_scale(target, shot)
  local profile = target.profile
  if not profile or not profile.frontal_damage or target.fire_at then return 1 end
  local effect = shot.weapon.effect
  if effect ~= "impact" and effect ~= "spread" then return 1 end
  local facing = directions[target.direction]
  if shot.dx*facing[1] + shot.dy*facing[2] <= -diagonal then return profile.frontal_damage end
  return 1
end

function Game:impact(target, shot, x, y, travel)
  local weapon = shot.weapon
  local z = shot_height(target)
  local amount = weapon.damage
  local label = weapon.effect
  if weapon.min_damage then
    local reach = weapon.speed * weapon.life
    amount = amount * (1 - (1 - weapon.min_damage) * min(1, travel / reach))
  end
  if shot.level then amount = amount * (weapon.min_charge + (1 - weapon.min_charge) * shot.level) end
  if shot.bounced then amount, label = amount * weapon.bank_bonus, "bank" end
  local shield = shield_scale(target, shot)
  if shield < 1 then amount, label = amount * shield, "block" end
  self:damage(target, amount, weapon.effect, shot.contacts)
  if shot.kind == "frost" then
    if target.health > 0 then
      if not target.frost_until then target.frost_at = self.time end
      target.frost_until, target.frost_bonus = self.time + weapon.frost_time, weapon.shatter
      target.frost_speed = weapon.frost_speed
    end
    self:burst(x, y, 1, "flake", z)
  elseif shot.kind == "flame" then
    target.scorched = true
    if target.health > 0 then
      local burn = target.burn or {weapon=weapon, next_at=self.time + weapon.burn_interval}
      burn.ticks = weapon.burn_ticks
      target.burn = burn
    end
    self:burst(x, y, 2, "ember", z)
  else
    self:mark(target, x, y)
    local effect = impact_fx[shot.kind]
    if effect then self:fx(effect, x, y, nil, z)
    else self:burst(x, y, shot.kind == "pellet" and 2 or 5, "spark", z) end
    if shot.level and shot.level >= 1 then
      -- A full charge splashes the targets around the one it struck.
      self:shake(x, y, 2.4, 0.16)
      for _, other in ipairs(shot.targets) do
        if other ~= target and other.health > 0 and self:area_distance(x,y,z,other,weapon.splash) then
          self:damage(other, amount, weapon.effect, shot.contacts)
        end
      end
    end
  end
  self:report(target, label, shot.contacts[target])
end

local function update_target(game, target)
  local burn = target.burn
  if burn and game.time >= burn.next_at then
    local weapon = burn.weapon
    local damage = game:damage(target, weapon.burn_damage, "burn")
    burn.ticks, burn.next_at = burn.ticks - 1, burn.next_at + weapon.burn_interval
    if burn.ticks == 0 then target.burn = nil end
    game:burst(target.x, target.y, 3, "ember", shot_height(target))
    game:report(target, "burn", damage)
  end
  if target.frost_until then
    if game.time >= target.frost_until then
      game:clear_frost(target)
      game.dirty = true
    elseif target ~= game then game.dirty = true end
  end
  if target.vx then
    local fade = exp(-KNOCK_DECAY * game.dt)
    target.x, target.y = actor_position(game, target, target.x + target.vx*game.dt, target.y + target.vy*game.dt)
    target.vx, target.vy = target.vx*fade, target.vy*fade
    if abs(target.vx) + abs(target.vy) < 4 then target.vx, target.vy = nil, nil end
    if target.home_x then target.reset_at = max(target.reset_at or 0, game.time + RECOVER_AFTER) end
    game.dirty = true
  end
  if target.reset_at and game.time >= target.reset_at then
    target.health = target.surface.health
    target.reset_at, target.scorched, target.cracked, target.burn = nil, nil, nil, nil
    target.vx, target.vy = nil, nil
    game:clear_frost(target)
    target.x, target.y = target.home_x, target.home_y
    target.marks, game.dirty = {}, true
  end
end

function Game:update_targets()
  if self.burn or self.frost_until then update_target(self,self) end
  for _, target in ipairs(self.targets) do update_target(self,target) end
  for _, plate in ipairs(self.reflectors) do
    if plate.struck_at and self.time - plate.struck_at < 0.25 then self.dirty = true end
  end
end

function Game:shake(x, y, strength, duration)
  local dx, dy = x-self.x, y-self.y
  local amplitude = strength * max(0, 1 - (dx*dx + dy*dy) / (112*112))
  if amplitude == 0 then return end
  local active = self.camera_shake
  if active and active.strength * (1 - (self.time-active.started)/active.duration) > amplitude then return end
  self.camera_shake = {started=self.time, strength=amplitude, duration=duration}
  self.dirty = true
end

function Game:scorch_ground(x, y, z)
  local marks = self.scorch_marks
  for index = #marks, 1, -1 do
    local dx, dy = x-marks[index].x, y-marks[index].y
    if z == marks[index].z and dx*dx + dy*dy <= SCORCH_MERGE_DISTANCE^2 then table.remove(marks, index) end
  end
  if #marks == MAX_SCORCH_MARKS then table.remove(marks, 1) end
  marks[#marks+1] = {x=x, y=y, z=z}
  self.dirty = true
end

-- Area effects use the same cover as direct fire, including a roof between floors.
function Game:area_distance(x, y, z, target, radius)
  local dx, dy = target.x-x, target.y-y
  local dz
  if z or target.roof then
    z = z or Level.AIM_HEIGHT
    dz = (shot_height(target) or Level.AIM_HEIGHT)-z
  end
  local distance = dx*dx + dy*dy + (dz or 0)^2
  if distance <= radius*radius and (not self.level or self:line_clear(x,y,target.x,target.y,z,dz)) then
    return sqrt(distance)
  end
end

function Game:explode(x, y, shot, direct, z)
  local weapon = shot.weapon
  local rocket = shot.kind == "rocket"
  local tnt = shot.kind == "tnt"
  local level = self.level
  local water = level and (not z or z < Level.ROOF_HEIGHT) and Level.water_at(level, x, y)
  if not rocket and not water then self:scorch_ground(x, y, z) end
  local strength, shake_time = 3.2, 0.18
  local blast_style, blast_time, embers, clouds = "blast", 0.25, 19, 14
  if tnt then
    strength, shake_time = 5.0, 0.29
    blast_style, blast_time, embers, clouds = "tnt_blast", 0.34, 26, 18
  elseif rocket then
    strength, shake_time = 3.8, 0.22
    blast_style, blast_time, embers, clouds = "rocket_blast", 0.30, 22, 15
  end
  if water then blast_style, embers, clouds = "water_blast", 12, 0 end
  self:shake(x, y, strength, shake_time)
  self:particle(x, y, 0, 0, blast_time, blast_style, weapon.radius, z)
  self:burst(x, y, embers, water and "flake" or "ember", z)
  for index = 1, clouds do
    local angle = index * 2.4
    local speed = 4 + self.random() * 28
    self:particle(x+cos(angle)*3, y+sin(angle)*3, cos(angle)*speed, sin(angle)*speed-14,
      0.45+self.random()*0.35, "smoke", nil, z)
  end
  local count, total, last = 0, 0, nil
  for _, target in ipairs(shot.targets) do
    local distance = target.health > 0 and (target == direct and 0 or self:area_distance(x,y,z,target,weapon.radius))
    if distance then
      local amount = weapon.damage * (1 - (1 - weapon.min_damage) * distance / weapon.radius)
      if target == direct then amount = amount + weapon.direct end
      total = total + self:damage(target, amount, weapon.effect, shot.contacts)
      target.cracked = true
      count, last = count + 1, target
    end
  end
  if count == 1 then
    self:report(last, weapon.effect, total)
  elseif count > 1 then
    self:message(string.format("BLAST  %d TARGETS  %d DMG", count, total))
  end
  if level then
    for _, hit in ipairs(Level.blast_cells(level, x, y, weapon.radius, z)) do
      self:strike_tile(hit[1], weapon.damage * (weapon.min_damage + (1-weapon.min_damage)*hit[2]))
    end
  end
end

-- Gunfire and blasts wear down destructible level tiles. Explosive tiles chain.
function Game:strike_tile(cell, amount)
  local level = self.level
  if not level or not cell or not level.hp[cell] then return end
  local broke, blast, bx, by = Level.damage(level, cell, amount)
  if not broke then return end
  self.dirty = true
  self:burst(bx, by, 6, "dust")
  if blast then
    self.pending_blasts = self.pending_blasts or {}
    self.pending_blasts[#self.pending_blasts+1] = {x=bx, y=by, weapon=blast}
  end
end

function Game:chain_blasts()
  local pending = self.pending_blasts
  if not pending then return end
  local targets = {self}
  for _, enemy in ipairs(self.enemies) do targets[#targets+1] = enemy end
  -- Large barrel fields can chain without recursing or exhausting a badge tick.
  for _ = 1, min(4, #pending) do
    local blast = table.remove(pending, 1)
    self:explode(blast.x, blast.y, {kind="barrel", targets=targets, contacts={},
      weapon={radius=blast.weapon.radius, damage=blast.weapon.damage, min_damage=0.25, direct=0, effect="blast"}})
  end
  if #pending == 0 then self.pending_blasts = nil end
end

function Game:damage_along(x, y, dx, dy, reach, amount, kind, z, dz, seen)
  if not self.level then return end
  while true do
    local _, cell = Level.entry(self.level,x,y,dx,dy,reach,0,kind,nil,z,dz,seen)
    if not cell then return seen end
    seen = seen or {}
    seen[cell] = true
    self:strike_tile(cell, amount)
  end
end

local function contact(targets, shot, step, ignore)
  if step == 0 then return end
  local nearest, entry, aim = nil, math.huge, 0
  for _, target in ipairs(targets) do
    if target.health > 0 and not (ignore and ignore[target]) then
      local dx, dy = target.x-shot.x, target.y-shot.y
      local forward = dx*shot.dx + dy*shot.dy
      local across = dx*shot.dy - dy*shot.dx
      local half_chord = target.surface.radius^2 - across^2
      if half_chord >= 0 then
        local reach = sqrt(half_chord)
        local first, last = max(0, forward-reach), min(step, forward+reach)
        local touch = first <= last and body_entry(target, first, last, shot.z, shot.dz)
        if touch and touch < entry then
          nearest, entry, aim = target, touch, max(0, forward)
        end
      end
    end
  end
  return nearest, entry, aim
end

function Game:update_shots(dt)
  local projectiles, particles = self.projectiles, self.particles
  if #projectiles + #particles > 0 then self.dirty = true end
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.age = p.age + dt
    if p.age >= p.life then table.remove(particles, i)
    else p.x, p.y = p.x+p.vx*dt, p.y+p.vy*dt end
  end
  for i = #projectiles, 1, -1 do
    local shot = projectiles[i]
    local mover = Game.movers[shot.kind]
    if mover and mover(self, shot, dt) or not mover and self:move_shot(shot, dt) then
      table.remove(projectiles, i)
    end
    if self.health == 0 then return end
  end
end

-- Straight flight for bullets, pellets, flames, frost, rockets, grenades, TNT and charge bolts.
-- Returns true when the shot is spent.
function Game:move_shot(shot, dt)
  do
    local kind = shot.kind
    local speed = shot.weapon.speed
    local step = min(dt, shot.life - shot.age) * speed
    local nx, ny = shot.x + shot.dx*step, shot.y + shot.dy*step
    local expired = shot.age + dt >= shot.life
    local hit, entry, aim
    if kind ~= "grenade" then hit, entry, aim = contact(shot.targets, shot, step) end
    local barrier, cell
    if kind ~= "grenade" then
      barrier, cell = self:cover_entry(shot.x,shot.y,shot.dx,shot.dy,step,0,"shot",nil,shot.z,shot.dz)
    elseif self.level then
      barrier, cell = self:cover_entry(shot.x,shot.y,shot.dx,shot.dy,step,0,"lob",shot.region,shot.z,shot.dz)
    end
    local amount = shot.weapon.damage
    if shot.level then amount = amount * (shot.weapon.min_charge + (1-shot.weapon.min_charge)*shot.level) end
    if self.level and kind ~= "grenade" and kind ~= "rocket" and kind ~= "tnt" then
      local travel = min(step, barrier or step, entry or step)
      shot.tiles_hit = self:damage_along(shot.x,shot.y,shot.dx,shot.dy,travel,amount,"soft",shot.z,shot.dz,shot.tiles_hit)
    end
    if barrier and (not entry or barrier <= entry) then
      -- Blasts go off just in front of the wall so the wall itself shelters what is behind it.
      if self.level then barrier = max(0, barrier-0.01) end
      local x, y = shot.x+shot.dx*barrier, shot.y+shot.dy*barrier
      local z = shot.z and shot.z+shot.dz*barrier
      if kind == "rocket" or kind == "grenade" then self:explode(x, y, shot, nil, z)
      else
        local effect = kind == "flame" and "ember" or kind == "frost" and "flake" or "spark"
        self:burst(x, y, kind == "pellet" and 2 or 4, effect, z)
        self:strike_tile(cell, amount)
      end
      return true
    end
    if hit or expired then
      if kind == "rocket" or kind == "grenade" or kind == "tnt" then
        local z = hit and shot_height(hit) or shot.z and shot.z+shot.dz*step
        self:explode(hit and hit.x or nx, hit and hit.y or ny, shot, hit, z)
      elseif hit then
        local at = min(aim, barrier and max(entry,barrier-0.01) or aim)
        self:impact(hit, shot, shot.x + shot.dx*at, shot.y + shot.dy*at, shot.age*speed + entry)
      elseif kind ~= "flame" and kind ~= "frost" then self:burst(nx, ny, 2, "dust", shot.z and shot.z+shot.dz*step) end
      return true
    else
      if kind == "rocket" then
        for puff = floor(shot.age * 40) + 1, floor((shot.age + dt) * 40) do
          local distance = (puff / 40 - shot.age) * speed - 7
          self:particle(shot.x+shot.dx*distance, shot.y+shot.dy*distance, -shot.dx*7, -shot.dy*7-5,
            0.30, "exhaust", nil, shot.z and shot.z+shot.dz*distance)
        end
      end
      shot.x, shot.y, shot.age = nx, ny, shot.age + dt
      if shot.z then shot.z = shot.z+shot.dz*step end
    end
  end
  return false
end

Game.movers = {}

-- The bankshot round turns on the first reflector it reaches before any target.
function Game.movers.bank(self, shot, dt)
  local weapon = shot.weapon
  local step = min(dt, weapon.life - shot.age) * weapon.speed
  local barrier = self:cover_entry(shot.x,shot.y,shot.dx,shot.dy,step,0,"shot",nil,shot.z,shot.dz)
  for _, plate in ipairs(self.reflectors) do
    if shot.bounced ~= plate then
      local px, py = plate.x-shot.x, plate.y-shot.y
      local along = px*shot.dx + py*shot.dy
      if along >= 0 and along <= step and (not barrier or along < barrier) and abs(px*shot.dy - py*shot.dx) <= 3.5
        and not contact(shot.targets, shot, along) then
        local dot = shot.dx*plate.ux + shot.dy*plate.uy
        shot.dx, shot.dy = 2*dot*plate.ux - shot.dx, 2*dot*plate.uy - shot.dy
        shot.x, shot.y, shot.age = plate.x, plate.y, shot.age + along / weapon.speed
        shot.bounced, plate.struck_at = plate, self.time
        self:fx("bank-ricochet", plate.x, plate.y)
        return false
      end
    end
  end
  return self:move_shot(shot, dt)
end

-- The disc flies out for its life, then homes back to the hero. Each leg can hit a target once.
function Game.movers.disc(self, shot, dt)
  local weapon = shot.weapon
  local step = weapon.speed * min(dt, weapon.life-shot.age)
  if shot.age >= weapon.life then
    if not shot.returning then shot.returning, shot.contacts = true, {} end
    local tx, ty = self.x-shot.x, self.y-shot.y
    local distance = sqrt(tx*tx + ty*ty)
    local caught = distance < 7 and (not self.level
      or not self:cover_entry(shot.x,shot.y,tx,ty,1,0,"lob",shot.region))
    if caught or distance == 0 or shot.age > weapon.life + 2.5 then
      if caught then self:fx("disc-catch", self.x, self.y) end
      self.disc_out, self.dirty = nil, true
      return true
    end
    shot.dx, shot.dy = tx/distance, ty/distance
    step = min(distance, weapon.speed*dt*weapon.return_speed)
  end
  local barrier, cell
  if self.level then barrier, cell = self:cover_entry(shot.x,shot.y,shot.dx,shot.dy,step,0,"lob",shot.region) end
  if barrier then step = max(0, barrier-0.01) end
  local hit, entry, aim = contact(shot.targets, shot, step, shot.contacts)
  if hit then self:impact(hit, shot, shot.x + shot.dx*aim, shot.y + shot.dy*aim, entry) end
  shot.tiles_hit = self:damage_along(shot.x,shot.y,shot.dx,shot.dy,step,weapon.damage,"soft",nil,nil,shot.tiles_hit)
  shot.x, shot.y = shot.x + shot.dx*step, shot.y + shot.dy*step
  shot.age = shot.age + dt
  if barrier then
    self:strike_tile(cell, weapon.damage)
    self:fx("disc-hit", shot.x, shot.y)
    if shot.returning then
      self.disc_out = nil
      return true
    end
    shot.age = weapon.life
  end
  return false
end

-- The orb flies until it strikes something or runs out, then holds a well that drags
-- light targets in before it collapses.
function Game.movers.orb(self, shot, dt)
  local weapon = shot.weapon
  if not shot.well_at then
    local step = min(dt, weapon.life - shot.age) * weapon.speed
    local hit, entry = contact(shot.targets, shot, step)
    if hit then step = entry end
    local barrier = self.level and self:cover_entry(shot.x,shot.y,shot.dx,shot.dy,step,0,"lob",shot.region)
    if barrier then step = max(0, barrier-0.01) end
    shot.x, shot.y, shot.age = shot.x + shot.dx*step, shot.y + shot.dy*step, shot.age + dt
    if hit or barrier or shot.age >= weapon.life then
      shot.well_at = self.time
      self:message("GRAVITY WELL OPEN")
    end
    return false
  end
  for _, target in ipairs(shot.targets) do
    if target.surface.light and target.health > 0 and not target.roof then
      local dx, dy = shot.x-target.x, shot.y-target.y
      local distance = sqrt(dx*dx + dy*dy)
      if distance <= weapon.pull and distance > 6 and (not self.level or self:line_clear(shot.x,shot.y,target.x,target.y)) then
        local move = min(distance - 6, weapon.pull_speed*dt) / distance
        local x, y = target.x + dx*move, target.y + dy*move
        if self.cover or self.level then x, y = actor_position(self, target, x, y) end
        target.x, target.y = x, y
        if target.home_x then target.reset_at = max(target.reset_at or 0, self.time + RECOVER_AFTER) end
      end
    end
  end
  if self.time - shot.well_at < weapon.well_time then return false end
  self.orb_out = nil
  self:fx("well-collapse", shot.x, shot.y)
  self:shake(shot.x, shot.y, 1.8, 0.14)
  local count, total, last = 0, 0, nil
  for _, target in ipairs(shot.targets) do
    if target.health > 0 and self:area_distance(shot.x,shot.y,nil,target,weapon.collapse) then
      total, count, last = total + self:damage(target, weapon.damage, weapon.effect, shot.contacts), count + 1, target
    end
  end
  self:summary(weapon.effect, shot.contacts, last, count, total)
  return true
end

-- Accumulate exposure so crossing a tile briefly costs less than standing on it.
function Game:hazard_tick(dt)
  local rate = Level.hazard(self.level, self.x, self.y)
  if rate <= 0 then return end
  local exposure = (self.hazard_damage or 0) + rate*dt
  local damage = floor(exposure+1e-9)
  self.hazard_damage = max(0, exposure-damage)
  if damage > 0 then
    self:enemy_hit(damage, "hazard")
  end
end

function Game:charge_level(weapon)
  return min(1, (self.time - self.charge_from) / weapon.charge_time)
end

local function drill_result(game)
  if game.health == 0 then return "lost" end
  if game.pending_blasts then return end
  if game.mission then return Mission.update(game) end
  if game.squad then return Squad.update(game) end
  for _, enemy in ipairs(game.enemies) do
    if enemy.health > 0 then return end
  end
  return "won"
end

function Game:update(ms, keys)
  if self.result then return end
  local dt = clamp(ms, 0, 80) / 1000
  self.dt = dt
  self.time, self.cooldown = self.time + dt, max(0, self.cooldown - dt)
  if self.grenade_ready_at and self.time >= self.grenade_ready_at then
    self.grenade_ready_at, self.dirty = nil, true
  end
  if self.camera_shake then
    local shake = self.camera_shake
    if self.time - shake.started >= shake.duration then self.camera_shake = nil end
    self.dirty = true
  end
  if self.flash > 0 then self.flash, self.dirty = max(0, self.flash-dt), true end
  if self.hurt_until and self.time >= self.hurt_until then self.hurt_until, self.dirty = nil, true end
  if self.notice and self.time >= self.message_until then self.notice, self.dirty = nil, true end
  self:update_targets()

  if self.health > 0 then
    local dx = (keys.right and 1 or 0) - (keys.left and 1 or 0)
    local dy = (keys.down and 1 or 0) - (keys.up and 1 or 0)
    local direction = facing[dy+2][dx+2]
    if direction ~= 0 then
      local d = directions[direction]
      local travel = MOVE_SPEED*dt*(self.frost_speed or 1)
      if self:move_actor(self, d[1]*travel, d[2]*travel, direction) and not self.level then self:collect() end
    elseif self.pose ~= 1 then self.pose, self.walk, self.dirty = 1, 0, true end
    if self.level then
      self:collect()
      self:hazard_tick(dt)
      Level.update(self.level)
    end

    self:update_shots(dt)
    if self.health > 0 then self:chain_blasts() end
    if self.health > 0 then Enemies.update(self) end
  end
  if self.drill then
    self.result = drill_result(self)
    if self.result then
      self.projectiles, self.fire_until, self.charge_from = {}, nil, nil
      self.flash, self.hurt_until, self.camera_shake = 0, nil, nil
      self.burn = nil
      self:clear_frost(self)
      if self.result == "lost" then self.pose, self.walk = 1, 0 end
      self.dirty = true
      return
    end
  end
  if self.squad or self.practice then Enemies.separate(self) end

  local weapon = Game.weapons[self.weapon]
  if self.fire_until and self.time > self.fire_until then self.fire_until = nil end
  local ready = weapon and self:held_weapon() ~= 0 and self.cooldown == 0
    and not (self.orb_out and weapon.kind == "orb")
  if weapon and weapon.kind == "charge" then
    -- Holding Select builds the charge; releasing it fires. A quick tap fires the minimum.
    if self.charge_from then
      self.dirty = true
      if not keys.select then
        self:fire(weapon, self:charge_level(weapon))
        self.charge_from = nil
      end
    elseif ready and (self.fire_until or keys.select) then
      self.charge_from, self.fire_until, self.dirty = self.time, nil, true
    end
  elseif ready and (self.fire_until or weapon.hold and keys.select) then
    self:fire(weapon)
  elseif self.fire_until and not weapon then
    self:message("WALK OVER A WEAPON TO PICK IT UP")
    self.fire_until = nil
  end
end

return Game
