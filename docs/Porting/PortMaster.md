---
tags: [porting, blocked]
updated: 2026-09-09
---

# PortMaster / Anbernic H700

Target device: Anbernic H700 family (RG-xx), running Stock OS Mod, games
delivered via PortMaster.

## Blocking, in order

- [ ] **Check PortMaster's available Godot runtimes — do this first.**
      Runtimes are version-pinned (`godot_runtime="godot_4.3"` in the launch
      script). This project is built on **4.7.2**. If there is no 4.7 runtime,
      the `.pck` will not load and the project has to be rebuilt in a supported
      version. That would invalidate a chunk of [[Next Steps]], so it is worth
      knowing before doing any of it.
- [ ] Get a working `.sh`. Easiest path is installing any existing Godot port
      from PortMaster and copying its script, so it matches this firmware.
- [ ] Confirm the on-device layout. This card uses folders and `.sh` files side
      by side in `PORTS/`, not the standard `ROMS/Ports/` + `ports/` split.
- [ ] Device needs wifi on first launch to pull the shared Godot runtime.
- [ ] Retune `MOVE_DELAY` for the d-pad — see [[Next Steps]].

## Why the keyboard bindings matter

gptokeyb translates physical buttons into **keyboard** events. Joypad-only
bindings would do nothing on device. Every action in `project.godot` is bound
to both a key and a joypad button, and it has to stay that way. See
[[Presentation#Controls]].

## Rendering notes

PortMaster runs Godot via **FRT**, a custom export template for KMS/DRM devices
without X11. Prebuilt binaries live in the PortMaster runtime repo.

The project already uses `gl_compatibility` for both desktop and mobile
renderers, which is the right choice here.

The Linux export preset exists but has no `export_path` set yet.

## Resolution

The panel is 640x480 on most H700 devices. The base viewport is 320x240, so it
doubles exactly — and since 640x480 is 4:3, the
[[Architecture#Resolution|constant field of view]] logic lands on a clean
integer zoom of 2 with no bedrock showing. This is the best case for the
scaling scheme, which is deliberate.

## Reference

- Device: [Anbernic-H700-RG-xx-StockOS-Modification](https://github.com/cbepx-me/Anbernic-H700-RG-xx-StockOS-Modification)
- [PortMaster for StockOS MOD](https://github.com/kai4man/PortMaster-for-StockOS-MOD)
- Godot 4 port template: binarycounter/Westonpack wiki, "Godot 4 Example"
- [gptokeyb mapping docs](https://portmaster.games/gptokeyb-documentation.html)

Related: [[Next Steps]], [[Tooling]]
