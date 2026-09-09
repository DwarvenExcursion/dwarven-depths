extends Node2D

# ---------------------------------------------------------------
# Dwarven Depths
# Endless vertical mining roguelite. Dig down, grab gems, outrun the water.
#
# This file owns state, input, camera and rendering order. The interesting
# parts live in scripts/: Mine (world), Flood (water), Dwarf (player art),
# TinyFont + hud.gd (UI), Apollo (palette).
# ---------------------------------------------------------------

const TILE := 16
const VIEW_ROWS := 15          # constant vertical field of view, every screen

const MOVE_DELAY := 0.11
const BOMB_COST := 3
const VOL_STEP := 0.1
const SETTINGS_PATH := "user://settings.cfg"

const SWING_TIME := 0.09       # how long the dig animation frame holds
const DANGER_ROWS := 9.0       # distance at which the HUD starts warning

enum State { TITLE, PLAY, DEAD }

var state := State.TITLE
var mine := Mine.new()
var flood := Flood.new()

var player := Vector2i(10, 2)
var gems := 0
var deepest := 0
var best := 0
var volume := 0.7

var move_cd := 0.0
var last_dir := Vector2i(0, 1)
var facing := 1
var swing := 0.0
var shake := 0.0
var band := ""

var bits: Array[Dictionary] = []   # dig debris

@onready var cam: Camera2D = $Camera2D
@onready var hud: Control = $UI/Hud

@onready var sfx_dig: AudioStreamPlayer = $SfxDig
@onready var sfx_gem: AudioStreamPlayer = $SfxGem
@onready var sfx_blast: AudioStreamPlayer = $SfxBlast
@onready var sfx_death: AudioStreamPlayer = $SfxDeath


func _ready() -> void:
	load_settings()
	apply_volume()
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()
	mine.generate_to(VIEW_ROWS + Flood.WINDOW_DOWN)
	band = Apollo.stratum(0)["name"]
	push_hud()


# --- Resolution ---------------------------------------------------
#
# The shaft is a fixed COLS wide, so we cannot simply show more world on a
# wider screen without exposing the void beside it. Instead the camera locks
# a constant VIEW_ROWS of vertical field of view, capped so the shaft always
# fits horizontally. Every player on every panel sees exactly the same amount
# of mine; wider screens get bedrock at the sides rather than black bars, and
# the HUD anchors to the real corners.

func fit_camera() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var z: float = minf(vp.y / float(VIEW_ROWS * TILE),
		vp.x / float(Mine.COLS * TILE))
	cam.zoom = Vector2(z, z)
	queue_redraw()


func view_rect() -> Rect2:
	var half := get_viewport_rect().size / cam.zoom * 0.5
	return Rect2(cam.get_screen_center_position() - half, half * 2.0)


# --- Settings -----------------------------------------------------

func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	# linear_to_db(0) is -inf, which misbehaves; mute instead.
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.001)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("run", "best", best)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("settings save failed: %d" % err)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume = clampf(cfg.get_value("audio", "volume", 0.7), 0.0, 1.0)
		best = cfg.get_value("run", "best", 0)


# --- Drawing ------------------------------------------------------

func _draw() -> void:
	var vr := view_rect()
	var y0: int = maxi(0, int(floor(vr.position.y / TILE)) - 1)
	var y1: int = int(ceil(vr.end.y / TILE)) + 1

	_draw_bedrock(vr, y0, y1)

	for y in range(y0, y1):
		var st := Apollo.stratum(y)
		for x in Mine.COLS:
			var p := Vector2i(x, y)
			var t: int = mine.at(p)
			var px := x * TILE
			var py := y * TILE

			if t == Mine.EMPTY:
				draw_rect(Rect2(px, py, TILE, TILE), Apollo.VOID)
				_draw_water(p, px, py)
				continue

			var base: Color = st["dirt"]
			var hi: Color = st["dirt_hi"]
			var lo: Color = st["dirt_lo"]
			if t == Mine.STONE:
				base = st["rock"]
				hi = st["rock_hi"]
				lo = st["rock_lo"]

			draw_rect(Rect2(px, py, TILE, TILE), base)

			# Bevel only faces open space, so tunnels get outlined instead of
			# the whole field turning into horizontal stripes.
			if mine.is_open(Vector2i(x, y - 1)):
				draw_rect(Rect2(px, py, TILE, 2), hi)
			if mine.is_open(Vector2i(x, y + 1)):
				draw_rect(Rect2(px, py + TILE - 2, TILE, 2), lo)
			if mine.is_open(Vector2i(x - 1, y)):
				draw_rect(Rect2(px, py, 1, TILE), hi)
			if mine.is_open(Vector2i(x + 1, y)):
				draw_rect(Rect2(px + TILE - 1, py, 1, TILE), lo)

			if t == Mine.DIRT and (x * 7 + y * 13) % 5 == 0:
				draw_rect(Rect2(px + 5, py + 6, 3, 3), lo)

			if t == Mine.GEM:
				draw_rect(Rect2(px + 4, py + 4, TILE - 8, TILE - 8), Apollo.GEM)
				draw_rect(Rect2(px + 5, py + 5, 3, 3), Apollo.GEM_HI)

	for b in bits:
		draw_rect(Rect2(b["p"].x, b["p"].y, 2, 2), b["c"])

	var sub: float = clampf(flood.at(player) / Flood.DROWN, 0.0, 1.0)
	Dwarf.draw_at(self, Vector2(player.x * TILE, player.y * TILE),
		facing, swing > 0.0, sub)


