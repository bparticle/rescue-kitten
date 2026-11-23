import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { installHeadlessClock } from './headless-clock.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const mosa = process.env.MOSA_BADGE_DIR ?? path.resolve(root, '..', 'mosa-badge');
const { SolanaOS } = await import(pathToFileURL(path.join(mosa, 'tools', 'lib', 'host.mjs')));
const { to565 } = await import(pathToFileURL(path.join(mosa, 'tools', 'lib', 'host-core.mjs')));
const app = process.env.DUST_RANGE_APP_DIR ?? path.join(root, 'apps', 'dust-range');
const badge = await new SolanaOS({ dir: app }).launch();
const tick = Number(process.env.DUST_RANGE_TICK_MS ?? 16);
const step = 104 * tick / 1000;
installHeadlessClock(badge, tick);
const frames = badge.frames;
const advance = (ms) => badge.frames(Math.ceil(ms / tick));
const dark = ([r, g, b]) => r === 0 && g === 0 && b === 0;
const red = ([r, g, b]) => r > 80 && r > 4 * Math.max(g, b);

let peak = badge.lastInstructions();
let peakHeap = 0;
let peakObjects = badge.objects.size;
const call = badge.call.bind(badge);
const heap = badge.engine.global.get('__heap');
badge.call = (...args) => {
  const result = call(...args);
  peak = Math.max(peak, badge.lastInstructions());
  peakHeap = Math.max(peakHeap, heap());
  peakObjects = Math.max(peakObjects, badge.objects.size);
  assert.deepEqual(badge.errors, []);
  return result;
};

function state() {
  const values = badge.lua('return table.concat({range_status()}, ",")').split(',');
  const [x, y, weapon, found, hits, shots, direction, projectiles, particles] = values.slice(0, 9).map(Number);
  return { x, y, weapon, found, hits, shots, direction, projectiles, particles,
    scene: values[9], choice: Number(values[10]), page: Number(values[11]),
    mode: values[12], health: Number(values[13]), result: values[14],
    wave: Number(values[15]), remaining: Number(values[16]), practice: values[17],
    enemyPage: Number(values[18]) };
}

function renderedHealth() {
  const strip = [...badge.objects.values()].find((object) => object.y === 194 && object.h === 24);
  const offset = 6 * strip.w + 211;
  const track = to565(0x474841);
  return [...strip.px.subarray(offset, offset + 35)].filter((pixel) => pixel !== track).length;
}

async function walkTo(x, y) {
  const dx = x - state().x;
  if (Math.abs(dx) > step) await badge.hold(dx > 0 ? 'right' : 'left', Math.round(Math.abs(dx) / step));
  const dy = y - state().y;
  if (Math.abs(dy) > step) await badge.hold(dy > 0 ? 'down' : 'up', Math.round(Math.abs(dy) / step));
  assert.ok(Math.abs(x - state().x) < step + 0.01 && Math.abs(y - state().y) < step + 0.01);
}

