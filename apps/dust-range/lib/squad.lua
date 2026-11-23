local Squad = {}
local min, max, sqrt = math.min, math.max, math.sqrt
local BETWEEN_WAVES, RECOVERY_HP, ATTACK_GAP = 1.65, 24, 0.24
local SPAWN_CLEARANCE, MAX_ACTIVE, REINFORCEMENT_DELAY = 24, 8, 0.52
local Endless

Squad.arena = {left=328, right=568, top=242, bottom=398}
local center_x, center_y = 448, 320
local slots = {
  {67,3,7}, {-67,-3,3}, {3,-42,5}, {-3,42,1}, {61,-41,6}, {-61,41,2}, {-61,-41,4}, {61,41,8},
}
local edge_slots = {
  {-100,-64,4}, {-50,-64,4}, {0,-64,5}, {50,-64,6}, {100,-64,6},
  {-100,64,2}, {-50,64,2}, {0,64,1}, {50,64,8}, {100,64,8}, {-105,0,3}, {105,0,7},
}
local waves = {
  {roster={{"soldier",1}, {"runner",2}},
    hint="STEP OUT OF THE RUNNER STRIKE MARK"},
  {roster={{"rifleman",3}, {"runner",4}, {"soldier",2}},
    supply=2, hint="RIFLEMEN FIRE IN THREE-SHOT BURSTS"},
  {roster={{"scatterguard",1}, {"runner",3}, {"lobber",6}, {"soldier",4}},
    supply=3, hint="LOBBERS MARK WHERE A GRENADE WILL LAND"},
  {roster={{"warden",1}, {"rifleman",2}, {"runner",3}, {"runner",4}, {"lobber",5}},
    supply=8, hint="WARDEN SHIELDS OPEN WHEN THEY AIM"},
  {roster={{"warden",1}, {"scatterguard",2}, {"runner",3}, {"skirmisher",4}, {"lobber",5}, {"rifleman",6}},
    hint="SKIRMISHERS STRAFE BETWEEN SHOTS"},
  {roster={{"warden",1}, {"scatterguard",2}, {"runner",3}, {"skirmisher",4}, {"lobber",5}, {"medic",6}, {"rifleman",7}},
    supply=11, hint="HIT MEDICS TO INTERRUPT THEIR HEALS"},
  {roster={{"warden",1}, {"scatterguard",2}, {"runner",3}, {"skirmisher",4}, {"lobber",5}, {"medic",6},
      {"rifleman",7}, {"bruiser",8}}, hint="ARC SHOTS INTERRUPT BRUISER CHARGES"},
}

local function spawn_position(game, x, y, slot)
  local sx, sy = x+slot[1], y+slot[2]
  local dx, dy = sx-game.x, sy-game.y
  local distance = sqrt(dx*dx + dy*dy)
  if distance >= SPAWN_CLEARANCE then return sx, sy end
  if distance > 0 then
    local step = (SPAWN_CLEARANCE+0.5) / distance
    sx, sy = game:clamp_position(game.x+dx*step, game.y+dy*step)
    if (sx-game.x)^2 + (sy-game.y)^2 >= SPAWN_CLEARANCE^2 then return sx, sy end
  end
  -- If a boundary clips the adjusted spawn, shift inward from the player instead.
  dx, dy = center_x-game.x, center_y-game.y
  local inward = sqrt(dx*dx + dy*dy)
  if inward < SPAWN_CLEARANCE then return game.x+SPAWN_CLEARANCE, game.y end
  local step = (SPAWN_CLEARANCE+0.5) / inward
  return game.x+dx*step, game.y+dy*step
end

local function group_origin(game)
  return max(center_x-34, min(center_x+34, game.x)), max(center_y-22, min(center_y+22, game.y))
end

local function clear_spawn(game, x, y)
  if (x-game.x)^2 + (y-game.y)^2 < SPAWN_CLEARANCE^2 or not game:can_stand(x,y,10) then return false end
  for _, enemy in ipairs(game.enemies) do
    if (x-enemy.x)^2 + (y-enemy.y)^2 < 19^2 then return false end
  end
  return true
end

