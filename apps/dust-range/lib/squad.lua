-- The shared attack schedule for mission enemies: attacks release one after another.
local Squad = {}
local ATTACK_GAP = 0.24

-- lead is the time an attacker needs to get into position before its windup starts.
function Squad.reserve_attack(game, enemy, lead)
  local squad = game.squad
  if not squad then return true end
  local profile = enemy.profile
  local release = game.time + (lead or 0) + profile.windup
  if release < squad.next_attack_at then return false end
  -- A rush only starts once the previous attack has gone off, so two never close in together.
  if lead and game.time < (squad.last_release or 0) then return false end
  squad.last_release = release
  local burst_time = ((profile.burst or 1) - 1) * (profile.burst_interval or 0)
  local dash_time = profile.dash_distance and profile.dash_distance/profile.dash_speed or 0
  squad.next_attack_at = release + burst_time + dash_time + ATTACK_GAP
  return true
end

return Squad
