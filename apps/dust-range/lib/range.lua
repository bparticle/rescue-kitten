local Range = {}

-- Damage, distances, and timing are tuned for the badge playfield.
-- led_slot groups the 15 weapons onto the six top LEDs by family.
Range.weapons = {
  { name="Handgun", art="handgun", kind="bullet", effect="impact", lane="EAST", test="board",
    damage=18, speed=380, life=0.31, delay=0.145, muzzle=8, offset=3 },
  { name="Assault rifle", art="assault-rifle", kind="bullet", effect="impact", lane="NORTH", test="steel",
    damage=32, speed=440, life=0.34, delay=0.075, muzzle=10, offset=3, hold=true },
  { name="Pump shotgun", art="pump-shotgun", kind="pellet", effect="spread", lane="WEST", test="pattern",
    damage=12, count=5, spread=0.105, min_damage=0.45,
    speed=310, life=0.20, delay=0.32, muzzle=10, offset=3 },
  { name="Grenade", art="grenade", kind="grenade", effect="blast", lane="NORTH", test="marker", test_count=3,
    damage=70, radius=36, min_damage=0.25,
    speed=89, life=0.41, delay=0.96, muzzle=4, offset=5 },
  { name="Rocket launcher", art="rocket-launcher", kind="rocket", effect="blast", lane="EAST", test="block",
    damage=82, direct=54, radius=28, min_damage=0.25,
    speed=170, life=0.54, delay=0.44, muzzle=10, offset=5 },
  { name="Flamethrower", art="flamethrower", kind="flame", effect="heat", lane="WEST", test="cloth",
    damage=3, count=3, spread=0.105, burn_damage=5, burn_ticks=4, burn_interval=0.30,
    speed=128, life=0.20, delay=0.060, muzzle=10, offset=4, hold=true },
  { name="TNT", art="tnt", kind="tnt", effect="blast", lane="SOUTH", test="block", led_slot=4,
    test_count=2, test_title="2 BLOCKS",
    damage=120, radius=47, min_damage=0.20, speed=0, life=1.6, delay=0.55 },
  { name="Rail rifle", art="rail-rifle", kind="rail", effect="pierce", lane="EAST", test="plank", led_slot=2,
    test_count=3, damage=40, pierce=0.8, speed=520, life=0.34, delay=0.62, muzzle=11, offset=3 },
  { name="Bankshot", art="bankshot", kind="bank", effect="impact", lane="EAST", test="offset", led_slot=1,
    test_title="OFFSET PLATE", damage=22, bank_bonus=1.5,
    speed=300, life=0.55, delay=0.30, muzzle=7, offset=3 },
  { name="Boomerang disc", art="boomerang-disc", kind="disc", effect="slash", lane="WEST", test="post",
    led_slot=4, damage=24, return_speed=1.25, speed=170, life=0.42, delay=0.25, muzzle=6, offset=4 },
  { name="Arc projector", art="arc-projector", kind="arc", effect="shock", lane="EAST", test="node",
    led_slot=6, test_count=3, damage=28, chain=2, chain_range=42, chain_damage=0.7,
    speed=600, life=0.16, delay=0.42, muzzle=10, offset=3 },
  { name="Cryo sprayer", art="cryo-sprayer", kind="frost", effect="frost", lane="SOUTH", test="dummy",
    led_slot=6, damage=2, count=3, spread=0.12, frost_time=4.0, shatter=30,
    speed=120, life=0.22, delay=0.070, muzzle=9, offset=3, hold=true },
  { name="Charge cannon", art="charge-cannon", kind="charge", effect="energy", lane="NORTH", test="bulwark",
    led_slot=5, damage=90, min_charge=0.2, charge_time=1.0, splash=14,
    speed=240, life=0.50, delay=0.35, muzzle=11, offset=3 },
  { name="Gravity orb", art="gravity-orb", kind="orb", effect="gravity", lane="WEST", test="crate",
    led_slot=5, test_count=3, damage=18, pull=34, pull_speed=46, well_time=1.5, collapse=16,
    speed=130, life=0.46, delay=0.50, muzzle=7, offset=3 },
  { name="Shock hammer", art="shock-hammer", kind="hammer", effect="smash", lane="SOUTH", test="pad",
    led_slot=3, test_count=2, damage=34, reach=20, arc=75, knockback=24,
    speed=0, life=0, delay=0.45, muzzle=8, offset=0 },
}

Range.surfaces = {
  board   = { name="BOARD",   health=70,  radius=8,  scale={} },
  steel   = { name="STEEL",   health=110, radius=8,  scale={impact=0.55, spread=0.45, heat=0.30, burn=0.30,
    pierce=0.8, smash=0.6} },
  pattern = { name="PATTERN", title="PATTERN BOARD", health=90, radius=13, scale={} },
  marker  = { name="MARKER",  title="3 MARKERS", health=85, radius=6, scale={}, light=true },
  block   = { name="BLOCK",   health=155, radius=10, scale={impact=0.45, spread=0.35, heat=0.35, burn=0.35,
    smash=0.5} },
  cloth   = { name="CLOTH",   title="CLOTH SCREEN", health=55, radius=9, scale={heat=1.5, burn=1.5} },
  plank   = { name="PLANK",   title="3 PLANKS", health=60, radius=6, scale={} },
  offset  = { name="OFFSET",  title="OFFSET PLATE", health=70, radius=7, scale={} },
  post    = { name="POST",    health=75,  radius=6,  scale={} },
  node    = { name="NODE",    title="3 NODES", health=65, radius=6, scale={} },
  dummy   = { name="DUMMY",   title="FROST DUMMY", health=95, radius=8, scale={} },
  bulwark = { name="BULWARK", health=200, radius=11, scale={impact=0.5, spread=0.4, heat=0.4, burn=0.4,
    energy=1.25} },
  crate   = { name="CRATE",   title="3 CRATES", health=60, radius=6, scale={}, light=true },
  pad     = { name="PAD",     title="2 PADS", health=70, radius=6, scale={}, light=true },
}

