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
local has_index, levels = pcall(require, "levels.index")
if not has_index or type(levels) ~= "table" then levels = {} end
local has_levels, level_choice = #levels > 0, 1
local briefing_choice, active_mission, missions_back = 1, nil, "briefing"
screen:loading()
if indicators then indicators:clear() end
if sys.tick then sys.tick(16) end

local function open_menu()
  scene, choice, page = "menu", 1, math.max(1, game.weapon)
  cancel_pressed_at, game.fire_until = nil, nil
  menu:open()
  menu_dirty = true
end

local function resume_game()
  scene, resume_keys = "range", sys.keys()
  game.dirty = true
  menu:close()
end

local function start_game(kind, id)
  game = Game.new(SEED, kind, not range.survey and range.ground or nil, id)
  if game.survey then screen:loading() end
  resume_game()
end

local function show_briefing(index)
  briefing_choice, scene, menu_dirty = index, "briefing", true
  menu:open()
end

local function show_missions(from, index)
  missions_back, level_choice = from, index
  scene, menu_dirty = "missions", true
  menu:open()
end

local function open_range()
  game = range
  if range.survey then screen:loading() end
  resume_game()
end

if has_levels then show_briefing(1) end

local function retry()
  if game.mission then show_briefing(active_mission)
  else start_game(game.drill or true, game.practice) end
end

local function navigate(key, repeated)
  if key == "back" then
    if repeated then return end
    if scene == "briefing" then
      show_missions(missions_back, briefing_choice)
    elseif scene == "missions" then
      if missions_back == "briefing" then show_briefing(briefing_choice)
      elseif missions_back == "range" then resume_game()
      else scene, menu_dirty = "menu", true end
    elseif scene == "specs" then
      scene, menu_dirty = "menu", true
    else
      resume_game()
    end
  elseif scene == "briefing" then
    if key == "select" and not repeated then
      active_mission = briefing_choice
      start_game("level", levels[active_mission].id)
    end
  elseif scene == "missions" then
    if key == "up" or key == "down" then
      level_choice = (level_choice - 1 + (key == "up" and -1 or 1)) % (#levels + 1) + 1
      menu_dirty = true
    elseif key == "select" and not repeated then
      if levels[level_choice] then show_briefing(level_choice)
      else open_range() end
    end
  elseif scene == "menu" then
    local options = Menu.options(game.drill, has_levels)
    if key == "up" or key == "down" then
      choice = (choice - 1 + (key == "up" and -1 or 1)) % #options + 1
      menu_dirty = true
    elseif (key == "left" or key == "right") and not repeated then
      screen.pickup_motion = not screen.pickup_motion
      if storage then pcall(storage.set, "pickup_motion", screen.pickup_motion) end
      menu_dirty = true
    elseif key == "select" and not repeated then
      local action = options[choice][1]
      if action == "resume" then resume_game()
      elseif action == "specs" then scene, enemy_guide, menu_dirty = "specs", false, true
      elseif action == "drill" then
        if game.mission then missions_back = "menu" end
        retry()
      elseif action == "missions" then show_missions("menu", game.mission and active_mission or 1)
      elseif action == "endless" then start_game("endless")
      elseif action == "range" then open_range()
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
      start_game("practice", Enemies.guide[enemy_page][1])
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
  if game.survey then return true end
  if key == "select" then
    if not repeated then
      if game.result == "won" and game.mission then
        show_missions("range", active_mission % #levels + 1)
      elseif game.result then
        if game.mission then missions_back = "range" end
        retry()
      else game:request_fire() end
    end
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
      if scene == "briefing" then
        menu:draw_briefing(levels[briefing_choice], briefing_choice)
        if indicators then indicators:clear() end
      elseif scene == "missions" then
        menu:draw_missions(level_choice, levels)
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
        menu:draw_pause(choice, game, screen:weapon_art(game:held_weapon())[game.direction][1], has_levels, screen.pickup_motion)
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
