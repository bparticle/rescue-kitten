local Endless = {}
local floor, min = math.floor, math.min
local MAX_ROSTER = 14

local units = {
  {kind="soldier", cost=2, limit=2},
  {kind="runner", cost=1, limit=2},
  {kind="rifleman", cost=3, limit=2},
  {kind="scatterguard", cost=3, limit=2},
  {kind="lobber", cost=4, limit=1},
  {kind="warden", cost=4, limit=2},
  {kind="skirmisher", cost=2, limit=2},
  {kind="medic", cost=3, limit=1},
  {kind="bruiser", cost=5, limit=1},
  {kind="marksman", cost=4, limit=1, first_wave=4},
  {kind="cinder", cost=4, limit=1, first_wave=5},
  {kind="cryo", cost=4, limit=1, first_wave=7},
}

function Endless.roster(wave, roll, slot_count)
  local budget = 9 + 2*min(wave-1, 14)
  if wave > 5 then budget = budget - floor(roll()*6) end
  local open, choices, counts, roster = {}, {}, {}, {}
  while budget > 0 and #roster < MAX_ROSTER do
    if #open == 0 then
      for slot = 1, slot_count do open[slot] = slot end
    end
    local count = 0
    for _, unit in ipairs(units) do
      if unit.cost <= budget and wave >= (unit.first_wave or 1) and (counts[unit.kind] or 0) < unit.limit then
        count = count + 1
        choices[count] = unit
      end
    end
    if count == 0 then break end

    local unit = choices[1+floor(roll()*count)]
    local last = #open
    local slot = 1+floor(roll()*last)
    roster[#roster+1] = {unit.kind, open[slot]}
    counts[unit.kind] = (counts[unit.kind] or 0) + 1
    open[slot] = open[last]
    open[last] = nil
    budget = budget - unit.cost
  end
  return roster
end

return Endless
