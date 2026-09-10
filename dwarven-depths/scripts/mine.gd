class_name Mine
extends RefCounted

## The tile world. Generated lazily, one row at a time, forever downward.
## Nothing here knows about the player, the flood, or drawing.

enum { EMPTY, DIRT, STONE, GEM }

const COLS := 20
const SKY_ROWS := 3          # open air above the dirt; the flood ignores it

## How often a chamber starts, as a fraction of the stratum's `cave` value.
## Chambers and per-tile porosity are drawn from the same curve so there is
## one number per band to tune, not three.
const CHAMBER_RATE := 0.35
const SPECKLE_RATE := 0.5

var tiles := {}          # Vector2i -> int
var generated_to := -1

## Chambers still being cut. A chamber is declared at its top row and carved
## into each row as that row generates, because generation only ever moves
## downward and never revisits.
var _chambers: Array[Dictionary] = []


func reset() -> void:
	tiles.clear()
	generated_to = -1
	_chambers.clear()


func at(p: Vector2i) -> int:
	# Ungenerated space reads as DIRT so callers never see a hole in the world.
	return tiles.get(p, DIRT)


func is_open(p: Vector2i) -> bool:
	return tiles.get(p, DIRT) == EMPTY


func carve(p: Vector2i) -> void:
	tiles[p] = EMPTY


func in_bounds_x(x: int) -> bool:
	return x >= 0 and x < COLS


## Walls are STONE columns at both edges, so the shaft is a closed vessel.
## The flood relies on that: water must never leak out the sides.
func generate_to(row: int) -> void:
	while generated_to < row:
		generated_to += 1
		var st := Apollo.stratum(generated_to)
		var cave: float = st["cave"]

		for x in COLS:
			var t := DIRT
			if x == 0 or x == COLS - 1:
				t = STONE
			elif generated_to < SKY_ROWS:
				t = EMPTY          # open sky, and the flood's inlet
			elif randf() < cave * SPECKLE_RATE:
				# Rock that has already broken. Rolled before stone so the
				# deep tiers stay passable: they are the hardest to cut and
				# also the most likely to be open somewhere.
				t = EMPTY
			elif randf() < st["stone"]:
				t = STONE
			elif randf() < st["gem"]:
				t = GEM
			tiles[Vector2i(x, generated_to)] = t

		_open_chamber(generated_to, cave)
		_cut_chambers(generated_to)


## Chambers grow with depth because `cave` does. Deep rock is the hardest to
## dig and the most likely to have already collapsed into a room, which is
## what keeps a 0.56-stone band from being a wall -- and it gives anything
## that needs open space somewhere to live.
##
## Held clear of the opening rows: a chamber at the surface would drop the
## dwarf into a hole before he has dug anything.
func _open_chamber(y: int, cave: float) -> void:
	if cave <= 0.0 or y < SKY_ROWS + 6:
		return
	if randf() >= cave * CHAMBER_RATE:
		return

	var rx: float = 1.2 + cave * 16.0
	var ry: float = 1.0 + cave * 9.0
	_chambers.append({
		"cx": randf_range(2.0, float(COLS - 3)),
		"cy": float(y) + ry,          # declared at the top, centre is below
		"rx": rx,
		"ry": ry,
	})


## Carve every live chamber's slice of this row, then retire the ones the
## generator has passed. An ellipse rather than a box so the rooms read as
## caves and not as excavations.
func _cut_chambers(y: int) -> void:
	for i in range(_chambers.size() - 1, -1, -1):
		var c: Dictionary = _chambers[i]
		var dy: float = (float(y) - c["cy"]) / c["ry"]
		if dy > 1.0:
			_chambers.remove_at(i)
			continue
		if dy < -1.0:
			continue

		var hw: float = c["rx"] * sqrt(1.0 - dy * dy)
		# Never the border columns. The shaft has to stay a closed vessel or
		# the flood leaks out the sides.
		var x0: int = maxi(1, int(round(c["cx"] - hw)))
		var x1: int = mini(COLS - 2, int(round(c["cx"] + hw)))
		for x in range(x0, x1 + 1):
			tiles[Vector2i(x, y)] = EMPTY
