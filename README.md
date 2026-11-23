# Dustpaw

A top-down mission game for the Breakpoint 2026 badge. It uses the Lua canvas and controls from the Mosa Badge development environment.

## Play

Open the [Solana OS app loader](https://solana.com/breakpoint/badge/apps/submit) and drop in `dist/dustpaw.zip` or the `apps/dust-range` folder. Choose **Try in emulator** to play in the browser or **Run on badge** to sideload over USB.

Use Solana OS 2.0 or newer for the 6 MiB Lua heap. The app uses the LED permission. Solana OS 2.3 and later support its 16 ms tick request.

Dustpaw has two modes: **Missions**, the main game, and the **Testing Range**. The game opens on the **Mission Map**. Only Backyard is open at first: each rescue unlocks the next mission, and cleared missions stay open to replay. Locked stops show a padlock and can be browsed but not opened. Select Backyard to see its title card, then press **Select** to start. Walk up to the kitten to pick it up, then carry it to the exit. Its cries wake every guard, and from Farmhouse on an alarm squad moves in near the exit. You move 15% slower while carrying it. In missions with several waves, each wave from the second one on is a checkpoint: if you go down, press **Select** to retry from the start of that wave with the health, weapons, score and time you had when it arrived. **Retry Mission** in the pause menu starts over from the briefing. After a successful rescue, press **Select** to return to the map. Cleared missions are saved on the device, and the map highlights the first unfinished mission when you return from a rescue or relaunch the game.

Weapons you pick up in a mission are saved as soon as you collect them, even if the rescue fails. Every later mission starts with its own loadout plus your saved weapons, and **Cancel** cycles through all of them. The Testing Range and enemy practice keep their own gear and don't add to your saved weapons.

On the map, press **Left/Right** to follow the route and **Select** to open the briefing of any unlocked location. Press **Up** for the Testing Range and **Down** for Weapon Specs.

- **D-pad** moves the hero and sets the firing direction. Double-tap a direction to dash about 50 px. You take no damage during the dash, and you can dash again after 0.7 seconds. Hold a second direction while tapping to dash diagonally. Walk over a floating weapon to pick it up and equip it. When the nearest available pickup is at the edge of the screen or beyond it, the marker is amber for weapons and a green cross for medkits.
- **Select** fires, throws, swings, or places the equipped item. Hold it for the rifle, flamethrower and cryo sprayer. Hold and release it to fire the charge cannon. The range has unlimited ammunition.
- Tap **Cancel** to cycle through collected weapons and the unarmed stance. Hold **Cancel** for 1.2 seconds to pause at the menu.
- Every pause menu has the same entries in the same order: **Resume**, **Retry** (in a mission or practice), **Mission Map**, **Testing Range** (when you're not already there), **Weapon Specs** and **Exit Game**. Use **Up/Down** and **Select** to choose. Use **Left/Right** on the pause menu to toggle pickup bobbing. In Weapon Specs, **Left/Right** browse weapons and **Select** goes to the next page. **Cancel** goes back one screen: to the menu, or to the map if you opened Weapon Specs there. **Home** returns directly to the launcher.
- In **Weapon Specs**, press **Down** for the Enemy Field Guide. Browse enemy profiles with **Left/Right** and press **Select** to practice against that enemy. **Up** returns to Weapon Specs. The medic practice includes an injured ally so you can try interrupting the heal.

The pickup message points toward that weapon's test target. The direction follows the D-pad, so tap toward the target before firing. You can shoot any target with any weapon.

Each target has a health bar. The HUD shows the damage type, damage dealt, and remaining health. A blast that hits several targets reports their combined damage. Each shot or flame pulse counts once per target, even when several pellets land. Burn ticks continue draining health after you release Select. Targets recover after three seconds without damage or about two seconds after breaking.

The six top LEDs show the equipped weapon's family: 1 pistols (handgun, bankshot), 2 rifles (assault rifle, rail rifle), 3 close range (shotgun, shock hammer), 4 throwables (grenade, TNT, boomerang disc), 5 heavy (rocket launcher, charge cannon, gravity orb) and 6 projectors (flamethrower, arc projector, cryo sprayer). A newly collected slot flares gold, the weapon in hand glows amber, and a confirmed hit sends a red pulse from the center to the edges.

Your health is shown at the right of the HUD in every mode. Enemy practice starts at 100 HP; each mission sets its own starting health. When wounded, you also get a small bar above your character. The playfield border and two side LEDs flash on damage, and the HUD warns at 25 HP or below. The weapon-testing range is safe for testing your gear.

Walk over a medkit in a mission to restore up to 30 HP. A medkit stays available until you pick it up while wounded.

In missions, earn 10 points per enemy hit and 100 extra when an enemy goes down. Defeats less than 2.5 seconds apart build a streak: the second is worth 200, the third 300 and every later one 400. Each defeat briefly holds the action and shows the points it earned above the enemy. Multiple pellets from one shot award 10 points per enemy hit. Extracting with the kitten earns 500 points. Each successful mission also awards a time bonus of 600 if you finish within the mission's par time. Past par, the bonus drops by 10 per second.

Walk over a hamburger to double combat and rescue points for 10 seconds. Another hamburger restarts the countdown. The HUD shows your score and the remaining boost time, and the mission results show the final score, your time and the time bonus.

Each mission has three stars: one for the rescue, one for finishing within par time, and one for losing no more than a quarter of your starting health. The briefing lists the three goals, and the stars you've earned stay lit. Stars add up across runs, so you can go for one goal at a time. The device saves your best score and best time for each mission and shows them on the briefing. The results screen marks newly earned stars and any new best. The Mission Map shows each mission's stars under its marker and your star total at the top right. Clears saved before stars were added count as one star.

## Missions

Ten kitten rescues, from a backyard with one guard to a three-wave assault on a fortress. Each mission adds weapons, enemy types and new ways to hide the kitten:

| # | Mission | New in this mission |
| --- | --- | --- |
| 1 | Backyard | One soldier, the kitten in plain sight |
| 2 | Orchard | Assault rifle pickup, a runner, the kitten behind a hedge |
| 3 | Farmhouse | Shotgun in the coop, a rifleman, the kitten under a roof |
| 4 | Crate Yard | Grenades, scatterguards, a lobber, barrels, the kitten boxed in by crates |
| 5 | Riverside | Rail rifle, wardens on the bridge, a marksman, a second wave, the kitten on an island |
| 6 | Hedge Maze | Boomerang disc and arc projector, skirmishers, a medic, the kitten at the centre |
| 7 | Burning Barn | Cryo sprayer and flamethrower, cinders, a bruiser, fire pits |
| 8 | Cold Storage | TNT, rocket launcher, charge cannon, cryo techs, a rooftop marksman, the kitten in a sealed vault |
| 9 | Outpost | Every material in the tileset, the kitten in the barn across the river |
| 10 | Fortress | Gravity orb and shock hammer, all enemy types, three waves, rooftop marksmen |

## Enemy practice

- In **Weapon Specs**, press **Down** for the Enemy Field Guide and **Select** to practice against any enemy. You start with the handgun and assault rifle, plus the arc projector as a counter.
- Runners circle at a distance and rush in one at a time, then mark the ground before striking. Riflemen fire bursts, and scatterguards hold just inside their short spread. Lobbers mark a grenade's landing zone. Wardens lower their frontal shield while aiming, and skirmishers strafe between shots. Hit a medic during its green cue to interrupt a heal. Sidestep a bruiser's marked charge or interrupt it with the arc projector. Bruisers back off after each charge. Marksmen show a pink lane before they fire. A red edge marker points to an enemy beyond the screen.
- Cinders can leave the player burning. Cryo techs slow movement until their frost wears off or a follow-up hit shatters it. The HUD shows BURNING or CHILLED while those effects are active.
- At 0 HP, combat stops. After a win or loss, press **Select** to retry at full health. Hold **Cancel** to pause, then choose **Testing Range** to resume the original weapon-testing session.

## Level editor

Run `node tools/level-builder/server.mjs` and open http://localhost:5178 to build missions. To make a rescue mission, choose **Rescue kitten and carry it to the exit**, then place a **Kitten** and an **Exit** with the Entities tool. Export the level to add it to the **Mission Map**. [Level editor guide](docs/LEVELS.md)

## Weapon and target specifications

Damage values are game points before target modifiers. Distances are measured in the game's native pixels from the weapon muzzle. The [range profiles](apps/dust-range/lib/range.lua) define the values used by the game.
The in-game guide displays every weapon from the start, including gear you haven't picked up yet.

| Weapon | Damage and effect | Travel | Test target from cache |
| --- | --- | --- | --- |
| Handgun | 18 impact per shot. Leaves a single mark. | 118 px | **East to the board** (70 HP). Its plain surface shows single-hit damage. |
| Assault rifle | 32 impact per shot. Hold Select for repeated hits. | 150 px | **North to the steel plate** (110 HP). It takes 55% impact damage. Fire both guns at the board to compare their full damage. |
| Pump shotgun | Five pellets, up to 12 each. Pellet damage drops with travel and the spread widens. | 62 px | **West to the pattern board** (90 HP). Step closer, then compare the marks and damage from near and far shots. |
| Grenade | Up to 70 blast damage per target, falling to 25% at the edge. Detonates at the end of its arc and leaves a black scorch patch after the smoke clears. | 36 px, 36 px blast radius | **North to the three markers** (85 HP each). Throw from the cache to compare the center marker's health bar with the outer two. |
| Rocket launcher | Up to 82 blast damage per target, with 54 extra on direct contact. The splash falls to 25% at the edge. | 92 px, 28 px blast radius | **East to the block** (155 HP). It takes 45% impact damage and full blast damage. Aim at the block, then try a near miss. |
| Flamethrower | Three streams per pulse at 3 damage each. A hit adds four burn ticks of 5 damage over 1.2 seconds. Fresh heat refreshes the burn. | 26 px | **West to the cloth screen** (55 HP). It takes 150% heat and burn damage. Fire once at close range and watch it keep burning. |
| TNT | Up to 120 blast damage per target, falling to 20% at the edge. The fuse bar shrinks before the blast and a scorch mark remains. | Planted at your feet, 1.6 s fuse, 47 px blast radius | **South to the two blocks** (155 HP each). Walk between them, tap Select, then step back to watch the blast. |
| Rail rifle | 40 pierce damage to every target on the line. Each target after the first takes 80% of the previous hit. | 177 px | **East to the three planks** (60 HP each). One shot from the cache pierces all three. |
| Bankshot | 22 impact per shot, 150% after bouncing off an angled reflector. | 165 px including the bounce | **East to the reflector**, which turns the round north onto the **offset plate** (70 HP). |
| Boomerang disc | 24 slash damage on the way out and again on the return. Catch the disc before throwing again. | 71 px out, then back to you | **West to the post** (75 HP). Stand in line with it to land both hits. |
| Arc projector | 28 shock damage to the first target, then 70% to up to two targets within 42 px of it. | 96 px | **East to the three nodes** (65 HP each). Hit the front node to chain to the other two. |
| Cryo sprayer | Three streams of 2 frost damage per pulse. Frost lasts 4 seconds. Any other hit shatters it for 30 bonus damage. | 26 px | **South to the frost dummy** (95 HP). Coat it, then switch weapons and shoot it. |
| Charge cannon | 18 to 90 energy damage, scaling with a charge of up to 1 second. A full charge also hits targets within 14 px. | 120 px | **North to the bulwark** (200 HP). It takes 125% energy damage and 50% impact damage. |
| Gravity orb | Opens a well where the orb stops. The well pulls light targets within 34 px, then collapses after 1.5 seconds for 18 damage. | 60 px | **West to the three crates** (60 HP each). They return to their places when they recover. |
| Shock hammer | 34 smash damage across a 150° arc in front of you. Light targets are knocked back 24 px. | 20 px reach | **South to the two pads** (70 HP each). Stand next to them and swing. |

## Starter arsenal

The 15-weapon roster keeps the original six and adds nine distinct ways to hit a target. All 15 are playable, each with its own cache and test target.

| Addition | Behavior |
| --- | --- |
| TNT | Drops at the player's feet. Its short fuse gives the player time to move before a wide blast. |
| Rail Rifle | Pierces multiple targets lined up behind one another. |
| Bankshot | Ricochets off one angled reflector to reach an offset target. |
| Boomerang Disc | Can hit targets on the outward flight and again on the way back. |
| Arc Projector | Chains from the first target to its nearest neighbors. |
| Cryo Sprayer | Coats targets in frost. A follow-up impact shatters the coating for bonus damage. |
| Charge Cannon | Hold Select to build a charge, then release to fire. |
| Gravity Orb | Pulls lightweight targets into a cluster for a follow-up shot. |
| Shock Hammer | Sweeps a close-range arc and knocks lightweight targets back. |

## Assets and testing

Source assets live in `sprites/`. The hero uses eight-direction, 28 Ã— 28 walk and idle poses. The playfield displays its native pixels at 2Ã—. The HUD uses display pixels directly.

On firmware that supports `sys.tick`, the game requests a 16 ms update interval. Movement and weapon timing use elapsed time, and the walk cycle follows distance traveled. Firmware caches the terrain as native images. The headless host draws the same pixels from the packed tile data.

Each of the 15 weapons has a hero walk sheet (`sprites/hero/walk-<weapon>.png`) and an idle column in `idle-hero.png`. Effect sheets for the starter-arsenal weapons live in `sprites/effects/<weapon>/`. `effects-layout.json` gives each sheet's frame size, frame rate, use (fire, travel, impact and so on), playback and the frame where looping starts. Directional sheets have one row per facing, N to NW. The rail beam and arc bolt are tiles that repeat every `tileStep` pixels along the shot. TNT reuses the existing blast, scorch and fuse art in `art/effects.lua` and `lib/view.lua`.

- `python tools/build_assets.py` regenerates the packaged Lua artwork after PNG edits, including one `art/fx-<weapon>.lua` module per effect set. It requires Pillow.
- `python tools/draw_new_weapon_art.py` drew the first pass of the starter-arsenal hero sheets and effect sheets. It overwrites those PNGs, so run it only to start over. Edit the PNGs directly after that.
- `node tools/smoke.mjs` checks the range, enemy practice, menus, input, and LEDs with the sibling `mosa-badge` headless host at 16 ms per tick. It reports callback instructions, sampled Lua heap, and UI objects.
- `node tools/bench.mjs` measures startup, combat in the Fortress mission and repeat retries. It estimates sideload file-read costs and compares the packed-run fallback with a model of the native RGB565 tile renderer. On the badge or official emulator, `lua mem` in the console reports the previous run's actual peaks after closing the app.
- `node tools/love-check.mjs` checks that the [LÖVE version](hosts/love/README.md) still runs the current game. It runs both smoke suites on the LuaJIT translation and boots the game in LÖVE when LÖVE is installed.
- Both tools accept `DUST_RANGE_TICK_MS=30` for the original cadence, `DUST_RANGE_APP_DIR` for an extracted release, and `MOSA_BADGE_DIR` for a different headless host checkout.

Enemy profiles in `apps/dust-range/lib/enemies.lua` define health, hit radius, movement, weapons, and behavior. Range-keeping (`fire_range` and `retreat_range`), the melee standoff ring (`standoff`), and charge and support behavior live in `lib/ai/`. `lib/squad.lua` holds the attack schedule missions share, which staggers attack releases and lets only one melee rush start at a time.

Run `python tools/package.py` to rebuild `dist/dustpaw.zip` and check file count, unpacked size, and path limits.
