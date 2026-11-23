local Ranged = {}
local sqrt, min = math.sqrt, math.min

function Ranged.update(game, enemy)
  local profile = enemy.profile
  if enemy.fire_at then
    if game.time >= enemy.fire_at then
      game:fire_enemy(enemy, enemy.aim_x, enemy.aim_y)
      if enemy.burst_left and enemy.burst_left > 1 then
        enemy.burst_left = enemy.burst_left - 1
        enemy.fire_at = enemy.fire_at + profile.burst_interval
      else
        enemy.fire_at, enemy.burst_left, enemy.ready_at = nil, nil, game.time + profile.recovery
      end
      game.dirty = true
    end
    return
  end

  local dx, dy = game.x-enemy.x, game.y-enemy.y
  local distance_sq = dx*dx + dy*dy
  if not enemy.alerted and distance_sq > profile.notice_range^2 then
    game:move_actor(enemy, 0, 0, enemy.direction)
    return
  end
  if distance_sq == 0 then
    local step = profile.speed*game.dt
    if not game:move_actor(enemy, step, 0, 7) then game:move_actor(enemy, -step, 0, 3) end
    return
  end

  local distance = sqrt(distance_sq)
  local direction = game.direction_of(dx, dy)
  local blocked = false
  if game:obstructed() then
    local lob = profile.shot and profile.shot.aimed_lob
    if lob then blocked = not game:can_lob(enemy, game)
    else blocked = not game:attack_clear(enemy, game) end
    if (blocked or distance > profile.fire_range) and game:detour(enemy, game.x, game.y) then return end
    if blocked and not enemy.roof then
      game:move_actor(enemy, 0, 0, direction)
      return
    end
  end
  local travel = 0
  if blocked then
    travel = min(profile.speed*game.dt, distance)
  elseif distance > profile.fire_range then
    travel = min(profile.speed*game.dt, distance-profile.fire_range+1)
  elseif distance < profile.retreat_range then
    travel = -min(profile.speed*game.dt, profile.retreat_range-distance+1)
  end
  local drift = 0
  if profile.strafe_speed and distance <= profile.fire_range+6 and distance >= profile.retreat_range then
    drift = enemy.strafe_side * profile.strafe_speed * game.dt
  end
  local moving = game:move_actor(enemy, (dx*travel-dy*drift)/distance, (dy*travel+dx*drift)/distance, direction)
  if drift ~= 0 and not moving then enemy.strafe_side = -enemy.strafe_side end

  if not blocked and distance <= profile.fire_range and game.time >= enemy.ready_at then
    -- If the map edge prevents a retreat, the windup still gives the player time to move.
    if (distance >= profile.retreat_range or travel < 0 and not moving) and game:reserve_enemy_attack(enemy) then
      game:move_actor(enemy, 0, 0, direction)
      enemy.fire_at = game.time + profile.windup
      enemy.burst_left = profile.burst
      enemy.aim_x, enemy.aim_y = game.x, game.y
      game.dirty = true
    end
  end
end

return Ranged
