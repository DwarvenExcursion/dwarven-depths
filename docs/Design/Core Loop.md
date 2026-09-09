---
tags: [design]
updated: 2026-09-09
---

# Core Loop

You dig straight down through procedurally generated rock. Water pours in
behind you and never stops. Gems are currency for blasts. Death is inevitable;
depth is the score.

## Mechanics

| Mechanic | Detail |
|---|---|
| Movement | Grid-based. Moving into dirt destroys it and you occupy the tile. |
| Stone | Impassable. Route around it, or blast it. |
| Gems | +1 each. Currency, not score. |
| Blast (Z / A) | Costs 3 gems. Clears a 3x3 two tiles ahead in the facing direction, and recovers any gems inside. |
| Water | See [[The Flood]]. |
| Death | Water reaches your tile at drowning depth. |
| Score | Depth reached. Gems are shown separately. |

## The decision the game is built around

Every sideways move costs depth, and depth is the only thing keeping you ahead
of the water. That is the whole game. Everything else exists to make that
trade interesting:

- **Stone** forces the detour, so difficulty is "how often are you made to
  spend depth" rather than "how fast can you press down".
- **Gems** are worth a detour only if the blast they buy saves more depth than
  the detour cost.
- **The water** is what turns spent depth into a real loss instead of an
  abstraction.

Since the flood rework this trade has a second, richer form: a wide horizontal
gallery is a **sump**. Water that spreads sideways into it is water that is not
stacking up behind you, so cutting sideways buys real time — at exactly the
cost of the depth you did not gain. See [[The Flood#Galleries are sumps]].

## Tuning knobs

Everything worth touching, in one place:

```gdscript
# main.gd
MOVE_DELAY   0.11    # dig repeat. 0.08 frantic, 0.15 deliberate
BOMB_COST    3       # gems per blast
VIEW_ROWS    15      # vertical field of view, every screen
DANGER_ROWS  9.0     # when the HUD starts warning

# scripts/flood.gd  -- see The Flood for what these actually do
HEAD         0.20
INFLOW_BASE  0.30
INFLOW_RAMP  0.0026
LEASH        10.0
```

`MOVE_DELAY` is still set from a mechanical keyboard and will need retuning for
a d-pad. That is listed in [[Next Steps]] because it changes the design of
everything built on top of it.

## States

`TITLE -> PLAY -> DEAD -> PLAY`. One enum in `main.gd`, no separate scenes.
`restart()` serves as both "start game" and "play again". The title screen
doubles as the settings screen.

Related: [[Strata and Difficulty]], [[Presentation]], [[Architecture]]
