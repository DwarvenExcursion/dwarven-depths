---
tags: [log]
date: 2026-09-09
---

# 2026-09-09 — Phase 1: falling, pause, audio buses

Phase 1 of the work order in `dwarven-depths/scripts/HANDOFF.md`. Three of its
four items landed. The fourth was already obsolete.

## 1.1 was already fixed, and its patch would have been a regression

The work order describes the flood as a row leashed to the player's deepest
point — `flood_row = max(creep, deepest - FLOOD_LEAD)`, `FLOOD_LEAD = 6` — and
asks for a clamp so the leash cannot snap the water on top of the dwarf.

**That code no longer exists.** It was replaced earlier the same day by the
volume simulation in [[The Flood]]. There is no `flood_row`, no `FLOOD_LEAD`,
no `SHAFT_MAX`. The leash survives only as an *inflow rate multiplier*
(`LEASH`, `LEASH_GAIN`, `LEASH_MAX`) which cannot place water anywhere — it
makes more water arrive at the top of the window, and that water still has to
fall down the shaft a tile at a time.

Applying the suggested patch would have reintroduced row arithmetic into a
simulation that deliberately has none. Left alone.

The second half of 1.1 checks out: the death test is
`flood.is_lethal(player)`, against the player's current tile, not `deepest`.

## 1.2 Falling

There was no gravity at all before this — the dwarf could walk on air. So this
was not "replace the instant drop", it was "add falling".

`_step_fall()` accelerates at `GRAVITY` to a `FALL_MAX` terminal speed,
carrying a fractional row accumulator between frames so a drop resolves one row
at a time. Measured with [[Tooling|falltest]]:

| drop | time | frames | max rows in one frame | landing stun |
|---|---|---|---|---|
| 3 rows | 0.37 s | 22 | 1 | none |
| 6 rows | 0.57 s | 34 | 1 | 0.066 s |
| 13 rows | 1.03 s | 62 | 1 | 0.220 s |
| 30 rows | 2.17 s | 130 | 1 | 0.450 s (capped) |

Air control is one column per `AIR_DRIFT`. First tuning was 0.16 s, which gave
about six columns of drift on a 13-row fall — free flight, not steering. At
0.40 s a 13-row drop steers **two columns out of six available**, which is what
the work order asked for. The first drift is charged rather than free, so
stepping off a ledge does not grant an instant sideways move.

**This is what a tick means now.** One row at terminal speed is 1/15 s against
a 0.11 s walk step, so falling is about 1.6x walking. Anything that moves on a
tick — the phase 4 enemies — is specified against that.

Not verified: feel, on a d-pad. Every number above is from a harness on a
keyboard. See [[Next Steps]] item 1.

## 1.3 Pause

`State.PAUSE` in the existing enum, as specified — not `get_tree().paused`. The
simulation stops because the branch returns before `flood.step()` is reached,
so there is nothing to remember to exempt. Falls survive a pause: `fall_v` and
`fall_acc` are untouched, so resuming continues the drop mid-air.

`quit_game` is state-dependent now. It pauses during a run, and only quits
outright from the title or death screens.

## 1.4 Audio buses

`default_bus_layout.tres` adds SFX and Music under Master; the four existing
players moved to SFX and a looping Music player was added. The title screen has
two volume lines selected with up/down and moved with left/right.

`settings.cfg` gained `audio/sfx` and `audio/music`. An older config holding a
single `audio/volume` loads without error and seeds both — the legacy key is
used as the *default* for the two new ones.

**There is no music track**, deliberately: nothing here generates or commits
audio of unclear licensing. `_start_music()` checks `ResourceLoader.exists()`
and returns quietly, so a missing file is silent rather than an error every
frame. Supply `res://audio/music/theme.ogg` and it loops on its own.

## Other discrepancies with the work order

- It says the game is one script (`main_v6.gd`). It is `main.gd` plus six
  scripts under `scripts/`. Followed the real layout, as instructed.
- It says stretch mode `viewport`, aspect `keep`. Actually `canvas_items` /
  `expand` — see [[Architecture#Resolution]], which is deliberate.
- It says `DESIGN.md` holds the design. That is now a pointer to this vault.
- It references `user://best.txt`. Best depth already lives in `settings.cfg`
  under `run/best`. Phase 3's migration step is therefore already done.

## Left undone

- `capture.gd`'s scripted dwarf now interacts with gravity, so its shots differ
  from the pre-gravity set — it reaches depth 5 where it used to reach 39. The
  harness drives `try_move()` directly while `_process` applies gravity
  underneath it. Worth rewriting that harness to drive input instead.
- Two ObjectDB instances leak at exit under the tool scripts. Pre-existing,
  most likely the update checker's in-flight `HTTPRequest`.
