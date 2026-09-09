extends SceneTree

## Headless flood tuning harness.
##
##   godot --headless --path . --script res://tools/floodsim.gd
##
## Plays the game with a scripted dwarf so you can change a constant in
## flood.gd and see what it did to survival time in about four seconds,
## instead of playing twenty runs to find out. Add scenarios as you add
## mechanics -- this is the only place the water gets measured.

const TILE := 16
const MOVE_DELAY := 0.11
const DT := 1.0 / 60.0
const MAX_TIME := 240.0
const SEED := 20260909    # fixed, so a tuning change is the only variable


func _initialize() -> void:
	print("")
	print("=== flood tuning ===")
	print("inflow %.2f + %.3f/row   leash %.0f   drown %.2f"
		% [Flood.INFLOW_BASE, Flood.INFLOW_RAMP, Flood.LEASH, Flood.DROWN])
	print("")

	_greedy_run()
	_stall_test(40, 4.0)
	_stall_test(120, 4.0)
	_pocket_test()
	_gallery_test()

	print("")
	quit()


# --- Scenarios ----------------------------------------------------

## A dwarf who only ever digs down, sidestepping stone. This is the skill
## ceiling for descent, so whatever depth it reaches is roughly the best a
## human can do -- if this run never dies, the game has no difficulty curve.
func _greedy_run() -> void:
	seed(SEED)
	var mine := Mine.new()
	var flood := Flood.new()
	mine.generate_to(60)

	var p := Vector2i(10, 2)
	var deepest := 0
	var cd := 0.0
	var t := 0.0
	var marks := {60: -1.0, 130: -1.0, 210: -1.0}
	var gap_sum := 0.0
	var gap_n := 0
	var gap_min := 999

	while t < MAX_TIME:
		t += DT
		cd -= DT
		if cd <= 0.0:
			p = _greedy_step(mine, p)
			deepest = maxi(deepest, p.y)
			if marks.has(deepest) and marks[deepest] < 0.0:
				marks[deepest] = t
			cd = MOVE_DELAY
		flood.step(mine, p.y, DT)
		if t > 3.0 and flood.wet_front > 0:
			var g: int = p.y - flood.wet_front
			gap_sum += g
			gap_n += 1
			gap_min = mini(gap_min, g)
		if flood.is_lethal(p):
			break

	print("greedy dig   died at depth %4d after %5.1fs  (%.1f rows/s)"
		% [deepest, t, float(deepest) / maxf(t, 0.001)])
	print("               lead over water: avg %.1f rows, tightest %d"
		% [gap_sum / maxf(gap_n, 1), gap_min])
	for row in [60, 130, 210]:
		var when: float = marks[row]
		print("               reached %3d at %s" % [row,
			("%.1fs" % when) if when > 0.0 else "never"])


## How long you have if a stone wall stops you dead at a given depth. This is
## the number that decides whether a detour is a decision or a death sentence,
## so it has to start from a state a real run could actually be in: dig down
## honestly, THEN freeze. Boring a shaft instantly and settling gives a much
## grimmer answer, because the water has been pouring into a finished hole.
func _stall_test(depth: int, _settle: float) -> void:
	seed(SEED)
	var mine := Mine.new()
	var flood := Flood.new()
	mine.generate_to(depth + 40)

	var p := Vector2i(10, 2)
	var cd := 0.0
	var t := 0.0
	while p.y < depth and t < MAX_TIME:
		t += DT
		cd -= DT
		if cd <= 0.0:
			p = _greedy_step(mine, p)
			cd = MOVE_DELAY
		flood.step(mine, p.y, DT)
		if flood.is_lethal(p):
			print("stall @%3d   never got there -- drowned at %d en route"
				% [depth, p.y])
			return

	var lead := p.y - maxi(flood.front, flood.wet_front)
	var held := 0.0
	while held < 90.0:
		held += DT
		flood.step(mine, p.y, DT)
		if flood.is_lethal(p):
			break
	print("stall @%3d   arrived %.0fs, water %2d rows back, drowned after %4.1fs"
		% [depth, t, lead, held])


## Blast a chamber that is never connected to the shaft and it must stay dry
## forever. If this fails the water is leaking through solid rock.
func _pocket_test() -> void:
	seed(SEED)
	var mine := Mine.new()
	var flood := Flood.new()
	var p := _bore(mine, 40)

	var pocket := Vector2i(4, 30)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			mine.carve(pocket + Vector2i(dx, dy))

	var t := 0.0
	while t < 30.0:
		t += DT
		flood.step(mine, p.y, DT)
	print("sealed pocket water level %.3f  (want 0.000)" % flood.at(pocket))


## A wide horizontal gallery should buy time: the same inflow now has to fill
## twenty tiles per row instead of one. If this is not clearly slower than the
## bare stall test, side tunnels are not a real decision and SIDE_RATE or the
## leash needs looking at.
func _gallery_test() -> void:
	seed(SEED)
	var mine := Mine.new()
	var flood := Flood.new()
	var p := _bore(mine, 40)

	for y in range(32, 40):
		for x in range(1, Mine.COLS - 1):
			mine.carve(Vector2i(x, y))

	var t := 0.0
	while t < 4.0:
		t += DT
		flood.step(mine, p.y, DT)

	var held := 0.0
	while held < 60.0:
		held += DT
		flood.step(mine, p.y, DT)
		if flood.is_lethal(p):
			break
	print("gallery @ 40 drowned after %4.1fs of standing still" % held)


# --- Helpers ------------------------------------------------------

## Carve a clean 1-wide shaft straight down to `depth` and return the dwarf.
func _bore(mine: Mine, depth: int) -> Vector2i:
	mine.generate_to(depth + Flood.WINDOW_DOWN + 20)
	for y in range(0, depth + 1):
		mine.carve(Vector2i(10, y))
	return Vector2i(10, depth)


## Down if you can, otherwise sidestep toward the nearest column that is not
## stone. Deliberately dumb -- a real player routes further ahead.
func _greedy_step(mine: Mine, p: Vector2i) -> Vector2i:
	mine.generate_to(p.y + 40)
	var down := p + Vector2i(0, 1)
	if mine.at(down) != Mine.STONE:
		mine.carve(down)
		return down
	for dx in [1, -1, 1, -1]:
		var side := p + Vector2i(dx, 0)
		if mine.in_bounds_x(side.x) and mine.at(side) != Mine.STONE:
			mine.carve(side)
			return side
	return p
