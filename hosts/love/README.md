# Dustpaw on LÖVE

Runs the badge app in `apps/dust-range` unchanged on [LÖVE 11.5](https://love2d.org): Windows, macOS, Linux, and Linux handhelds such as the ANBERNIC RG40XXV through PortMaster. The badge stays the source of truth; this folder only adds the platform layer.

## Run

From the repository root:

```
love hosts/love
```

Use `lovec` on Windows to see errors in the console.

| Badge | Keyboard | Gamepad |
| --- | --- | --- |
| D-pad | Arrow keys | D-pad or left stick |
| Select | Z, Space, Enter | A |
| Cancel | X, Backspace | B |
| Home | Esc | Guide, or Start + Back |

F11 toggles fullscreen. On ARM devices the game starts fullscreen. Set `DUSTPAW_FULLSCREEN=1` to force fullscreen and `DUSTPAW_SWAP_AB=1` if a device maps Select to the wrong button.

## How it works

- `main.lua` provides the part of the Solana OS API the game uses: `ui.canvas` (with `rect`, `pixel`, `line` and `show`), `sys`, `led`, `storage` and the `on_key`, `on_tick` and `on_exit` callbacks. Canvases are drawn in creation order, scaled to whole pixels where the window allows. The eight badge LEDs appear in a strip above the app area: six at the top centre and the two side LEDs at the edges. The frame is 320 × 240, so it scales exactly 2× on a 640 × 480 handheld.
- The badge runs Lua 5.4/5.5 and LÖVE runs LuaJIT (Lua 5.1). `compat/lua54.lua` translates each game file when it loads, turning `//`, `&`, `|`, `~`, `<<`, `>>` and unary `~` into calls defined in `compat/runtime.lua`. Line numbers stay the same, so error messages point at the original source. The badge build doesn't use these calls, so its instruction budget is unaffected.
- `ui.load` isn't provided, so tiles are drawn from their packed runs, as on the headless host.
- Storage is saved to `storage.lua` in LÖVE's save folder (`%APPDATA%/LOVE/dustpaw` on Windows).
- The game is read from `game/` inside a packaged `.love` file if present, otherwise from `../../apps/dust-range`, or from `DUSTPAW_GAME_DIR`.

## Check

`node tools/love-check.mjs` confirms that the LÖVE host still runs the current game. It checks API coverage and the translation, runs both smoke suites with LuaJIT semantics, and boots the game in LÖVE. Run it with the badge checks after every game change. The rules for keeping hosts in sync and protecting the badge budgets are in `CLAUDE.md`.

## Not done yet

- Packaging: a `.love` with `apps/dust-range` copied under `game/`, plus a PortMaster port folder (launch script, `port.json`, and the LÖVE runtime PortMaster provides).
- Testing on the RG40XXV itself, including which physical button SDL reports as A.
- Sound and other features beyond the badge's limits, behind a capability table the game can check.
