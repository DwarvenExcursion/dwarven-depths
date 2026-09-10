# Dwarven Depths — Work Order

Handoff for Claude Code. Read this whole file before touching anything, then work
one phase at a time and stop for review at each phase boundary.

---

## 0. Orientation

**Project:** Endless vertical mining roguelite. Dig down, grab gems, outrun a
rising flood. Godot 4.7.2, GDScript.

**Read first:**
- `DESIGN.md` in the repo root — current state, mechanics table, and the
  long-term direction. Section 3 ("The Mega Bonk Direction") is the target this
  work order moves toward.
- The current main script (`main_v6.gd` or whatever the latest version is).

**Architecture as it stands:** the entire game is one script drawing colored
rects via `_draw()`. No tilesets, no sprites, no physics bodies, no collision
shapes. The world is a `Dictionary` keyed by `Vector2i` holding tile-type ints
(`EMPTY`, `DIRT`, `STONE`, `GEM`). Movement is grid-based on a `MOVE_DELAY`
repeat timer. A `State` enum drives `TITLE` / `PLAY` / `DEAD`.

### Hard constraints — do not violate

- **Viewport is 320×240**, stretch mode `viewport`, aspect `keep`, renderer
  `gl_compatibility`. Everything must read at that size. Assume a 3.5" screen.
- **Controller-first.** The real target is an Anbernic H700 handheld d-pad, not
  a keyboard. Every input must work on d-pad + face buttons. Nothing may require
  a mouse or a key that isn't mapped in the input map.
- **Palette is Apollo 46** by AdamCYounis. Any new color must be an actual hex
  from that palette. Do not invent colors.
- **No new dependencies.** No addons, no plugins, no external libraries.
- **Keep the `_draw()` rect approach.** Do not migrate to TileMapLayer, sprites,
  or `CharacterBody2D` during this work order, even where it would be more
  idiomatic. That migration is a separate decision made later.
- Do not touch export presets or chase the PortMaster/FRT runtime question. The
  Godot 4.7.2 vs. pinned-runtime compatibility issue is unresolved and out of
  scope here.

### Ground rules

- **Verify before you assume.** Parts of this document describe existing code
  from memory of a design conversation, not from reading the file. Where a
  variable name or expression is quoted below, confirm it against the actual
  source before editing. If the real code differs, follow the real code and note
  the discrepancy in your summary.
- **One phase per commit.** Do not start phase N+1 until phase N is reviewed.
- **Preserve the version-file convention** the repo already uses (`main_v6.gd` →
  `main_v7.gd`) unless the repo has moved to plain `main.gd`, in which case
  follow that.
- **Update `DESIGN.md`** at the end of each phase: move completed items out of
  the roadmap, record any design decision you made and why.
- Ask before adding a new scene file. This project deliberately has very few.

---

## Phase 1 — Fall physics and the flood bug (one commit)

These four items ship together because the first two are the same job and the
last two are trivial and independent.

### 1.1 Fix the flood leash killing the player through open air

**Symptom:** the player dies while visibly above the water, most often right
after dropping down a tunnel/shaft.

**Diagnosis to verify:** the flood target is leashed to the player's deepest
point, something like `flood_row = max(creep, deepest - FLOOD_LEAD)` with
`FLOOD_LEAD = 6`. Shafts are generated with `SHAFT_MAX = 13`. Falls currently
resolve in a single frame, so a long drop increments `deepest` by up to 13 at
once, and the leash then snaps the water to `deepest - 6`, which lands *above*
the player's new row. The player is inside the water before it ever animated
toward them.

**Fix:** the leash term must never place water at or above the player. Clamp the
leash only — leave the natural `creep` alone so the flood can still catch the
player honestly.

```gdscript
var leash := float(deepest - FLOOD_LEAD)
leash = min(leash, pos.y - 1.0)      # leash may never snap onto the player
flood_y = max(creep, leash)
```

Also confirm the death check compares the flood against the player's **current
row** (`pos.y`), not against `deepest`. If it uses `deepest`, that is a second
instance of the same bug and must be fixed too.

**Acceptance:** falling the full `SHAFT_MAX` distance from just ahead of the
flood never causes an instant death. Water is always visibly touching the player
on the frame they die.

