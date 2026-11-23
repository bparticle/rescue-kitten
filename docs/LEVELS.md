# Levels and tiles

Dustpaw levels are tile maps built with the local level builder and exported as Lua modules the badge loads from `apps/dust-range/levels/`. Tiles are 16 × 16 native pixels, drawn top down like the rest of the game.

## Run the builder

```
node tools/level-builder/server.mjs
```

Open http://localhost:5178. Saved levels go to `levels/<id>.json`. **Export to badge** writes `apps/dust-range/levels/<id>.lua` and rebuilds `levels/index.lua`, which adds the level to the **Mission Map**. Set **Menu order** to place it on the route. **Briefing** is an optional line shown on the mission's briefing screen. It wraps to two lines of 27 characters, and the badge font has letters, digits and `/ . % < > + -`. **Build ZIP** runs `tools/package.py`.

Each map region holds up to ten locations. Further exports continue the same route onto the next region. New missions use a camp illustration by default. To give a mission its own landmark, add its level ID and drawing to `tools/draw_overworld.py` and run `python tools/draw_overworld.py` to regenerate the packed artwork. Completion is saved by level ID, so reordering missions keeps their cleared status. A mission is open when it comes first, is cleared, or follows a cleared mission on the route.

| Key | Tool |
| --- | --- |
| B / R / F / E | Paint, rectangle (Shift for an outline), flood fill, erase |
| I or Alt+click | Pick the tile under the cursor |
| H | House: walls, floor, roof, a south doorway and optional wall openings in one drag |
| N | Entities: player spawn, enemies (kind, facing, wave, surface), weapon pickups, medkits, hamburgers, kitten, exit |
| Space or right-drag, wheel | Pan and zoom |
| 1 / 2 / 3, [ / ] | Ground, structure and roof layer, brush size |
| O / T / G | Cycle collision overlay, roof display, grid |
| Ctrl+Z / Ctrl+Y / Ctrl+S | Undo, redo, save |

Other tools:

- `node tools/levels-smoke.mjs` checks rooftop combat, tile interactions, Outpost, every bundled mission (valid, a kitten rescue, kitten and exit reachable), the mission map and the badge's per-tick budget in the headless host.
- `node tools/level-builder/campaign.mjs` drafted the ten missions. It skips levels that already exist in `levels/`, so builder edits are safe. `--force` redrafts and overwrites them, and you can name level ids to redraft only those.
- `node tools/level-builder/export.mjs` re-exports every level in `levels/` without the editor, for example after changing tile properties.
- `python tools/draw_tiles.py` redraws `sprites/tiles/tileset.png`. `python tools/build_assets.py` packs it with the properties into `art/tiles.lua`.
- `node tools/level-builder/sample-outpost.mjs` rebuilds `levels/outpost.json` (mission 9) and overwrites builder edits to it. Outpost uses all 45 materials: bridge decking, a gravel path with planters, a sandy bank, cracked asphalt, a metal checkpoint, both barbed wire directions, debris, and ridges, vents and a skylight on the roofs.

## Painting connected tiles

- Paint roofs, asphalt, cobblestone, gravel, sand, rugs or water as a patch or path. Changes update the neighbouring edges, including diagonal cutouts. The roof edge includes an eave and gutter.
- Paint a skylight, vent or ridge over any roof. Paint the roof material again to clear the detail, or erase the cell to cut a hole. Details hide with the rest of their roof when the player enters.
- Paint narrow walls and cover cell by cell or use a one-tile rectangle outline. Adjacent ends connect automatically. Add an open doorway to make a walkway through a wall. Wall openings look like a sill between top-down jambs and let shots pass.
- Paint a strip of road markings through asphalt or cracked asphalt. Connect the strip around bends and through junctions. Roads and paths preserve the dirt, grass or mud under their trimmed edges when painted over terrain. Rugs preserve the floor underneath.

## Kitten rescue missions

Set **Objective** to **Rescue kitten and carry it to the exit**. Place one **Kitten** and one **Exit** with the Entities tool, then export the level. The player picks up the kitten by walking up to it and completes the mission at the exit. Enemy waves are optional. All ten bundled missions are rescues: open `backyard` for the simplest one.

The builder warns when the kitten **cannot be reached on foot**. Crate Yard and Cold Storage do this on purpose: crates and brick walls seal the kitten in, and the player breaks through. `levels-smoke.mjs` checks that destructible tiles open a way through in every bundled mission.

Place a **Hamburger** from the Entities tool to give players 10 seconds of double combat and rescue points when they walk over it.

## Rooftop enemies

In **Entities → Enemy**, set **Surface** to **Rooftop** and place the enemy on a painted roof. The **Rooftop** overlay highlights the deck and any blockers tall enough to reach it. Ranged enemies stay on their connected roof, which is 24 px above ground. Place runners and bruisers on the ground so they can reach the player.

Shots and sightlines can clear low walls, but a tall tree or the roof deck itself can intercept them. To return fire, step outside the building and aim along the enemy's line on screen. Direct-fire weapons pick up a visible rooftop target when there is no closer ground target in the lane. Give players a clear angle from outside the roof edge when a rooftop enemy is required for the objective.

## Tile property checklist

Every tile's behaviour comes from `sprites/tiles/materials.json`. The game, the asset packer and the builder all read that one file.

