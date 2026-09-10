---
tags: [roadmap]
updated: 2026-09-09
---

# Next Steps

Ordered. The ordering matters more than the contents.

## 1. Play it

**The dwarf now falls** (2026-09-09). That is the single biggest change to how
the game feels since the flood rewrite, and it is tuned against a harness on a
keyboard — the numbers are in [[2026-09-09 Phase 1 — falling, pause, audio
buses]]. Twenty runs, then decide whether `GRAVITY`, `FALL_MAX`, `AIR_DRIFT`
and the stun constants are right.

One consequence to form an opinion on: with gravity, digging upward no longer
holds you up. You carve the tile above, step into it, and fall straight back
down. Climbing is now a staircase job. That may be correct for a game about
descending, or it may need a ledge-grab.

Nothing below is worth doing before you have played twenty runs of what is
there now. The [[The Flood|flood]] was rewritten from a rising line into a real
simulation on 2026-09-09; it is tuned against a harness, not against a human.

Specifically, form an opinion on:

- Does the water **read**? Can you tell at a glance where it is and how close?
- Is the stall margin right? ~8.6 s at depth 40 by measurement.
- Are galleries too strong? The harness says a wide gallery survives 60 s of
  standing still. That may be an exploit rather than a mechanic.
- Does the run end too early? The scripted dwarf dies around depth 108 and has
  never reached CRYSTAL — see [[Strata and Difficulty]].

Tune in `flood.gd`, rerun [[Tooling|floodsim]], repeat.

## 2. Retune `MOVE_DELAY` for a d-pad

0.11 was set on a mechanical keyboard. **D-pad feel changes the design of
everything built after it** — an enemy that is fair at 0.11 s dig repeat is
impossible at 0.18. This is why it sits above the enemy work.

Blocked on having a handheld build, which is [[PortMaster]].

## 3. Confirm the PortMaster runtime

See [[PortMaster]]. It is first among the porting tasks because if there is no
Godot 4.7 runtime available, the project has to be rebuilt in a supported
version and **that invalidates a lot of the work below**. Check it early.

## 4. Polish that is cheap and clearly good

- ~~Separate SFX bus~~ — done 2026-09-09. SFX and Music are separate buses with
  separate sliders. The music player is wired but **there is no track**; drop
  an `.ogg` at `res://audio/music/theme.ogg` and it loops automatically.
- Water sound — a loop whose volume tracks how close the wet front is. The
  flood is now a physical thing and it should be audible.
- A "you were N rows from your best" line on the death screen.

## 5. Then, and only then, the roguelite

[[Mega Bonk Direction]]. Do not start the entity layer until the core loop is
confirmed fun on the handheld.

---

## Deliberately not doing

- **A real tilesheet.** Everything renders through `_draw()` from text. That is
  a constraint worth keeping until it actually hurts — it means no import step,
  no asset pipeline, and the whole game is greppable.
- **Widening the shaft on wide monitors.** Constant field of view is a fairness
  decision, not a limitation. See [[Architecture#Resolution]].

Related: [[Dwarven Depths]], [[Tooling]]
