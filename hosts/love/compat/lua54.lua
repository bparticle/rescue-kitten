-- Translates the badge's Lua 5.4/5.5 source into LuaJIT (Lua 5.1) source.
--
-- Only the operators LuaJIT can't parse change: `a // b`, `a & b`, `a | b`, `a ~ b`,
-- `a << b`, `a >> b` and unary `~a` become calls to __idiv, __band, __bor, __bxor,
-- __shl, __shr and __bnot. Everything else, including whitespace and line breaks,
-- is copied as it was, so error messages keep the original line numbers.
--
-- The parser follows the Lua grammar and its operator priorities (lparser.c), so
-- `mask & 8 ~= 0` becomes `__band(mask, 8) ~= 0`.

local M = {}

local OPS = {
  ["//"] = "__idiv", ["&"] = "__band", ["|"] = "__bor", ["~"] = "__bxor",
  ["<<"] = "__shl", [">>"] = "__shr",
}

-- {left, right} priority, as in lparser.c.
local PRIORITY = {
  ["+"] = {10, 10}, ["-"] = {10, 10},
  ["*"] = {11, 11}, ["%"] = {11, 11}, ["/"] = {11, 11}, ["//"] = {11, 11},
  ["^"] = {14, 13},
  ["&"] = {6, 6}, ["|"] = {4, 4}, ["~"] = {5, 5}, ["<<"] = {7, 7}, [">>"] = {7, 7},
  [".."] = {9, 8},
  ["=="] = {3, 3}, ["<"] = {3, 3}, ["<="] = {3, 3}, ["~="] = {3, 3}, [">"] = {3, 3}, [">="] = {3, 3},
  ["and"] = {2, 2}, ["or"] = {1, 1},
}
local UNARY_PRIORITY = 12

local KEYWORDS = {}
for word in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do
  KEYWORDS[word] = true
end

local SYMBOLS = {
  "...", "..", "::", "<<", ">>", "//", "==", "~=", "<=", ">=",
  "+", "-", "*", "/", "%", "^", "#", "&", "~", "|", "<", ">", "=",
  "(", ")", "{", "}", "[", "]", ";", ":", ",", ".",
}

-- Comments become blank text with the same line breaks.
local function blank(text)
  return (text:gsub("[^\n]", ""))
end

