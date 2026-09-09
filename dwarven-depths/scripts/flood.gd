class_name Flood
extends RefCounted

## Water that actually flows through the tunnels you dug.
##
## Every open tile holds a volume in [0,1]. Each tick water falls into the
## tile below it, then equalises sideways with its neighbours. Dirt and stone
## block it outright, so an unbreached pocket stays dry and a sealed side
## chamber becomes a sump that drinks water you would otherwise be swimming in.
##
## Why this reads as a chase rather than an instant drowning: the front is
## limited by VOLUME, not by reach. A thin film races down your shaft in a
## second, but it cannot drown you until enough litres have accumulated, and
## litres arrive at a fixed inflow rate. Dig straight down and the whole inflow
## stacks up right behind your heels. Dig a wide gallery and the same inflow
## has to fill ten tiles per row instead of one, which buys you real time --
## paid for in the depth you did not gain.
##
## Only a window of rows around the player is simulated. Above the window the
## mine is solid water, which is why injection happens at the window's top edge
## rather than at the surface. The leash below guarantees the front never
## escapes that window.

const TICK := 1.0 / 20.0     # simulation rate, independent of framerate

## HEAD is the whole trick. A tile passes water downward only once it holds
## more than this, so the descending front has to WET every tile on the way
## down before it can go deeper. Without it water behaves like a falling-sand
## trickle: it reaches the bottom of your shaft in a single second, and since
## the bottom of your shaft is where you are standing, you drown at depth 11.
## With it the front descends at roughly inflow/HEAD rows per second, which is
## a number the dwarf can outrun -- and stop outrunning when he hits stone.
const HEAD      := 0.20

const DOWN_RATE := 0.30      # max volume a tile can drop per tick
const SIDE_RATE := 0.10      # sideways equalisation; deliberately much slower
const SEEP      := 0.010     # below this a tile is a stain, not a flow
const WET       := 0.05      # visible at all
const DROWN     := 0.55      # lethal, and drawn as solid water

const WINDOW_UP   := 18      # rows simulated above the player
const WINDOW_DOWN := 14

# Inflow is the difficulty curve. Divide by HEAD to get roughly "rows the
# front descends per second", and compare that against how fast the dwarf
# actually gets down -- about 9 rows/s through clean dirt, far less once
# stone starts forcing detours.
const INFLOW_BASE := 0.30
const INFLOW_RAMP := 0.0026  # per row of depth

## Hard leash. A clean straight dig outruns the front indefinitely at shallow
## depths, and a threat you cannot see is not a threat. When the wet front
## falls more than LEASH rows behind, inflow scales up until it catches back
## up. This is the one deliberately unphysical rule in the file and it is
## load-bearing. The cap matters as much as the gain: without it the boost
## compounds off a front that has not spawned yet and the run ends instantly.
const LEASH := 10.0
const LEASH_GAIN := 0.22
const LEASH_MAX := 2.4

var level := {}              # Vector2i -> float in [0,1]
var front := -8              # deepest row holding lethal water (drives the HUD)
var wet_front := -8          # deepest row holding any flow (drives the leash)
var sim_top := Mine.SKY_ROWS

var _acc := 0.0
var _t := 0.0


func reset() -> void:
	level.clear()
	front = -8
	wet_front = -8
	sim_top = Mine.SKY_ROWS
	_acc = 0.0
	_t = 0.0


func at(p: Vector2i) -> float:
	if p.y < sim_top:
		# Above the window is the drowned mass -- but only once the window has
		# actually left the surface. While it is still parked at the sky the
		# rows above it are open air, and reporting them as full would draw a
		# flooded sky over the title screen.
		return 1.0 if sim_top > Mine.SKY_ROWS else 0.0
	return level.get(p, 0.0)


func is_lethal(p: Vector2i) -> bool:
	return at(p) >= DROWN


func time() -> float:
	return _t