## Fills the space outside the shaft on wide screens. Same rock as the current
## stratum, darkened, with a few striations so it reads as more mountain
## rather than as a rendering mistake.
func _draw_bedrock(vr: Rect2, y0: int, y1: int) -> void:
	var deep: Color = Apollo.stratum(int(cam.position.y / TILE))["deep"]
	var shaft_w := float(Mine.COLS * TILE)
	if vr.position.x < 0.0:
		draw_rect(Rect2(vr.position.x, vr.position.y, -vr.position.x, vr.size.y), deep)
	if vr.end.x > shaft_w:
		draw_rect(Rect2(shaft_w, vr.position.y, vr.end.x - shaft_w, vr.size.y), deep)

	var seam := deep.lightened(0.06)
	for y in range(y0, y1, 3):
		if vr.position.x < 0.0:
			draw_rect(Rect2(vr.position.x, y * TILE, -vr.position.x, 1), seam)
		if vr.end.x > shaft_w:
			draw_rect(Rect2(shaft_w, y * TILE, vr.end.x - shaft_w, 1), seam)


## Water reads as two different things depending on whether it is going
## somewhere. If the tile below is open and also wet, this tile is a length of
## falling stream: fill it edge to edge and let opacity carry the volume.
## Bottom-anchoring it instead would draw a separate little puddle in every
## tile of the shaft, which stacks into rungs rather than a stream. If the
## water has nowhere left to fall it is a surface, so it gets a real level and
## a bright crest with a one-pixel ripple.
func _draw_water(p: Vector2i, px: int, py: int) -> void:
	var w: float = flood.at(p)
	if w < Flood.WET:
		return

	var below := p + Vector2i(0, 1)
	var flowing: bool = mine.is_open(below) and flood.at(below) < 1.0

	if flowing and w < Flood.DROWN:
		draw_rect(Rect2(px, py, TILE, TILE),
			Color(Apollo.FLOOD, 0.30 + w * 0.75))
		return

	var body: Color = Apollo.FLOOD if w >= Flood.DROWN else Color(Apollo.FLOOD, 0.62)
	var hgt: float = ceil(w * TILE)
	draw_rect(Rect2(px, py + TILE - hgt, TILE, hgt), body)

	if flood.at(p + Vector2i(0, -1)) < w - 0.08:
		var ripple := 1.0 if sin(flood.time() * 3.4 + p.x * 1.7) > 0.0 else 0.0
		draw_rect(Rect2(px, py + TILE - hgt - ripple, TILE, 1), Apollo.FLOOD_HI)


# --- Actions ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	if event.is_action_pressed("dig"):
		blast()


func spawn_bits(p: Vector2i, col: Color, n: int) -> void:
	for i in n:
		bits.append({
			"p": Vector2(p.x * TILE + randf_range(3, TILE - 3),
				p.y * TILE + randf_range(3, TILE - 3)),
			"v": Vector2(randf_range(-34, 34), randf_range(-58, -14)),
			"t": randf_range(0.22, 0.5),
			"c": col,
		})


func try_move(dir: Vector2i) -> void:
	var target := player + dir
	if not mine.in_bounds_x(target.x) or target.y < 0:
		return
	last_dir = dir
	if dir.x != 0:
		facing = dir.x
	mine.generate_to(target.y + VIEW_ROWS + Flood.WINDOW_DOWN)

	var t: int = mine.at(target)
	if t == Mine.STONE:
		return

	var st := Apollo.stratum(target.y)
	if t == Mine.DIRT:
		swing = SWING_TIME
		spawn_bits(target, st["dirt_lo"], 4)
		sfx_dig.pitch_scale = randf_range(0.9, 1.1)
		sfx_dig.play()
	if t == Mine.GEM:
		gems += 1
		shake = 1.5
		swing = SWING_TIME
		spawn_bits(target, Apollo.GEM_HI, 7)
		sfx_gem.play()

	mine.carve(target)
	player = target
	if player.y > deepest:
		deepest = player.y
		var band_name: String = Apollo.stratum(deepest)["name"]
		if band_name != band:
			band = band_name
			hud.announce(band_name)
	queue_redraw()