const preview = process.argv[2];
try {
  badge.lua(`
    local Game = require("lib.game")
    local View = require("lib.view")
    local screen = View.new()
    local function advance(game, duration, keys)
      while duration > 0 do
        local step = math.min(duration, ${tick})
        game:update(step, keys or {})
        if game.draw_each_step then screen:draw(game) end
        duration = duration - step
      end
    end
    local function fire(game, weapon, x, y, direction, duration)
      game.x, game.y, game.direction, game.weapon = x, y, direction, weapon
      game:request_fire()
      advance(game, duration)
    end

    local board = Game.new(427)
    fire(board, 1, 502, 320, 3, 320)
    assert(board.targets[1].health == 52 and #board.targets[1].marks == 1)
    fire(board, 2, 502, 320, 3, 360)
    assert(board.targets[1].health == 20 and board.hits == 2)
    advance(board, 3100)
    assert(board.targets[1].health == 70 and #board.targets[1].marks == 0)

    local steel = Game.new(427)
    fire(steel, 2, 571, 261, 1, 360)
    assert(steel.targets[2].health == 92)

    local near, far = Game.new(427), Game.new(427)
    fire(near, 3, 338, 383, 7, 230)
    fire(far, 3, 370, 383, 7, 230)
    assert(#near.targets[3].marks == 5 and near.hits == 1)
    assert(far.targets[3].health > near.targets[3].health and far.hits == 1)

    local grenade = Game.new(427)
    local outside = grenade.targets[1]
    outside.x, outside.y = 404, 256
    fire(grenade, 4, 399, 257, 1, 300)
    assert(#grenade.scorch_marks == 0, "grenade leaves no mark in flight")
    advance(grenade, 150)
    local center, left, right = grenade.targets[4], grenade.targets[5], grenade.targets[6]
    assert(center.cracked and left.cracked and right.cracked and grenade.hits == 3,
      "the wider grenade blast reaches both outlying markers")
    assert(center.health < left.health and center.health < right.health)
    assert(outside.health == outside.surface.health, "targets beyond the blast stay intact")
    local mark = grenade.scorch_marks[1]
    assert(#grenade.scorch_marks == 1 and math.abs(mark.x-404) < 0.01 and math.abs(mark.y-216.51) < 0.01,
      "the scorch mark stays at the grenade landing point")
    advance(grenade, 3200)
    assert(#grenade.particles == 0 and center.health == center.surface.health and grenade.scorch_marks[1] == mark,
      "the mark outlasts smoke and target recovery")
    fire(grenade, 4, 402, 257, 1, 450)
    assert(#grenade.scorch_marks == 1 and grenade.scorch_marks[1] ~= mark,
      "a nearby repeat detonation replaces the mark")

    local rocket, splash = Game.new(427), Game.new(427)
    fire(rocket, 5, 654, 389, 3, 570)
    fire(splash, 5, 630, 404, 3, 570)
    assert(rocket.targets[7].health == 19 and rocket.hits == 1)
    assert(splash.targets[7].health > rocket.targets[7].health and splash.hits == 1)
    assert(#rocket.scorch_marks == 0 and #splash.scorch_marks == 0)
    fire(rocket, 5, 654, 389, 3, 570)
    assert(rocket.targets[7].health == 0 and rocket.hits == 2)
    advance(rocket, 1700)
    assert(rocket.targets[7].health == 155 and not rocket.targets[7].cracked)

    local heat = Game.new(427)
    fire(heat, 6, 260, 238, 7, 240)
    assert(heat.targets[8].health == 40 and heat.targets[8].burn and heat.hits == 1)
    advance(heat, 1250)
    assert(heat.targets[8].health == 8 and not heat.targets[8].burn and heat.hits == 1)
    assert(heat.targets[8].scorched)
    advance(heat, 3100)
    assert(heat.targets[8].health == 55 and not heat.targets[8].scorched)

    local tnt = Game.new(427)
    fire(tnt, 7, 498, 477, 1, ${tick})
    local planted = tnt.projectiles[1]
    assert(planted.x == 498 and planted.y == 477, "TNT drops at the player's exact position")
    tnt.x = 560
    tnt:cycle()
    advance(tnt, 1599)
    assert(tnt.weapon == 0 and planted.x == 498 and planted.y == 477 and tnt.hits == 0,
      "walking and switching weapons leave the waiting TNT in place")
    assert(#tnt.projectiles == 1 and #tnt.scorch_marks == 0, "TNT waits for its fuse")
    advance(tnt, 2)
    assert(tnt.hits == 2 and #tnt.projectiles == 0 and #tnt.scorch_marks == 1)
    assert(tnt.targets[9].health < 155 and tnt.targets[9].health == tnt.targets[10].health)
    assert(tnt.targets[8].health == tnt.targets[8].surface.health)
    assert(tnt.scorch_marks[1].x == 498 and tnt.scorch_marks[1].y == 477)

    -- Starter arsenal. Every scenario also renders each step so the effect art is exercised.
    local function range(...)
      local game = Game.new(427)
      while game.survey do game:prepare() end
      game.draw_each_step = true
      return game
    end

    local rail = range()
    fire(rail, 8, 698, 147, 3, ${tick})
    local p1, p2, p3 = rail.targets[11], rail.targets[12], rail.targets[13]
    assert(p1.health == 20 and p2.health == 28 and p3.health == 34 and rail.hits == 3,
      "the rail slug pierces all three planks, 80% per extra target")
    advance(rail, 300)

    local bank, direct = range(), range()
    fire(bank, 9, 148, 437, 3, 500)
    local plate = bank.targets[14]
    assert(plate.health == 37 and bank.hits == 1, "the bounced round hits the offset plate for 150%")
    assert(bank.reflectors[1].struck_at, "the reflector lights when struck")
    fire(direct, 9, 205, 440, 1, 500)
    assert(direct.targets[14].health == 48, "a straight shot deals the base damage")

    local disc = range()
    fire(disc, 10, 108, 314, 7, 260)
    assert(disc.targets[15].health == 51 and disc:held_weapon() == 0, "the disc hits on the way out")
    advance(disc, 1300)
    assert(disc.targets[15].health == 27 and disc.hits == 2, "the disc hits again on the return")
    assert(not disc.disc_out and disc:held_weapon() == 10 and #disc.projectiles == 0, "the hero catches the disc")

    local arc = range()
    fire(arc, 11, 748, 517, 3, ${tick})
    local n1, n2, n3 = arc.targets[16], arc.targets[17], arc.targets[18]
    assert(n1.health == 37 and n2.health == 45 and n3.health == 45 and arc.hits == 3,
      "the arc forks from the first node to both neighbours at 70%")
    advance(arc, 300)

    local cryo = range()
    fire(cryo, 12, 341, 575, 5, 300)
    local dummy = cryo.targets[19]
    assert(dummy.frost_until and dummy.health < 95 and dummy.health >= 89, "cryo spray coats the dummy")
    local frosted = dummy.health
    fire(cryo, 1, 341, 575, 5, 200)
    assert(dummy.health == frosted - 48 and not dummy.frost_until, "a follow-up shot shatters the frost for +30")
    fire(cryo, 12, 341, 575, 5, 300)
    advance(cryo, 4100)
    assert(not dummy.frost_until, "frost wears off")

    local full, tap = range(), range()
    full.x, full.y, full.direction, full.weapon = 485, 90, 1, 13
    advance(full, 1100, {select=true})
    assert(full.charge_from and full.shots == 0, "holding Select charges without firing")
    advance(full, 400)
    assert(full.targets[20].health == 87 and full.shots == 1, "a full charge deals 90 energy at 125%")
    tap.x, tap.y, tap.direction, tap.weapon = 485, 90, 1, 13
    tap:request_fire()
    advance(tap, 400)
    assert(tap.targets[20].health >= 170 and tap.targets[20].health <= 177 and tap.shots == 1,
      "a tap fires a minimum charge")

    local orb = range()
    fire(orb, 14, 118, 570, 7, 600)
    assert(orb.orb_out and #orb.projectiles == 1, "the orb opens a well")
    local c1 = orb.targets[21]
    assert(c1.x ~= c1.home_x or c1.y ~= c1.home_y, "the well drags light crates in")
    orb:request_fire()
    advance(orb, 1500)
    assert(orb.shots == 1, "only one well at a time")
    for id = 21, 23 do
      assert(orb.targets[id].health == 42, "the collapse damages every pulled crate")
    end
    assert(orb.hits == 3 and not orb.orb_out and #orb.projectiles == 0)
    advance(orb, 3100)
    assert(c1.x == c1.home_x and c1.y == c1.home_y and c1.health == 60, "crates return home on recovery")

    local hammer = range()
    fire(hammer, 15, 829, 290, 5, ${tick})
    local pad1, pad2 = hammer.targets[24], hammer.targets[25]
    assert(pad1.health == 36 and pad2.health == 36 and hammer.hits == 2, "the swing hits both pads")
    advance(hammer, 400)
    assert(pad1.y > 322 and pad2.y > 322, "the pads are knocked back about 24 px")
    local ahead = range()
    fire(ahead, 15, 829, 330, 1, ${tick})
    assert(ahead.hits == 2, "the swing reaches targets in front of the hero only")
    local behind = range()
    fire(behind, 15, 829, 290, 1, ${tick})
    assert(behind.hits == 0, "targets behind the hero are safe")

    local drill = Game.new(427, true)
    local soldier = drill.enemies[1]
    local start_x = soldier.x
    advance(drill, 400)
    assert(soldier.x < start_x and soldier.pose > 1, "the soldier approaches with the shared walk cycle")
    assert(drill.health == 100 and #drill.projectiles == 0)
    advance(drill, 300)
    assert(soldier.fire_at and soldier.pose == 1, "the soldier stops to aim before firing")
    advance(drill, 160, {up=true})
    advance(drill, 440)
    assert(drill.health == 100 and drill.hits == 0 and soldier.health == 54,
      "the windup locks the shot direction, and enemy fire cannot hit its shooter")
    advance(drill, 1800)
    assert(drill.health == 82 and drill.hits == 0, "the next handgun shot hits the player for 18")
    local check_runner = function(dodge)
      local game = Game.new(427, true)
      game.enemies, game.targets = {}, {}
      local runner = game:spawn_enemy("runner", game.x+30, game.y, 7)
      advance(game, 280)
      assert(runner.fire_at and runner.pose == 1, "the runner stops and marks its strike")
      if dodge then advance(game, 160, {up=true}) end
      advance(game, 380)
      assert(game.health == (dodge and 100 or 84) and game.hits == 0, "runner strikes have a dodge window")
    end
    check_runner(false)
    check_runner(true)

    local rifle = Game.new(427, true)
    rifle.enemies, rifle.targets = {}, {}
    local rifleman = rifle:spawn_enemy("rifleman", rifle.x+78, rifle.y, 7)
    advance(rifle, 520)
    assert(rifleman.burst_left == 3 and #rifle.projectiles == 0)
    advance(rifle, 1000)
    assert(rifle.health == 76 and rifleman.health == 44 and rifle.hits == 0,
      "a stationary player takes three rounds of 8 damage from a rifle burst")

    local shotgun = rifle:spawn_enemy("scatterguard", rifle.x-24, rifle.y, 3)
    rifle:fire_enemy(shotgun, rifle.x, rifle.y)
    assert(#rifle.projectiles == 3 and rifle.projectiles[1].dy ~= rifle.projectiles[3].dy)
    for _, shot in ipairs(rifle.projectiles) do
      assert(shot.targets[1] == rifle and #shot.targets == 1, "every hostile pellet targets the player only")
    end

    local check_lob = function(dodge)
      local game = Game.new(427, true)
      game.enemies, game.targets = {}, {}
      local lobber = game:spawn_enemy("lobber", game.x+42, game.y, 7)
      advance(game, 600)
      assert(lobber.fire_at and #game.projectiles == 0, "the lobber marks its landing position in advance")
      advance(game, 140)
      local lob = assert(game.projectiles[1])
      local reach = (lob.life-lob.age)*lob.weapon.speed
      assert(math.abs(lob.x+lob.dx*reach-lobber.aim_x) < 0.001)
      assert(math.abs(lob.y+lob.dy*reach-lobber.aim_y) < 0.001)
      if dodge then advance(game, 220, {up=true}) end
      advance(game, 600)
      assert(game.health == (dodge and 100 or 73) and lobber.health == 40,
        "the blast lands on the marked point and only damages the player faction")
    end
    check_lob(false)
    check_lob(true)

    local shields = Game.new(427, true)
    local warden = shields:spawn_enemy("warden", shields.x+40, shields.y, 7)
    local shell = {weapon=Game.weapons[1], kind="bullet", contacts={}, dx=1, dy=0}
    shields:impact(warden, shell, warden.x, warden.y, 40)
    assert(warden.health == 75 and shields.notice:find("BLOCK", 1, true), "the shield reduces frontal impact")
    shell.contacts, shell.dx = {}, -1
    shields:impact(warden, shell, warden.x, warden.y, 40)
    assert(warden.health == 57, "the shield does not protect the rear")
    shell.contacts, shell.dx, warden.fire_at = {}, 1, 1
    shields:impact(warden, shell, warden.x, warden.y, 40)
    assert(warden.health == 39, "the shield opens during the warden windup")

    local support = Game.new(427, true)
    support.enemies, support.targets = {}, {}
    local patient = support:spawn_enemy("soldier", support.x+43, support.y, 7)
    local medic = support:spawn_enemy("medic", support.x+64, support.y+16, 7)
    patient.health, patient.ready_at, medic.ready_at = 14, 10, 10
    advance(support, 80)
    assert(medic.heal_target == patient and medic.fire_at, "the medic warns before healing an ally")
    support:damage(medic, 5, "impact")
    assert(not medic.heal_target and not medic.fire_at, "damage interrupts healing")
    advance(support, 340)
    assert(patient.health == 14)
    advance(support, 1100)
    assert(patient.health == 40, "the next completed heal restores 26 HP")

    local flank = Game.new(427, true)
    flank.enemies, flank.targets = {}, {}
    local skirmisher = flank:spawn_enemy("skirmisher", flank.x+52, flank.y, 7)
    skirmisher.ready_at = 10
    advance(flank, 220)
    assert(math.abs(skirmisher.y-flank.y) > 9 and math.abs(skirmisher.x-flank.x) < 55,
      "the skirmisher moves laterally while waiting to shoot")

    for _ = 1, 32 do flank:fire_enemy(skirmisher, flank.x, flank.y) end
    assert(#flank.projectiles == 24, "hostile fire leaves room in the projectile list")
    flank.weapon = 3
    flank:fire(Game.weapons[3])
    assert(#flank.projectiles == 29, "a full player spread fits while the hostile list is at capacity")

    local function charge_drill()
      local game = Game.new(427, true)
      game.enemies, game.targets = {}, {}
      local bruiser = game:spawn_enemy("bruiser", game.x+46, game.y, 7)
      advance(game, 540)
      assert(bruiser.fire_at and bruiser.pose == 1 and not bruiser.dash_left)
      return game, bruiser
    end
    local charge = charge_drill()
    advance(charge, 620)
    assert(charge.health == 72 and charge.hits == 0, "a charge deals damage once as it crosses the player")

    local dodge_charge = charge_drill()
    advance(dodge_charge, 160, {up=true})
    advance(dodge_charge, 460)
    assert(dodge_charge.health == 100, "sidestepping the marked charge lane avoids damage")

    local stop_charge, bruiser = charge_drill()
    advance(stop_charge, 290)
    assert(bruiser.dash_left and stop_charge.health == 100)
    stop_charge:damage(bruiser, 28, "shock")
    assert(not bruiser.fire_at and not bruiser.dash_left, "shock can stop an active charge")
    advance(stop_charge, 380)
    assert(stop_charge.health == 100)

    local function beam_drill(dodge)
      local game = Game.new(427, true)
      game.enemies, game.targets = {}, {}
      local marksman = game:spawn_enemy("marksman", game.x+80, game.y, 7)
      advance(game, 880)
      assert(marksman.fire_at and game.health == 100, "the marksman shows its lane before firing")
      if dodge then advance(game, 125, {up=true}) end
      advance(game, 280)
      assert(game.health == (dodge and 100 or 71) and #game.projectiles == 0,
        "the beam travels along its locked lane and can be dodged")
    end
    beam_drill(false)
    beam_drill(true)

    local function sprayed_by(kind)
      local game = Game.new(427, true)
      game.enemies, game.targets = {}, {}
      local foe = game:spawn_enemy(kind,game.x+24,game.y,7)
      foe.ready_at = 10
      game:fire_enemy(foe,game.x,game.y)
      advance(game, 220)
      return game
    end
    local burning = sprayed_by("cinder")
    assert(burning.health == 94 and burning.burn, "enemy heat ignites the player")
    advance(burning, 940)
    assert(burning.health == 85 and not burning.burn, "the player's burn deals three ticks and expires")
    local cold = sprayed_by("cryo")
    assert(cold.health == 97 and cold.frost_speed == 0.74, "cryo spray chills the player")
    local before_y = cold.y
    advance(cold, 100, {up=true})
    assert(math.abs(before_y-cold.y - 104*0.1*0.74) < 0.01)
    assert(cold:damage(cold, 5, "impact") == 15 and not cold.frost_speed,
      "an impact shatters the coat and restores movement speed")

    local thawing = sprayed_by("cryo")
    advance(thawing, 1500)
    assert(thawing.health == 97 and not thawing.frost_until and not thawing.frost_speed,
      "frost expires and combat health does not regenerate on its own")

    for _, lethal in ipairs({"projectile", "burn"}) do
      local game = Game.new(427, true, nil, "cinder")
      local enemy = game.enemies[1]
      game.health, game.weapon, game.charge_from = 3, 13, 0
      game:spawn(game, Game.weapons[1], {}, enemy.x-9, enemy.y, 1, 0)
      if lethal == "projectile" then
        game:spawn(enemy, Game.weapons[1], {}, game.x+8, game.y, -1, 0)
      else
        game.burn = {weapon=Game.weapons[6], ticks=4, next_at=0}
        game.frost_until, game.frost_speed = 1, 0.74
      end
      local start_x = game.x
      game:update(${tick}, {right=lethal=="burn", select=true})
      assert(game.result == "lost" and game.health == 0 and game.x == start_x)
      assert(enemy.health == enemy.surface.health and game.hits == 0 and game.shots == 0,
        "queued shots and held inputs stop on the lethal tick")
      game:cycle()
      assert(game.weapon == 13 and #game.projectiles == 0 and not game.charge_from
        and not game.burn and not game.frost_speed and not game.hurt_until)
    end

    local medkits = Game.new(427, "squad")
    local kit = medkits.pickups[1]
    medkits.x, medkits.y = kit.x-12, kit.y
    medkits.health = 40
    advance(medkits, ${tick}, {right=true})
    assert(medkits.health == 70 and medkits.notice == "MEDKIT  +30 HP")
    assert(not medkits:pickup_visible(kit) and medkits.weapon == 1 and medkits.found == 0)

    local squad = Game.new(427, "squad")
    assert(squad.squad.wave == 1 and #squad.enemies == 2 and #squad.targets == 2)
    local soldier, runner = squad.enemies[1], squad.enemies[2]
    assert(squad:reserve_enemy_attack(soldier))
    assert(not squad:reserve_enemy_attack(runner), "a second attack cannot release on top of the first")
    squad.time = 0.5
    assert(squad:reserve_enemy_attack(runner), "the next attacker can reserve its own release window")
    squad.health = 50
    squad.burn = {weapon=Game.weapons[6], ticks=4, next_at=10}
    squad.frost_until, squad.frost_speed = 10, 0.74
    local supplies = {2, 3, 8, 8, 11, 11}
    local a = squad.arena
    local spawn_checks = {{a.right,320}, {448,a.top}, {a.left,a.bottom}, {a.right,a.top}, {547,373}, {448,320}}
    for wave = 1, squad.squad.total do
      for _, enemy in ipairs(squad.enemies) do enemy.health = 0 end
      advance(squad, 60)
      if wave < squad.squad.total then
        assert(squad.squad.remaining == 0 and #squad.targets == 0 and #squad.projectiles == 0)
        assert(squad.health == math.min(100, 50 + 24*wave))
        assert(not squad.burn and not squad.frost_speed, "wave recovery clears active status effects")
        squad.x, squad.y = table.unpack(spawn_checks[wave])
        local deadline = squad.time + 2
        while squad.squad.wave == wave and squad.time < deadline do advance(squad, ${tick}) end
        assert(squad.squad.wave == wave + 1 and #squad.targets == wave + 2)
        assert(squad.weapon == supplies[wave])
        for _, enemy in ipairs(squad.enemies) do
          assert((enemy.x-squad.x)^2 + (enemy.y-squad.y)^2 >= 24^2-0.01, "spawns leave room around the player")
          assert(enemy.x >= a.left and enemy.x <= a.right and enemy.y >= a.top and enemy.y <= a.bottom)
        end
      end
    end
    assert(squad.result == "won", "the final wave completes the trial")

    local run, replay = Game.new(427, "endless"), Game.new(427, "endless")
    assert(run.weapon == 2 and run.owned[11] and run.squad.total == nil)
    local saw_reinforcements = false
    for wave = 1, 40 do
      assert(run.squad.wave == wave and replay.squad.wave == wave)
      assert(#run.enemies >= 2 and #run.enemies <= 8 and run.targets == run.enemies)
      assert(#run.enemies == #replay.enemies)
      local roster = run.squad.roster
      local lobbers, medics, bruisers = 0, 0, 0
      assert(#roster == #replay.squad.roster and #roster <= 14)
      for index, entry in ipairs(roster) do
        local name, slot = table.unpack(entry)
        assert(name == replay.squad.roster[index][1] and slot == replay.squad.roster[index][2],
          "the same seed reproduces composition and slots")
        if name == "lobber" then lobbers = lobbers + 1 end
        if name == "medic" then medics = medics + 1 end
        if name == "bruiser" then bruisers = bruisers + 1 end
      end
      assert(lobbers <= 1 and medics <= 1 and bruisers <= 1, "the encounter caps specialist roles")
      for _ = 1, 30 do run.random() end
      local deadline = run.time + 8
      while run.squad.wave == wave and run.time < deadline do
        for _, enemy in ipairs(run.enemies) do enemy.health = 0 end
        for _, enemy in ipairs(replay.enemies) do enemy.health = 0 end
        advance(run, 80)
        advance(replay, 80)
        assert(#run.enemies <= 8 and #run.enemies == #replay.enemies)
        if run.squad.incoming and not saw_reinforcements then
          local first = run.squad.incoming
          local deployed = run.squad.deployed
          run.x, run.y = first.x, first.y
          replay.x, replay.y = first.x, first.y
          advance(run, 550)
          advance(replay, 550)
          local rerouted = assert(run.squad.incoming)
          assert(run.squad.deployed == deployed and (rerouted.x ~= first.x or rerouted.y ~= first.y),
            "an occupied reinforcement mark is moved before deployment")
          saw_reinforcements = true
        end
      end
      assert(run.squad.wave == wave+1 and replay.squad.wave == wave+1)
      assert(not run.result and not replay.result, "clearing an endless wave never ends the run")
    end
    assert(saw_reinforcements, "later waves admit queued enemies as slots open")

    local function cover_session()
      local game = Game.new(427, "endless")
      for index = #game.enemies, 1, -1 do game.enemies[index] = nil end
      game.squad.deployed = #game.squad.roster
      local wall = game.cover[1]
      return game, wall, (wall.top + wall.bottom)*0.5
    end
    local cover, wall, centerline = cover_session()
    cover.x, cover.y = wall.left-15, centerline
    cover:move_actor(cover, 24, 0, 3)
    assert(cover.x < wall.left-6 and cover.x > wall.left-7, "movement stops at the edge of cover")
    local protected = cover:spawn_enemy("soldier", wall.right+17, centerline, 7)
    for _, weapon in ipairs({1,2,3,8,11}) do
      cover.weapon = weapon
      cover:fire(Game.weapons[weapon])
      for _ = 1, 20 do cover:update_shots(0.02) end
    end
    assert(protected.health == 54 and cover.hits == 0, "barricades stop all direct shots in the endless loadout")
    local sniper = cover:spawn_enemy("marksman", wall.right+32, centerline, 7)
    cover:fire_enemy(sniper, cover.x, cover.y)
    assert(cover.health == 100, "cover blocks a marksman's beam after it locks")
    sniper.health = 0
    cover.x, cover.y = wall.right+17, centerline
    protected.x, protected.y = wall.left-16, centerline
    advance(cover, 1000)
    assert(cover:line_clear(protected.x,protected.y,cover.x,cover.y), "ranged enemies route around cover")
    assert(cover:can_stand(protected.x,protected.y,protected.surface.radius))

    local routing = cover_session()
    local scout = routing:spawn_enemy("bruiser", 516.4, 383, 3)
    routing.dt = ${tick} / 1000
    for _, route in ipairs({{516.4,383,401.2,261}, {502,370.4,375.9,262.4}, {533.1,375.8,381.5,260.9}}) do
      scout.x, scout.y = route[1], route[2]
      for _ = 1, math.ceil(8/routing.dt) do
        local dx, dy = route[3]-scout.x, route[4]-scout.y
        local distance = math.sqrt(dx*dx+dy*dy)
        if distance < 2 then break end
        if not routing:detour(scout,route[3],route[4]) then
          local step = math.min(1, scout.profile.speed*routing.dt/distance)
          routing:move_actor(scout,dx*step,dy*step,routing.direction_of(dx,dy))
        end
      end
      assert((scout.x-route[3])^2 + (scout.y-route[4])^2 < 4, "corridor routes converge across multiple corners")
    end

    local blocked_charge, ramp, lane = cover_session()
    blocked_charge.x, blocked_charge.y = ramp.left-15, lane
    local charging = blocked_charge:spawn_enemy("bruiser", ramp.right+18, lane, 7)
    charging.aim_x, charging.aim_y, charging.fire_at = blocked_charge.x, lane, 0
    advance(blocked_charge, 480)
    assert(charging.x > ramp.right+charging.surface.radius and not charging.dash_left and blocked_charge.health == 100)
    local throwing = blocked_charge:spawn_enemy("lobber", ramp.right+16, lane, 7)
    blocked_charge:fire_enemy(throwing,blocked_charge.x,blocked_charge.y)
    for _ = 1, 40 do blocked_charge:update_shots(0.02) end
    assert(blocked_charge.health == 73, "lobbed attacks still reach over the barricade")

    local layouts = Game.new(427, "endless")
    local original = layouts.cover
    assert(layouts:rotate_cover(4) and layouts.cover ~= original)
    assert(layouts:can_stand(layouts.x,layouts.y,layouts.surface.radius), "layout changes leave the player's position open")
    local shifted = layouts.cover
    assert(not layouts:rotate_cover(5) and layouts.cover == shifted)
    assert(layouts:rotate_cover(7) and layouts.cover ~= shifted)

    local drops = Game.new(427, "endless")
    local first_cinder = drops:spawn_enemy("cinder", 474, 291, 7)
    local second_cinder = drops:spawn_enemy("cinder", 474, 277, 7)
    first_cinder.health, second_cinder.health = 0, 0
    advance(drops, ${tick})
    assert(#drops.pickups == 1 and drops.pickups[1].id == 6, "duplicate roles drop only one unclaimed weapon")
    drops.x, drops.y = drops.pickups[1].x, drops.pickups[1].y
    drops:collect()
    assert(drops.weapon == 6 and drops.owned[6])
    screen.canvas:remove()
    screen.strip:remove()
  `);
  // Collect the isolated combat fixtures before sampling the app's live heap.
  badge.lua('return __gc()');

  await badge.frames(10);
  assert.equal(state().weapon, 0);
  assert.equal(state().found, 0);
  assert.equal(renderedHealth(), 35, 'the range opens with a full player life bar');
  assert.ok(badge.leds.every(dark));
  if (preview) badge.screenshot(path.join(preview, 'dust-range-unarmed.png'));
  await badge.press('select');
  assert.equal(state().shots, 0);

  await walkTo(502, 320);
  assert.equal(state().weapon, 1);
  assert.ok(badge.leds[0][0] > 106 && badge.leds[0][1] > 56, 'the collected slot flares gold');
  assert.ok(badge.leds.slice(1).every(dark));
  await badge.press('select', { after: 0 });
  assert.equal(state().projectiles, 1);
  assert.equal(state().shots, 1);
  assert.ok(!badge.leds.some(red), 'firing does not trigger a hit pulse');
  if (preview) badge.screenshot(path.join(preview, 'dust-range-preview.png'));
  const hitFrames = Math.ceil(180 / tick);
  let spent = 0;
  while (state().hits === 0 && spent < hitFrames) {
    await badge.frames(1);
    spent++;
  }
  assert.equal(state().hits, 1);
  assert.ok(red(badge.leds[2]) && red(badge.leds[3]), 'the hit lights up the center pair immediately');
  assert.ok(!red(badge.leds[0]) && !red(badge.leds[5]));
  if (preview) badge.screenshot(path.join(preview, 'dust-range-impact.png'));
  await badge.frames(hitFrames - spent);
  await advance(80);
  assert.ok(badge.leds.slice(0, 6).every(red), 'the red pulse reaches both ends of the top row');
  assert.ok(badge.leds.slice(6).every(dark), 'hit feedback does not use the side LEDs');
  await badge.hold('select', Math.ceil(240 / tick));
  assert.equal(state().shots, 2, 'the handgun fires once per press');
  assert.equal(state().hits, 2, 'a second shot damages a standing target');
  await advance(320);
  assert.deepEqual(badge.leds[0], [106, 56, 12], 'the selected slot returns to steady amber');
  assert.ok(badge.leds.slice(1).every(dark));
  await badge.press('select', { after: 0 });
  assert.equal(state().shots, 3);
  await advance(64);
  await badge.press('select', { after: 0 });
  assert.equal(state().shots, 3, 'a tap during recoil waits for the cooldown');
  await advance(84);
  assert.equal(state().shots, 4, 'a buffered tap fires after the cooldown');

  for (const [x, y, weapon, minShots, projectiles] of [
    [571, 261, 2, 3, 1], [370, 378, 3, 1, 5], [399, 257, 4, 1, 1],
    [654, 390, 5, 1, 1], [268, 232, 6, 3, 3],
  ]) {
    if (weapon === 3) await walkTo(state().x, y);
    await walkTo(x, y);
    assert.equal(state().weapon, weapon);
    assert.equal(state().found, weapon);
    const before = state().shots;
    await badge.press('select', { after: 0 });
    assert.equal(state().projectiles, projectiles);
    if (weapon === 2 || weapon === 6) {
      await advance(90);
      await badge.hold('select', Math.ceil(360 / tick));
    }
    assert.ok(state().shots >= before + minShots);
    if (weapon === 4 || weapon === 5) {
      await advance(weapon === 4 ? 420 : 550);
      assert.equal(state().projectiles, 0);
      assert.ok(state().particles >= 20, 'explosive effects appear after flight');
    }
    await advance(1000);
    assert.equal(state().particles + state().projectiles, 0);
  }
  await walkTo(498, 423);
  assert.equal(state().weapon, 7);
  assert.equal(state().found, 7);
  assert.ok(badge.leds[3][0] > 106, 'TNT uses the throwable LED');
  await walkTo(498, 477);
  const beforeTnt = state().hits;
  await badge.press('select', { after: 0 });
  assert.equal(state().projectiles, 1);
  await badge.hold('left', Math.ceil(240 / tick));
  if (preview) badge.screenshot(path.join(preview, 'dust-range-tnt-fuse.png'));
  await advance(1320);
  assert.equal(state().hits, beforeTnt, 'TNT stays planted until its full fuse elapses');
  await advance(96);
  assert.equal(state().hits, beforeTnt + 2);
  assert.equal(state().projectiles, 0);
  if (preview) badge.screenshot(path.join(preview, 'dust-range-tnt-blast.png'));

  for (let weapon = 0; weapon <= 7; weapon++) {
    await badge.press('back', { after: 0 });
    assert.equal(state().weapon, (weapon + 7) % 8, 'Cancel waits for release');
    await badge.frames(1);
    assert.equal(state().weapon, weapon);
  }

  const start = state();
  const key = badge.engine.global.get('__keys_set');
  key('up', true);
  key('right', true);
  await badge.frames(10);
  key('up', false);
  key('right', false);
  const end = state();
  assert.equal(end.direction, 2);
  assert.ok(Math.abs(Math.hypot(end.x - start.x, end.y - start.y) - step * 10) < 0.01);
  await walkTo(17, 17);
  await badge.hold('left', 10);
  await badge.hold('up', 10);
  assert.deepEqual([state().x, state().y], [16, 16]);
  await walkTo(880, 624);

  key('back', true);
  assert.equal(badge.call('on_key', 'back', 0), true);
  await advance(400);
  assert.equal(badge.call('on_key', 'back', 1), true);
  assert.equal(state().weapon, 7, 'gear stays equipped while Cancel is held');
  key('back', false);
  await badge.frames(1);
  assert.equal(state().weapon, 0, 'releasing early cycles gear once');
  assert.equal(badge.exited, false);

  await badge.press('back', { after: 0 });
  await badge.press('back', { after: 0 });
  await badge.frames(1);
  assert.equal(state().weapon, 2, 'two rapid Cancel taps both count');

  key('back', true);
  badge.call('on_key', 'back', 0);
  await advance(400);
  assert.equal(badge.call('on_key', 'back', true), true);
  await frames(1, 1199 - Math.ceil(400 / tick) * tick);
  assert.equal(state().weapon, 2);
  assert.equal(state().scene, 'range');
  await frames(1, 1);
  assert.equal(state().scene, 'menu', 'holding Cancel for 1200 ms opens the menu');
  assert.equal(badge.exited, false);
  assert.equal(state().weapon, 2, 'gear stays equipped while paused');
  assert.ok(badge.leds.every(dark), 'opening the menu clears the gear lights');
  if (preview) badge.screenshot(path.join(preview, 'dust-range-menu.png'));
  badge.call('on_key', 'back', true);
  key('back', false);
  await badge.frames(1);
  assert.equal(state().scene, 'menu', 'repeating and releasing the opening press keep the menu open');
  await badge.press('left');
  assert.equal(JSON.parse(badge.storageJson()).pickup_motion, false);
  await badge.press('right');
  assert.equal(JSON.parse(badge.storageJson()).pickup_motion, true);

  const paused = state();
  await badge.press('down');
  await badge.press('select');
  assert.equal(state().scene, 'specs');
  assert.equal(state().page, 2, 'the guide opens at the equipped weapon');
  await badge.press('left');
  const ledSlots = [1, 2, 3, 4, 5, 6, 4, 2, 1, 4, 6, 6, 5, 5, 3];
  for (let weapon = 1; weapon <= 15; weapon++) {
    assert.equal(state().page, weapon);
    assert.ok(!dark(badge.leds[ledSlots[weapon - 1] - 1]), 'the guide lights the corresponding weapon slot');
    if (preview) badge.screenshot(path.join(preview, `dust-range-spec-${weapon}.png`));
    await badge.press('right');
  }
  assert.equal(state().page, 1, 'paging forward wraps to the first weapon');
  await badge.press('left');
  assert.equal(state().page, 15, 'paging backward wraps to the last weapon');
  await badge.press('select');
  assert.equal(state().page, 1, 'Select advances in the guide');
  await badge.press('down');
  assert.equal(state().enemyPage, 1, 'Down opens the enemy field guide');
  await badge.press('left');
  assert.equal(state().enemyPage, 12, 'the enemy roster wraps independently');
  await badge.press('up');
  assert.equal(state().enemyPage, 0);
  assert.equal(state().page, 1, 'the weapon page is retained across guide tabs');
  await badge.press('back');
  assert.equal(state().scene, 'menu');
  assert.equal(state().choice, 2, 'returning from the guide keeps the menu selection');
  assert.deepEqual([state().x, state().y, state().shots], [paused.x, paused.y, paused.shots]);
  await badge.press('up');
  await badge.hold('select', Math.ceil(480 / tick));
  assert.equal(state().scene, 'range');
  assert.equal(state().weapon, paused.weapon);
  assert.equal(state().shots, paused.shots, 'holding Select to resume never fires the equipped rifle');
  assert.deepEqual(badge.leds[1], [106, 56, 12], 'the equipped light returns after resume');
  await badge.press('select');
  assert.equal(state().shots, paused.shots + 1, 'a new press fires normally');

  await badge.hold('back', Math.ceil(1240 / tick));
  assert.equal(state().scene, 'menu');
  await badge.press('back');
  assert.equal(state().scene, 'range', 'Cancel resumes from the pause menu');
  await badge.hold('back', Math.ceil(1240 / tick));
  assert.equal(state().scene, 'menu');

  const savedRange = state();
  await badge.press('down');
  await badge.press('down');
  await badge.press('select');
  await advance(720);
  assert.equal(state().mode, 'drill');
  assert.equal(state().weapon, 1);
  assert.equal(state().shots, 0, 'Select opens the drill without firing');
  assert.equal(state().health, 100, 'the first shot gives the player time to react');
  assert.equal(renderedHealth(), 35);
  if (preview) badge.screenshot(path.join(preview, 'dust-range-soldier.png'));
  for (let tries = 0; tries < Math.ceil(1500 / tick) && state().health === 100; tries++) await badge.frames(1);
  assert.equal(state().health, 82);
  assert.equal(renderedHealth(), 29, 'player damage shortens the visible health bar');
  assert.ok(badge.leds.slice(6).every(red), 'incoming damage lights the side LEDs');
  assert.ok(!badge.leds.slice(0, 6).some(red), 'the gear LEDs keep their separate hit feedback');
  await advance(240);
  assert.ok(badge.leds.slice(6).every(dark), 'the damage flash fades between hits');
  for (let tries = 0; tries < Math.ceil(9000 / tick) && state().health > 25; tries++) await badge.frames(1);
  await advance(220);
  assert.equal(state().health, 10);
  assert.equal(renderedHealth(), 4, 'the bar remains proportional at critical health');
  if (preview) badge.screenshot(path.join(preview, 'dust-range-player-low-health.png'));
  await advance(9000);
  assert.equal(state().health, 0);
  assert.equal(renderedHealth(), 0, 'the downed player has an empty bar');
  assert.equal(state().result, 'lost');
  assert.equal(state().hits, 0, 'incoming fire leaves the player hit counter alone');
  assert.ok(badge.leds.every(dark));
  const downed = state();
  await badge.hold('right', Math.ceil(320 / tick));
  assert.deepEqual(state(), downed, 'movement and combat stay frozen while down');
  if (preview) badge.screenshot(path.join(preview, 'dust-range-drill-lost.png'));
  await badge.press('select');
  await advance(220);
  assert.equal(state().result, 'active');
  assert.equal(state().health, 100, 'Select restarts the drill at full health');
  assert.equal(renderedHealth(), 35);
  for (let shot = 0; shot < 3; shot++) {
    await badge.press('select');
    await advance(240);
  }
  assert.equal(state().result, 'won');
  assert.equal(state().hits, 3, 'three handgun hits defeat the soldier');
  if (preview) badge.screenshot(path.join(preview, 'dust-range-drill-won.png'));
  await badge.hold('back', Math.ceil(1240 / tick));
  assert.equal(state().scene, 'menu');
  await badge.press('down');
  await badge.press('down');
  await badge.press('select');
  assert.equal(state().mode, 'range');
  for (const field of ['x', 'y', 'weapon', 'found', 'hits', 'shots']) {
    assert.equal(state()[field], savedRange[field], 'the range resumes where the player left it');
  }

  await badge.hold('back', Math.ceil(1240 / tick));
  await badge.press('up');
  await badge.press('up');
  await badge.press('select');
  assert.equal(state().mode, 'squad');
  assert.equal(state().wave, 1);
  assert.equal(state().remaining, 2);
  assert.equal(state().shots, 0);
  if (preview) badge.screenshot(path.join(preview, 'dust-range-squad.png'));
  for (let shot = 0; shot < 3; shot++) {
    await badge.press('select');
    await advance(180);
  }
  assert.equal(state().remaining, 1, 'the wave stays active after a single enemy is defeated');
  await badge.press('left');
  for (let shot = 0; shot < 2; shot++) {
    await badge.press('select');
    await advance(180);
  }
  assert.equal(state().remaining, 0);
  assert.equal(state().weapon, 2, 'clearing wave one supplies the rifle');
  await advance(1650);
  assert.equal(state().wave, 2);
  assert.equal(state().remaining, 3);
  await badge.hold('back', Math.ceil(1240 / tick));
  assert.equal(state().scene, 'menu');
  const pausedSquad = state();
  await advance(500);
  assert.deepEqual(state(), pausedSquad, 'pause freezes the trial and its combat timers');
  await badge.press('down');
  await badge.press('select');
  assert.equal(state().mode, 'squad');
  assert.equal(state().wave, 1, 'retry restarts the selected trial mode');
  assert.equal(state().weapon, 1);
  await badge.hold('back', Math.ceil(1240 / tick));
  await badge.press('down');
  await badge.press('down');
  await badge.press('select');
  assert.equal(state().mode, 'range');
  for (const field of ['x', 'y', 'weapon', 'found', 'hits', 'shots']) {
    assert.equal(state()[field], savedRange[field], 'the trial preserves range progress');
  }
  await badge.hold('back', Math.ceil(1240 / tick));
  await badge.press('down');
  await badge.press('select');
  await badge.press('down');
  assert.equal(state().enemyPage, 12);
  if (preview) badge.screenshot(path.join(preview, 'dust-range-enemy-guide.png'));
  await badge.press('select');
  assert.equal(state().mode, 'practice');
  assert.equal(state().practice, 'cryo');
  assert.equal(state().weapon, 2);
  assert.equal(state().shots, 0, 'the guide opens practice without firing');
  await badge.press('back');
  assert.equal(state().weapon, 11, 'practice supplies the arc projector as a counter');
  await badge.hold('back', Math.ceil(1240 / tick));
  await badge.press('down');
  await badge.press('select');
  assert.equal(state().practice, 'cryo', 'retry retains the selected enemy profile');
  assert.equal(state().weapon, 2);
  await badge.hold('back', Math.ceil(1240 / tick));
  await badge.press('down');
  await badge.press('down');
  await badge.press('select');
  assert.equal(state().mode, 'range');
  assert.equal(state().x, savedRange.x);
  assert.equal(state().y, savedRange.y);
  await badge.hold('back', Math.ceil(1240 / tick));
  assert.equal(state().scene, 'menu');
  await badge.press('up');
  assert.equal(state().choice, 6, "EXIT GAME follows the LEVELS entry");
  await badge.press('select', { after: 0 });
  assert.equal(badge.exited, true, 'Exit Game returns to the launcher');
  assert.ok(badge.leds.every(dark));

  assert.ok(peak < 110_000, `callback budget regressed: ${peak}`);
  assert.ok(peakObjects === 3, `expected two playfield canvases and one menu, saw ${peakObjects} objects`);
  console.log(`Passed at ${tick} ms per tick. Checked the arsenal, controls, LEDs, menus, duel and Squad Trial.`);
  console.log(`Headless peaks: ${Math.ceil(peak)} / 200000 instructions, ${Math.ceil(peakHeap)} KiB sampled Lua heap, ${peakObjects} UI objects.`);
} finally {
  badge.close();
}
