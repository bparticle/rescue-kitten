-- Native-pixel silhouettes. Periods leave the terrain visible between the flames.
local Effects = {}
local min, abs, byte = math.min, math.abs, string.byte

local function sprite(rows, colors, turns)
  local by_byte = {}
  for symbol, color in pairs(colors) do by_byte[byte(symbol)] = color end
  local runs = {}
  local center_x, center_y = #rows[1]//2, #rows//2
  for row, pixels in ipairs(rows) do
    local width, column = #pixels, 1
    while column <= width do
      local symbol = byte(pixels, column)
      local after = column + 1
      while after <= width and byte(pixels, after) == symbol do after = after + 1 end
      local color = by_byte[symbol]
      if color then
        local x1, y1 = column-1-center_x, row-1-center_y
        local x2, y2 = after-2-center_x, y1
        for _ = 1, turns or 0 do x1,y1,x2,y2 = -y1,x1,-y2,x2 end
        runs[#runs+1] = {min(x1,x2),min(y1,y2),abs(x2-x1)+1,abs(y2-y1)+1,color}
      end
      column = after
    end
  end
  return runs
end

-- Sprites are decoded on first use. Decoding them all at load took most of the boot budget.
local function lazy(build)
  return setmetatable({}, {__index=function(built, key)
    local value = build(key)
    if value then rawset(built, key, value) end
    return value
  end})
end

function Effects.stamp(c, runs, x, y)
  for _, run in ipairs(runs) do c:rect(x+run[1],y+run[2],run[3],run[4],run[5]) end
end

local metal = {
  X=0x31292a, D=0x484944, M=0x7d7e78, I=0xc1beb0,
  O=0x667454, R=0xbd4339, H=0xf38868,
}
local east = {
  "XX............",
  "XMX.......XX..",
  ".XXIIIIMRRHRX.",
  "..XOMOOMRRHHRX",
  ".XXMDDDDRRRDX.",
  "XMX.......XX..",
  "XX............",
}
local southeast = {
  "...........",
  "XX.........",
  "XMX........",
  ".XIMX......",
  "..XIMX.....",
  "...XOOMX...",
  "....XDRRX..",
  ".....XRRHX.",
  "......XHHXX",
  ".......XXX.",
  "...........",
}

-- Odd facings turn the east sprite, even facings the southeast one: facing 3 (E) and 4 (SE) are unturned.
Effects.rockets = lazy(function(direction)
  direction = math.tointeger(direction)
  if not direction or direction < 1 or direction > 8 then return end
  local turn = ((direction - (direction % 2 == 1 and 3 or 4)) % 8) // 2
  return sprite(direction % 2 == 1 and east or southeast, metal, turn)
end)

local tongues = {
  {
    ".........",
    "..R..OO..",
    ".ROOOYYO.",
    "ROYYHYYOR",
    "..OOYYOR.",
    "...RR.O..",
    ".........",
  },
  {
    ".........",
    ".RR.O....",
    "ROOYYOO..",
    ".OYYHHYOR",
    "..OROYYO.",
    ".....ORR.",
    "......R..",
  },
  {
    "....R....",
    "...OO....",
    ".ROYOO.R.",
    "ROYYHYOO.",
    ".OOYYHYYR",
    "..R.OOOO.",
    ".....R...",
  },
}

local heats = {
  {R=0xb84a2f, O=0xe87332, Y=0xffb455, H=0xffe6a4},
  {R=0x9b392d, O=0xd95628, Y=0xf6913d, H=0xffc86a},
  {R=0x733732, O=0xa64632, Y=0xd56334, H=0xe9934c},
}
Effects.flames = lazy(function(heat)
  local colors = heats[heat]
  return colors and lazy(function(frame)
    local rows = tongues[frame]
    return rows and sprite(rows, colors)
  end)
end)

local fire = {R=0x902f2d, S=0xc8402f, O=0xef692d, Y=0xffaf48, H=0xffe59a, W=0xfff5cf}
local scorch_rows = {
  "...................................",
  "...............SSS.................",
  "..............CCCAAA...............",
  "........SSSSSAAACCAAASSSS..........",
  ".......SS..AACCCCCCCAAA.SSS........",
  "......SSSSACCCKKKKKKCAAAAASSS...SS.",
  ".........AACCCCCKKCCCCCCAAAAAA.SSS.",
  "..SSSS..AACCCKKKKKKKCCCCKKKCAAAAASS",
  "..SSSAAAACCCKKKKKKKKKKKKKKKKKCAACS.",
  "..AAAAACCCKKKCCCKKKKKKKKKKCCCAACSS.",
  "..AAACCCKKKKKKKKKKKKKKKKKCCCAAA....",
  "SSCCCCCCKKKKKKKKKKKKKKKKKKCCCASS.S.",
  "S...CCKCCCCCCKKKCCCKKKKCCCAAAA.S...",
  "...SSAAACCCCCKKKKKKKKKKKCCCCCCSS...",
  ".......ACCCCKKKKKCCCKKKKCCCCCA.....",
  ".......CCCCCKCCCKKKCCKCCCCCCCASS...",
  ".....SSCCCCCCKKCCCCCCCCCCCCCAA.....",
  ".....SSCCCKCCCCCCCCCCCCCCCAAASS....",
  ".......SCCCCCKKCAAACCCCCCAASSS.....",
  ".....SSSSAAAAAAASS...SAACSSS.......",
  "........SSSSSS...SSSSSS............",
  "....S.S..SSSSS.S.SS...SS...........",
  "...........S.......................",
}
local scorch_colors = {S=0x6f5b4c, A=0x463a33, C=0x2d2826, K=0x19181a}

local blast_rows = {
  {
    "........Y........",
    "....O..OHY.......",
    ".....OYHWHYO..O..",
    "..S.OHWWWWHYO....",
    "R.SYHWWWWWHHYOS..",
    ".SYHHWWWWWHHYOOS.",
    "...OYHHWHHYOS...R",
    "..O.OYHHYOS......",
    "......OY..S......",
    ".....O...S.......",
    ".................",
  },
  {
    ".........SS........",
    ".....R..SOYOS......",
    "...RSOSSOYHYOR.....",
    "...SOYOOYYHYOOOS...",
    ".RSOYYHHYOHYOSOOS..",
    "SOYYHYYYOYYOOOYOSR.",
    "RSOYYYOOYYYHHYYOOSR",
    "..SOYOOYOYYHYOOSS..",
    ".RRSOSOOYYOOYOSR...",
    "....RRSSOOOSS.R....",
    "...S....RSR..S.....",
    "...................",
    "...................",
  },
  {
    ".......R...SS..........",
    "....SR...SSOOS..R......",
    "...SOOSRSSOYOS.SSR.....",
    ".RSSOSR.SOORSRSOOSR....",
    ".SOOS.....R...SOYOS.R..",
    "SOOS.SR....RS.SOOS..SS.",
    ".SSR..RS..SOOS.SR..SOSR",
    "..R.......RSS.....SSSR.",
    "...SSR...R..R..RSSSR...",
    "..RSOOS......RSSR......",
    "....SSR.R...SR.....R...",
    "..........RSSR.........",
    ".......................",
  },
  {
    "..............R........",
    "....R....R..SR...R.....",
    "...SR.........R.RSR....",
    "..SOR..R.........SR....",
    "...R.......R.........R.",
    "R.......RSR.......R....",
    ".R..R....R..........SR.",
    ".....R.........RR..SR..",
    "..R.....R.....SR.......",
    "....RSR........R.......",
    ".............R.........",
    ".......................",
    ".......................",
  },
}
Effects.blasts = lazy(function(frame)
  local rows = blast_rows[frame]
  return rows and sprite(rows, fire)
end)

setmetatable(Effects, {__index=function(_, key)
  if key ~= "scorch" then return end
  local runs = sprite(scorch_rows, scorch_colors)
  Effects.scorch = runs
  return runs
end})

return Effects
