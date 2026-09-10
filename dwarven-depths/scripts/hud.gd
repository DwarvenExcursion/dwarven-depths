extends Control

## All screen-space UI. Lives on a CanvasLayer so it never moves with the
## camera, and anchors to the full rect so it lands in the real corners of
## whatever window it is given -- 320x240 on the handheld, 1920x1080 on
## desktop, anything in between.
##
## Main pushes state into the public vars below and calls queue_redraw().
## The HUD never reaches back into the game.

enum Mode { TITLE, PLAY, DEAD, PAUSE }

const PAD := 5.0
const BAR_H := 15.0

var mode: int = Mode.TITLE
var depth := 0
var best := 0
var gems := 0
var bomb_cost := 3
var vol_sfx := 0.7
var vol_music := 0.7
var vol_sel := 0         # which volume line the title screen has selected
var pause_sel := 0       # which pause-menu entry is selected
var stratum_name := "SURFACE"
var danger := 0.0        # 0..1, how close the water is
var new_best := false

var banner := ""
var banner_t := 0.0

var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(queue_redraw)


func announce(text: String) -> void:
	banner = text
	banner_t = 2.2
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if banner_t > 0.0:
		banner_t = maxf(0.0, banner_t - delta)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	match mode:
		Mode.PLAY:
			_draw_danger(w, h)
			_draw_bar(w)
			_draw_gems(h)
			_draw_banner(w)
		Mode.TITLE:
			_draw_title(w, h)
		Mode.PAUSE:
			_draw_pause(w, h)
		Mode.DEAD:
			_draw_dead(w, h)


# --- In-game ------------------------------------------------------

## Red creeping in from the edges as the water closes. Reads peripherally,
## so it warns you without asking you to look away from the dig face.
func _draw_danger(w: float, h: float) -> void:
	if danger <= 0.01:
		return
	var pulse := 0.72 + 0.28 * sin(_t * 7.0)
	var a := danger * danger * 0.5 * pulse
	var band := 3.0 + danger * 9.0
	draw_rect(Rect2(0, 0, w, band), Color(Apollo.FLOOD_HI, a))
	draw_rect(Rect2(0, h - band, w, band), Color(Apollo.FLOOD_HI, a))
	draw_rect(Rect2(0, 0, band, h), Color(Apollo.FLOOD_HI, a))
	draw_rect(Rect2(w - band, 0, band, h), Color(Apollo.FLOOD_HI, a))


func _draw_bar(w: float) -> void:
	# Opaque on purpose: any transparency and the stone and dirt behind it show
	# through, and the readouts sit on a blotchy, shifting ground.
	draw_rect(Rect2(0, 0, w, BAR_H), Apollo.VOID)
	draw_rect(Rect2(0, BAR_H, w, 1), Color(Apollo.SLATE_D, 0.8))

	# Bottom-aligned with the big number beside it, not top-aligned.
	TinyFont.draw_text(self, Vector2(PAD, 8), "DEPTH", Apollo.SLATE_XL, 1)
	var dv := str(depth)
	TinyFont.draw_text(self, Vector2(PAD + TinyFont.width("DEPTH", 1) + 4, 3),
		dv, Apollo.WHITE, 2)

	# Stratum sits between depth and best; it is context, not a readout.
	TinyFont.draw_centered(self, w * 0.5, 5, stratum_name,
		Apollo.SLATE_XL, Color(Apollo.VOID, 0.0), 1)

	var bt := "BEST " + str(best)
	TinyFont.draw_text(self, Vector2(w - PAD - TinyFont.width(bt, 1), 5),
		bt, Apollo.SLATE_L, 1)


