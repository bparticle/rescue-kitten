local Charge = {}
local min, max, sqrt = math.min, math.max, math.sqrt

local function finish(game, enemy)
  enemy.fire_at, enemy.dash_left = nil, nil
  enemy.ready_at = game.time + enemy.profile.recovery
  game:move_actor(enemy, 0, 0, enemy.direction)
  game.dirty = true
end

local function hits_player(game, enemy, from_x, from_y)
  local dx, dy = enemy.x-from_x, enemy.y-from_y
  local px, py = game.x-from_x, game.y-from_y
  local length_sq = dx*dx + dy*dy
  local fraction = length_sq > 0 and min(1, max(0, (px*dx+py*dy)/length_sq)) or 0
  local near_x, near_y = px-dx*fraction, py-dy*fraction
  return near_x*near_x + near_y*near_y <= enemy.profile.contact_radius^2
end

function Charge.interrupt(game, enemy, effect)
  if effect == "shock" and (enemy.fire_at or enemy.dash_left) then finish(game, enemy) end
end

function Charge.update(game, enemy)
  local profile = enemy.profile
  if enemy.dash_left then
    local travel = min(enemy.dash_left, profile.dash_speed*game.dt)
    if travel == 0 then return end
    local from_x, from_y = enemy.x, enemy.y
    local barrier = game:cover_entry(from_x,from_y,enemy.dash_dx,enemy.dash_dy,travel,enemy.surface.radius)
    if barrier then travel = max(0, barrier-0.05) end
    local moved = game:move_actor(enemy, travel*enemy.dash_dx, travel*enemy.dash_dy, enemy.direction)
    if not enemy.dash_hit and hits_player(game, enemy, from_x, from_y)
      and (not game.level or game:melee_clear(enemy.x,enemy.y,game.x,game.y)) then
      enemy.dash_hit = true
      game:enemy_hit(profile.damage, "smash")
    end
    enemy.dash_left = enemy.dash_left - travel
    if barrier or not moved or enemy.dash_left <= 0 then finish(game, enemy) end
    return
  end

  if enemy.fire_at then
    if game.time >= enemy.fire_at then
      local dx, dy = enemy.aim_x-enemy.x, enemy.aim_y-enemy.y
      local distance = sqrt(dx*dx + dy*dy)
      enemy.dash_dx = distance > 0 and dx/distance or 1
      enemy.dash_dy = distance > 0 and dy/distance or 0
      enemy.dash_left, enemy.dash_hit, enemy.fire_at = profile.dash_distance, false, nil
      game:burst(enemy.x, enemy.y, 6, "dust")
      game.dirty = true
    end
    return
  end

  if game.time < enemy.ready_at then return end
  local dx, dy = game.x-enemy.x, game.y-enemy.y
  local distance = sqrt(dx*dx + dy*dy)
  local direction = distance > 0 and game.direction_of(dx, dy) or enemy.direction
  local blocked = game:obstructed() and not game:melee_clear(enemy.x,enemy.y,game.x,game.y)
  if not enemy.alerted and distance > profile.notice_range then
    game:move_actor(enemy, 0, 0, enemy.direction)
  elseif (blocked or distance > profile.fire_range) and game:detour(enemy, game.x, game.y) then
    return
  elseif blocked then
    game:move_actor(enemy, 0, 0, direction)
  elseif distance > profile.fire_range then
    local step = min(profile.speed*game.dt, distance-profile.fire_range+0.75)/distance
    game:move_actor(enemy, dx*step, dy*step, direction)
  else
    game:move_actor(enemy, 0, 0, direction)
    if game:reserve_enemy_attack(enemy) then
      enemy.aim_x, enemy.aim_y, enemy.fire_at = game.x, game.y, game.time + profile.windup
      game.dirty = true
    end
  end
end

return Charge
