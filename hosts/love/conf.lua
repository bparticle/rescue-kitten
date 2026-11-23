function love.conf(t)
  t.identity = "dustpaw"
  t.version = "11.5"
  t.window.title = "Dustpaw"
  t.window.width = 960   -- 3× the badge frame (320 × 240)
  t.window.height = 720
  t.window.minwidth = 320
  t.window.minheight = 240
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.video = false
end