func _draw_gems(h: float) -> void:
	var y := h - PAD - 9.0
	_gem_icon(Vector2(PAD, y))
	TinyFont.draw_outlined(self, Vector2(PAD + 11, y + 2), str(gems),
		Apollo.GEM_HI, Apollo.VOID, 1)

	# Blast readiness as pips: you read "one more gem" at a glance, which you
	# cannot do from a bare number against a cost.
	var px := PAD + 11 + TinyFont.width(str(gems), 1) + 7
	for i in bomb_cost:
		var lit := gems > i
		var r := Rect2(px + i * 5, y + 2, 3, 5)
		draw_rect(r, Apollo.VOID)
		draw_rect(r.grow(-0.0), Apollo.EMBER if lit else Color(Apollo.SLATE, 0.7))
	if gems >= bomb_cost:
		TinyFont.draw_outlined(self, Vector2(px + bomb_cost * 5 + 4, y + 2),
			"[Z] BLAST", Apollo.GOLD, Apollo.VOID, 1)


func _gem_icon(p: Vector2) -> void:
	draw_rect(Rect2(p.x + 2, p.y + 1, 5, 1), Apollo.GEM)
	draw_rect(Rect2(p.x + 1, p.y + 2, 7, 3), Apollo.GEM)
	draw_rect(Rect2(p.x + 2, p.y + 5, 5, 1), Apollo.GEM)
	draw_rect(Rect2(p.x + 3, p.y + 6, 3, 1), Apollo.GEM)
	draw_rect(Rect2(p.x + 2, p.y + 2, 2, 2), Apollo.GEM_HI)


func _draw_banner(w: float) -> void:
	if banner_t <= 0.0:
		return
	var a: float = clampf(banner_t / 0.6, 0.0, 1.0)
	var y := size.y * 0.30
	var bw := TinyFont.width(banner, 2) + 16.0
	draw_rect(Rect2(roundf(w * 0.5 - bw * 0.5), y - 6, bw, 22),
		Color(Apollo.VOID, 0.7 * a))
	TinyFont.draw_centered(self, w * 0.5, y, banner,
		Color(Apollo.GOLD, a), Color(Apollo.VOID, a), 2)


# --- Title / death ------------------------------------------------

func _panel(w: float, h: float, pw: float, ph: float) -> Vector2:
	var o := Vector2(roundf(w * 0.5 - pw * 0.5), roundf(h * 0.5 - ph * 0.5))
	draw_rect(Rect2(o.x - 1, o.y - 1, pw + 2, ph + 2), Color(Apollo.SLATE_D, 0.9))
	draw_rect(Rect2(o, Vector2(pw, ph)), Color(Apollo.VOID, 0.88))
	return o


func _draw_title(w: float, h: float) -> void:
	var o := _panel(w, h, 190.0, 138.0)   # +8 for the second volume line
	var cx := w * 0.5
	var y := o.y + 10.0

	TinyFont.draw_centered(self, cx, y, "DWARVEN", Apollo.GOLD, Apollo.BARK_XD, 3)
	y += 20.0
	TinyFont.draw_centered(self, cx, y, "DEPTHS", Apollo.GOLD, Apollo.BARK_XD, 3)
	y += 22.0
	TinyFont.draw_centered(self, cx, y, "DIG DOWN. OUTRUN THE WATER.",
		Apollo.SLATE_XL, Color(Apollo.VOID, 0.0), 1)
	y += 13.0
	TinyFont.draw_centered(self, cx, y, "ARROWS DIG   [Z] BLAST   ESC QUIT",
		Apollo.SLATE_L, Color(Apollo.VOID, 0.0), 1)

	y += 14.0
	_volume_row(cx, y, "SFX", vol_sfx, vol_sel == 0)
	y += 9.0
	_volume_row(cx, y, "MUSIC", vol_music, vol_sel == 1)

	y += 15.0
	var blink: float = 0.55 + 0.45 * sin(_t * 4.0)
	TinyFont.draw_centered(self, cx, y, "PRESS ENTER / START",
		Color(Apollo.WHITE, blink), Apollo.VOID, 1)

	# Inside the panel, not below it. Outside, it sits over open terrain and
	# the gem tiles behind it read as a halo around the text.
	if best > 0:
		y += 14.0
		TinyFont.draw_centered(self, cx, y, "BEST DEPTH " + str(best),
			Apollo.SLATE_L, Color(Apollo.VOID, 0.0), 1)


