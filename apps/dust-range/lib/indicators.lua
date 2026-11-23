local Range = require("lib.range")

local Indicators = {}
Indicators.__index = Indicators

local abs, floor, min, max = math.abs, math.floor, math.min, math.max
local TOP_SLOTS, HIT_STAGGER, HIT_HOLD, HIT_FADE, PICKUP_FADE = 6, 0.035, 0.045, 0.19, 0.28

local function gear_slot(id)
  local weapon = Range.weapons[id]
  return weapon and (weapon.led_slot or id)
end

function Indicators.new()
  if not led or not led.set then return end
  local total = min(8, led.count or TOP_SLOTS)
  return setmetatable({
    count=min(TOP_SLOTS,total), total=total,
    colors={}, hits=0, found=0,
  }, Indicators)
end

function Indicators:set(slot, r, g, b)
  local color = (r << 16) | (g << 8) | b
  if self.colors[slot] == color then return end
  led.set(slot,r,g,b)
  self.colors[slot] = color
end

function Indicators:clear()
  self.held = nil
  for slot = 1, self.total do self:set(slot,0,0,0) end
end

function Indicators:show_spec(selected)
  self.held = nil
  local active = gear_slot(selected)
  for slot = 1, self.total do
    if slot == active then self:set(slot,106,56,12)
    else self:set(slot,0,0,0) end
  end
end

local function mix(from, to, amount)
  return floor(from+(to-from)*amount+0.5)
end

function Indicators:update(game)
  if self.game ~= game then
    self.game, self.hits, self.found = game, game.hits, game.found
    self.held, self.hit_at, self.pickup_at = nil, nil, nil
  end
  if game.result then
    self:clear()
    return
  end
  for slot = TOP_SLOTS+1, self.total do self:set(slot,game.hurt_until and 126 or 0,0,0) end
  if self.hits ~= game.hits then
    self.hits, self.hit_at = game.hits, game.time
  end
  if self.found ~= game.found then
    self.found, self.pickup_at, self.pickup_slot = game.found, game.time, gear_slot(game.weapon)
  end

  local held = game:held_weapon()
  if held == self.held and not self.hit_at and not self.pickup_at then return end
  self.held = held
  local active = gear_slot(held)
  local owned_slots = {}
  for id = 1, #Range.weapons do
    if game.owned[id] then owned_slots[gear_slot(id)] = true end
  end
  local hit_age = game.time - (self.hit_at or -math.huge)
  local pickup_age = game.time - (self.pickup_at or -math.huge)
  local last_delay = ((self.count-1)//2)*HIT_STAGGER
  if hit_age >= last_delay+HIT_HOLD+HIT_FADE then self.hit_at = nil end
  if pickup_age >= PICKUP_FADE then self.pickup_at = nil end

  for slot = 1, self.count do
    local r,g,b = 0,0,0
    if slot == active then
      r,g,b = 106,56,12
    elseif owned_slots[slot] then
      r,g,b = 30,14,3
    end
    if self.pickup_at and slot == self.pickup_slot then
      local gold = 1-pickup_age/PICKUP_FADE
      r,g,b = mix(r,178,gold),mix(g,114,gold),mix(b,34,gold)
    end

    -- The middle pair lights up on the hit tick, then the red pulse travels outward.
    local age = hit_age-floor(abs(slot-(self.count+1)/2))*HIT_STAGGER
    if age >= 0 and age < HIT_HOLD+HIT_FADE then
      local red = 1-max(0,age-HIT_HOLD)/HIT_FADE
      r,g,b = mix(r,192,red),mix(g,9,red),mix(b,4,red)
    end
    self:set(slot,r,g,b)
  end
end

return Indicators
