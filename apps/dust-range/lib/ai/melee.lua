local Melee = {}
local min, sqrt = math.min, math.sqrt

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

  local blocked = game:obstructed() and not game:melee_clear(enemy.x,enemy.y,game.x,game.y)
  if (blocked or distance > profile.fire_range) and game:detour(enemy, game.x, game.y) then return end
  if blocked then
    game:move_actor(enemy, 0, 0, direction)
  elseif distance > profile.fire_range then
    local travel = min(profile.speed*game.dt, distance - profile.fire_range+0.75)
    game:move_actor(enemy, dx/distance*travel, dy/distance*travel, direction)
  else
    game:move_actor(enemy, 0, 0, direction)
    if game.time >= enemy.ready_at and game:reserve_enemy_attack(enemy) then
      enemy.fire_at = game.time + profile.windup
      enemy.aim_x, enemy.aim_y = game.x, game.y
      game.dirty = true
    end
  end
end

return Melee
