local Ranged = require("lib.ai.ranged")

local Support = {}
local min, sqrt = math.min, math.sqrt

local function injured_ally(game, enemy)
  local target, best, distance = nil, -math.huge, math.huge
  for _, ally in ipairs(game.enemies) do
    if ally ~= enemy and ally.health > 0 and ally.roof == enemy.roof then
      local need = ally.surface.health - ally.health
      if need > 0 then
        local dx, dy = ally.x-enemy.x, ally.y-enemy.y
        local range = dx*dx + dy*dy
        local benefit = min(need, enemy.profile.heal) - sqrt(range)*0.25
        if benefit > best then target, best, distance = ally, benefit, range end
      end
    end
  end
  return target, distance
end

function Support.interrupt(game, enemy)
  if not enemy.heal_target then return end
  enemy.heal_target, enemy.fire_at = nil, nil
  enemy.heal_ready_at = game.time + enemy.profile.heal_recovery*0.5
end

function Support.update(game, enemy)
  local profile = enemy.profile
  local patient = enemy.heal_target
  if patient then
    if game.time < enemy.fire_at then return end
    local dx, dy = patient.x-enemy.x, patient.y-enemy.y
    if patient.health > 0 and dx*dx+dy*dy <= profile.heal_range^2
      and game:attack_clear(enemy,patient) then
      patient.health = min(patient.surface.health, patient.health + profile.heal)
      game:particle(patient.x, patient.y-11, 0, -11, 0.38, "heal", nil, patient.roof and game.level.roof_height)
    end
    enemy.heal_target, enemy.fire_at = nil, nil
    enemy.heal_ready_at = game.time + profile.heal_recovery
    game.dirty = true
    return
  end
  if enemy.fire_at or game.time < (enemy.heal_ready_at or 0) then return Ranged.update(game, enemy) end

  local ally, distance_sq = injured_ally(game, enemy)
  if not ally then return Ranged.update(game, enemy) end
  local dx, dy = ally.x-enemy.x, ally.y-enemy.y
  local direction = distance_sq > 0 and game.direction_of(dx, dy) or enemy.direction
  local blocked = game:obstructed() and not game:attack_clear(enemy,ally)
  if (blocked or distance_sq > profile.heal_range^2) and game:detour(enemy, ally.x, ally.y) then return end
  if blocked then
    return Ranged.update(game, enemy)
  elseif distance_sq > profile.heal_range^2 then
    local distance = sqrt(distance_sq)
    local step = min(profile.speed*game.dt, distance - profile.heal_range*0.8) / distance
    game:move_actor(enemy, dx*step, dy*step, direction)
  else
    game:move_actor(enemy, 0, 0, direction)
    enemy.heal_target, enemy.fire_at = ally, game.time + profile.heal_windup
    game.dirty = true
  end
end

return Support
