---
tags: [system, workflow]
updated: 2026-09-09
---

# Tooling

Godot lives at
`C:\Users\austi\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
(the `_console.exe` beside it is the one that prints to a terminal — use that
for anything you want output from).

All commands run from `dwarven-depths/`.

## Run the game

```bash
godot --path .
```

## Check it compiles and boots

```bash
godot --headless --path . --quit-after 300
```

Fast, and catches every parse error. Note that **headless never calls
`_draw()`**, so rendering bugs slip straight through it. To exercise drawing,
drop `--headless`.

## floodsim — the flood tuning harness

```bash
godot --headless --path . --script res://tools/floodsim.gd
```

Plays the game with a scripted dwarf and prints what the water did. Change one
constant in `flood.gd`, rerun, compare. The seed is fixed so a tuning change is
the only variable.

Scenarios, and what each is protecting:

| Scenario | Question it answers |
|---|---|
| `greedy dig` | How deep can a competent player get, and what lead do they hold? |
| `stall @ N` | You hit stone at depth N. How many seconds do you have? |
| `sealed pocket` | Does water leak through solid rock? Must stay `0.000`. |
| `gallery @ 40` | Does cutting sideways actually buy time? |

Healthy output as of 2026-09-09:

```
greedy dig   died at depth  108 after  20.9s  (5.2 rows/s)
               lead over water: avg 13.1 rows, tightest 0
stall @ 40   arrived 5s, water 19 rows back, drowned after  8.6s
sealed pocket water level 0.000  (want 0.000)
gallery @ 40 drowned after 60.0s of standing still
```

If `stall` drops near zero, the water is on top of the player and there is no
reaction window. If `greedy dig` never dies, there is no difficulty curve.
Both have happened; both were caught here rather than by playing.

> [!tip] Add a scenario when you add a mechanic
> This is the only place the water gets measured. When enemies land, the
> question "can an enemy pin you long enough to drown" belongs here.

## capture — screenshots

```bash
godot --path . --script res://tools/capture.gd
```

Loads the real `main.tscn` and drives it by calling the game's own methods,
then writes PNGs to `shots/`. It resizes the window between shots, so the set
doubles as proof that the layout survives 640x480, 1280x720 and ultrawide.

It calls game methods rather than synthesising keystrokes deliberately —
`keybd_event` goes to whatever window has focus, and loses to any overlay that
happens to pop up.

`shots/` is gitignored; delete it freely.

## Export

```bash
godot --headless --path . --export-release "Windows Desktop"
```

Goes to `GameExports/DwarvenDepths.exe`. The Linux preset exists but has no
export path set yet — see [[PortMaster]].

Related: [[Architecture]], [[The Flood]], [[Next Steps]]
