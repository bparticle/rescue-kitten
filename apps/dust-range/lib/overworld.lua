local Pixels = require("lib.pixels")

local Overworld = {}
Overworld.__index = Overworld

-- Route coordinates are native map pixels. Bends belong to the leg arriving at each stop.
local stops = {
  {18,64},
  {47,63, {{27,64},{33,61},{42,61}}},
  {77,64, {{54,63},{60,66},{70,66}}},
  {111,63,{{86,64},{93,62},{104,62}}},
  {139,52,{{119,63},{125,60},{130,54}}},
  {113,37,{{134,51},{130,48},{126,43},{120,39}}},
  {82,39, {{103,39},{98,40},{90,39}}},
  {51,38, {{72,39},{66,37},{58,37}}},
  {26,24, {{43,36},{38,33},{33,33},{28,29}}},
  {67,18, {{34,25},{43,25},{53,21},{59,18}}},
}

local MAP_Y = 22
local INK, PANEL, EDGE = 0x262923, 0x34362d, 0x666b4e
local TEXT, DIM, CREAM = 0xf6e9d0, 0xbeb095, 0xf1d592
local GREEN, AMBER, LOCKED = 0xc7dc8c, 0xffc36d, 0x968d70
local STAR, STAR_EMPTY = 0xffc36d, 0x5c5442
local text = Pixels.text

local PACK_SIZE = 3

local function whole(value)
  return type(value) == "number" and math.tointeger(value) or nil
end

function Overworld.new(levels, store)
  local saved = store and store.get("mission_clears")
  local cleared = type(saved) == "table" and saved or {}
  local count = 0
  for _, level in ipairs(levels) do
    if cleared[level.id] == true then count = count + 1 end
  end
  -- Weapons picked up in missions, kept as a sorted list of weapon IDs.
  local kept, arsenal = store and store.get("arsenal"), {}
  if type(kept) == "table" then
    for _, id in ipairs(kept) do
      id = type(id) == "number" and math.tointeger(id)
      if id and id > 0 then arsenal[id] = true end
    end
  end
  -- Best score (s), best time in seconds (t) and earned star bits (k) per mission id.
  local stored, records = store and store.get("mission_records"), {}
  if type(stored) == "table" then
    for id, entry in pairs(stored) do
      if type(entry) == "table" then
        local s, t, k = whole(entry.s), whole(entry.t), whole(entry.k)
        if s and t and k then records[id] = {s=s, t=t, k=k} end
      end
    end
  end
  -- The weapon pack: up to PACK_SIZE arsenal weapons a mission starts with, 0 for an empty slot.
  -- With no saved pack, the newest weapons (highest ids) fill it.
  local saved_pack, pack, used = store and store.get("pack"), {}, {}
  for slot = 1, PACK_SIZE do
    local id = type(saved_pack) == "table" and whole(saved_pack[slot])
    if id and arsenal[id] and not used[id] then pack[slot], used[id] = id, true else pack[slot] = 0 end
  end
  if type(saved_pack) ~= "table" then
    local slot = 1
    for id = 99, 1, -1 do
      if arsenal[id] and slot <= PACK_SIZE then pack[slot], slot = id, slot + 1 end
    end
  end
  local self = setmetatable({levels=levels, store=store, cleared=cleared, count=count, arsenal=arsenal,
    records=records, pack=pack}, Overworld)
  self:count_stars()
  return self
end

Overworld.PACK_SIZE = PACK_SIZE

function Overworld:save_pack()
  if self.store then pcall(self.store.set, "pack", self.pack) end
end

-- The pack as a set ({[id]=true}) for Game.new.
function Overworld:pack_set()
  local set = {}
  for _, id in ipairs(self.pack) do
    if id > 0 and self.arsenal[id] then set[id] = true end
  end
  return set
end

-- True when the arsenal holds any weapon, so the briefing shows the pack.
function Overworld:has_arsenal()
  return next(self.arsenal) ~= nil
end

