---
tags: [design]
updated: 2026-09-09
---

# Strata and Difficulty

Four depth bands, defined in `scripts/apollo.gd::STRATA`. Each has its own
stone and gem density, its own colour set, and its own bedrock tone for the
space beside the shaft on wide screens.

| Band | Starts at | Stone | Gem | Feel |
|---|---|---|---|---|
| SURFACE | 0 | 0.10 | 0.07 | Tan earth, grey rock. Open, forgiving. |
| DEEP EARTH | 60 | 0.18 | 0.06 | Dark brown, blue-grey. |
| CRYSTAL | 130 | 0.26 | 0.05 | Purple. |
| MAGMA | 210 | 0.34 | 0.04 | Blood red. |

Crossing a boundary announces the band name via the HUD banner.

## Two difficulty curves, and they must be read together

**Stone density** is the curve the player feels as friction. More stone means
more forced detours, and a detour costs depth directly — see [[Core Loop]].

**Inflow ramp** is the curve that decides when the run ends.
`Flood.INFLOW_RAMP` (0.0026 per row) makes the water front descend faster with
depth until it is simply quicker than the dwarf. See [[The Flood]].

These compound. Stone slows the dwarf at the same depths that inflow speeds the
water, so the wall arrives faster than either curve alone would suggest.

## Where the wall currently is

Measured with [[Tooling|floodsim]], fixed seed:

- The scripted dwarf dies around **depth 108** after ~21 s.
- It reaches DEEP EARTH (60) comfortably.
- It has **never reached CRYSTAL (130)**.

So MAGMA at 210 is currently unreachable content. That is not necessarily
wrong — the [[Mega Bonk Direction|roguelite upgrades]] are meant to be what
gets you there, and having the bands defined ahead of the player is fine. But
be aware of it before treating a MAGMA run as a design target.

The scripted dwarf is deliberately dumb — it sidesteps into whatever is
adjacent with no lookahead — so a human who routes well should get further.
Confirm with real play before moving the ramp.

> [!note] If you want CRYSTAL reachable now
> Lower `INFLOW_RAMP`. It was already softened from 0.0034 to 0.0026 on
> 2026-09-09. Rerun the harness after any change.

Related: [[Core Loop]], [[The Flood]], [[Presentation]]