func step(mine: Mine, focus_row: int, dt: float) -> void:
	_t += dt
	_acc += dt
	# Cap catch-up so a frame hitch cannot fast-forward the flood into you.
	var budget := 4
	while _acc >= TICK and budget > 0:
		_acc -= TICK
		budget -= 1
		_tick(mine, focus_row)
	if _acc >= TICK:
		_acc = 0.0


## The window is never allowed above the sky. The open rows at the surface are
## COLS wide, and since a tile has to reach HEAD before it passes anything
## downward, letting the water in there means priming 3 x 18 tiles -- half a
## minute of inflow -- before a drop ever enters the shaft. Starting at the
## first dirt row instead means the water enters through the hole the dwarf
## made, which is both faster and a better story.
func _tick(mine: Mine, focus_row: int) -> void:
	var new_top: int = maxi(Mine.SKY_ROWS, focus_row - WINDOW_UP)
	if new_top > sim_top:
		sim_top = new_top
		for p in level.keys():
			if p.y < sim_top:
				level.erase(p)

	_inject(mine, focus_row)
	_fall(mine)
	_spread(mine)
	_settle(focus_row)


## Water enters at the top of the window, through whichever tiles are open
## there. If you tunnelled sideways and left one narrow chimney behind you,
## the entire inflow funnels through that chimney -- which is the whole point.
func _inject(mine: Mine, focus_row: int) -> void:
	var inlets: Array[Vector2i] = []
	for x in Mine.COLS:
		var p := Vector2i(x, sim_top)
		if mine.is_open(p):
			inlets.append(p)
	if inlets.is_empty():
		return

	var rate := INFLOW_BASE + float(maxi(focus_row, 0)) * INFLOW_RAMP
	var gap := float(focus_row - wet_front)
	if gap > LEASH:
		rate *= minf(1.0 + (gap - LEASH) * LEASH_GAIN, LEASH_MAX)

	var share: float = rate * TICK / float(inlets.size())
	for p in inlets:
		level[p] = minf(1.0, level.get(p, 0.0) + share)


func _fall(mine: Mine) -> void:
	var moved := {}
	for p in level:
		var w: float = level[p]
		if w <= HEAD:
			continue
		var below: Vector2i = p + Vector2i(0, 1)
		if not mine.is_open(below):
			continue
		var room: float = 1.0 - level.get(below, 0.0)
		if room <= 0.0:
			continue
		var t: float = minf(minf(w - HEAD, room), DOWN_RATE)
		moved[p] = moved.get(p, 0.0) - t
		moved[below] = moved.get(below, 0.0) + t
	_apply(moved)


## Each neighbour pair is visited from both sides, but only the downhill
## direction transfers, so a pair moves exactly once per tick.
func _spread(mine: Mine) -> void:
	var moved := {}
	for p in level:
		var w: float = level[p]
		if w < SEEP:
			continue
		for dx in [-1, 1]:
			var n: Vector2i = p + Vector2i(dx, 0)
			if not mine.is_open(n):
				continue
			var wn: float = level.get(n, 0.0)
			if wn >= w:
				continue
			var t: float = minf((w - wn) * SIDE_RATE, w)
			moved[p] = moved.get(p, 0.0) - t
			moved[n] = moved.get(n, 0.0) + t
	_apply(moved)


func _apply(moved: Dictionary) -> void:
	for p in moved:
		level[p] = clampf(level.get(p, 0.0) + moved[p], 0.0, 1.0)


func _settle(focus_row: int) -> void:
	var deepest := -8
	var wettest := -8
	var cull: int = focus_row + WINDOW_DOWN
	for p in level.keys():
		var w: float = level[p]
		if w < 0.004 or p.y > cull:
			level.erase(p)      # drop dribble so the dict cannot creep upward
			continue
		if w >= WET and p.y > wettest:
			wettest = p.y
		if w >= DROWN and p.y > deepest:
			deepest = p.y
	front = deepest
	wet_front = wettest
