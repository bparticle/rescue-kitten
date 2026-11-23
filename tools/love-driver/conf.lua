dofile(os.getenv("DUSTPAW_HOST") .. "/conf.lua")
local conf = love.conf
function love.conf(t)
  conf(t)
  t.identity = "dustpaw-check" -- keeps test saves apart from real play
end
