---
tags: [roadmap, unbuilt]
updated: 2026-09-09
---

# Mega Bonk Direction

The long-term shape: a run-based roguelite with meta-progression, in the vein
of Vampire Survivors / Mega Bonk. **Everything on this page is unbuilt.**

Gated behind [[Next Steps]] — none of it until the core loop is confirmed fun
on the handheld.

## Zones

Each stratum becomes a real place rather than a palette swap:

- A distinct enemy set
- A distinct hazard
- A tier boundary you either survive or do not
- Its own music track

Note that [[Strata and Difficulty|CRYSTAL and MAGMA are currently unreachable]].
Zone content for bands nobody reaches is wasted work — either the upgrades
below have to carry the player there, or the ramp moves.

## Enemies

Per-zone rosters. Design constraint: everything must work on a grid, with
movement resolved in discrete steps, so it stays readable at 320x240 and
playable on a d-pad.

- **Surface** — slow burrowing grubs, block your path, one hit to clear
- **Deep earth** — bats that move two tiles per turn, erratic
- **Crystal** — stationary shard emitters; hazard zones rather than chasers
- **Magma** — things that chase, and are faster than you dig

> [!warning] Enemies interact with the flood
> An enemy that pins you in place is a drowning, not an inconvenience — the
> stall margin is about 8 seconds. Every enemy design needs a
> [[Tooling|floodsim]] scenario asking "how long can this thing hold me".

## Powerups

Found or purchased mid-run:

- Faster dig (lower `MOVE_DELAY`)
- Wider blast radius
- Cheaper blasts
- Brief flood slow
- Sideways dash
- Gem magnet

"Brief flood slow" is now a much more interesting item than it was — with a
real simulation it could instead be *drainage*, opening a sump below you.

## Meta-progression

- Beat a tier, unlock a cosmetic dwarf
- Customisation: beard, helmet, pick, colour scheme — all Apollo palette, and
  all editable as text in `dwarf.gd`
- Persistent unlock currency, separate from in-run gems

## Structural changes required

- Enemies mean the world can no longer be a bare dict of ints. It needs an
  entity layer with its own update step. [[Architecture|The module split]] was
  done with this in mind: `Mine` is already queryable without going through the
  renderer.
- Turn-based-ish enemy movement tied to `MOVE_DELAY` ticks, not per-frame.
- A run summary screen between zones.
- A save file with unlock state — `user://settings.cfg` already carries volume
  and best depth and can grow.

Related: [[Next Steps]], [[Core Loop]], [[Architecture]]
