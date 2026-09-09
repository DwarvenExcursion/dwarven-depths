---
tags: [log]
date: 2026-09-09
---

# 2026-09-09 — Rename, flood rework, dwarf, resolution, UI

Big session. Five things landed.

## Renamed to Dwarven Depths

The Godot project was still called "Anbernic Custom Game" and lived in
`anbernic-custom-game/`, while the design doc and the built exe both said
Dwarven Depths. Now consistent: `config/name`, the folder (`dwarven-depths/`),
and the window title. The GitHub repo is still `AnbernicCustomGame` — renaming
that is a web-side action and was left alone.

Also removed two stray `main.tscn*.tmp` files that had been committed.

## The flood is now a simulation

Was: a horizontal line at `flood_row` that rose on a timer and never noticed
the terrain, leashed to 6 rows behind the deepest point.

Now: per-tile water volumes that fall, spread sideways, and are blocked by dirt
and stone. Full writeup in [[The Flood]]. Three findings worth remembering:

**A physical simulation is unplayable.** Water pools at the lowest point, and
the lowest point is exactly where the player is standing. First run of the
harness: dead at depth 11 after 1.1 s. The fix — `HEAD`, a minimum a tile must
hold before it passes water down — is what converts "reach" into "volume" and
turns the water back into a chase.

**The leash had to stay.** It is the descendant of the old `FLOOD_LEAD` and it
is still load-bearing. It also has to be *capped*: an uncapped boost compounds
off a front that has not spawned yet and kills the run instantly.

**The open sky was a ten-litre bucket.** Rows 0–2 are 18 tiles wide, and every
one of them had to reach `HEAD` before a drop entered the shaft — about thirty
seconds of nothing. Caught by screenshotting the game and seeing no water at
all. Water now enters at the first dirt row, through the hole the dwarf made.

## The square is a dwarf

`scripts/dwarf.gd`. 14x14, two frames, stored as text. Helmet with a lamp,
beard, tunic, boots, pick. Mirrors by facing; swings on each dig. See
[[Presentation#The dwarf]].

## Dynamic resolution

Constant vertical field of view at any window size, bedrock beside the shaft
instead of letterboxing, HUD anchored to real corners. Verified at 640x480,
1280x720 and 1720x620. See [[Architecture#Resolution]].

Found a real bug doing this: `_draw()` was never reissued on the title screen,
so it showed a stale frame with the bottom third of the world unpainted.

## UI

Custom 3x5 bitmap font (`tinyfont.gd`) replacing the default vector font, which
was soft at the sizes this game needs. Rebuilt HUD: depth/stratum/best bar,
gem count with blast-readiness pips, edge danger pulse, stratum banner, and
proper title and death panels. See [[Presentation#HUD]].

## Two harnesses added

`tools/floodsim.gd` and `tools/capture.gd` — see [[Tooling]]. Both earned their
keep immediately: floodsim caught the depth-11 drowning, capture caught the
missing water and the stale title frame. Neither would have been obvious from
reading the code.

## Left undone

- Not playtested by a human. Everything above is tuned against a scripted
  dwarf. This is the top item in [[Next Steps]].
- CRYSTAL and MAGMA still unreachable — [[Strata and Difficulty]].
- Galleries may be too strong: >60 s of safety in the harness.
- [[PortMaster]] runtime check still not done.
