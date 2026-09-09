---
tags: [moc]
updated: 2026-09-09
---

# Dwarven Depths

Endless vertical mining roguelite. Dig down, grab gems, outrun the water.
Godot 4.7.2. Windows desktop now, Anbernic H700 handheld later.

> [!info] This vault
> Open the `docs/` folder as an Obsidian vault. Notes link with `[[wikilinks]]`;
> the graph view is the fastest way to see what a change touches. The code lives
> one level up in `dwarven-depths/`.

## Start here

- [[Core Loop]] — what the game is, and the one decision it is built around
- [[The Flood]] — the water simulation, and why it is shaped the way it is
- [[Architecture]] — which file owns what
- [[Next Steps]] — what to do next, in order

## Design

- [[Core Loop]]
- [[The Flood]]
- [[Strata and Difficulty]]
- [[Presentation]]

## Systems

- [[Architecture]]
- [[Tooling]] — the headless harnesses, and how to run the game

## Ahead

- [[Next Steps]]
- [[Mega Bonk Direction]] — the long-term roguelite shape
- [[PortMaster]] — getting it onto the handheld

## Log

- [[2026-09-09 Flood rework]]

## Status

| Thing | State |
|---|---|
| Core loop | Playable, tuned against [[Tooling\|floodsim]] |
| Flood | Rewritten as a real per-tile simulation, 2026-09-09 |
| Player art | Pixel dwarf, two frames, mirrored by facing |
| Resolution | Scales to any window; constant vertical field of view |
| UI | Custom 3x5 bitmap font, anchored HUD, title and death screens |
| Handheld build | Not started — blocked on [[PortMaster]] runtime check |