- [x] **walk**: blocks movement for the player and enemies. Enemies route around it.
- [x] **shots**: stops direct fire, including bullets, beams, streams and rockets. Walking barriers also stop enemy melee attacks.
- [x] **lobs**: stops grenades, lobber shells, discs and gravity orbs. Low cover such as sandbags leaves it off, so grenades arc over.
- [x] **sight**: blocks enemy line of sight. Hedges and bushes hide you without stopping bullets.
- [x] **pierce**: the rail rifle passes through it (wood walls, crates, trees).
- [x] **hp** and **breaksTo**: gunfire and blasts wear down tiles until they break. Shots still damage fences, wire and rail-pierceable props when passing through. Neighbouring walls re-join around the gap.
- [x] **explodes**: a blast when destroyed. Explosive barrels hurt everyone nearby and chain into other barrels.
- [x] **slow**: speed multiplier for anyone standing on the tile (mud, sand, shallow water, bushes, barbed wire, rubble).
- [x] **hazard**: damage per second to the player (barbed wire, fire pit).
- [x] **overhead**: roofs cover ground actors and effects, hide while you stand below, and support rooftop enemies. Ground-level throws can travel within the same building. The roof intercepts incoming throws and shots that cross the deck.
- [x] **autotile**: walls, fences, hedges and sandbags join at ends, corners and junctions. Shaped surfaces pick from 47 outlines, including inside corners. Openings and doorways turn to follow adjoining walls. Road markings follow asphalt and connect around turns.
- [x] **span** and **bounds**: walls and props use collision footprints that follow their visible shape. The movement and gunfire overlays show those footprints.
- [x] **height**: the top of an obstacle. Elevated rays clear it when their path stays above it.

| Tile | Movement | Gunfire | Grenades | Sight | Other |
| --- | --- | --- | --- | --- | --- |
| Stone wall | ✓ | ✓ | ✓ | ✓ | Indestructible |
| Brick wall | ✓ | ✓ | ✓ | ✓ | 320 HP, leaves rubble |
| Wood wall | ✓ | ✓ | ✓ | ✓ | Rail pierces, 150 HP |
| Wall opening | ✓ | – | – | – | Shoot through, can't walk through |
| Open doorway | – | – | – | – | Decorative threshold |
| Metal wall | ✓ | ✓ | ✓ | ✓ | Indestructible |
| Sandbags | ✓ | ✓ | – | – | Low cover, 220 HP |
| Wood fence | ✓ | – | – | – | 40 HP |
| Hedge | ✓ | – | – | ✓ | Hides you |
| Crate | ✓ | ✓ | – | – | Rail pierces, 60 HP |
| Explosive barrel | ✓ | ✓ | – | – | 15 HP, 70 damage blast over 34 px |
| Boulder | ✓ | ✓ | ✓ | ✓ | |
| Planter | ✓ | – | – | – | |
| Tree | ✓ | ✓ | ✓ | ✓ | Rail pierces |
| Bush | – | – | – | ✓ | 70% speed |
| Barbed wire (E–W, N–S) | – | – | – | – | 50% speed, 14 HP/s, 30 HP |
| Fire pit | – | – | – | – | 24 HP/s |
| Deep water | ✓ | – | – | – | Shoot across rivers. Blasts in water splash. |
| Shallow water, mud, sand | – | – | – | – | 60%, 85% and 90% speed |
| Roofs (red, slate, thatch, tin) | – | – | ✓ from outside | – | Overhead |

## Level capability checklist

- [x] Three layers per cell: ground, structure, roof.
- [x] Terrain brushes reuse the range's dirt, grass and mud tiles with random variants and rotations. **Regenerate terrain** runs the game's own terrain generator from a seed.
- [x] Player spawn and facing, starting health and starting loadout.
- [x] Enemies of all 12 kinds, with facing and wave number. The first wave holds position until it sees you or is hit. Later waves arrive hunting.
- [x] Weapon pickups for all 15 weapons.
- [x] Medkits that restore up to 30 HP when a wounded player walks over one.
- [x] Objectives: clear every wave, reach the exit, clear then exit, or carry a kitten to the exit.
- [x] Enemy pathfinding over the tile grid, eight ways without cutting corners.
- [x] Walls shield actors and destructible tiles from blasts. Walls and roofs also block gravity and charged-shot splash across them.
- [x] Builder checks for placement clearance, rooftop support, walking routes, objectives and nearby starting enemies.
- [x] Collision overlays for movement, gunfire, thrown weapons, sight, destructible tiles and rooftops, plus a badge-screen frame.
- [x] The level loads over several ticks behind the loading screen and routing refreshes 100 cells per tick, so a 96 × 96 level stays inside the badge's per-callback budget.

## Limits

- Levels are 10 × 7 to 96 × 96 tiles. A 96 × 96 level with 24 enemies peaked at 132,000 of 200,000 instructions per tick and about 3 MB of Lua heap in the headless host.
- Each exported level is one bundled file. With the ten missions the app uses 58 of 64 files and 972 KB of the 1 MiB package, so about five more missions of Outpost's size (10 KB) fit.
- `art/tiles.lua` is 212 KB of the 256 KiB per-file limit. Each new area material (47 outlines) adds 14 to 20 KB, so only two or three more fit unless their art is simplified.
- Tiles keep their own palette of up to 91 colours, separate from the sprite palette. The atlas uses 89.
- Actors use a 6 px body against tiles, so every enemy fits through a one-tile doorway.

## Export format

`apps/dust-range/levels/<id>.lua` returns the level size, objective, health, loadout and entities. It also has one string per layer, with one or two characters per cell. Each character indexes that layer's legend of `material/variant` keys, or `T<n>` for range terrain tiles. An `@` suffix can add supporting artwork such as a surface underneath, lane markings or a roof detail. The first line holds JSON metadata that the builder uses to rebuild `index.lua`.
