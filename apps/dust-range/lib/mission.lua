-- Plays a level exported by tools/level-builder: spawn, loadout, enemy waves and the objective.
local Mission = {}
local BETWEEN_WAVES, WAKE_CALL, INTERACT_RADIUS = 1.6, 64, 10
local RESCUE_POINTS, TIME_BONUS_MAX, TIME_BONUS_PER_SECOND = 500, 600, 10

-- checkpoint: a snapshot taken when a later wave arrived (see Mission.snapshot), or nil.
function Mission.start(game, id, checkpoint)
  local Level = require("lib.level")
  local def = require("levels." .. id)
  local level = Level.new(def)
  game.level, game.level_id = level, id
  game.width, game.height = level.w*Level.SIZE, level.h*Level.SIZE
  game.targets = game.enemies
  game.pickups = {}
  if def.health and def.health ~= game.surface.health then
    game.surface = {name="PLAYER", health=def.health, radius=game.surface.radius, scale={}}
    game.health = def.health
  end
  game.owned = {}
  for _, id in ipairs(def.loadout or {}) do game.owned[id] = true end
  -- The weapon pack (up to three weapons kept from earlier missions) joins the loadout.
  for id in pairs(game.arsenal or {}) do
    if game.weapons[id] then game.owned[id] = true end
  end
  game.weapon = (def.loadout or {})[1] or next(game.owned) or 0
  if not next(game.owned) then game.owned[0] = true end

  local mission = {waves={}, alarm={}, name=def.name, objective=def.objective or "clear", par=def.par}
  game.mission = mission
  local total = 0
  for _, entity in ipairs(def.entities or {}) do
    local kind = entity[1]
    if kind == "spawn" then
      game.x, game.y, game.direction = entity[2], entity[3], entity[4] or 5
    elseif kind == "enemy" then
      local wave = entity[6] or 1
      if wave == 0 then
        -- Wave 0 is the alarm squad: it moves in when the kitten is picked up.
        mission.alarm[#mission.alarm+1] = entity
      else
        mission.waves[wave] = mission.waves[wave] or {}
        table.insert(mission.waves[wave], entity)
        total = math.max(total, wave)
      end
    elseif kind == "pickup" then
      -- A weapon kept from an earlier run doesn't lie around again: bring it in the pack instead.
      -- Its pickup stays in the list (collected) so checkpoint indexes don't shift.
      game.pickups[#game.pickups+1] = {id=entity[2], x=entity[3], y=entity[4],
        collected=game.kept and game.kept[entity[2]] or nil}
    elseif kind == "medkit" then
      game:add_medkit(entity[2], entity[3])
    elseif kind == "hamburger" then
      game.pickups[#game.pickups+1] = {kind=kind, x=entity[2], y=entity[3]}
    elseif kind == "exit" then
      game.exit = {x=entity[2], y=entity[3]}
    elseif kind == "kitten" then
      mission.kitten = {x=entity[2], y=entity[3]}
    end
  end
  if not game.exit and (mission.objective == "exit" or mission.objective == "clear-exit") then
    mission.objective = "clear"
  end
  -- Waves count from 1 even if the builder skipped numbers.
  local ordered = {}
  for wave = 1, total do
    if mission.waves[wave] then ordered[#ordered+1] = mission.waves[wave] end
  end
  mission.waves = ordered
  game.squad = {wave=1, total=math.max(1, #ordered), remaining=0, next_attack_at=0, mission=true}
  if checkpoint then return Mission.resume(game, checkpoint) end
  Mission.spawn_wave(game, 1)
  if mission.objective == "rescue-kitten" then game:message("WALK UP TO THE KITTEN")
  elseif mission.objective == "exit" then game:message("REACH THE EXIT")
  else game:message((mission.name or "MISSION"):upper()) end
end

function Mission.spawn_wave(game, wave)
  local entries = game.mission.waves[wave]
  if not entries then return end
  for index, entity in ipairs(entries) do
    local enemy = game:spawn_enemy(entity[2], entity[3], entity[4], entity[5] or 5, entity[7])
    enemy.ready_at = game.time + 0.5 + (index-1)*0.1
    -- The opening wave holds position until it sees the player. Later waves arrive hunting.
    if wave == 1 then enemy.dormant = true else enemy.alerted = true end
  end
  if wave > 1 then game.checkpoint = Mission.snapshot(game, wave) end
  if wave > 1 then game:message("WAVE " .. wave .. " INCOMING") end
end

local function count_remaining(game)
  local squad, mission = game.squad, game.mission
  local remaining = #game.enemies
  for wave = squad.wave+1, #mission.waves do remaining = remaining + #mission.waves[wave] end
  return remaining
end

local function wake(game, enemy)
  enemy.dormant, enemy.alerted = nil, true
  for _, other in ipairs(game.enemies) do
    if other.dormant and (other.x-enemy.x)^2 + (other.y-enemy.y)^2 <= WAKE_CALL^2 then
      other.dormant, other.alerted = nil, true
    end
  end
end

local function in_reach(game, point)
  local dx, dy = point.x-game.x, point.y-game.y
  return dx*dx + dy*dy <= INTERACT_RADIUS^2 and not game:cover_entry(game.x,game.y,dx,dy,1,0,"walk")
end

-- Stars are bits: 1 for completing the mission, 2 for finishing within par time,
-- 4 for losing at most a quarter of the starting health.
Mission.STAR_CLEAR, Mission.STAR_PAR, Mission.STAR_HEALTH = 1, 2, 4

function Mission.damage_limit(health)
  return (health or 100)//4
end

function Mission.stars(par, health, seconds, damage)
  local stars = Mission.STAR_CLEAR
  if par and seconds <= par then stars = stars | Mission.STAR_PAR end
  if damage <= Mission.damage_limit(health) then stars = stars | Mission.STAR_HEALTH end
  return stars
end

-- The full time bonus holds until par, then drops by 10 per second.
local function complete(game)
  local mission = game.mission
  if mission.objective == "rescue-kitten" then game:add_score(RESCUE_POINTS) end
  local seconds = math.floor(game.time + 1e-9)
  local late = math.max(0, seconds - (mission.par or 0))
  game.time_bonus = math.max(0, TIME_BONUS_MAX - late*TIME_BONUS_PER_SECOND)
  game.score = game.score + game.time_bonus
  game.clear_time = seconds
  game.stars = Mission.stars(mission.par, game.surface.health, seconds, game.damage_taken or 0)
  return "won"
end

-- The kitten's cries wake every guard, and the alarm squad moves in. Returns true if anyone heard.
function Mission.raise_alarm(game)
  local mission, heard = game.mission, false
  if mission.alarm_raised then return false end
  mission.alarm_raised = true
  for _, enemy in ipairs(game.enemies) do
    if enemy.dormant then enemy.dormant, enemy.alerted, heard = nil, true, true end
  end
  for index, entity in ipairs(mission.alarm) do
    local enemy = game:spawn_enemy(entity[2], entity[3], entity[4], entity[5] or 5, entity[7])
    enemy.ready_at, enemy.alerted, heard = game.time + 0.6 + (index-1)*0.15, true, true
  end
  return heard
end

-- What a retry from this wave restores. Taken as the wave arrives, so earlier enemies are gone.
function Mission.snapshot(game, wave)
  local mission, owned, collected = game.mission, {}, {}
  for id in pairs(game.owned) do owned[#owned+1] = id end
  for index, item in ipairs(game.pickups) do
    if item.collected then collected[#collected+1] = index end
  end
  local destroyed = {}
  for index, cell in ipairs(game.level.destroyed) do destroyed[index] = cell end
  return {
    level=game.level_id, wave=wave, x=game.x, y=game.y, direction=game.direction,
    health=game.health, weapon=game.weapon, owned=owned, collected=collected, destroyed=destroyed,
    score=game.score, time=game.time, damage=game.damage_taken or 0,
    carrying=mission.carrying, alarm=mission.alarm_raised,
  }
end

function Mission.resume(game, checkpoint)
  local Level, mission = require("lib.level"), game.mission
  for _, cell in ipairs(checkpoint.destroyed) do Level.destroy(game.level, cell) end
  for _, index in ipairs(checkpoint.collected) do game.pickups[index].collected = true end
  game.owned = {}
  for _, id in ipairs(checkpoint.owned) do game.owned[id] = true end
  game.x, game.y, game.direction = checkpoint.x, checkpoint.y, checkpoint.direction
  game.health, game.weapon = checkpoint.health, checkpoint.weapon
  game.score, game.time, game.damage_taken = checkpoint.score, checkpoint.time, checkpoint.damage
  mission.carrying, mission.alarm_raised = checkpoint.carrying, checkpoint.alarm
  mission.exit_open = checkpoint.carrying
  game.squad.wave = checkpoint.wave
  Mission.spawn_wave(game, checkpoint.wave)
  game:message("CHECKPOINT  WAVE " .. checkpoint.wave)
end

function Mission.update(game)
  local squad, mission = game.squad, game.mission
  for index = #game.enemies, 1, -1 do
    local enemy = game.enemies[index]
    if enemy.health == 0 then
      table.remove(game.enemies, index)
    elseif enemy.dormant then
      local dx, dy = game.x-enemy.x, game.y-enemy.y
      if dx*dx + dy*dy <= enemy.profile.notice_range^2
        and game:can_notice(enemy, game) then
        wake(game, enemy)
      end
    end
  end

  local remaining = count_remaining(game)
  if squad.remaining ~= remaining then squad.remaining, game.dirty = remaining, true end

  local rescue = mission.objective == "rescue-kitten"
  if rescue and mission.kitten and not mission.carrying and in_reach(game, mission.kitten) then
    mission.carrying, mission.exit_open = true, true
    game:message(Mission.raise_alarm(game) and "KITTEN FOUND  GUARDS ALERTED" or "KITTEN FOUND  REACH THE EXIT")
  end

  if game.exit and in_reach(game, game.exit) then
    if mission.objective == "exit" or (mission.objective == "clear-exit" and remaining == 0)
      or (rescue and mission.carrying) then return complete(game) end
    if not mission.exit_hint then
      if rescue then game:message("FIND THE KITTEN FIRST")
      elseif mission.objective == "clear-exit" then game:message("CLEAR THE AREA FIRST") end
      mission.exit_hint = true
    end
  else
    mission.exit_hint = nil
  end

  if squad.next_wave_at then
    if game.time >= squad.next_wave_at then
      squad.wave, squad.next_wave_at = squad.wave + 1, nil
      Mission.spawn_wave(game, squad.wave)
    end
    return
  end
  if #game.enemies > 0 then return end
  if squad.wave < #mission.waves then
    squad.next_wave_at = game.time + BETWEEN_WAVES
    game:message("WAVE CLEAR")
    return
  end
  if mission.objective == "clear" then return complete(game) end
  if mission.objective == "clear-exit" and not mission.exit_open then
    mission.exit_open = true
    game:message("AREA CLEAR  REACH THE EXIT")
  end
end

return Mission
