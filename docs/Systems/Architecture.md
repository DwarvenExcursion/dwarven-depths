---
tags: [system]
updated: 2026-09-09
---

# Architecture

The game was one 327-line `main.gd` drawing coloured rects. It is now a small
set of modules, split along the seams that [[Mega Bonk Direction|the roadmap]]
is going to push on — an entity layer needs a world it can query without going
through the renderer.

Everything still renders through `_draw()`. There are no tilesets, no sprites
on disk, and no physics. That is a deliberate constraint, not a stopgap: it
keeps the whole game editable as text.

## Module map

```
dwarven-depths/
├── main.gd            state machine, input, camera, render order
├── main.tscn           Main / UI(CanvasLayer > Hud) / Camera2D / 4x Sfx
├── scripts/
│   ├── apollo.gd       class Apollo   palette + strata table
│   ├── mine.gd         class Mine     tile world, lazy generation
│   ├── flood.gd        class Flood    the water simulation
│   ├── dwarf.gd        class Dwarf    player pixel art
│   ├── tinyfont.gd     class TinyFont 3x5 bitmap font
│   └── hud.gd          (Control)      all screen-space UI
├── tools/
│   ├── floodsim.gd     headless flood tuning harness
│   └── capture.gd      screenshot runner
├── sounds/             four synthesised chiptune WAVs
└── shots/              capture.gd output (gitignored)
```

## Who may talk to whom

- `Mine` knows nothing about the player, the water, or drawing.
- `Flood` knows about `Mine` (it asks which tiles are open) and nothing else.
- `Dwarf` and `TinyFont` are pure drawing, both static.
- `hud.gd` **never reaches back into the game.** `main.gd` pushes state into
  its public fields and calls `queue_redraw()`. Keep it that way; the HUD is
  the thing most likely to grow tendrils.
- `main.gd` owns everything else.

`Apollo` is a leaf that everything may use. If a colour is not in it, it does
not go in the game.

## Resolution

The shaft is a fixed `COLS` (20) wide, so we cannot simply show more world on a
wider screen without exposing the void beside it. Instead:

- **Constant vertical field of view.** `fit_camera()` sets camera zoom so
  exactly `VIEW_ROWS` (15) rows fill the viewport height, capped so the shaft
  always fits horizontally. Every player on every panel sees the same amount of
  mine — a widescreen monitor is not an advantage.
- **Bedrock, not letterboxing.** The space beside the shaft on wide screens is
  filled with darkened stratum rock and faint striations, so it reads as more
  mountain rather than as a rendering mistake.
- **The HUD anchors to real corners.** It lives on a `CanvasLayer` at
  `PRESET_FULL_RECT` and redraws on `size_changed`.

Project settings: base viewport 320x240, stretch mode `canvas_items`, aspect
`expand`. Verified at 640x480 (handheld), 1280x720, and 1720x620 ultrawide —
see `shots/`.

> [!warning] `_draw()` is not automatic
> `_draw()` reads the camera, so it has to be reissued whenever the camera
> moves. The title screen originally drew once and then kept a stale frame with
> the bottom third of the world unpainted. Every state that moves the camera
> must call `queue_redraw()`.

## GDScript gotchas hit here

Worth knowing before the next parse error:

- `round()`, `ceil()` and `floor()` return **Variant**. `var x := round(y)`
  fails as "type inferred from a Variant value" with warnings-as-errors on. Use
  `roundf()` / `ceilf()`, or annotate the type.
- Accessing a member of a `Dictionary` value gives Variant, so
  `var before := main.player` fails where `var before: Vector2i = main.player`
  works.
- Mutating a struct inside a Dictionary in place (`d["v"].y += 1`) is fragile.
  Read it out, change it, put it back.
- `await` inside `SceneTree._process` turns it into a coroutine and its `bool`
  return is silently discarded — the runner does nothing at all, with no error.
- Adding a `class_name` script while the editor is closed leaves
  `.godot/global_script_class_cache.cfg` stale, and every reference fails as
  "Identifier not declared". Fix:
  `godot --headless --editor --path . --quit`.

Related: [[Tooling]], [[The Flood]], [[Presentation]]
