-- Plays a level exported by tools/level-builder: spawn, loadout, enemy waves and the objective.
local Level = require("lib.level")

local Mission = {}
local BETWEEN_WAVES, WAKE_CALL, EXIT_RADIUS = 1.6, 64, 10

function Mission.list()
  local ok, index = pcall(require, "levels.index")
  return ok and index or {}
end

function Mission.start(game, id)
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
  game.weapon = (def.loadout or {})[1] or 0
  if not next(game.owned) then game.owned[0] = true end

  local mission = {waves={}, name=def.name, objective=def.objective or "clear"}
  game.mission = mission
  local total = 0
  for _, entity in ipairs(def.entities or {}) do
    local kind = entity[1]
    if kind == "spawn" then
      game.x, game.y, game.direction = entity[2], entity[3], entity[4] or 5
    elseif kind == "enemy" then
      local wave = entity[6] or 1
      mission.waves[wave] = mission.waves[wave] or {}
      table.insert(mission.waves[wave], entity)
      total = math.max(total, wave)
    elseif kind == "pickup" then
      game.pickups[#game.pickups+1] = {id=entity[2], x=entity[3], y=entity[4]}
    elseif kind == "medkit" then
      game:add_medkit(entity[2], entity[3])
    elseif kind == "exit" then
      game.exit = {x=entity[2], y=entity[3]}
    end
  end
  -- Objectives: "clear" every wave, reach the "exit", or "clear-exit" (clear, then leave).
  if mission.objective ~= "clear" and not game.exit then mission.objective = "clear" end
  -- Waves count from 1 even if the builder skipped numbers.
  local ordered = {}
  for wave = 1, total do
    if mission.waves[wave] then ordered[#ordered+1] = mission.waves[wave] end
  end
  mission.waves = ordered
  game.squad = {wave=1, total=math.max(1, #ordered), remaining=0, next_attack_at=0, mission=true}
  Mission.spawn_wave(game, 1)
  game:message(mission.objective == "exit" and "REACH THE EXIT" or (mission.name or "LEVEL"):upper())
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

  if game.exit then
    local dx, dy = game.x-game.exit.x, game.y-game.exit.y
    if dx*dx + dy*dy <= EXIT_RADIUS^2 and not game:cover_entry(game.x,game.y,dx,dy,1,0,"walk") then
      if mission.objective == "exit" or (mission.objective == "clear-exit" and remaining == 0) then return "won" end
      if mission.objective == "clear-exit" and not mission.exit_hint then
        mission.exit_hint = true
        game:message("CLEAR THE AREA FIRST")
      end
    elseif mission.exit_hint then mission.exit_hint = nil end
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
  if mission.objective == "clear" then return "won" end
  if mission.objective == "clear-exit" and not mission.exit_open then
    mission.exit_open = true
    game:message("AREA CLEAR  REACH THE EXIT")
  end
end

return Mission
