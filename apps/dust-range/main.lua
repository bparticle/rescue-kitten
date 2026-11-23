local Game = require("lib.game")
local View = require("lib.view")
local Menu = require("lib.menu")
local Indicators = require("lib.indicators")
local Enemies = require("lib.enemies")

local SEED = 427
local range = Game.new(SEED)
local game = range
local screen = View.new()
screen.pickup_motion = not storage or storage.get("pickup_motion") ~= false
local menu = Menu.new()
local indicators = Indicators.new()
local MENU_HOLD_MS = 1200
local scene, choice, page = "range", 1, 1
local enemy_page, enemy_guide = 1, false
local cancel_pressed_at, resume_keys, menu_dirty
local endless_unlocked = storage and storage.get("endless_unlocked") == true
local has_index, levels = pcall(require, "levels.index")
if not has_index or type(levels) ~= "table" then levels = {} end
local has_levels, level_choice = #levels > 0, 1
screen:loading()
if indicators then indicators:clear() end
if sys.tick then sys.tick(16) end

local function open_menu()
  scene, choice, page = "menu", 1, math.max(1, game.weapon)
  cancel_pressed_at, game.fire_until = nil, nil
  menu:open()
  menu_dirty = true
end

local function resume_range()
  scene, resume_keys = "range", sys.keys()
  game.dirty = true
  menu:close()
end

local function start_drill(kind, practice)
  game = Game.new(SEED, kind, not range.survey and range.ground or nil, practice)
  if game.survey then screen:loading() end
  resume_range()
end

local function navigate(key, repeated)
  if key == "back" then
    if repeated then return end
    if scene == "specs" or scene == "levels" then
      scene, menu_dirty = "menu", true
    else
      resume_range()
    end
  elseif scene == "levels" then
    if key == "up" or key == "down" then
      level_choice = (level_choice - 1 + (key == "up" and -1 or 1)) % #levels + 1
      menu_dirty = true
    elseif key == "select" and not repeated then
      start_drill("level", levels[level_choice].id)
    end
  elseif scene == "menu" then
    local options = Menu.options(game.drill, endless_unlocked, has_levels)
    if key == "up" or key == "down" then
      choice = (choice - 1 + (key == "up" and -1 or 1)) % #options + 1
      menu_dirty = true
    elseif (key == "left" or key == "right") and not repeated then
      screen.pickup_motion = not screen.pickup_motion
      if storage then pcall(storage.set, "pickup_motion", screen.pickup_motion) end
      menu_dirty = true
    elseif key == "select" and not repeated then
      local action = options[choice][1]
      if action == "resume" then resume_range()
      elseif action == "specs" then scene, enemy_guide, menu_dirty = "specs", false, true
      elseif action == "drill" then start_drill(game.drill or true, game.level_id or game.practice)
      elseif action == "levels" then scene, menu_dirty = "levels", true
      elseif action == "squad" then start_drill("squad")
      elseif action == "endless" then start_drill("endless")
      elseif action == "range" then
        game = range
        resume_range()
      else sys.exit() end
    end
  elseif (key == "up" or key == "down") and not repeated then
    enemy_guide = key == "down"
    menu_dirty = true
  elseif enemy_guide then
    if key == "left" or key == "right" then
      enemy_page = (enemy_page - 1 + (key == "left" and -1 or 1)) % #Enemies.guide + 1
      menu_dirty = true
    elseif key == "select" and not repeated then
      start_drill("practice", Enemies.guide[enemy_page][1])
    end
  elseif key == "left" or key == "right" or (key == "select" and not repeated) then
    page = (page - 1 + (key == "left" and -1 or 1)) % #Game.weapons + 1
    menu_dirty = true
  end
end

function on_key(key, repeat_key)
  local repeated = repeat_key == true or (type(repeat_key) == "number" and repeat_key > 0)
  if scene ~= "range" then
    navigate(key, repeated)
    return true
  end
  if resume_keys and not repeated then resume_keys[key] = nil end
  if key == "select" then
    if not repeated then
      if game.result then start_drill(game.drill, game.level_id or game.practice)
      else game:request_fire() end
    end
    return true
  end
  if key == "right" and not repeated and game.drill == "squad" and game.result == "won" then
    start_drill("endless")
    return true
  end
  if key == "back" then
    if not repeated then
      -- A fresh press settles the previous tap if it ended between ticks.
      if cancel_pressed_at then game:cycle() end
      cancel_pressed_at = sys.millis()
    end
    return true
  end
  return key == "up" or key == "down" or key == "left" or key == "right"
end

function on_tick(ms)
  if scene == "range" and cancel_pressed_at then
    local keys = sys.keys()
    if not keys.back then
      cancel_pressed_at = nil
      game:cycle()
    elseif sys.millis() - cancel_pressed_at >= MENU_HOLD_MS then
      open_menu()
    end
  end
  if scene ~= "range" then
    if menu_dirty then
      if scene == "levels" then
        menu:draw_levels(level_choice, levels)
        if indicators then indicators:clear() end
      elseif scene == "specs" then
        if enemy_guide then
          local entry = Enemies.guide[enemy_page]
          local profile = Enemies.profile(entry[1])
          menu:draw_enemy(enemy_page,#Enemies.guide,entry,profile,screen:enemy_portrait(profile))
          if indicators then indicators:show_spec(profile.weapon) end
        else
          menu:draw_specs(page)
          if indicators then indicators:show_spec(page) end
        end
      else
        menu:draw_pause(choice, game, screen:weapon_art(game:held_weapon())[game.direction][1], endless_unlocked,
          has_levels, screen.pickup_motion)
        if indicators then indicators:clear() end
      end
      menu_dirty = false
    end
    return
  end
  screen:prepare_tiles()
  if game.survey then
    game:prepare()
    return
  end
  local keys = sys.keys()
  if resume_keys then
    for key in pairs(resume_keys) do
      if keys[key] then keys[key] = nil
      else resume_keys[key] = nil end
    end
    if not next(resume_keys) then resume_keys = nil end
  end
  game:update(ms, keys)
  if game.drill == "squad" and game.result == "won" and not endless_unlocked then
    endless_unlocked = true
    if storage then pcall(storage.set, "endless_unlocked", true) end
  end
  if indicators then indicators:update(game) end
  if game.dirty or screen:needs_pickup_frame(game) then
    screen:draw(game)
    game.dirty = false
  end
end

function on_exit()
  if indicators then indicators:clear() end
end

-- The same read-only snapshot is available to the Mosa headless smoke test.
function range_status()
  return game.x, game.y, game.weapon, game.found, game.hits, game.shots, game.direction,
    #game.projectiles, #game.particles, scene, choice, page,
    (game.squad or game.practice) and game.drill or game.drill and "drill" or "range", game.health, game.result or "active",
    game.squad and game.squad.wave or 0, game.squad and game.squad.remaining or 0,
    game.practice or "-", scene == "specs" and enemy_guide and enemy_page or 0
end
