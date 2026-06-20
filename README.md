# Hex Tactics

A hex-grid turn-based tactics roguelite, rebuilt from scratch on **LÖVE 2D** (no Tiled).
Portrait / mobile-first rendering with a fixed design resolution scaled to the screen.

## Run

```
love .            # desktop
```
On Android, pack with `love-android` (the window is portrait & touch-ready).

Placeholder art is generated to `assets/png/` by `tools/gen_pngs.ps1` (GDI+, no LÖVE needed):

```
powershell -ExecutionPolicy Bypass -File tools/gen_pngs.ps1
```
The code falls back to procedural canvas sprites if a PNG is missing, so the game runs
even before generating them.

## Project layout

```
main.lua                 entry point: state machine, camera, input routing
conf.lua                 window / modules
src/core/                hex math, map loader, registry, entity
src/content/             DATA REGISTRIES — add new content here
  terrain.lua            terrain types + rules
  statuses.lua           hex/entity statuses + dig sites
  attacks.lua            attack definitions (dash, shoot, bite, ...)
  units.lua              allies, enemies, obstacles, buildings, trains
  abilities.lua          global mana spells + manager
  trains.lua             train movement
  progression.lua        upgrade choices + artifacts
  objectives.lua         win/lose conditions
src/game/                game.lua (orchestrator), input, ai, pathfinding
src/render/              camera, renderer, ui
src/assets/              sound.lua (procedural SFX), sprites/ (per-category sprite files)
maps/                    *.lua maps in the new table format
tools/gen_pngs.ps1       placeholder PNG generator
```

## Adding new content (the design goal)

All content lives in **registries** — adding something new is one entry, no engine changes.

- **New attack**: add a def to `src/content/attacks.lua` and call `attacks.register({ id=..., name=..., range=..., damage=..., targetMode="melee"|"line"|"cell"|"self", execute=function(a,tq,tr,grid,entities,ctx) ... end })`. Use the shared helpers `attacks.pushEntity`, `attacks.dirTowards`, `attacks.lineFirst`, `attacks.getEntityAt`.
- **New unit / enemy / building**: add a def to `src/content/units.lua` via `units.register({ id=..., name=..., type=..., side=..., maxHealth=..., moveRange=..., attacks={ "atkId", ... }, movement="walk"|"fly"|"hover"|"water_walk", aura=..., ... })`.
- **New global spell**: add a def to `src/content/abilities.lua` (`onActivate`, `onClickHex`, `collectOverlays`, `manaCost`, `key`) and add its id to `abilities.order`.
- **New status**: `statuses.define("id", { color=..., onHexTurnEnd=..., onEntityTurnEnd=..., modifyMoveRange=..., blocksMove=... })` in `src/content/statuses.lua`.
- **New objective**: `objectives.register({ id=..., describe=..., check=... })` in `src/content/objectives.lua`, then reference it from a map's `objective = { type="id", ... }`.
- **New map**: copy `maps/map1.lua`. It's a plain Lua table: `terrain`, `entities`, `statuses`, `digSites`, `trains`, `deployZone`, `objective`, `maxTurns`, `radius`.
- **New sprite**: drop `<id>.png` in `assets/png/` (or `terrain_<id>.png` / `status_<id>.png`). The matching registry in `src/assets/sprites/` picks it up automatically.

## Map format (no Tiled)

```lua
return {
  name = "Crossroads", radius = 4, size = 46, maxTurns = 14,
  terrain = { ["2,-1"] = "railway", ["4,-2"] = "water" },   -- defaults to "grass"
  entities = { { def="Zombie", q=0, r=-4, side="enemy" }, { def="Tower", q=-3, r=2, side="neutral" } },
  statuses = { { type="fire", q=0, r=-3, data={duration=6} } },
  digSites = { { q=-1, r=0, timer=3, spawn="Zombie" } },
  trains   = { { path={{q=2,r=-1},{q=1,r=0},...}, length=2 } },
  deployZone = { {q=-4,r=4}, ... },           -- where the squad may be placed
  objective = { type="kill_all" },            -- or "survive" / "protect" / "kill_target"
}
```

## Controls

- Tap an ally to select; tap a highlighted cell to move; tap the ally again to enter attack mode; tap a red cell to attack.
- **Switch Attack** button (or `Tab`/`Q`) cycles the selected unit's attack.
- **Spells** dropdown (top-right) or hotkeys `H`eal, e`X`tra move, `W`ind, `U`nearth, `M`ind control, `D`ecay.
- **End Turn** button or `R`estart; `Esc` returns to menu; `F5` debug auto-win.
