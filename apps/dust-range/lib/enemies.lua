local Ranged = require("lib.ai.ranged")
local Melee = require("lib.ai.melee")
local Support = require("lib.ai.support")
local Charge = require("lib.ai.charge")
local Range = require("lib.range")

local Enemies = {}
local function enemy_shot(weapon, tuning)
  return setmetatable(tuning, {__index=Range.weapons[weapon]})
end

local profiles = {
  soldier = {
    behavior=Ranged.update, skin="soldier", weapon=1, speed=52,
    notice_range=116, fire_range=68, retreat_range=36, windup=0.52, recovery=0.95,
    surface={name="SOLDIER", health=54, radius=7, scale={}, light=true},
  },
  runner = {
    behavior=Melee.update, skin="runner", weapon=0, speed=91,
    notice_range=300, fire_range=15, standoff=52, circle_speed=26, windup=0.44, recovery=0.85, hit_radius=9, damage=16,
    surface={name="RUNNER", health=27, radius=7, scale={}, light=true},
  },
  rifleman = {
    behavior=Ranged.update, skin="rifleman", weapon=2, speed=39,
    notice_range=300, fire_range=92, retreat_range=52, windup=0.78, recovery=1.45,
    burst=3, burst_interval=0.12, shot=enemy_shot(2, {damage=8, speed=255}),
    surface={name="RIFLEMAN", health=44, radius=8, scale={}, light=true},
  },
  scatterguard = {
    behavior=Ranged.update, skin="scatterguard", weapon=3, speed=65,
    notice_range=300, fire_range=46, retreat_range=30, windup=0.63, recovery=1.14,
    shot=enemy_shot(3, {damage=7, count=3, spread=0.20}),
    surface={name="SCATTERGUARD", health=64, radius=8, scale={impact=0.85}},
  },
  lobber = {
    behavior=Ranged.update, skin="lobber", weapon=4, speed=47,
    notice_range=120, fire_range=58, retreat_range=36, windup=0.68, recovery=1.56,
    shot=enemy_shot(4, {aimed_lob=true, damage=27, radius=19, speed=82, life=0.78}),
    surface={name="LOBBER", health=40, radius=7, scale={}, light=true},
  },
  warden = {
    behavior=Ranged.update, skin="warden", weapon=1, speed=34,
    notice_range=120, fire_range=50, retreat_range=26, windup=0.64, recovery=1.18,
    frontal_damage=0.30, shot=enemy_shot(1, {damage=13, speed=290}),
    surface={name="WARDEN", health=80, radius=9, scale={}},
  },
  skirmisher = {
    behavior=Ranged.update, skin="skirmisher", weapon=9, speed=63, strafe_speed=55,
    notice_range=128, fire_range=62, retreat_range=38, windup=0.46, recovery=0.95,
    shot=enemy_shot(1, {damage=12, speed=300, muzzle=7}),
    surface={name="SKIRMISHER", health=36, radius=7, scale={}, light=true},
  },
  medic = {
    behavior=Support.update, on_hit=Support.interrupt, skin="medic", weapon=1, speed=62,
    notice_range=128, fire_range=46, retreat_range=30, windup=0.62, recovery=1.25,
    heal=26, heal_range=41, heal_windup=0.65, heal_recovery=1.15,
    shot=enemy_shot(1, {damage=10, speed=275}),
    surface={name="MEDIC", health=46, radius=7, scale={}, light=true},
  },
  bruiser = {
    behavior=Charge.update, on_hit=Charge.interrupt, skin="bruiser", weapon=0, speed=44,
    notice_range=125, fire_range=50, retreat_range=34, windup=0.72, recovery=1.06,
    dash_distance=58, dash_speed=168, contact_radius=11, damage=28,
    surface={name="BRUISER", health=112, radius=10, scale={smash=0.75}},
  },
  marksman = {
    behavior=Ranged.update, skin="marksman", weapon=8, speed=48, beam_range=105,
    notice_range=145, fire_range=106, retreat_range=60, windup=1.02, recovery=1.68,
    shot=enemy_shot(8, {kind="bullet", effect="energy", damage=29}),
    surface={name="MARKSMAN", health=40, radius=7, scale={}, light=true},
  },
  cinder = {
    behavior=Ranged.update, skin="cinder", weapon=6, speed=61, drop=6,
    notice_range=120, fire_range=33, retreat_range=24, windup=0.59, recovery=1.28,
    shot=enemy_shot(6, {damage=2, life=0.23, burn_damage=3, burn_ticks=3, burn_interval=0.28}),
    surface={name="CINDER", health=58, radius=8, scale={heat=0.55, burn=0.55}},
  },
  cryo = {
    behavior=Ranged.update, skin="cryo", weapon=12, speed=67, drop=12,
    notice_range=120, fire_range=33, retreat_range=24, windup=0.68, recovery=1.38,
    shot=enemy_shot(12, {damage=1, life=0.25, frost_time=1.28, frost_speed=0.74, shatter=10}),
    surface={name="CRYO TECH", health=47, radius=8, scale={frost=0.5}, light=true},
  },
}

