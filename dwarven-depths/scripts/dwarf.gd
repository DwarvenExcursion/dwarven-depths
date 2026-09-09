class_name Dwarf
extends RefCounted

## The player, drawn as pixel art from a text bitmap.
##
## Kept as strings rather than a PNG on purpose: the whole game renders through
## _draw(), there is no import step to babysit, and editing the dwarf means
## editing two blocks of text. Every glyph resolves through KEY into an Apollo
## colour, so he cannot drift off-palette.
##
## Frames face RIGHT. Facing left mirrors in x, which also swaps the helmet
## lamp to the leading edge -- exactly what you want.

const W := 14
const H := 14
const INSET := 1     # 14x14 sprite centred in a 16px tile

const KEY := {
	"h": Apollo.BRONZE,    # helmet
	"H": Apollo.RUST,      # helmet brim
	"L": Apollo.GOLD,      # lamp core
	"l": Apollo.AMBER,     # lamp glow
	"s": Apollo.SAND,      # skin
	"e": Apollo.SLATE_D,   # eye
	"b": Apollo.BONE,      # beard
	"B": Apollo.MIST,      # beard shadow
	"t": Apollo.AZURE,     # tunic
	"k": Apollo.SOIL_XD,   # belt
	"w": Apollo.SOIL_D,    # pick handle
	"m": Apollo.SLATE_XL,  # pick head
	"o": Apollo.BARK_XD,   # boots
}

const IDLE := [
	"..............",
	"....hhhhhh....",
	"...hhhhhhhh...",
	"..hhhhhhhhhh..",
	"..HHHHHHHHHHLl",
	"....ssssss....",
	"....sesses....",
	"...bbbbbbbb...",
	"..BbbbbbbbbBmm",
	"..Bbbbbbbbb.m.",
	"...bbbbbbbb.w.",
	"....tttttt..w.",
	"...tkkkkkkt.w.",
	"...oo....oo...",
]

## Helmet dips a pixel and the pick swings down to strike. Alternating this
## with IDLE on the dig cooldown is what sells the digging.
const SWING := [
	"..............",
	"..............",
	"....hhhhhh....",
	"...hhhhhhhh...",
	"..hhhhhhhhhh..",
	"..HHHHHHHHHHLl",
	"....ssssss....",
	"....sesses....",
	"...bbbbbbbb...",
	"..BbbbbbbbbB..",
	"...bbbbbbbb...",
	"....tttttt.w..",
	"...tkkkkkkt.w.",
	"...oo....oomm.",
]

# Horizontal runs, baked once. A naive per-pixel draw is ~190 draw_rect calls
# every frame for one sprite; run-merging cuts it to about 40.
static var _runs := {}


static func _bake(frame: Array) -> Array:
	var out: Array = []
	for y in frame.size():
		var row: String = frame[y]
		var x := 0
		while x < row.length():
			var c := row[x]
			if c == ".":
				x += 1
				continue
			var run := 1
			while x + run < row.length() and row[x + run] == c:
				run += 1
			out.append([x, y, run, KEY[c] as Color])
			x += run
	return out


static func runs(frame: Array) -> Array:
	var id: int = frame.hash()
	if not _runs.has(id):
		_runs[id] = _bake(frame)
	return _runs[id]


## origin: top-left of the dwarf's tile in world pixels.
## facing: -1 or 1. submerged: 0..1, sinks his colours toward the water.
static func draw_at(ci: CanvasItem, origin: Vector2, facing: int,
		swinging: bool, submerged: float = 0.0) -> void:
	var frame: Array = SWING if swinging else IDLE
	var ox := origin.x + INSET
	var oy := origin.y + INSET

	# Lamp bloom. Drawn as a stepped cross rather than a translucent square,
	# because a square of flat alpha over the rock reads as a rendering bug,
	# not as light.
	var lamp_x := ox + (W - 2.0 if facing >= 0 else 1.0)
	var lamp_y := oy + (5.0 if swinging else 4.0)
	var glow := Color(Apollo.GOLD, 0.13)
	ci.draw_rect(Rect2(lamp_x - 2.0, lamp_y, 6.0, 2.0), glow)
	ci.draw_rect(Rect2(lamp_x - 1.0, lamp_y - 2.0, 4.0, 6.0), glow)

	for r in runs(frame):
		var x: int = r[0]
		var y: int = r[1]
		var n: int = r[2]
		var col: Color = r[3]
		if submerged > 0.0:
			col = col.lerp(Apollo.DENIM, submerged * 0.45)
		var px := ox + (float(x) if facing >= 0 else float(W - x - n))
		ci.draw_rect(Rect2(px, oy + float(y), float(n), 1.0), col)
