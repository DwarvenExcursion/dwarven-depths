extends RefCounted

## Things in the mine that move.
##
## The tile world is a Dictionary of ints and cannot represent anything with
## state, so anything that moves lives here instead: a flat array of
## dictionaries, updated on the same tick model the fall uses.
##
## Deliberately not a `class_name`. Adding one while the editor is closed
## leaves the global class cache stale, and the documented fix -- an editor
## import pass -- hangs on this project. main.gd preloads this file instead.
##
## ## Update order
##
## Fixed, and it matters, because enemy behaviour should be predictable rather
## than emergent from whoever happened to run first:
##
##   1. the player moves (dig, fall, drift)
##   2. entities move
##   3. overlaps are resolved
##
## So a goblin can never step onto a tile the player is about to vacate and
## claim it retroactively, and the player is never punished for a move that
## was legal when they made it.

enum { GOBLIN }

# --- Goblin ---------------------------------------------------------
#
# Built to be an obstacle first and a threat second. It walks a heading, turns
# when blocked, and never pathfinds -- so it cannot corner you, and anything
# it does is visible several ticks before it matters.
#
# The tick is slow on purpose. At 0.55 s it moves at a fifth of the dwarf's
# walking rate, which means you always have the option to dig it out rather
# than react to it.
const GOBLIN_TICK := 0.55
const GOBLIN_MIN_DEPTH := 60      # the surface stays clean
const GOBLIN_PER_CAVE := 0.40     # spawn chance per row, scaled by `cave`
const GOBLIN_MAX := 12            # alive at once, anywhere in the window

var list: Array[Dictionary] = []

var _spawned_to := -1
var _acc := 0.0


func reset() -> void:
	list.clear()
	_spawned_to = -1
	_acc = 0.0


func at(p: Vector2i) -> int:
	for e in list:
		if e["p"] == p:
			return e["kind"]
	return -1


func blocks(p: Vector2i) -> bool:
	return at(p) != -1


## One hit clears a goblin. Returns true if something was there, so the caller
## can spend the dig on it instead of moving into the tile.
func clear_at(p: Vector2i) -> bool:
	for i in list.size():
		if list[i]["p"] == p:
			list.remove_at(i)
			return true
	return false


# --- Spawning -------------------------------------------------------

## Goblins want somewhere to stand, so they are seeded from the same `cave`
## curve that decides how much open space a band has. Deep bands are roomier
## and therefore more populated, with no extra number in the strata table.
func spawn_ahead(mine: Mine, to_row: int) -> void:
	if _spawned_to < 0:
		_spawned_to = maxi(GOBLIN_MIN_DEPTH, mine.SKY_ROWS)

	while _spawned_to < to_row:
		_spawned_to += 1
		if _spawned_to < GOBLIN_MIN_DEPTH or list.size() >= GOBLIN_MAX:
			continue

		var cave: float = Apollo.stratum(_spawned_to)["cave"]
		if cave <= 0.0 or randf() >= cave * GOBLIN_PER_CAVE:
			continue

		var spot := _standing_spot(mine, _spawned_to)
		if spot.x < 0:
			continue
		list.append({
			"kind": GOBLIN,
			"p": spot,
			"dir": 1 if randf() < 0.5 else -1,
			"bob": randf() * TAU,
		})


## An open tile with something solid under it. Goblins do not fly and do not
## fall -- if there is no floor on this row, there is no goblin on this row.
func _standing_spot(mine: Mine, y: int) -> Vector2i:
	var start := 1 + randi() % (mine.COLS - 2)
	for i in mine.COLS - 2:
		var x: int = 1 + (start - 1 + i) % (mine.COLS - 2)
		var p := Vector2i(x, y)
		if not _walkable(mine, p) or blocks(p):
			continue
		# Must have somewhere to walk. A one-tile pocket in the speckle is a
		# legal place to stand and a terrible place to put something whose
		# only tell is which way it is facing -- it would turn on the spot
		# forever. This is what makes goblins a cavern animal.
		if _has_room(mine, p):
			return p
	return Vector2i(-1, -1)


func _has_room(mine: Mine, p: Vector2i) -> bool:
	for dx in [-1, 1]:
		for dy in [0, -1, 1]:
			if _walkable(mine, p + Vector2i(dx, dy)):
				return true
	return false


# --- Update ---------------------------------------------------------

## Returns the number of gems stolen this step, so main can apply the cost
## without this file reaching into the game.
func step(mine: Mine, flood: Flood, player: Vector2i, view_top: int, delta: float) -> int:
	_acc += delta
	var stolen := 0

	while _acc >= GOBLIN_TICK:
		_acc -= GOBLIN_TICK
		stolen += _tick(mine, player)

	_cull(flood, view_top)
	return stolen


func _tick(mine: Mine, player: Vector2i) -> int:
	var stolen := 0

	for e in list:
		if e["kind"] != GOBLIN:
			continue

		var here: Vector2i = e["p"]
		var ahead: Vector2i = here + Vector2i(e["dir"], 0)

		# A goblin that reaches the dwarf takes one gem and runs. Non-lethal on
		# purpose: the thing that ends runs here is being out of gems in front
		# of stone, so the sharpest thing an enemy can do is take one.
		#
		# Only ever straight ahead, never on a diagonal step, so the eyes are a
		# truthful warning about where the next grab can come from.
		if ahead == player:
			stolen += 1
			e["dir"] = -e["dir"]
			continue

		# Level, then up a step, then down one. Without the steps a goblin on
		# any broken ground has nowhere legal to put its foot and spends its
		# life turning around on the spot.
		var tried := [ahead, ahead + Vector2i(0, -1), ahead + Vector2i(0, 1)]
		var went := false
		for i in tried.size():
			var t: Vector2i = tried[i]
			if t == player or blocks(t) or not _walkable(mine, t):
				continue
			# Climbing needs headroom; it does not tunnel through the ceiling.
			if i == 1 and not mine.is_open(here + Vector2i(0, -1)):
				continue
			e["p"] = t
			went = true
			break

		if not went:
			e["dir"] = -e["dir"]

	return stolen


func _walkable(mine: Mine, p: Vector2i) -> bool:
	if p.x <= 0 or p.x >= mine.COLS - 1:
		return false
	return mine.is_open(p) and not mine.is_open(p + Vector2i(0, 1))


## Drowned, or scrolled far enough above the view to be irrelevant. Culling on
## the flood rather than on distance means a goblin you outran is gone for the
## same reason you would be.
func _cull(flood: Flood, view_top: int) -> void:
	for i in range(list.size() - 1, -1, -1):
		var p: Vector2i = list[i]["p"]
		if p.y < view_top - 24 or flood.is_lethal(p):
			list.remove_at(i)