### 1.2 Multi-tick falling and platform physics

**Goal:** falls resolve over time instead of in one frame, and open space becomes
navigable rather than just a teleport.

Currently an empty tile below the player drops them to the floor instantly.
Replace with:

- A `fall_speed` / velocity variable and a fall accumulator, so the player
  descends one row per fall tick with acceleration up to a capped terminal speed.
- Horizontal input during a fall gives limited air control (one column of drift
  per N fall ticks). Tune the value; the intent is that a fall is steerable but
  not free flight.
- Walking off a ledge starts a fall rather than snapping.
- Landing stun scales with distance fallen. Keep the existing `STUN_MAX` ceiling.
- `deepest` updates continuously during the fall, not in one jump. Combined with
  1.1 this means the flood leash follows the player down smoothly.

**This phase defines what "a tick" means for the rest of the game.** Enemy
movement in phase 4 is specified relative to it, so get the feel right here.

**Acceptance:** a 13-row shaft drop is readable as a fall, not a teleport. The
player can steer one or two columns during it. Landing from max height produces a
noticeable but recoverable stun. Test on a controller d-pad, not a keyboard.

### 1.3 Pause menu

Add `State.PAUSE` to the existing state enum. On pause, skip the entire
simulation update (flood, generation, movement, timers) and draw a dimmed
overlay with resume / restart / quit. Toggle on `ui_cancel` and on the Start
button; both must be bound in the input map.

Do not use `get_tree().paused` and `PROCESS_MODE_WHEN_PAUSED` for this. The game
is a single `_process` loop with a state machine already — a new state branch is
smaller, and it keeps everything in one place.

**Acceptance:** the flood does not advance while paused. Pausing mid-fall and
resuming continues the fall correctly. Menu is fully navigable on a d-pad.

### 1.4 Audio bus split and music

The existing volume control adjusts the **Master** bus, which will dim music
along with sound effects once music exists.

1. Create **SFX** and **Music** buses in the Audio panel, both routed to Master.
2. Route the four existing `AudioStreamPlayer`s (dig, gem, blast, death) to SFX.
3. Change the volume code from `get_bus_index("Master")` to targeting SFX and
   Music separately. The title screen currently exposes one volume line with
   `<` `>` — make it two lines (`SFX` and `MUSIC`), selected with up/down.
4. Add a music `AudioStreamPlayer` on the Music bus with looping enabled.
5. Persist both volumes to the existing `user://settings.cfg` via `ConfigFile`.
   Preserve backward compatibility: an existing config with a single volume key
   should load without erroring and apply that value to both buses.

**Track sourcing is not your call.** Do not generate music, do not commit
placeholder audio from anywhere with unclear licensing. Wire the player, point it
at `res://audio/music/theme.ogg`, and handle a missing file gracefully (no
crash, no error spam, game runs silent). Leave a note in your summary that the
file needs to be supplied.

**Acceptance:** SFX volume no longer affects music. Both settings survive a
restart. Missing music file does not crash or spam the console.

---

## Phase 2 — Strata expansion (small, data-only)

Extend the strata array past the current four (`at` 0 / 60 / 130 / 210) with at
least four more tiers. Each entry needs `at`, `stone`, `gem`, `cave`, and its
colors, all from Apollo 46.

Continue the existing curves: stone density rises, gem density falls, `cave`
threshold drops (more open space) as depth increases. Keep the progression
smooth — no cliff where a tier suddenly becomes unplayable.

`stratum()` must handle depths past the last defined tier by clamping to it, not
by indexing out of bounds.

**Acceptance:** depth 600+ generates valid, traversable terrain. Each new tier is
visually distinct from its neighbors at 320×240. No index errors at any depth.

---

## Phase 3 — Unlocks and elevators

**Design decision already made:** the game stays endless. There are no discrete
authored levels and no boss gates. "Levels" means depth strata, and unlocking
means **elevators**.

If reviewing this changes that decision, stop and flag it, because it invalidates
this entire phase.

- Reaching a depth threshold for the first time permanently unlocks an elevator
  at that depth. Thresholds every 100 rows is a reasonable starting point.
- From the title screen the player picks a starting elevator from those unlocked.
  Runs begin at that depth with zero gems.
