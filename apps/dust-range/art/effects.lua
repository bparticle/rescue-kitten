-- Native-pixel silhouettes. Periods leave the terrain visible between the flames.
local Effects = {}
local min, abs = math.min, math.abs

local function sprite(rows, colors, turns)
  local runs = {}
  local center_x, center_y = #rows[1]//2, #rows//2
  for row, pixels in ipairs(rows) do
    local column = 1
    while column <= #pixels do
      local symbol = pixels:sub(column,column)
      local after = column + 1
      while pixels:sub(after,after) == symbol do after = after + 1 end
      if colors[symbol] then
        local x1, y1 = column-1-center_x, row-1-center_y
        local x2, y2 = after-2-center_x, y1
        for _ = 1, turns or 0 do x1,y1,x2,y2 = -y1,x1,-y2,x2 end
        runs[#runs+1] = {min(x1,x2),min(y1,y2),abs(x2-x1)+1,abs(y2-y1)+1,colors[symbol]}
      end
      column = after
    end
  end
  return runs
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

Effects.rockets = {}
for turn = 0, 3 do
  Effects.rockets[(2+turn*2)%8+1] = sprite(east,metal,turn)
  Effects.rockets[(3+turn*2)%8+1] = sprite(southeast,metal,turn)
end

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

Effects.flames = {}
for heat, colors in ipairs({
  {R=0xb84a2f, O=0xe87332, Y=0xffb455, H=0xffe6a4},
  {R=0x9b392d, O=0xd95628, Y=0xf6913d, H=0xffc86a},
  {R=0x733732, O=0xa64632, Y=0xd56334, H=0xe9934c},
}) do
  Effects.flames[heat] = {}
  for frame, rows in ipairs(tongues) do Effects.flames[heat][frame] = sprite(rows,colors) end
end

local fire = {R=0x902f2d, S=0xc8402f, O=0xef692d, Y=0xffaf48, H=0xffe59a, W=0xfff5cf}
Effects.scorch = sprite({
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
}, {S=0x6f5b4c, A=0x463a33, C=0x2d2826, K=0x19181a})

Effects.blasts = {
  sprite({
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
  },fire),
  sprite({
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
  },fire),
  sprite({
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
  },fire),
  sprite({
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
  },fire),
}

return Effects