func blast() -> void:
	if state != State.PLAY or gems < BOMB_COST:
		return
	gems -= BOMB_COST
	var center := player + last_dir * 2
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := center + Vector2i(dx, dy)
			if p.x <= 0 or p.x >= Mine.COLS - 1 or p.y < 0:
				continue
			mine.generate_to(p.y + VIEW_ROWS + Flood.WINDOW_DOWN)
			var t: int = mine.at(p)
			if t == Mine.GEM:
				gems += 1
			if t != Mine.EMPTY:
				spawn_bits(p, Apollo.stratum(p.y)["dirt_lo"], 3)
			mine.carve(p)
	spawn_bits(center, Apollo.EMBER, 10)
	shake = 5.0
	sfx_blast.play()
	queue_redraw()


func die() -> void:
	state = State.DEAD
	shake = 0.0
	cam.offset = Vector2.ZERO
	bits.clear()
	sfx_death.play()
	hud.new_best = deepest > best
	if deepest > best:
		best = deepest
		save_settings()
	hud.mode = hud.Mode.DEAD
	hud.danger = 0.0
	push_hud()


# --- Main loop ----------------------------------------------------

func _process(delta: float) -> void:
	match state:
		State.TITLE:
			_title_step()
			return
		State.DEAD:
			queue_redraw()
			if Input.is_action_just_pressed("start_game"):
				restart()
			return

	move_cd -= delta
	if move_cd <= 0.0:
		var dir := Vector2i.ZERO
		if Input.is_action_pressed("move_left"):    dir = Vector2i(-1, 0)
		elif Input.is_action_pressed("move_right"): dir = Vector2i(1, 0)
		elif Input.is_action_pressed("move_up"):    dir = Vector2i(0, -1)
		elif Input.is_action_pressed("move_down"):  dir = Vector2i(0, 1)
		if dir != Vector2i.ZERO:
			try_move(dir)
			move_cd = MOVE_DELAY

	swing = maxf(0.0, swing - delta)
	flood.step(mine, player.y, delta)
	_step_bits(delta)

	if flood.is_lethal(player):
		die()
		return

	cam.position = Vector2(Mine.COLS * TILE * 0.5, player.y * TILE + TILE * 0.5)
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 14.0)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO

	push_hud()
	queue_redraw()


func _title_step() -> void:
	# 0.5 puts the top of the view exactly on row 0, so no part of the title
	# screen looks at empty space above the world.
	cam.position = Vector2(Mine.COLS * TILE * 0.5, VIEW_ROWS * TILE * 0.5)
	cam.offset = Vector2.ZERO
	# _draw() reads the camera, so it has to be reissued after the camera
	# moves. Without this the title screen keeps whatever the very first
	# frame drew, and the world below the fold is simply never painted.
	queue_redraw()

	var changed := false
	if Input.is_action_just_pressed("move_left"):
		volume = maxf(0.0, volume - VOL_STEP)
		changed = true
	elif Input.is_action_just_pressed("move_right"):
		volume = minf(1.0, volume + VOL_STEP)
		changed = true
	if changed:
		apply_volume()
		save_settings()
		sfx_gem.play()   # doubles as a preview of the new level
		push_hud()

	if Input.is_action_just_pressed("start_game"):
		restart()


func _step_bits(delta: float) -> void:
	for i in range(bits.size() - 1, -1, -1):
		var b: Dictionary = bits[i]
		b["t"] -= delta
		if b["t"] <= 0.0:
			bits.remove_at(i)
			continue
		var v: Vector2 = b["v"]
		v.y += 340.0 * delta
		b["v"] = v
		b["p"] = (b["p"] as Vector2) + v * delta


func push_hud() -> void:
	hud.depth = deepest
	hud.best = best
	hud.gems = gems
	hud.bomb_cost = BOMB_COST
	hud.volume = volume
	hud.stratum_name = band
	if state == State.PLAY:
		# The lethal front only exists once water pools on you, which is too
		# late to be a warning. The wet front is where the stream actually is.
		var gap := float(player.y - flood.wet_front)
		hud.danger = clampf(1.0 - gap / DANGER_ROWS, 0.0, 1.0)


func restart() -> void:
	mine.reset()
	flood.reset()
	bits.clear()
	player = Vector2i(10, 2)
	gems = 0
	deepest = 0
	move_cd = 0.0
	last_dir = Vector2i(0, 1)
	facing = 1
	swing = 0.0
	shake = 0.0
	band = Apollo.stratum(0)["name"]
	state = State.PLAY
	hud.mode = hud.Mode.PLAY
	hud.danger = 0.0
	hud.banner_t = 0.0
	mine.generate_to(VIEW_ROWS + Flood.WINDOW_DOWN)
	push_hud()
	queue_redraw()