Enemies.guide = {
  {"soldier","HANDGUN","MOVE OFF THE AIM POINT BEFORE THE SHOT"},
  {"runner","CLOSE STRIKE","STEP OUTSIDE THE ORANGE STRIKE RING"},
  {"rifleman","THREE-SHOT BURST","KEEP MOVING UNTIL THE BURST ENDS"},
  {"scatterguard","SHORT SPREAD","FIGHT BEYOND THE SPREAD"},
  {"lobber","AREA BLAST","LEAVE THE MARKED LANDING ZONE"},
  {"warden","FRONTAL SHIELD","SHOOT WHEN THE SHIELD DROPS OR USE ARC"},
  {"skirmisher","STRAFING PISTOL","CATCH IT WHILE IT STOPS TO AIM"},
  {"medic","HEALING SUPPORT","HIT DURING THE GREEN HEAL CUE"},
  {"bruiser","CHARGE","SIDESTEP THE LANE OR INTERRUPT WITH ARC"},
  {"marksman","LONG BEAM","LEAVE THE PINK LANE OR STEP BEHIND COVER"},
  {"cinder","FIRE SPRAY","STAY OUT OF THE SHORT SPRAY"},
  {"cryo","FROST SPRAY","STAY BACK TO AVOID THE SLOW AND SHATTER"},
}

function Enemies.profile(kind)
  return assert(profiles[kind], "Unknown enemy: " .. kind)
end

function Enemies.new(kind, x, y, direction)
  local profile = Enemies.profile(kind)
  return {
    profile=profile, surface=profile.surface, health=profile.surface.health,
    x=x, y=y, direction=direction, pose=1, walk=0, weapon=profile.weapon, flash=0, ready_at=0,
  }
end

function Enemies.update(game)
  for _, enemy in ipairs(game.enemies) do
    if enemy.health > 0 then
      if enemy.flash > 0 then
        enemy.flash, game.dirty = math.max(0, enemy.flash-game.dt), true
      end
      if not enemy.dormant then enemy.profile.behavior(game, enemy) end
      if game.health == 0 then return end
    end
  end
end

-- Keep packs readable at close range. Actors hold their ground through a windup.
function Enemies.separate(game)
  local enemies = game.enemies
  for i = 1, #enemies - 1 do
    local a = enemies[i]
    if a.health > 0 and not a.dormant then
      local fixed_a = a.fire_at or a.dash_left
      for j = i + 1, #enemies do
        local b = enemies[j]
        local fixed_b = b.fire_at or b.dash_left
        if b.health > 0 and not b.dormant and a.roof == b.roof and not (fixed_a and fixed_b) then
          local dx, dy = b.x - a.x, b.y - a.y
          local space = a.surface.radius + b.surface.radius
          local distance_sq = dx*dx + dy*dy
          if distance_sq < space*space then
            local distance = math.sqrt(distance_sq)
            local nx, ny = 1, 0
            if distance > 0 then nx, ny = dx/distance, dy/distance end
            local push = math.min(26*game.dt, space - distance)
            if not fixed_a then game:nudge_enemy(a, -nx*push, -ny*push) end
            if not fixed_b then game:nudge_enemy(b, nx*push, ny*push) end
          end
        end
      end
    end
  end
end

return Enemies
