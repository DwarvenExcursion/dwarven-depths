class_name Mine
extends RefCounted

## The tile world. Generated lazily, one row at a time, forever downward.
## Nothing here knows about the player, the flood, or drawing.

enum { EMPTY, DIRT, STONE, GEM }

const COLS := 20
const SKY_ROWS := 3          # open air above the dirt; the flood ignores it

var tiles := {}          # Vector2i -> int
var generated_to := -1


func reset() -> void:
	tiles.clear()
	generated_to = -1


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
		for x in COLS:
			var t := DIRT
			if x == 0 or x == COLS - 1:
				t = STONE
			elif generated_to < SKY_ROWS:
				t = EMPTY          # open sky, and the flood's inlet
			elif randf() < st["stone"]:
				t = STONE
			elif randf() < st["gem"]:
				t = GEM
			tiles[Vector2i(x, generated_to)] = t