## Two lines now that SFX and music are separate buses. The selected one gets
## the arrows and a lit label, so it is obvious which one left/right moves.
## Labels are padded to the same width to keep both pip bars on one column.
func _volume_row(cx: float, y: float, label: String, v: float, on: bool) -> void:
	var pips := 10
	var total := TinyFont.width("MUSIC", 1) + 6.0 + pips * 5.0 + 14.0
	var x := roundf(cx - total * 0.5)

	var arrow: Color = Apollo.GOLD if on else Color(Apollo.SLATE, 0.0)
	TinyFont.draw_text(self, Vector2(x, y), "<", arrow, 1)
	x += 6.0
	TinyFont.draw_text(self, Vector2(x, y), label,
		Apollo.WHITE if on else Apollo.SLATE_L, 1)
	x += TinyFont.width("MUSIC", 1) + 5.0

	var filled := int(round(v * pips))
	for i in pips:
		var lit: Color = Apollo.GEM if on else Apollo.SLATE_L
		draw_rect(Rect2(x + i * 5, y, 3, 5),
			lit if i < filled else Color(Apollo.SLATE, 0.8))
	x += pips * 5.0 + 3.0
	TinyFont.draw_text(self, Vector2(x, y), ">", arrow, 1)


## Pause. Deliberately plain: it is a stop, not a screen to look at.
func _draw_pause(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(Apollo.VOID, 0.72))
	var o := _panel(w, h, 150.0, 86.0)
	var cx := w * 0.5
	var y := o.y + 12.0

	TinyFont.draw_centered(self, cx, y, "PAUSED", Apollo.GOLD, Apollo.BARK_XD, 3)
	y += 24.0

	const ITEMS := ["RESUME", "RESTART", "QUIT"]
	for i in ITEMS.size():
		var on: bool = i == pause_sel
		if on:
			TinyFont.draw_centered(self, cx, y, "> " + ITEMS[i] + " <",
				Apollo.WHITE, Apollo.BARK_XD, 1)
		else:
			TinyFont.draw_centered(self, cx, y, ITEMS[i],
				Apollo.SLATE_L, Color(Apollo.VOID, 0.0), 1)
		y += 11.0

	y += 4.0
	TinyFont.draw_centered(self, cx, y, "ESC / START RESUMES",
		Apollo.SLATE, Color(Apollo.VOID, 0.0), 1)


func _draw_dead(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(Apollo.BLOOD_XD, 0.45))
	var o := _panel(w, h, 168.0, 96.0)
	var cx := w * 0.5
	var y := o.y + 11.0

	TinyFont.draw_centered(self, cx, y, "DROWNED", Apollo.FLOOD_HI, Apollo.BLOOD_XD, 3)
	y += 26.0

	_stat(o.x + 14.0, y, "DEPTH", str(depth), Apollo.WHITE)
	_stat(o.x + 92.0, y, "GEMS", str(gems), Apollo.GEM_HI)
	y += 18.0

	if new_best:
		var flash: float = 0.5 + 0.5 * sin(_t * 8.0)
		TinyFont.draw_centered(self, cx, y, "NEW BEST!",
			Color(Apollo.GOLD, flash), Apollo.BARK_XD, 2)
	else:
		TinyFont.draw_centered(self, cx, y + 2, "BEST " + str(best),
			Apollo.SLATE_XL, Apollo.VOID, 1)
	y += 18.0

	var blink: float = 0.55 + 0.45 * sin(_t * 4.0)
	TinyFont.draw_centered(self, cx, y, "ENTER / START TO DIG AGAIN",
		Color(Apollo.WHITE, blink), Apollo.VOID, 1)


func _stat(x: float, y: float, label: String, value: String, col: Color) -> void:
	TinyFont.draw_text(self, Vector2(x, y), label, Apollo.SLATE_L, 1)
	TinyFont.draw_text(self, Vector2(x, y + 8), value, col, 2)
