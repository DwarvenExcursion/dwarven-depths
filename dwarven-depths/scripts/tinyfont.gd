class_name TinyFont
extends RefCounted

## A 3x5 bitmap font drawn with draw_rect.
##
## Godot's default font is a hinted vector face; at the 8-10px sizes this game
## needs it goes soft and fights the pixel art. This is deliberately the same
## kind of asset as everything else here -- text you can edit -- and it stays
## perfectly crisp at any integer scale.
##
## Uppercase only. Lowercase input is folded up. Unknown glyphs render blank.

const GW := 3
const GH := 5
const ADVANCE := 4    # glyph + 1px gap, in unscaled pixels

const GLYPHS := {
	"0": ["###", "#.#", "#.#", "#.#", "###"],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"],
	"3": ["###", "..#", "###", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"],
	"5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"],
	"7": ["###", "..#", "..#", "..#", "..#"],
	"8": ["###", "#.#", "###", "#.#", "###"],
	"9": ["###", "#.#", "###", "..#", "###"],
	"A": [".#.", "#.#", "###", "#.#", "#.#"],
	"B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": [".##", "#..", "#..", "#..", ".##"],
	"D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"],
	"F": ["###", "#..", "##.", "#..", "#.."],
	"G": [".##", "#..", "#.#", "#.#", ".##"],
	"H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"],
	"J": ["..#", "..#", "..#", "#.#", ".#."],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"],
	"L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"],
	"N": ["#.#", "###", "###", "###", "#.#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"],
	"P": ["###", "#.#", "###", "#..", "#.."],
	"Q": ["###", "#.#", "#.#", "###", "..#"],
	"R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": [".##", "#..", ".#.", "..#", "##."],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#.#", "#.#", "###", "###", "#.#"],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
	"Z": ["###", "..#", ".#.", "#..", "###"],
	".": ["...", "...", "...", "...", ".#."],
	",": ["...", "...", "...", ".#.", "#.."],
	":": ["...", ".#.", "...", ".#.", "..."],
	"-": ["...", "...", "###", "...", "..."],
	"+": ["...", ".#.", "###", ".#.", "..."],
	"!": [".#.", ".#.", ".#.", "...", ".#."],
	"?": ["###", "..#", ".##", "...", ".#."],
	"/": ["..#", "..#", ".#.", "#..", "#.."],
	"<": ["..#", ".#.", "#..", ".#.", "..#"],
	">": ["#..", ".#.", "..#", ".#.", "#.."],
	"[": [".##", ".#.", ".#.", ".#.", ".##"],
	"]": ["##.", ".#.", ".#.", ".#.", "##."],
	"(": ["..#", ".#.", ".#.", ".#.", "..#"],
	")": ["#..", ".#.", ".#.", ".#.", "#.."],
	"*": ["#.#", ".#.", "#.#", "...", "..."],
	"'": [".#.", ".#.", "...", "...", "..."],
	"%": ["#.#", "..#", ".#.", "#..", "#.#"],
	"=": ["...", "###", "...", "###", "..."],
}


static func width(text: String, scale: int = 1) -> float:
	if text.is_empty():
		return 0.0
	return float(text.length() * ADVANCE - 1) * scale


static func height(scale: int = 1) -> float:
	return float(GH * scale)


## Draws with the top-left of the text box at `pos`.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String,
		color: Color, scale: int = 1) -> void:
	var s := float(scale)
	var pen := pos.x
	for i in text.length():
		var g: Variant = GLYPHS.get(text[i].to_upper())
		if g != null:
			for row in GH:
				var line: String = g[row]
				var x := 0
				while x < GW:
					if line[x] != "#":
						x += 1
						continue
					var run := 1
					while x + run < GW and line[x + run] == "#":
						run += 1
					ci.draw_rect(Rect2(pen + x * s, pos.y + row * s,
						run * s, s), color)
					x += run
		pen += ADVANCE * s


## Text with a 1px hard shadow in every direction. Essential over the world,
## where the background can be any colour in the palette.
static func draw_outlined(ci: CanvasItem, pos: Vector2, text: String,
		color: Color, outline: Color, scale: int = 1) -> void:
	var s := float(scale)
	for o in [Vector2(-s, 0), Vector2(s, 0), Vector2(0, -s), Vector2(0, s),
			Vector2(-s, -s), Vector2(s, -s), Vector2(-s, s), Vector2(s, s)]:
		draw_text(ci, pos + o, text, outline, scale)
	draw_text(ci, pos, text, color, scale)


static func draw_centered(ci: CanvasItem, center_x: float, y: float,
		text: String, color: Color, outline: Color, scale: int = 1) -> void:
	draw_outlined(ci, Vector2(roundf(center_x - width(text, scale) * 0.5), y),
		text, color, outline, scale)