-- Animated effect sheets in art/fx-<weapon>.lua: module, frame count, frames per second.
Range.effects = {
  ["rail-muzzle"]={"rail-rifle",4,30}, ["rail-beam"]={"rail-rifle",4,24}, ["rail-pierce"]={"rail-rifle",5,24},
  ["bank-muzzle"]={"bankshot",3,30}, ["bank-ricochet"]={"bankshot",5,24}, ["bank-impact"]={"bankshot",4,24},
  ["disc-throw"]={"boomerang-disc",3,24}, ["disc-hit"]={"boomerang-disc",4,24},
  ["disc-catch"]={"boomerang-disc",3,20},
  ["arc-muzzle"]={"arc-projector",3,30}, ["arc-zap"]={"arc-projector",4,24},
  ["cryo-muzzle"]={"cryo-sprayer",3,30}, ["frost-shatter"]={"cryo-sprayer",6,24},
  ["charge-release"]={"charge-cannon",3,30}, ["charge-impact"]={"charge-cannon",6,24},
  ["orb-launch"]={"gravity-orb",3,24}, ["well-collapse"]={"gravity-orb",5,20},
  ["hammer-swing"]={"shock-hammer",4,30}, ["hammer-shock"]={"shock-hammer",5,24},
  ["knock-skid"]={"shock-hammer",3,18},
  -- Looping sheets the view plays directly.
  ["bank-round"]={"bankshot",2,20}, reflector={"bankshot",3,12}, ["disc-spin"]={"boomerang-disc",4,20},
  ["arc-bolt"]={"arc-projector",3,20}, ["cryo-puff"]={"cryo-sprayer",3,54}, ["frost-coat"]={"cryo-sprayer",4,8},
  ["charge-orb"]={"charge-cannon",6,12}, ["charge-bolt-low"]={"charge-cannon",2,20},
  ["charge-bolt-full"]={"charge-cannon",4,20}, ["orb-shot"]={"gravity-orb",4,16},
  ["gravity-well"]={"gravity-orb",6,12},
}
Range.muzzle_effects = {
  rail="rail-muzzle", bank="bank-muzzle", disc="disc-throw", arc="arc-muzzle",
  frost="cryo-muzzle", charge="charge-release", orb="orb-launch",
}

-- Offsets from the start point. A fourth value hides the label on a cluster.
function Range.targets(x, y)
  local layout = {
    {113, 3, "board"}, {125, -105, "steel"}, {-151, 60, "pattern"},
    {-44, -101, "marker"}, {-73, -104, "marker"}, {-14, -103, "marker"},
    {273, 74, "block"}, {-221, -86, "cloth"},
    {29, 157, "block"}, {71, 157, "block"},
    {290, -170, "plank"}, {320, -170, "plank", true}, {350, -170, "plank", true},
    {-240, 85, "offset"},
    {-385, -10, "post"},
    {345, 200, "node"}, {367, 172, "node", true}, {367, 228, "node", true},
    {-110, 280, "dummy"},
    {40, -268, "bulwark"},
    {-397, 222, "crate"}, {-422, 262, "crate", true}, {-375, 268, "crate", true},
    {370, -12, "pad"}, {392, -12, "pad", true},
  }
  local targets = {}
  for id, spot in ipairs(layout) do
    local surface = Range.surfaces[spot[3]]
    local tx, ty = x+spot[1], y+spot[2]
    targets[id] = {x=tx, y=ty, home_x=tx, home_y=ty, kind=spot[3], surface=surface,
      health=surface.health, marks={}, label=not spot[4] and spot[3] ~= "marker"}
  end
  return targets
end

-- Angled plates for the bankshot. "/" turns an eastbound round north.
function Range.reflectors(x, y)
  local d = 1 / math.sqrt(2)
  return { {x=x-240, y=y+120, slope="/", ux=d, uy=-d} }
end

-- Supply caches, in weapon order.
function Range.pickups(x, y)
  local spots = {
    {54, 0}, {123, -59}, {-78, 58}, {-49, -63}, {206, 70}, {-180, -88}, {50, 103},
    {250, -170}, {-300, 120}, {-340, -10}, {300, 200}, {-110, 230}, {40, -230}, {-330, 250}, {380, -40},
  }
  local pickups = {}
  for id, spot in ipairs(spots) do pickups[id] = {x=x+spot[1], y=y+spot[2], id=id} end
  return pickups
end

return Range