local function lex(src, name)
  local tokens, pos, len, pre = {}, 1, #src, {}
  local function fail(msg) error(("%s: %s near byte %d"):format(name, msg, pos), 0) end
  local function long_bracket(at)
    local eq = src:match("^%[(=*)%[", at)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local _, last = src:find(close, at, true)
    if not last then fail("unfinished long bracket") end
    return last
  end
  if src:sub(1, 2) == "#!" then pos = (src:find("\n", 1, true) or len + 1) end
  while true do
    -- whitespace and comments
    while pos <= len do
      local ws = src:match("^%s+", pos)
      if ws then
        pre[#pre + 1] = ws
        pos = pos + #ws
      elseif src:sub(pos, pos + 1) == "--" then
        local last = long_bracket(pos + 2)
        if not last then last = (src:find("\n", pos, true) or len + 1) - 1 end
        pre[#pre + 1] = " " .. blank(src:sub(pos, last))
        pos = last + 1
      else
        break
      end
    end
    local ws = table.concat(pre)
    pre = {}
    if pos > len then
      tokens[#tokens + 1] = {t = "<eof>", v = "", pre = ws}
      return tokens
    end
    local c = src:sub(pos, pos)
    local tok
    if c:match("[%a_]") then
      local word = src:match("^[%w_]+", pos)
      tok = {t = KEYWORDS[word] and word or "<name>", v = word}
    elseif c:match("%d") or (c == "." and src:sub(pos + 1, pos + 1):match("%d")) then
      local num = src:match("^0[xX][%x%.]*[pP][%+%-]?%d+", pos)
        or src:match("^0[xX][%x%.]*", pos)
        or src:match("^%d*%.?%d*[eE][%+%-]?%d+", pos)
        or src:match("^%d*%.?%d*", pos)
      tok = {t = "<number>", v = num}
    elseif c == '"' or c == "'" then
      local i = pos + 1
      while true do
        local ch = src:sub(i, i)
        if ch == "" or ch == "\n" then fail("unfinished string") end
        if ch == "\\" then
          if src:sub(i + 1, i + 1) == "z" then
            i = i + 2
            while src:sub(i, i):match("%s") do i = i + 1 end
          else
            i = i + 2
          end
        elseif ch == c then
          break
        else
          i = i + 1
        end
      end
      tok = {t = "<string>", v = src:sub(pos, i)}
    elseif c == "[" and long_bracket(pos) then
      tok = {t = "<string>", v = src:sub(pos, long_bracket(pos))}
    else
      for _, sym in ipairs(SYMBOLS) do
        if src:sub(pos, pos + #sym - 1) == sym then
          tok = {t = sym, v = sym}
          break
        end
      end
      if not tok then fail("unexpected symbol '" .. c .. "'") end
    end
    tok.pre = ws
    tokens[#tokens + 1] = tok
    pos = pos + #tok.v
  end
end

function M.translate(src, name)
  name = name or "?"
  local tokens = lex(src, name)
  local i = 1

  local function peek(k) return tokens[i + (k or 0)].t end
  local function fail(msg)
    local line = 1
    for k = 1, i do
      local _, n = (tokens[k].pre .. (k < i and tokens[k].v or "")):gsub("\n", "")
      line = line + n
    end
    error(("%s:%d: %s near '%s'"):format(name, line, msg, tokens[i].v), 0)
  end
  local function take()
    local tok = tokens[i]
    i = i + 1
    return tok.pre .. tok.v
  end
  local function expect(t)
    if peek() ~= t then fail("'" .. t .. "' expected") end
    return take()
  end
  local function accept(t)
    if peek() == t then return take() end
    return ""
  end

  -- Wraps an operand pair in a call, keeping the left operand's leading whitespace outside
  -- so `return a | b` stays `return __bor(a, b)`, never `return__bor(...)`.
  local function call(fn, left, right)
    local ws, body = left:match("^(%s*)(.*)$")
    return ws .. fn .. "(" .. body .. "," .. right .. ")"
  end

  local block, expr

  local function explist()
    local out = expr()
    while peek() == "," do out = out .. take() .. expr() end
    return out
  end

  local function body()
    local out = expect("(")
    if peek() ~= ")" then
      repeat
        if peek() == "..." then out = out .. take() break end
        out = out .. expect("<name>")
        if peek() ~= "," then break end
        out = out .. take()
      until false
    end
    return out .. expect(")") .. block() .. expect("end")
  end

  local function table_constructor()
    local out = expect("{")
    while peek() ~= "}" do
      if peek() == "[" then
        out = out .. take() .. expr() .. expect("]") .. expect("=") .. expr()
      elseif peek() == "<name>" and peek(1) == "=" then
        out = out .. take() .. take() .. expr()
      else
        out = out .. expr()
      end
      if peek() == "," or peek() == ";" then out = out .. take() else break end
    end
    return out .. expect("}")
  end

  local function args()
    local t = peek()
    if t == "(" then
      local out = take()
      if peek() ~= ")" then out = out .. explist() end
      return out .. expect(")")
    elseif t == "{" then
      return table_constructor()
    elseif t == "<string>" then
      return take()
    end
    fail("function arguments expected")
  end

  local function primary()
    local t = peek()
    if t == "<name>" then return take() end
    if t == "(" then return take() .. expr() .. expect(")") end
    fail("unexpected symbol")
  end

  local function suffixed()
    local out = primary()
    while true do
      local t = peek()
      if t == "." then
        out = out .. take() .. expect("<name>")
      elseif t == "[" then
        out = out .. take() .. expr() .. expect("]")
      elseif t == ":" then
        out = out .. take() .. expect("<name>") .. args()
      elseif t == "(" or t == "{" or t == "<string>" then
        out = out .. args()
      else
        return out
      end
    end
  end

  local function simple()
    local t = peek()
    if t == "<number>" or t == "<string>" or t == "nil" or t == "true" or t == "false" or t == "..." then
      return take()
    elseif t == "{" then
      return table_constructor()
    elseif t == "function" then
      return take() .. body()
    end
    return suffixed()
  end

  local function subexpr(limit)
    local out
    local t = peek()
    if t == "not" or t == "-" or t == "#" then
      out = take() .. subexpr(UNARY_PRIORITY)
    elseif t == "~" then
      local ws = tokens[i].pre
      i = i + 1
      out = ws .. "__bnot(" .. subexpr(UNARY_PRIORITY) .. ")"
    else
      out = simple()
    end
    while true do
      local op = peek()
      local prio = PRIORITY[op]
      if not prio or prio[1] <= limit then break end
      local fn = OPS[op]
      if fn then
        i = i + 1 -- the operator's own whitespace is dropped
        out = call(fn, out, subexpr(prio[2]))
      else
        out = out .. take() .. subexpr(prio[2])
      end
    end
    return out
  end

  function expr() return subexpr(0) end

  local function block_follow(t)
    return t == "else" or t == "elseif" or t == "end" or t == "until" or t == "<eof>"
  end

  local function statement()
    local t = peek()
    if t == ";" or t == "break" then
      return take()
    elseif t == "::" then
      return take() .. expect("<name>") .. expect("::")
    elseif t == "goto" then
      return take() .. expect("<name>")
    elseif t == "do" then
      return take() .. block() .. expect("end")
    elseif t == "while" then
      return take() .. expr() .. expect("do") .. block() .. expect("end")
    elseif t == "repeat" then
      return take() .. block() .. expect("until") .. expr()
    elseif t == "if" then
      local out = take() .. expr() .. expect("then") .. block()
      while peek() == "elseif" do out = out .. take() .. expr() .. expect("then") .. block() end
      if peek() == "else" then out = out .. take() .. block() end
      return out .. expect("end")
    elseif t == "for" then
      local out = take() .. expect("<name>")
      if peek() == "=" then
        out = out .. take() .. expr() .. expect(",") .. expr()
        if peek() == "," then out = out .. take() .. expr() end
      else
        while peek() == "," do out = out .. take() .. expect("<name>") end
        out = out .. expect("in") .. explist()
      end
      return out .. expect("do") .. block() .. expect("end")
    elseif t == "function" then
      local out = take() .. expect("<name>")
      while peek() == "." do out = out .. take() .. expect("<name>") end
      if peek() == ":" then out = out .. take() .. expect("<name>") end
      return out .. body()
    elseif t == "local" then
      local out = take()
      if peek() == "function" then return out .. take() .. expect("<name>") .. body() end
      repeat
        out = out .. expect("<name>")
        if peek() == "<" then -- <const> / <close>: LuaJIT has neither, so drop the attribute
          if peek(1) ~= "<name>" or peek(2) ~= ">" then fail("attribute expected") end
          i = i + 3
        end
        if peek() ~= "," then break end
        out = out .. take()
      until false
      if peek() == "=" then out = out .. take() .. explist() end
      return out
    elseif t == "return" then
      local out = take()
      if not block_follow(peek()) and peek() ~= ";" then out = out .. explist() end
      return out .. accept(";")
    end
    local out = suffixed()
    if peek() == "=" or peek() == "," then
      while peek() == "," do out = out .. take() .. suffixed() end
      out = out .. expect("=") .. explist()
    end
    return out
  end

  function block()
    local parts = {}
    while not block_follow(peek()) do
      parts[#parts + 1] = statement()
    end
    return table.concat(parts)
  end

  local out = block()
  if peek() ~= "<eof>" then fail("'<eof>' expected") end
  return out .. tokens[i].pre
end

return M