local function deployment_spot(game, preferred)
  local x, y = group_origin(game)
  for offset = 0, #slots-1 do
    local slot = slots[(preferred+offset-1)%#slots+1]
    local sx, sy = spawn_position(game, x, y, slot)
    if clear_spawn(game, sx, sy) then return sx, sy, slot[3] end
  end
  for _, slot in ipairs(edge_slots) do
    local sx, sy = center_x+slot[1], center_y+slot[2]
    if clear_spawn(game, sx, sy) then return sx, sy, slot[3] end
  end
end

local function deploy(game, kind, x, y, direction, delay)
  local enemy = game:spawn_enemy(kind, x, y, direction)
  enemy.ready_at, enemy.alerted = game.time + delay, true
end

local function spawn_wave(game)
  local squad = game.squad
  local wave = squad.total and waves[squad.wave]
  local roster = wave and wave.roster or Endless.roster(squad.wave, squad.roll, #slots)
  local moved_cover = game:rotate_cover(squad.wave)
  -- Spread the group around the player while keeping it inside the arena.
  squad.roster, squad.deployed = roster, 0
  for index = 1, min(MAX_ACTIVE, #roster) do
    local placement = roster[index]
    local sx, sy, direction = deployment_spot(game, placement[2])
    if not sx then break end
    deploy(game, placement[1], sx, sy, direction, 0.45 + (index - 1)*0.14)
    squad.deployed = index
  end
  squad.remaining = #roster
  squad.next_attack_at = game.time
  if wave then game:message(wave.hint)
  elseif squad.wave == 1 then game:message("BARRICADES BLOCK DIRECT SHOTS")
  elseif moved_cover then game:message("BARRICADES SHIFTED") end
end

function Squad.start(game, roll)
  game.arena = Squad.arena
  game.owned[0] = nil
  game.targets = game.enemies
  game.squad = {wave=1, total=#waves}
  if game.drill == "endless" then
    Endless = Endless or require("lib.endless")
    game.squad.total, game.squad.roll = nil, roll
    game.owned[2], game.owned[3], game.owned[8], game.owned[11] = true, true, true, true
    game.weapon = 2
  else
    game:add_medkit(center_x-35, center_y-26)
    game:add_medkit(center_x+40, center_y+27)
  end
  spawn_wave(game)
end

function Squad.reserve_attack(game, enemy)
  local squad = game.squad
  if not squad then return true end
  local profile = enemy.profile
  local release = game.time + profile.windup
  if release < squad.next_attack_at then return false end
  local burst_time = ((profile.burst or 1) - 1) * (profile.burst_interval or 0)
  local dash_time = profile.dash_distance and profile.dash_distance/profile.dash_speed or 0
  squad.next_attack_at = release + burst_time + dash_time + ATTACK_GAP
  return true
end

local function update_reinforcement(game, squad)
  local next_unit = squad.roster[squad.deployed+1]
  if not next_unit or #game.enemies >= MAX_ACTIVE then return end
  local incoming = squad.incoming
  if incoming and game.time < incoming.at then return end
  if incoming and clear_spawn(game, incoming.x, incoming.y) then
    deploy(game, next_unit[1], incoming.x, incoming.y, incoming.direction, 0.48)
    squad.incoming, squad.deployed = nil, squad.deployed + 1
    return
  end

  local x, y, direction = deployment_spot(game, next_unit[2])
  if x then
    squad.incoming = {x=x, y=y, direction=direction, at=game.time+REINFORCEMENT_DELAY}
    if not incoming then game:message("REINFORCEMENT INCOMING") end
  else
    squad.incoming = nil
  end
  game.dirty = true
end

function Squad.update(game)
  local squad = game.squad
  if squad.next_wave_at then
    if game.time >= squad.next_wave_at then
      squad.wave, squad.next_wave_at = squad.wave + 1, nil
      spawn_wave(game)
    end
    return
  end

  for index = #game.enemies, 1, -1 do
    local enemy = game.enemies[index]
    if enemy.health == 0 then
      if not squad.total and enemy.profile.drop then game:drop_weapon(enemy.profile.drop,enemy.x,enemy.y) end
      table.remove(game.enemies, index)
    end
  end
  update_reinforcement(game, squad)
  local remaining = #game.enemies + #squad.roster - squad.deployed
  if squad.remaining ~= remaining then squad.remaining, game.dirty = remaining, true end
  if remaining > 0 then return end
  if squad.wave == squad.total then return "won" end

  squad.next_wave_at = game.time + BETWEEN_WAVES
  squad.roster = nil
  game.projectiles = {}
  game.disc_out, game.orb_out, game.burn = nil, nil, nil
  game:clear_frost(game)
  local restored = min(RECOVERY_HP, game.surface.health - game.health)
  game.health = game.health + restored
  local supply = squad.total and waves[squad.wave+1].supply
  if supply then game:collect_weapon(supply) end
  local notice = restored > 0 and ("WAVE CLEAR   +" .. restored .. " HP") or "WAVE CLEAR"
  game:message(notice)
end

return Squad
