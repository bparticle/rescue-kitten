-- Test driver for tools/love-check.mjs: runs hosts/love/main.lua, presses scripted keys,
-- saves screenshots and quits. Any Lua error prints and exits with status 1 instead of
-- showing LÖVE's error screen.
--   DUSTPAW_HOST    absolute path of hosts/love
--   DUSTPAW_SCRIPT  "seconds:action ..." where action is down-<key>, up-<key>, shot-<name> or quit
local host = os.getenv("DUSTPAW_HOST")
package.path = host .. "/?.lua;" .. package.path

function love.errorhandler(msg)
  io.stderr:write("LOVE ERROR: ", tostring(msg), "\n", debug.traceback("", 2), "\n")
  io.stderr:flush()
  os.exit(1)
end

dofile(host .. "/main.lua")

local script = {}
for at, action in (os.getenv("DUSTPAW_SCRIPT") or ""):gmatch("([%d%.]+):([%w_%-]+)") do
  script[#script + 1] = {at = tonumber(at), action = action}
end
local t0, step, update = nil, 1, love.update
function love.update(dt)
  t0 = t0 or love.timer.getTime()
  local now = love.timer.getTime() - t0
  while script[step] and now >= script[step].at do
    local action = script[step].action
    local verb, arg = action:match("^(%a+)%-(.+)$")
    if verb == "down" then love.keypressed(arg)
    elseif verb == "up" then love.keyreleased(arg)
    elseif verb == "shot" then love.graphics.captureScreenshot(arg .. ".png")
    elseif action == "quit" then
      io.stdout:write("save dir: ", love.filesystem.getSaveDirectory(), "\n")
      io.stdout:write("fps: ", love.timer.getFPS(), "\n")
      love.event.quit()
    end
    step = step + 1
  end
  update(dt)
end
