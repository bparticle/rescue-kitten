local Range = require("lib.range")
local Pixels = require("lib.pixels")
local palette = require("art.palette")
local terrain = require("art.terrain")
local icons = require("art.icons")

local Menu = {}
Menu.__index = Menu
-- Every pause menu has the same entries in the same order. Entries that don't apply are left out:
-- Retry only in a mission or practice, Testing Range only away from it, Mission Map only with levels.
local option_lists = {}
function Menu.options(drill, has_levels)
  local key = tostring(drill) .. tostring(has_levels)
  local options = option_lists[key]
  if options then return options end
  options = {{"resume", drill and "RESUME" or "RESUME RANGE"}}
  if drill then options[#options+1] = {"drill", drill == "level" and "RETRY MISSION" or "RETRY"} end
  if has_levels then options[#options+1] = {"missions", "MISSION MAP"} end
  if drill then options[#options+1] = {"range", "TESTING RANGE"} end
  options[#options+1] = {"specs", "WEAPON SPECS"}
  options[#options+1] = {"exit", "EXIT GAME"}
  option_lists[key] = options
  return options
end

local text, stamp = Pixels.text, Pixels.stamp
local INK, PANEL, BORDER = 0x262320, 0x343029, 0x655840
local BRASS, TEXT, DIM = 0xecd590, 0xf6e9d0, 0xbeb095
local PLATE, GRID = 0x655e4b, 0x766d55
local effects = {
  impact = {name="IMPACT", color=0xe3be78},
  spread = {name="SPREAD", color=0xf0bc83},
  blast = {name="BLAST", color=0xf3a279},
  heat = {name="HEAT", color=0xe9a26b},
  pierce = {name="PIERCE", color=0x9fe3e0},
  slash = {name="SLASH", color=0xe2c890},
  shock = {name="SHOCK", color=0xbaf6e6},
  frost = {name="FROST", color=0xcdecff},
  energy = {name="ENERGY", color=0xffbf6e},
  gravity = {name="GRAVITY", color=0xc9b1ee},
  smash = {name="SMASH", color=0x95d6de},
}

local function right(c, value, x, y, color)
  text(c, value, x - (6*#value - 1), y, color)
end

local function frame(c, hint, back)
  c:rect(0,0,320,218,INK)
  c:rect(0,0,320,3,BRASS)
  c:rect(0,197,320,21,PANEL)
  c:rect(0,197,320,1,BORDER)
  text(c,hint,14,205,TEXT)
  right(c,back,306,205,DIM)
end

function Menu.new()
  return setmetatable({}, Menu)
end

function Menu:open()
  if not self.canvas then self.canvas = ui.canvas(0,0,320,218,{scale=1}) end
  self.canvas:show(true)
end

function Menu:close()
  self.canvas:show(false)
end

-- Split a briefing into lines of at most width characters at spaces.
local function wrap(value, width)
  local lines, line = {}, ""
  for word in value:gmatch("%S+") do
    if line ~= "" and #line + 1 + #word > width then
      lines[#lines+1], line = line, word
    else
      line = line == "" and word or line .. " " .. word
    end
  end
  if line ~= "" then lines[#lines+1] = line end
  return lines
end

local menu_rows = {[3]={36,28}, [4]={32,26}, [5]={25,21}, [6]={22,18}, [7]={18,16}}

function Menu:draw_pause(choice, game, hero, has_levels, pickup_motion)
  local c = self.canvas
  frame(c, "UP/DOWN MOVE  SELECT OPEN", "CANCEL RESUME")
  text(c,"DUSTPAW",14,19,BRASS,3)
  local title = game.drill and "DRILL PAUSED" or "RANGE PAUSED"
  if game.mission then title = "MISSION PAUSED" end
  if game.practice then title = "PRACTICE PAUSED" end
  right(c,title,306,29,DIM)
  c:rect(14,53,292,1,BORDER)

  local options = Menu.options(game.drill, has_levels)
  local spacing, height = table.unpack(menu_rows[#options])
  for index, option in ipairs(options) do
    local y = 65 + (index-1)*spacing
    local selected = index == choice
    c:rect(14,y+2,174,height,0x1d1a17)
    c:rect(14,y,174,height,selected and BRASS or PANEL)
    c:rect(14,y,3,height,selected and 0xb5744e or BORDER)
    if selected then text(c,">",21,y+(height-7)//2,INK) end
    text(c,option[2],29,y+(height-14)//2,selected and INK or TEXT,2)
  end

  c:rect(198,65,108,112,BORDER)
  c:rect(199,66,106,110,palette.ground)
  for row = 0, 2 do
    for col = 0, 2 do
      stamp(c,terrain[1+((row*3+col)*5)%#terrain],204+col*32,70+row*32,2)
    end
  end
  c:rect(236,136,30,7,0x7b6b57)
  stamp(c,hero,210,81,3)
  c:rect(199,161,106,15,INK)
  local caption = game.drill and "HP " .. game.health or "GEAR "..game.found.."/"..#Range.weapons
  text(c,caption,250-#caption*3,165,BRASS)
  text(c,pickup_motion and "L/R MOTION ON" or "L/R MOTION OFF",201,183,DIM)
end

local function percent(scale)
  return math.floor(scale*100+0.5).."%"
end

local function seconds(value)
  return string.format("%.1fS", value)
end

local function notes(weapon, surface)
  local kind = weapon.kind
  if kind == "rail" then
    return "PIERCES EVERY TARGET ON THE LINE",
      "EACH TARGET AFTER THE FIRST TAKES "..percent(weapon.pierce),
      "LINE UP ALL THREE PLANKS FOR ONE SHOT"
  elseif kind == "bank" then
    return "RICOCHETS OFF THE ANGLED REFLECTOR",
      "+"..percent(weapon.bank_bonus-1).." DAMAGE AFTER A BOUNCE",
      "AIM AT THE REFLECTOR TO HIT THE PLATE"
  elseif kind == "disc" then
    return "HITS ON THE WAY OUT AND ON THE RETURN",
      "CATCH THE DISC BEFORE THROWING AGAIN",
      "STAND IN LINE WITH THE POST"
  elseif kind == "arc" then
    return "CHAINS TO "..weapon.chain.." TARGETS WITHIN "..weapon.chain_range.." PX",
      "CHAINED TARGETS TAKE "..percent(weapon.chain_damage),
      "HIT THE FRONT NODE TO REACH ALL THREE"
  elseif kind == "frost" then
    return "HOLD SELECT TO COAT TARGETS IN FROST",
      "ANY OTHER HIT SHATTERS IT FOR +"..weapon.shatter,
      "FROST LASTS "..seconds(weapon.frost_time)
  elseif kind == "charge" then
    return "HOLD SELECT TO CHARGE. RELEASE TO FIRE",
      "FULL CHARGE IN "..seconds(weapon.charge_time).." SPLASHES "..weapon.splash.." PX",
      "BULWARK TAKES "..percent(surface.scale.energy).." ENERGY DAMAGE"
  elseif kind == "orb" then
    return "OPENS A WELL WHERE THE ORB STOPS",
      "PULLS LIGHT TARGETS WITHIN "..weapon.pull.." PX",
      "COLLAPSES AFTER "..seconds(weapon.well_time).." FOR "..weapon.damage.." DAMAGE"
  elseif kind == "hammer" then
    return "SWEEPS A "..(2*weapon.arc).." DEGREE ARC IN FRONT OF YOU",
      "KNOCKS LIGHT TARGETS BACK "..weapon.knockback.." PX",
      "STAND NEXT TO THE PADS AND SWING"
  elseif kind == "bullet" then
    if weapon.hold then
      return "HOLD SELECT FOR REPEATED IMPACTS",
        "STEEL TAKES "..percent(surface.scale.impact).." IMPACT DAMAGE"
    end
    return "LEAVES ONE IMPACT MARK PER SHOT"
  elseif weapon.kind == "pellet" then
    return "PELLETS SPREAD FARTHER APART AS THEY TRAVEL",
      "PELLET DAMAGE FALLS TO "..percent(weapon.min_damage).." AT MAX TRAVEL"
  elseif weapon.radius then
    local falloff = "BLAST FALLS TO "..percent(weapon.min_damage).." AT THE EDGE"
    if weapon.kind == "tnt" then
      return "SELECT DROPS TNT AT YOUR FEET", falloff, "PLANT BETWEEN THE BLOCKS AND BACK AWAY"
    end
    if weapon.direct then
      return "+"..weapon.direct.." DAMAGE ON A DIRECT HIT", falloff,
        "BLOCK TAKES "..percent(surface.scale.impact).." IMPACT DAMAGE"
    end
    return "DETONATES AT THE END OF THE THROW", falloff, "LEAVES A BLACK SCORCH PATCH"
  end
  return string.format("%d BURN TICKS OF %d DAMAGE OVER %.1fS",
      weapon.burn_ticks, weapon.burn_damage, weapon.burn_ticks*weapon.burn_interval),
    "FRESH HEAT REFRESHES THE BURN",
    "CLOTH TAKES "..percent(surface.scale.burn).." HEAT AND BURN DAMAGE"
end

local function spec_row(c, label, value, y)
  text(c,label,155,y,DIM)
  right(c,value,306,y,TEXT)
  c:rect(155,y+12,151,1,BORDER)
end

function Menu:draw_specs(page)
  local c = self.canvas
  local weapon, art = Range.weapons[page], icons[page]
  local effect = effects[weapon.effect]
  local surface = Range.surfaces[weapon.test]
  frame(c, "< >  BROWSE    SELECT NEXT", "CANCEL MENU")
  text(c,"WEAPON SPECS",14,13,BRASS)
  text(c,"DOWN ENEMIES",168,13,DIM)
  right(c,string.format("%02d/%02d",page,#Range.weapons),306,13,DIM)
  text(c,weapon.name:upper(),14,29,TEXT,2)
  right(c,effect.name,306,33,effect.color)
  c:rect(14,49,292,1,BORDER)

  c:rect(14,58,126,74,BORDER)
  c:rect(15,59,124,72,PLATE)
  for x = 22, 133, 11 do c:rect(x,59,1,72,GRID) end
  for y = 62, 130, 11 do c:rect(15,y,124,1,GRID) end
  c:rect(14,58,15,2,effect.color)
  c:rect(125,130,15,2,effect.color)
  stamp(c,art[3],77 - (art[1]*3)//2,95 - (art[2]*3)//2,3)

  local damage = tostring(weapon.damage)
  if weapon.count then damage = damage.." X "..weapon.count end
  if weapon.radius or weapon.min_damage then damage = "MAX "..damage end
  if weapon.min_charge then
    damage = math.floor(weapon.damage*weapon.min_charge+0.5).."-"..weapon.damage
  end
  spec_row(c,"DAMAGE PTS",damage,59)
  if weapon.kind == "tnt" then
    spec_row(c,"FUSE",string.format("%.1f S",weapon.life),78)
  elseif weapon.reach then
    spec_row(c,"REACH",weapon.reach.." PX",78)
  else
    spec_row(c,"TRAVEL",math.floor(weapon.speed*weapon.life+0.5).." PX",78)
  end
  spec_row(c,"COOLDOWN",math.floor(1000*weapon.delay+0.5).." MS",97)
  if weapon.radius then
    spec_row(c,"BLAST RADIUS",weapon.radius.." PX",116)
  elseif weapon.pull then
    spec_row(c,"PULL RADIUS",weapon.pull.." PX",116)
  elseif weapon.chain then
    spec_row(c,"CHAIN RANGE",weapon.chain_range.." PX",116)
  elseif weapon.min_charge then
    spec_row(c,"FIRE MODE","HOLD+RELEASE",116)
  else
    spec_row(c,"FIRE MODE",weapon.hold and "HOLD" or "TAP",116)
  end

  local first, second, third = notes(weapon, surface)
  text(c,first,14,141,TEXT)
  if second then text(c,second,14,151,DIM) end
  if third then text(c,third,14,161,DIM) end
  local health = surface.health.." HP"..(weapon.test_count and " EACH" or "")
  local label = weapon.test_title or surface.title or surface.name
  c:rect(14,174,292,16,PANEL)
  c:rect(14,174,3,16,effect.color)
  text(c,weapon.lane.." / "..label,23,179,BRASS)
  right(c,health,298,179,DIM)
end

function Menu:draw_enemy(page, count, entry, profile, art, colors)
  local c = self.canvas
  frame(c,"< >  BROWSE    SELECT PRACTICE","CANCEL MENU")
  text(c,"ENEMY FIELD GUIDE",14,13,BRASS)
  text(c,"UP WEAPONS",168,13,DIM)
  right(c,string.format("%02d/%02d",page,count),306,13,DIM)
  text(c,profile.surface.name,14,29,TEXT,2)
  c:rect(14,49,292,1,BORDER)

  c:rect(14,59,129,102,BORDER)
  c:rect(15,60,127,100,PLATE)
  for x = 20, 135, 11 do c:rect(x,60,1,100,GRID) end
  for y = 66, 150, 11 do c:rect(15,y,127,1,GRID) end
  c:rect(60,127,32,5,0x39362f)
  stamp(c,art,36,66,3,colors)

  spec_row(c,"ROLE",entry[2],64)
  spec_row(c,"HEALTH",profile.surface.health.." HP",84)
  spec_row(c,"AIM TIME",seconds(profile.heal_windup or profile.windup),104)
  c:rect(14,172,292,18,PANEL)
  c:rect(14,172,3,18,BRASS)
  text(c,entry[3],23,178,TEXT)
end

local objectives = {
  clear={"CLEAR ALL", "DEFEAT EVERY WAVE"},
  exit={"REACH EXIT", "MAKE IT TO THE EXIT"},
  ["clear-exit"]={"CLEAR + EXIT", "DEFEAT EVERY WAVE", "THEN REACH THE EXIT"},
  ["rescue-kitten"]={"RESCUE KITTEN", "WALK UP TO THE KITTEN", "CARRY IT TO THE EXIT"},
}

-- Returns true when the screen needs another call with rest = true to finish drawing.
-- Star goals under the briefing panel: each star lights up once earned.
local function star_goals(c, level, stars, y)
  local Mission = require("lib.mission")
  local goals = {
    {Mission.STAR_CLEAR, level.objective == "rescue-kitten" and "RESCUE" or "CLEAR"},
    {Mission.STAR_PAR, level.par and "PAR " .. level.par .. "S" or "NO PAR"},
    {Mission.STAR_HEALTH, "LOSE " .. Mission.damage_limit(level.health) .. " HP OR LESS"},
  }
  local x = 18
  for _, goal in ipairs(goals) do
    local earned = stars & goal[1] ~= 0
    Pixels.star(c,x,y,earned and 0xffc36d or 0x6b624c)
    text(c,goal[2],x+11,y,earned and TEXT or DIM)
    x = x + 11 + 6*#goal[2] + 16
  end
end

-- The weapon pack beside the briefing: one row per slot, the chosen slot outlined, its weapon named below.
local function draw_pack(c, pack, slot)
  c:rect(201,97,92,75,0x444738)
  text(c,"PACK",206,101,DIM)
  right(c,slot .. "/" .. #pack,288,101,DIM)
  for row, id in ipairs(pack) do
    local y = 111 + (row-1)*17
    local chosen = row == slot
    c:rect(205,y,84,15,chosen and BRASS or 0x5a5c48)
    c:rect(206,y+1,82,13,chosen and 0x5d5a45 or 0x3a3c30)
    local art = icons[id]
    if art then stamp(c,art[3],247-art[1]//2,y+7-art[2]//2,1)
    else text(c,"EMPTY",233,y+4,0x7b745e) end
  end
  local weapon = Range.weapons[pack[slot]]
  local name = weapon and weapon.name:upper() or "NO WEAPON"
  text(c,name,247-(6*#name-1)//2,163,weapon and TEXT or DIM)
end

-- record: the saved best for this mission ({s=score, t=seconds}) or nil. stars: earned star bits.
-- pack: the weapon pack (slot ids, 0 for empty) when the player has kept weapons; slot: the chosen slot.
function Menu:draw_briefing(level, index, rest, record, stars, pack, slot)
  stars = stars or 0
  local c = self.canvas
  local goal = objectives[level.objective] or objectives.clear
  local rescue = level.objective == "rescue-kitten"
  if rescue and index == 1 then
    local title = require("art.rescue-title")
    -- Each half of the title art is about 2,000 rects, so the halves draw on consecutive ticks.
    if rest then
      stamp(c,title.right,160,0,2,title.colors)
      return false
    end
    frame(c,"SELECT START", "CANCEL MAP")
    c:rect(0,0,320,176,title.background)
    stamp(c,title.left,0,0,2,title.colors)
    c:rect(0,176,320,21,INK)
    c:rect(0,176,320,1,BORDER)
    text(c,goal[1],14,180,BRASS,2)
    text(c,goal[2],181,179,TEXT)
    text(c,goal[3],181,188,TEXT)
    return true
  end
  frame(c,pack and "SELECT START  U/D L/R PACK" or "SELECT START", "CANCEL MAP")

  if record then text(c,"BEST " .. record.s .. "  " .. record.t .. "S",18,18,BRASS)
  else text(c,"DUSTPAW",18,18,DIM) end
  right(c,string.format("MISSION %02d",index),302,18,BRASS)
  c:rect(18,34,284,1,BORDER)

  local title = level.name:upper()
  local scale = #title <= 15 and 3 or #title <= 23 and 2 or 1
  text(c,title,18,52,BRASS,scale)
  c:rect(18,89,284,91,PANEL)
  c:rect(18,89,3,91,rescue and 0xb4cc92 or BRASS)
  text(c,"OBJECTIVE",32,100,DIM)
  text(c,goal[2],32,114,TEXT)
  if goal[3] then text(c,goal[3],32,126,TEXT) end
  if level.brief then
    for line_index, line in ipairs(wrap(level.brief, (rescue or pack) and 27 or 44)) do
      if line_index > 2 then break end
      text(c,line,32,136+line_index*12,BRASS)
    end
  end
  if pack then
    draw_pack(c,pack,slot)
  elseif rescue then
    local kitten = require("art.kitten")
    c:rect(201,97,92,75,0x444738)
    for x = 205, 289, 12 do c:rect(x,101,1,67,0x4f5342) end
    for y = 107, 167, 12 do c:rect(205,y,85,1,0x4f5342) end
    c:rect(220,153,52,8,0x35382d)
    c:rect(228,150,36,14,0x35382d)
    stamp(c,kitten.art,247-(kitten.w*4)//2,108,4,kitten.colors)
  end
  star_goals(c,level,stars,185)
end

return Menu
