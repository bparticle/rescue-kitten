local Melee = {}
local min, sqrt = math.min, math.sqrt
-- Extra time a committed rush may take before the runner gives up and circles again.
local COMMIT_SLACK, REGROUP = 0.6, 0.35

-- Melee units wait on a ring around the player and only close in once their attack slot is
-- reserved, so the player always sees the rush coming and has room to shoot first.
function Melee.update(game, enemy)
  local profile = enemy.profile
  if enemy.fire_at then
    if game.time >= enemy.fire_at then
      game:enemy_strike(enemy)
      enemy.fire_at, enemy.ready_at = nil, game.time + profile.recovery
      game.dirty = true
    end
    return
  end

  local dx, dy = game.x - enemy.x, game.y - enemy.y
  local distance = sqrt(dx*dx + dy*dy)
  local direction = distance > 0 and game.direction_of(dx, dy) or enemy.direction
  if not enemy.alerted and distance > profile.notice_range then
    game:move_actor(enemy, 0, 0, enemy.direction)
    return
  end

  local standoff = profile.standoff or profile.fire_range
  if enemy.commit_until and game.time > enemy.commit_until then
    enemy.commit_until, enemy.ready_at = nil, game.time + REGROUP
  end
  local on_ring = distance >= standoff - 8 and distance <= standoff + 12
  if not enemy.commit_until and game.time >= enemy.ready_at and (on_ring or standoff <= profile.fire_range) then
    local lead = math.max(0, distance - profile.fire_range) / profile.speed
    if game:reserve_enemy_attack(enemy, lead) then
      enemy.commit_until = game.time + lead + COMMIT_SLACK
    end
  end
  local reach = enemy.commit_until and profile.fire_range or standoff

  local blocked = game:obstructed() and not game:melee_clear(enemy.x,enemy.y,game.x,game.y)
  if (blocked or distance > reach) and game:detour(enemy, game.x, game.y) then return end
  if blocked then
    game:move_actor(enemy, 0, 0, direction)
  elseif distance > reach then
    local travel = min(profile.speed*game.dt, distance - reach + 0.75)
    game:move_actor(enemy, dx/distance*travel, dy/distance*travel, direction)
  elseif enemy.commit_until then
    game:move_actor(enemy, 0, 0, direction)
    enemy.commit_until, enemy.fire_at = nil, game.time + profile.windup
    enemy.aim_x, enemy.aim_y = game.x, game.y
    game.dirty = true
  else
    -- Hold the ring: fall back out after a strike and circle slowly while waiting for a slot.
    local back = distance < standoff - 6 and min(profile.speed*game.dt, standoff - distance) or 0
    local circle = (enemy.strafe_side or 1) * (profile.circle_speed or 0) * game.dt
    if distance == 0 then dx, dy, distance = 1, 0, 1 end
    local moved = game:move_actor(enemy, (-dx*back - dy*circle)/distance, (-dy*back + dx*circle)/distance,
      direction)
    if circle ~= 0 and not moved then enemy.strafe_side = -(enemy.strafe_side or 1) end
  end
end

return Melee
