---
tags: [design, system]
updated: 2026-09-09
---

# The Flood

`scripts/flood.gd`. Rewritten 2026-09-09 — see [[2026-09-09 Flood rework]] for
what it replaced and why.

## What it is

Every open tile holds a water volume in `[0, 1]`. Twenty times a second:

1. **Inject** — water enters at the top of the simulated window, through
   whichever tiles are open there.
2. **Fall** — a tile passes water to the tile below it, if that tile is open
   and has room.
3. **Spread** — water equalises sideways with open neighbours, much more slowly.
4. **Settle** — dribble is culled and the fronts are recomputed.

Dirt and stone block water outright. That single fact is what makes the water
reactive: it can only ever be where you have already dug.

## HEAD is the whole trick

```gdscript
const HEAD := 0.20
```

A tile passes water downward **only once it holds more than HEAD**. Without
this rule water behaves like falling sand: a thin film races down your shaft in
about a second, and since the bottom of your shaft is exactly where you are
standing, you drown at depth 11. This was measured, not guessed — it is the
first thing [[Tooling|floodsim]] reported.

With it, the descending front has to wet every tile on the way down before it
can go deeper, so it advances at roughly:

$$\text{front speed} \approx \frac{\text{inflow}}{\text{HEAD}}\ \text{rows/sec}$$

which is a number the dwarf can outrun — and stop outrunning the moment he hits
stone. **Changing `HEAD` or `INFLOW_BASE` changes the entire difficulty curve.**
Run the harness after touching either.

## Galleries are sumps

The emergent mechanic worth protecting. Inflow is a fixed volume per second. To
advance one row, the front has to bring every open tile in that row up to
`HEAD`. A 1-wide shaft needs one tile's worth; an 18-wide gallery needs
eighteen.

So cutting sideways genuinely slows the water, and it costs you exactly the
depth you did not gain. Measured, at depth 40:

| Situation | Time from standing still to drowning |
|---|---|
| Narrow shaft | ~8.6 s |
| Eight-row wide gallery | >60 s (survived the whole test) |

A **sealed** pocket — blasted out but never connected — never takes on a drop.
There is a regression test for this; if it ever fails, water is leaking through
solid rock.

## The leash

```gdscript
const LEASH := 10.0
const LEASH_GAIN := 0.22
const LEASH_MAX := 2.4
```

A clean straight dig outruns the front indefinitely at shallow depths, and a
threat you cannot see is not a threat. When the wet front falls more than
`LEASH` rows behind, inflow scales up until it catches back up.

This is the one deliberately unphysical rule in the file and it is
load-bearing — it is the descendant of the old `FLOOD_LEAD`. **The cap matters
as much as the gain.** An uncapped boost compounds off a front that has not
spawned yet, and the run ends in about a second.

The leash reads `wet_front`, not `front`:

- `front` — deepest **lethal** water. Barely exists mid-run, because water only
  becomes lethal once it pools on something. Drives nothing but the HUD's
  historical sense of danger.
- `wet_front` — deepest water of any depth. This is where the stream visibly
  is, and it is what both the leash and the HUD danger meter use.

## Two things that are abstractions, not physics

**The sky is excluded.** `sim_top` is never allowed above `Mine.SKY_ROWS`. The
open rows at the surface are 18 tiles wide, so letting water in there means
priming 3 x 18 tiles before a single drop enters the shaft — about thirty
seconds of nothing. Starting at the first dirt row instead means water enters
through the hole the dwarf made, which is faster *and* a better story.

**Above the window is solid water.** Only `WINDOW_UP` (18) rows above the
player are simulated; everything higher reports as full. That is 18 rows above
a player who can see about 7, so it is never on screen. The leash is what
guarantees the front cannot escape the window and make the lie visible.

## Rendering

In `main.gd::_draw_water`. Water reads as two different things depending on
whether it is going somewhere:

- **Flowing** (the tile below is open and not full) — fill the tile edge to
  edge, carry volume in the opacity. Bottom-anchoring it instead draws a
  separate puddle in every tile of the shaft, which stacks into rungs rather
  than a stream.
- **Surface** (nowhere left to fall) — a real bottom-anchored level, with a
  bright crest and a one-pixel ripple so a moving surface is distinguishable
  from a still one.

Related: [[Core Loop]], [[Tooling]], [[Architecture]]
