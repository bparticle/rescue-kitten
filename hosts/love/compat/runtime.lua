-- Lua 5.4 pieces LuaJIT lacks, for code that went through compat/lua54.lua.
-- bit.* works on 32-bit integers, which is also what the badge uses (int32 Lua).
local bit = require("bit")
local floor = math.floor

__idiv = function(a, b) return floor(a / b) end
__band, __bor, __bxor, __bnot = bit.band, bit.bor, bit.bxor, bit.bnot
__shl, __shr = bit.lshift, bit.rshift

table.unpack = table.unpack or unpack
table.pack = table.pack or function(...) return {n = select("#", ...), ...} end

math.tointeger = math.tointeger or function(x)
  if type(x) == "string" then x = tonumber(x) end
  if type(x) == "number" and x == floor(x) and x == x and x ~= math.huge and x ~= -math.huge then return x end
  return nil
end
math.type = math.type or function(x)
  if type(x) ~= "number" then return nil end
  return x == floor(x) and "integer" or "float"
end
math.maxinteger = math.maxinteger or 0x7fffffff
math.mininteger = math.mininteger or -0x80000000
