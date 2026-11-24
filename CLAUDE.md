# Dustpaw

A top-down mission game. It ships on two platforms from one codebase:

| Host | Where | Runs |
| --- | --- | --- |
| Breakpoint 2026 badge (Solana OS) | `apps/dust-range/` itself | Lua 5.4/5.5, int32, strict budgets |
| LÖVE 11.5 (desktop now; RG40XXV via PortMaster later) | `hosts/love/` | LuaJIT, through `compat/lua54.lua` |

Read `README.md` for the game and `hosts/love/README.md` for the LÖVE host.

## One game, many hosts

- **`apps/dust-range/` is the only game code.** Gameplay, levels, balance, menus and art changes go there, once. Never copy game logic into `hosts/`. A host only provides the platform: drawing, input, time, storage, LEDs and later sound.
- **Keeping hosts in sync is automatic, not on request.** Every change to `apps/dust-range/` or `hosts/` is checked on every host before it's called done (see Checks). The user doesn't need to ask.
- **When the game needs a new badge API** (a new `ui.*`, `sys.*` or `storage.*` call, or a new `on_*` callback), add it to `hosts/love/main.lua` in the same change. `tools/love-check.mjs` fails until you do. If the game feature-tests the API and works without it, add it to `OPTIONAL` in `tools/love-check.mjs` with the fallback named.
- **New hosts** (another handheld, web, mobile) go in `hosts/<name>/`. They implement the same badge API, get a check like `love-check.mjs`, and are added to this file.

## Budgets: badge limits stay intact; other hosts add on top

The badge sets the floor. The game must always fit it, whatever other hosts can do.

- **Badge budgets** (enforced by the badge checks; never loosen an assertion to make a change pass): 200,000 instructions per callback, with regression gates in `tools/smoke.mjs` (110k) and `tools/levels-smoke.mjs` (160k); 6 MiB Lua heap; 3 UI objects in play; 64 KiB `main.lua`; 64 bundled files and 1 MiB bundled bytes (`tools/package.py`). At 1.0.1 the package used 676,718 of 1,048,576 bytes and 60 of 64 files. Assets that only bigger hosts use never go in `apps/dust-range/`.
- **The simulation is identical everywhere:** field size, tick timing, damage, enemy behaviour, levels, scoring and saves. A mission must play the same on every host.
- **Extra headroom goes to presentation, behind capabilities.** A host may declare a global `host = {name = "love", caps = {...}}`. The badge has no `host` global. Game code reads it as `local caps = rawget(_G, "host") and host.caps or {}` and defaults every cap to badge behaviour. Examples:
  - **sound:** `caps.audio`. Game code emits named events, for example `Sound.play("rocket_hit")` in a `lib/sound.lua` that does nothing on the badge. The host maps names to files in `hosts/<name>/assets/`.
  - **raised display caps:** caps that exist only for the badge's frame budget, such as the six-bodies-per-floor limit, can rise through a cap value. Caps that change gameplay can't.
  - **more input:** `caps.buttons` for shoulder buttons. These are shortcuts only; every action must stay reachable with the badge's buttons.
- Gate presentation code that costs badge instructions on the cap, so the badge doesn't pay for it.

## Checks (run all of them before calling a change done or cutting a version)

```
node tools/smoke.mjs          # badge: gameplay and budgets on the headless Solana OS (../mosa-badge)
node tools/levels-smoke.mjs   # badge: missions, level rules, saves and level budget
node tools/love-check.mjs     # LÖVE: API coverage, translation, both smoke suites on LuaJIT semantics, boot in LÖVE
python tools/package.py       # badge: builds dist/dustpaw.zip and checks package limits
```

`love-check.mjs` skips the LÖVE boot step when LÖVE isn't installed, and says so. Report that instead of claiming the boot passed.

## Lua rules for game code (all hosts)

- Write for the badge: Lua 5.4/5.5 syntax, int32 integers, integer canvas coordinates.
- 5.4 operators (`//`, `&`, `|`, `~`, `<<`, `>>`) are fine; the LÖVE host translates them. Don't use `<close>`, the `utf8` global or `string.pack`/`unpack`; LuaJIT lacks them (`<const>` is stripped by the translator). `compat/runtime.lua` covers `math.tointeger`, `math.type` and `table.unpack`.
- Don't rely on Lua 5.4's integer/float distinction (`math.type`, `"%d"` with floats, `tostring(3.0) == "3.0"`). LuaJIT has only floats.

## Releasing

- Bump `apps/dust-range/app.json` (SemVer). Update `README.md` for user-visible changes. Write `dist/store-listing-<version>.txt` (summary of 80 characters at most, description, "New in" line).
- Run every check above, then commit as `Dustpaw <version>: <headline>` with a bulleted body.
- The badge upload goes through the Solana OS app loader (https://solana.com/breakpoint/badge/apps/submit) in the user's browser. Uploading publishes, so confirm with the user first.
- LÖVE builds aren't packaged yet. PortMaster packaging for the RG40XXV waits until the LÖVE version has sound and has been well tested locally.