-- Steps a pack slot to the next (step 1) or previous (step -1) arsenal weapon that no other slot holds.
-- Empty (0) sits between the last and the first weapon.
function Overworld:cycle_pack(slot, step)
  local options, taken = {0}, {}
  for other, id in ipairs(self.pack) do
    if other ~= slot then taken[id] = true end
  end
  for id = 1, 99 do
    if self.arsenal[id] and not taken[id] then options[#options+1] = id end
  end
  local at = 1
  for index, id in ipairs(options) do
    if id == self.pack[slot] then at = index end
  end
  local id = options[(at - 1 + step) % #options + 1]
  if id == self.pack[slot] then return false end
  self.pack[slot] = id
  self:save_pack()
  return true
end

-- Earned stars for a mission as bits. A clear saved before stars existed still counts as one.
function Overworld:stars(index)
  local level = self.levels[index]
  local record = level and self.records[level.id]
  return (record and record.k or 0) | (level and self.cleared[level.id] == true and 1 or 0)
end

function Overworld:count_stars()
  local total = 0
  for index = 1, #self.levels do
    local stars = self:stars(index)
    total = total + (stars & 1) + (stars >> 1 & 1) + (stars >> 2 & 1)
  end
  self.star_count = total
end

-- Keeps the best score, the best time and every star earned so far.
-- Returns what this run improved: best_score, best_time and the newly earned star bits.
function Overworld:record(index, score, seconds, stars)
  local id = self.levels[index].id
  local old = self.records[id]
  local gained = stars & ~self:stars(index)
  local result = {
    first=old == nil, gained=gained,
    best_score=old ~= nil and score > old.s, best_time=old ~= nil and seconds < old.t,
  }
  self.records[id] = {
    s=old and math.max(old.s, score) or score, t=old and math.min(old.t, seconds) or seconds,
    k=(old and old.k or 0) | stars,
  }
  self:count_stars()
  if self.store then pcall(self.store.set, "mission_records", self.records) end
  return result
end

function Overworld:complete(index)
  local id = self.levels[index].id
  if self.cleared[id] == true then return end
  self.cleared[id] = true
  self.count = self.count + 1
  if self.store then pcall(self.store.set, "mission_clears", self.cleared) end
end

-- Adds weapons picked up in a mission (ids[first..last]) to the saved arsenal.
function Overworld:keep_weapons(ids, first, last)
  local added = false
  for index = first, last do
    local id = ids[index]
    if id and id > 0 and not self.arsenal[id] then self.arsenal[id], added = true, true end
  end
  if added and self.store then
    local list = {}
    for id in pairs(self.arsenal) do list[#list+1] = id end
    table.sort(list)
    pcall(self.store.set, "arsenal", list)
  end
  -- New weapons fill empty pack slots.
  if added then
    local packed, changed = {}, false
    for _, id in ipairs(self.pack) do packed[id] = true end
    for index = first, last do
      local id = ids[index]
      if id and id > 0 and not packed[id] then
        for slot = 1, PACK_SIZE do
          if self.pack[slot] == 0 then self.pack[slot], packed[id], changed = id, true, true; break end
        end
      end
    end
    if changed then self:save_pack() end
  end
  return added
end

function Overworld:next_mission()
  for index, level in ipairs(self.levels) do
    if self.cleared[level.id] ~= true then return index end
  end
end

-- The first mission is always open. Each clear opens the one after it, and cleared missions stay open.
function Overworld:unlocked(index)
  local level, before = self.levels[index], self.levels[index-1]
  if not level then return false end
  return index == 1 or self.cleared[level.id] == true or self.cleared[before.id] == true
end

local function right(c, value, x, y, color)
  text(c,value,x-6*#value+1,y,color)
end

local function position(point)
  return point[1]*2, MAP_Y+point[2]*2
end

local function segment(c, a, b, color, thickness)
  local ax, ay = position(a)
  local bx, by = position(b)
  local horizontal = math.abs(bx-ax) >= math.abs(by-ay)
  for offset = -thickness, thickness do
    local dx, dy = horizontal and 0 or offset, horizontal and offset or 0
    c:line(ax+dx,ay+dy,bx+dx,by+dy,color)
  end
end

local function trail(c, first, last, bends, color, width)
  local a = first
  if bends then
    for _, b in ipairs(bends) do
      segment(c,a,b,color,width)
      a = b
    end
  end
  segment(c,a,last,color,width)
end

local function marker(c, point, index, state, selected, stars)
  local x, y = position(point)
  local label = string.format("%02d",index)
  local w = #label*6 + 8
  local left, top = x-w//2, y-6
  c:rect(left+1,top+3,w,12,0x31362a)
  c:rect(left,top+1,w,11,INK)
  c:rect(left+2,top,w-4,13,INK)
  c:rect(left+2,top+2,w-4,9,state == "CLEARED" and GREEN or state == "NEXT" and AMBER
    or state == "LOCKED" and LOCKED or CREAM)
  text(c,label,x-#label*3+1,top+3,INK)
  if state == "LOCKED" then
    -- A small padlock on the marker's shoulder.
    c:rect(x+7,top-9,7,1,INK)
    c:rect(x+7,top-9,1,5,INK)
    c:rect(x+13,top-9,1,5,INK)
    c:rect(x+8,top-8,5,1,CREAM)
    c:rect(x+8,top-8,1,4,CREAM)
    c:rect(x+12,top-8,1,4,CREAM)
    c:rect(x+6,top-4,9,7,INK)
    c:rect(x+7,top-3,7,5,CREAM)
    c:rect(x+10,top-2,1,2,INK)
  end
  if stars > 0 then
    -- Three pips under the marker, lit for each star earned.
    c:rect(x-8,top+14,17,5,INK)
    for slot = 0, 2 do
      c:rect(x-7+slot*6,top+15,3,3,stars >> slot & 1 == 1 and STAR or STAR_EMPTY)
    end
  end
  if state == "CLEARED" then
    c:line(x+7,top-2,x+9,top,INK)
    c:line(x+9,top,x+13,top-4,INK)
    c:line(x+7,top-3,x+9,top-1,GREEN)
    c:line(x+9,top-1,x+13,top-5,GREEN)
  end
  if selected then
    local l, r = left-4, left+w+3
    for _, px in ipairs({l,r}) do
      local direction = px == l and 1 or -1
      for _, py in ipairs({top-4,top+16}) do
        c:line(px,py,px+direction*4,py,TEXT)
      end
      c:rect(px,top-3,1,4,TEXT)
      c:rect(px,top+12,1,4,TEXT)
    end
  end
end

local function compass(c)
  local x, y = 287, 47
  text(c,"N",x-2,y-13,CREAM)
  c:line(x-9,y,x+9,y,0x9d9f77)
  c:line(x,y-4,x,y+7,0x9d9f77)
  c:line(x-2,y+1,x,y-4,CREAM)
  c:line(x+2,y+1,x,y-4,CREAM)
end

function Overworld:draw(c, selected)
  local art = require("art.overworld")
  local region = (selected-1)//#stops
  local first = region*#stops+1
  local length = math.min(#stops,#self.levels-first+1)
  local regions = (#self.levels-1)//#stops+1
  local next_mission = self:next_mission()
  local terrain = region == 0 and art.main or art.frontier
  local selected_level = self.levels[selected]

  c:rect(0,MAP_Y,320,156,0x284951)
  Pixels.stamp(c,terrain.left,0,MAP_Y,2,terrain.colors)
  Pixels.stamp(c,terrain.right,160,MAP_Y,2,terrain.colors)

  for slot = 2, length do
    local a, b = stops[slot-1], stops[slot]
    local leading = first+slot-1 == next_mission or first+slot-2 == next_mission
    local walked = self.cleared[self.levels[first+slot-2].id] == true
      and self.cleared[self.levels[first+slot-1].id] == true
    trail(c,a,b,b[3],0x534b37,3)
    local open = self:unlocked(first+slot-1)
    trail(c,a,b,b[3],walked and 0xbac387 or not open and 0x857a5c or leading and CREAM or 0xb7a374,2)
  end
  if region > 0 then
    trail(c,{0,65},stops[1],{{9,65}},0x534b37,3)
    trail(c,{0,65},stops[1],{{9,65}},CREAM,2)
  end
  if region < regions-1 then
    trail(c,stops[length],{77,0},{{74,18},{77,13}},0x534b37,3)
    trail(c,stops[length],{77,0},{{74,18},{77,13}},CREAM,2)
  end

  -- Add planks where the trail crosses the river between Riverside and the maze.
  if length >= 6 then
    for i = 0, 4 do
      local x, y = 268-3*i, MAP_Y+102-3*i
      c:line(x-3,y+2,x+2,y-3,0x8e6849)
    end
  end
  compass(c)
  local selected_state
  for slot = 1, length do
    local index = first+slot-1
    local point, level = stops[slot], self.levels[index]
    local x, y = position(point)
    local landmark = art.landmarks[level.id] or art.landmarks.camp
    Pixels.stamp(c,landmark,x-26,y-32,2,art.landmarks.colors)
    local state = self.cleared[level.id] == true and "CLEARED" or not self:unlocked(index) and "LOCKED"
      or index == next_mission and "NEXT" or "UNPLAYED"
    marker(c,point,index,state,index == selected,self:stars(index))
    if index == selected then selected_state = state end
  end

  c:rect(0,0,320,MAP_Y,INK)
  c:rect(0,0,320,2,CREAM)
  c:rect(0,MAP_Y-1,320,1,EDGE)
  text(c,"MISSION MAP",8,5,CREAM,2)
  if regions > 1 then text(c,string.format("REGION %02d/%02d",region+1,regions),145,10,DIM) end
  local total = self.star_count.."/"..3*#self.levels
  Pixels.star(c,304,3,STAR)
  right(c,total,300,3,STAR)
  right(c,self.count.."/"..#self.levels.." CLEARED",311,13,TEXT)

  c:rect(0,178,320,40,INK)
  c:rect(0,178,320,1,EDGE)
  c:rect(8,183,23,14,PANEL)
  text(c,string.format("%02d",selected),13,187,CREAM)
  local title = selected_level.name:upper()
  if #title <= 16 then text(c,title,39,183,TEXT,2)
  else text(c,title:sub(1,33),39,187,TEXT) end
  local status_color = selected_state == "CLEARED" and GREEN or selected_state == "NEXT" and AMBER
    or selected_state == "LOCKED" and LOCKED or DIM
  local stars = self:stars(selected)
  if stars > 0 then
    for slot = 0, 2 do Pixels.star(c,284+slot*10,187,stars >> slot & 1 == 1 and STAR or STAR_EMPTY) end
  else
    right(c,selected_state == "NEXT" and "NEXT STOP" or selected_state,311,187,status_color)
  end
  c:rect(0,201,320,17,PANEL)
  c:rect(0,201,320,1,EDGE)
  text(c,"L/R ROUTE",8,207,CREAM)
  text(c,"UP RANGE  DOWN SPECS",74,207,DIM)
  if selected_state == "LOCKED" then
    right(c,string.format("CLEAR %02d FIRST",selected-1),311,207,LOCKED)
  else
    right(c,"SELECT OPEN",311,207,TEXT)
  end
end

return Overworld
