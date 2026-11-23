local palette = require("art.palette")

local Pixels = {}
local byte = string.byte

-- Each glyph is five columns, with the low bit at the top.
local glyphs = {
  A="7e1111117e", B="7f49494936", C="3e41414122", D="7f4141221c", E="7f49494941",
  F="7f09090901", G="3e41495132", H="7f0808087f", I="41417f4141", J="2040413f01",
  K="7f08142241", L="7f40404040", M="7f020c027f", N="7f0408107f", O="3e4141413e",
  P="7f09090906", Q="3e4151215e", R="7f09192946", S="2649494932", T="01017f0101",
  U="3f4040403f", V="1f2040201f", W="7f2018207f", X="6314081463", Y="0708700807", Z="6151494543",
  ["0"]="3e5149453e", ["1"]="00427f4000", ["2"]="4261514946", ["3"]="2141454b31", ["4"]="1814127f10",
  ["5"]="2745454539", ["6"]="3c4a494930", ["7"]="0161510907", ["8"]="3649494936", ["9"]="064949291e",
  ["/"]="2010080402", ["-"]="0808080808", ["."]="0060600000", ["%"]="2313086462",
  ["<"]="0814224100", [">"]="0041221408", ["+"]="08083e0808",
}
-- Glyphs decode on first use, so boot doesn't pay for letters a screen never shows.
local letters = setmetatable({}, {__index=function(letters, char)
  local code = glyphs[char]
  if not code then
    letters[char] = false
    return false
  end
  local pixels = {}
  for x = 0, 4 do
    local mask = tonumber(code:sub(x*2+1,x*2+2),16)
    for y = 0, 6 do
      if mask & (1 << y) ~= 0 then pixels[#pixels+1] = x*8+y end
    end
  end
  letters[char] = pixels
  return pixels
end})

function Pixels.stamp(c, data, x, y, scale, colors)
  scale = scale or 1
  colors = colors or palette.colors
  local rect = c.rect
  for i = 1, #data, 5 do
    local dx, dy, width, height, index = byte(data, i, i + 4)
    rect(c, x+(dx-35)*scale, y+(dy-35)*scale, (width-35)*scale, (height-35)*scale, colors[index-35])
  end
end

-- A 7 by 7 star: {row, first column, width} for each run.
local star = {{0,3,1},{1,3,1},{2,0,7},{3,1,5},{4,2,3},{5,1,2},{5,4,2},{6,0,2},{6,5,2}}
function Pixels.star(c, x, y, color)
  for _, run in ipairs(star) do c:rect(x+run[2], y+run[1], run[3], 1, color) end
end

function Pixels.text(c, value, x, y, color, scale)
  for index = 1, #value do
    local glyph = letters[value:sub(index,index)]
    if glyph then
      if scale then
        for _, pixel in ipairs(glyph) do
          c:rect(x+(pixel >> 3)*scale, y+(pixel & 7)*scale, scale, scale, color)
        end
      else
        for _, pixel in ipairs(glyph) do c:pixel(x+(pixel >> 3), y+(pixel & 7), color) end
      end
    end
    x = x + 6 * (scale or 1)
  end
end

return Pixels