- The flood, strata, and generation all initialize correctly for a non-zero start
  depth. The `generated_to < 3` and `generated_to > 8` opening guards currently
  assume a start at row 0 — audit every such guard.
- Score is still `deepest`, but the death screen should show both absolute depth
  and depth gained this run.
- Best depth stays a single global number. Do not fragment it per elevator.

**Save file:** promote the current `user://best.txt` to a `ConfigFile` or JSON
save holding unlocked elevators, best depth, and total gems. Migrate an existing
`best.txt` on first load rather than discarding it, then leave the old file
alone.

**Acceptance:** starting at depth 300 produces terrain and flood behavior
identical to arriving there organically. Unlocks survive a restart. A fresh
install with no save file starts correctly with only depth 0 available.

**Why this moved ahead of enemies:** elevators make deep strata reachable in
seconds, which makes phase 4 testable. Balancing a magma-tier enemy is
impractical if reaching magma takes a perfect four-minute run.

---

## Phase 4 — Entity layer and enemies

The world dictionary holds tile-type ints and cannot represent something that
moves. This phase adds a real entity layer, and it is the largest refactor in
this document.

### 4.1 Entity layer

- An `entities` array of lightweight objects or dictionaries, each with a
  position, a type, and per-type state.
- Entities update on the same tick model established in phase 1. Movement is
  discrete and grid-aligned. No per-frame float movement, no physics bodies.
- Spawn rules read from the stratum data, so each tier gets its own roster and
  spawn rate.
- Entities are culled when they scroll far enough above the view or fall under
  the flood.
- Collision resolution order must be explicit and documented: player moves,
  then entities move, then overlaps are resolved. Write it down in `DESIGN.md`
  so enemy behavior is predictable rather than emergent from update order.

### 4.2 Worm (build first)

Burrows through dirt on a slow tick. Occupies and blocks a tile. One hit to
clear. No pathfinding — it moves along a simple heading and turns on obstruction.
It is an obstacle, not a threat.

Build this one first because it exercises the entire entity layer while being
nearly impossible to get unfair.

### 4.3 Bat (build second, expect to tune it hard)

Moves two tiles per tick, erratically, only through empty space. Does not
burrow, so it lives in caverns and shafts.

**Fairness is the whole problem here.** Two tiles per tick against a d-pad
repeat rate is fast enough to feel like a coin flip. Requirements:

- A telegraph tick before it moves, so the player can read the threat.
- Erratic, but weighted toward the player rather than pure random walk. Pure
  random reads as unfair in both directions.
- It must be avoidable by a player who is paying attention, at the *d-pad*
  `MOVE_DELAY`, not the keyboard one.

If the bat cannot be made fair inside this phase, ship the worm alone and say so.
A shipped worm beats an unfair bat.

**Acceptance:** entity layer supports both without special-casing. Neither enemy
can spawn on top of the player. Neither can trap the player in an unwinnable
position against stone. Performance is unchanged at 320×240.

---

## Phase 5 — Load cutscene

Last, deliberately. It introduces the game, so it can only be written once the
game is settled.

Short, skippable on any input, and honest about the mechanics: a dwarf descends,
water follows. Built with the same `_draw()` primitives as everything else — no
video, no imported image sequences. Runs on first launch and is replayable from
the title screen.

Must not delay a restart. Death → restart never replays it.

---

## Testing checklist for every phase

- Test on a controller d-pad, not a keyboard. `MOVE_DELAY` was tuned at 0.11 on a
  mechanical keyboard and the d-pad repeat feel is different.
- Verify at 320×240 actual size, not a scaled-up editor viewport.
- Run to at least depth 200 before calling a phase done.
- Zero GDScript warnings. The project has previously accumulated dead code after
  `return` statements — check for it.
- Confirm `user://settings.cfg` and the save file both survive a full restart.

## Known historical bug patterns in this codebase

Worth grepping for while you're in there:

- Functions accidentally nested inside other functions (`load_settings()` and
  `apply_volume()` were once defined inside `stratum()`, so settings never
  persisted).
- Dead code after `return` in `_process()`, which has previously caused HUD
  labels to draw over the title screen.
- Duplicate assignments to the same label leaving one branch unreachable.
- Cost/reward constants drifting out of sync (blast cost vs. gem award).
