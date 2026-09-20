# AGENTS.md

## Run the game

```powershell
cd "C:\Users\80STH\Desktop\test"
& "C:\Program Files\LOVE\love.exe" .
```

Love2D 11.5 installed. The game window will open — close it manually when done testing.

## Architecture map (read this first — saves exploration tokens)

- **Hero-only game**: one playable hero (`hero` global, `selectedHero` = hero def index in
  `entity/environment.lua`; `environment.createHero(def, q, r)`). Squad code was fully deleted.
- **Deploy**: `gamePhase == "deploy"` → player places hero → `confirmDeploy()` (core/game.lua)
  applies landing effects via `system/deploy_effects.lua` (`entity.deployEffect` registry).
- **Entity types** (entity/entity.lua): CHARACTER / OBSTACLE / BUILDING / EDGE (map borders,
  invulnerable, immune to statuses/dig sites).
- **Mechanism button** (top-right, `ui.drawMechanismButton` → `activateMechanisms()` in
  core/game.lua, 1-turn cooldown `mechanismUsedThisTurn`, reset in transitionToPlayerTurn):
  1. retractable highground (map field `retractable = {["q,r"]=true}`; upper-terrain marker
     `"lift"`; animation via `highgroundAnim` + `highgroundAnimInfo/CatchUp` in main.lua)
  2. teleporters (`system/teleporters.lua`; upper terrain `"teleporter:<id>"` pairs;
     button-activated only; undo re-runs `teleporters.scan(utm)` to reset cooldowns)
  3. conveyor belts (upper terrain `"conveyor:<dir>"`; dirs n/ne/se/s/sw/nw =
     `HexGrid.CONVEYOR_DIRS` cube steps — flat-top hexes have NO pure e/w neighbors;
     push into occupied cell = collision: `combat.applyCollisionDamage` + bounce)
- **Undo** (`system/undo.lua`): snapshot AFTER an action; `undo.undoLast()` pops to previous.
  Restores entities (by ref), hexStatuses, upperTerrain, terrainMap, elevationMap, digSites,
  abilities, mechanism flags, graveyard, `summonReviveUsed`.
- **Global abilities** (`system/global_abilities.lua`): one object per ability in
  `registry`. Commanders were removed — squads are just the hero, and its global abilities come
  from the hero def's `abilities` list (`environment.getHeroAbilities(idx)`), applied via
  `global_abilities.setSquadAbilities(names)`. Heal is universal for every squad
  (`global_abilities.universalAbilities`); "Revive <summon>" buttons are dynamic (graveyard) and
  need no unlock. `getDisplayOrder(state)` hides an ability while its optional `ab:isUsable(state)`
  returns false (e.g. Heal hides when nobody is wounded/debuffed). Hovering an affordable ability
  sets `state.previewManaSpend` so the top mana bar blinks the cells it would drain (chaos-threat
  style). Heal = +1 HP and cleanse all debuffs (fire/acid/decay/rooted/slow,
  keeps `empowered`) for EVERY living playable ally. Dead `e.isSummon` allies (Blade summons)
  get a per-summon "Revive <name>" button that resurrects the real summon at full HP with
  actions but `movesLeft = 0` (movement spent for the turn); once-per-summon tracked in
  `_G.summonReviveUsed` (snapshot/reset with graveyard).
- **EVERY ability and attack MUST be undoable (hard rule)**: any new/changed ability or attack
  that mutates battlefield state (terrain like Void's "emptiness", entities, hex statuses,
  upperTerrain, dig sites, globals) MUST call `undo.snapshot()` on the execute path and any new
  state it touches MUST be added to both `undo.snapshot` and `undo.restore`. If undoing does not
  fully revert it, the ability is not done.
- **Overlap guard**: `rebuildEntityIndex()` (main.lua) runs every frame and warns
  `[WARN] ENTITY OVERLAP` with traceback; AI batch moves reserve destinations via
  `_reservedCell` (combat/ai.lua `moveToCell`).
