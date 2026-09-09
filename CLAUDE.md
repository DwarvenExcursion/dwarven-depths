# Dwarven Depths

Endless vertical mining roguelite in Godot 4.7.2. Dig down, grab gems, outrun
the water. Windows desktop now; Anbernic H700 handheld via PortMaster later.

## Layout

- `dwarven-depths/` — the Godot project
- `docs/` — **an Obsidian vault.** Design and system documentation lives here,
  linked with `[[wikilinks]]`. Start at `docs/Dwarven Depths.md`.
- `pallette/apollo.hex` — the Apollo 46 palette
- `../GameExports/` — build output

## Read before changing things

| Changing… | Read |
|---|---|
| The water | `docs/Design/The Flood.md` |
| Difficulty, strata | `docs/Design/Strata and Difficulty.md` |
| Which file owns what | `docs/Systems/Architecture.md` |
| Art, font, HUD, audio, controls | `docs/Design/Presentation.md` |
| What to work on | `docs/Roadmap/Next Steps.md` |

Keep the docs current. When a design decision changes, update the note and add
a line to `docs/Log/`.

## Commands

Godot: `C:\Users\austi\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
(use the `_console` build for anything you want output from). Run from
`dwarven-depths/`.

```bash
godot --path .                                          # run the game
godot --headless --path . --quit-after 300              # compile + boot check
godot --headless --path . --script res://tools/floodsim.gd   # flood tuning
godot --path . --script res://tools/capture.gd               # screenshots
```

## Conventions

- **Everything renders through `_draw()`.** No tilesets, no sprite files, no
  physics. The dwarf and the font are text you edit. Keep it that way until it
  genuinely hurts.
- **All colours come from `Apollo`.** If a colour is not in `scripts/apollo.gd`,
  it does not go in the game. Highlight/shadow pairs must be neighbours on the
  same Apollo ramp.
- **`hud.gd` never reaches into the game.** `main.gd` pushes state into its
  public fields. Do not invert this.
- **Comments explain why, not what.** The existing comments carry the reasoning
  behind non-obvious decisions — match that.
- Tabs for indentation, as GDScript wants.

## Traps

These have all bitten. `docs/Systems/Architecture.md` has the full list.

- `round()` / `ceil()` / `floor()` return **Variant**; `var x := round(y)` is a
  parse error with warnings-as-errors. Use `roundf()` etc.
- Adding a `class_name` script while the editor is closed leaves the class
  cache stale — every reference fails as "Identifier not declared". Fix with
  `godot --headless --editor --path . --quit`.
- `--headless` never calls `_draw()`. It will not catch rendering bugs.
- `await` inside `SceneTree._process` silently discards the `bool` return.
- **Close the Godot editor before renaming files or editing `project.godot`** —
  it rewrites that file on exit and will clobber your changes.

## Verifying changes

Compiling is not evidence. For gameplay changes run `floodsim`; for anything
visual run `capture` and actually look at the PNGs in `shots/`.
