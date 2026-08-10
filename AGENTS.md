# AGENTS.md

## Run the game

```powershell
cd "C:\Users\80STH\Desktop\test"
& "C:\Program Files\LOVE\love.exe" .
```

Love2D 11.5 installed. The game window will open — close it manually when done testing.

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