- **AI danger avoidance**: `isCellDangerousForEntity(q,r,e)` (combat/ai.lua) = dig site
  (`status.hasDigSite` — NOT in hexStatuses!) + fire/acid/decay; dangerous cells are
  lowest-priority fallback in all move paths.
- **Trains** live only on `maps/map3.lua` (railway/tunnels). Creature Lab, Shop, Progression
  mode are LIVE but kept by owner request. Generic shop upgrades are recorded but NOT yet
  applied to the hero (`ponytail:` marker in ui/shop.lua `applyTake`).
- **Hex geometry (flat orientation)**: x = q·1.5R, y = r·1.732R, odd columns +0.5H down.
  Neighbors = N/NE/SE/S/SW/NW (screen). Cube↔axial via grid/hex_utils.lua.
- **HP bars** (`ui.drawChaosBar` hero, `ui.drawLeaderHPBar` map4): static; only the
  potentially-lost cells flicker when `state.previewDamaged[entity]` (hovered attack threat).
- **Attacks + visual hints MUST stay in sync (hard rule)**: any change to an attack's
  gameplay (new attack, damage/push/collision/status change, passive like Bulwark's
  `pushSpike`/Spikebound's `flipPad`) MUST be mirrored in the preview/hint layer, or the
  UI lies to the player. The single source of truth for collision prediction is
  `attack_preview.predictCollision` (`ui/attack_preview.lua`) — update BOTH the execute
  path (`combat/combat.lua`, e.g. `pushTargetToHex`/`applyCollisionDamage`) and this
  predictor, plus the attack's `attack_preview` handler if it has one. `ui.checkCollisionDamage`
  and the AI/threat + global-ability previews all route through `predictCollision`, so fixing
  it there covers them. Attack damage/push icons are derived from the computed preview
  (`preview.compute` → `applyPush`/`addCollisionDamage`/`getDamageIcon`); conveyor-belt
  collision hints (`ui/ui_buttons.lua` mechanism panel) are a separate coarse path. Keep the
  doc comment above `predictCollision` (`damage`/`occupantDmg`/`reason`) accurate.
  Player-attack previews also show the BASE attack damage as a number on the aimed cell
  (`preview.addDamageNumber` → `damageNumbers` → `ui.collectPreviewDamageNumbers` →
  `ui.drawPreviewDamageNumbers`); it is the raw `attack.damage` (0 skipped), never the summed
  total. Push arrows are shown by geometry even when the aimed cell is empty (Blade squad:
  Dash/Flip/Wide Strike/Vortex Strike/Strike).
- **Menu** auto-lists every `maps/*.lua` (no registration needed).

## Temp verification block pattern (env-gated, always remove after)

Insert at the end of `love.load` in main.lua, run with lovec.exe, read report file:

```lua
if os.getenv("NGTBS_TEMP_X") then
    local ok, err = xpcall(function()
        restartGame("maps/<map>.lua")     -- set selectedHero before if needed
        local report = {}
        local function chk(n, c) report[#report+1] = (c and "OK   " or "FAIL ") .. n end
        -- ...assert via chk(...)...
        local f = io.open("x_report.txt", "w")
        for _, l in ipairs(report) do f:write(l, "\n") end
        f:close()
        love.event.quit()
    end, function(e) return debug.traceback(e, 2) end)
    if not ok then
        local f = io.open("x_report.txt", "w"); f:write("ERROR: ", tostring(err), "\n"); f:close()
        love.event.quit()
    end
end
```

Run it:

```powershell
Get-Process -Name love* -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2
Remove-Item x_report.txt -ErrorAction SilentlyContinue
$env:NGTBS_TEMP_X = "1"
$p = Start-Process "C:\Program Files\LOVE\lovec.exe" -ArgumentList "." -PassThru -NoNewWindow
$p.WaitForExit(25000) | Out-Null
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; "TIMEOUT" } else { "EXITED" }
Remove-Item Env:\NGTBS_TEMP_X
Get-Content x_report.txt
```

Notes:
- TIMEOUT + NO REPORT = Lua error (love shows error screen, process stays alive). Syntax-check
  first: `lua -e "print(loadfile('main.lua') and 'OK' or 'SYNTAX ERROR')"`.
- `lua tests/run.lua` = headless suite. 1 pre-existing failure
  ("pushable building pushed off edge does not take damage") — ignore.
- For log-file output set `$env:NGTBS_LOG_FILE = "C:\Users\80STH\Desktop\test\x.log"` and
  grep with `Select-String -LiteralPath x.log -Pattern "..."`.

## Generating sprites programmatically (LOVE headless)

Sprites (e.g. `sprites/railway_track.png`) can be generated procedurally with LOVE itself.
Working recipe (verified):

1. **Use a game folder, not a bare file.** `love some.lua` single-file mode hangs.
   Put the generator as `main.lua` in a folder, e.g. `C:\Users\80STH\AppData\Local\Temp\opencode\railtool\main.lua`.

2. **Write pixels with ImageData** and save via `io` (LOVE sandboxes `ImageData:encode` to its
   save dir / rejects absolute paths):

   ```lua
   local data = love.image.newImageData(W, H)
   data:setPixel(x, y, r, g, b, a)   -- inside hex mask / alpha 0 outside
   local fd = data:encode("png")     -- returns FileData, NOT a string
   local f = io.open("C:/Users/80STH/Desktop/test/sprites/name.png", "wb")
   f:write(fd:getString())
   f:close()
   ```

3. **Debug via a log file**, not print: `love.exe`/`lovec.exe` is a GUI app, stdout goes nowhere.
   Wrap the body in `xpcall` and write tracebacks to a `.log` file; end with `love.event.quit()`.

4. **Kill stale `love` processes first** — LOVE is single-instance: a leftover instance blocks
   new runs (`Get-Process -Name love | Stop-Process -Force`).

5. Run with `lovec.exe` (console build) for visible error output, e.g.:

   ```powershell
   $p = Start-Process "C:\Program Files\LOVE\lovec.exe" -ArgumentList "<gamefolder>" -PassThru -NoNewWindow
   Start-Sleep 6; if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
   ```

6. **LOVE rotation convention**: positive rotation angle rotates clockwise-down on screen
   (verified: `rotate(math.rad(30))` maps (10,0) → (8.66, +5)). Hex sprites should use a flat-top
   hex mask: faces at normals 30°+60°·k, apothem `radius*cos(30°)`.

## PNG capture / pixel analysis (verified this session)

7. **Screenshot of the running game** — `love.graphics.captureScreenshot` needs an argument in
   LOVE 11.5 (filename OR callback; with no args it errors). Use the callback form to write
   anywhere via `io`:

   ```lua
   love.graphics.captureScreenshot(function(img)        -- img is ImageData
       local fd = img:encode("png")                     -- FileData, NOT a string
       local f = io.open("C:/path/shot.png", "wb")
       f:write(fd:getString()); f:close()
   end)
   ```

   Trigger it from a temporary `love.update` override inside an env-var-gated block in the
   game's `love.load` (see "TEMP TEST" pattern); `love.event.quit()` right after.

8. **Programmatic pixel analysis instead of viewing images** — the model cannot read PNGs.
   Draw to a canvas, read pixels back, scan for color transitions, dump the run to a log:

   ```lua
   local canvas = love.graphics.newCanvas(W, H)
   love.graphics.setCanvas(canvas); love.graphics.clear(0, 0, 0, 1)
   -- ...draw stuff...
   love.graphics.setCanvas()
   local img = canvas:newImageData()
   local r, g, b, a = img:getPixel(x, y)                -- scan lines for edge positions
   ```

9. **Standalone render/test folders are flaky**: a game folder WITHOUT the project's
   `conf.lua` (`highdpi`, `t.console`) hangs at startup — copy `conf.lua` in. After
   force-killing `lovec.exe`, the next run may hang at map load (leftover window/GPU state) —
   kill all `love*` processes and wait ~3 s between runs; prefer running inside the game
   folder via an env-var-gated temp block in `love.load`.
