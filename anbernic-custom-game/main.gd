extends Node2D

# ---------------------------------------------------------------
# Dwarven Depths
# Palette: Apollo 46 by AdamCYounis
# ---------------------------------------------------------------

const TILE := 16
const COLS := 20
const VIEW_ROWS := 15

const EMPTY := 0
const DIRT := 1
const STONE := 2
const GEM := 3

# --- Apollo palette ---------------------------------------------
const C_BG        := Color("090a14")   # darkest grey - open tunnel
const C_PLAYER    := Color("ebede9")   # lightest grey
const C_TEXT      := Color("a8b5b2")   # muted, so it won't blend with the player
const C_GEM       := Color("73bed3")
const C_GEM_HI    := Color("a4dddb")
const C_FLOOD     := Color("a53030")
const C_FLOOD_HI  := Color("cf573c")

# --- Tuning ------------------------------------------------------
const MOVE_DELAY := 0.11
const FLOOD_LEAD := 6.0
const BOMB_COST := 3
const VOL_STEP := 0.1
const SETTINGS_PATH := "user://settings.cfg"

const STRATA := [
	{"at": 0,   "stone": 0.10, "gem": 0.07,
		"dirt": Color("ad7757"), "dirt_hi": Color("c09473"), "dirt_lo": Color("7a4841"),
		"rock": Color("577277"), "rock_hi": Color("819796"), "rock_lo": Color("394a50")},
	{"at": 60,  "stone": 0.18, "gem": 0.06,
		"dirt": Color("7a4841"), "dirt_hi": Color("ad7757"), "dirt_lo": Color("4d2b32"),
		"rock": Color("394a50"), "rock_hi": Color("577277"), "rock_lo": Color("202e37")},
	{"at": 130, "stone": 0.26, "gem": 0.05,
		"dirt": Color("402751"), "dirt_hi": Color("7a367b"), "dirt_lo": Color("1e1d39"),
		"rock": Color("202e37"), "rock_hi": Color("394a50"), "rock_lo": Color("151d28")},
	{"at": 210, "stone": 0.34, "gem": 0.04,
		"dirt": Color("602c2c"), "dirt_hi": Color("884b2b"), "dirt_lo": Color("341c27"),
		"rock": Color("341c27"), "rock_hi": Color("602c2c"), "rock_lo": Color("241527")},
]

enum State { TITLE, PLAY, DEAD }

var state := State.TITLE
var world := {}                    # Vector2i -> int
var player := Vector2i(10, 2)
var generated_to := -1
var score := 0
var deepest := 0
var best := 0
var flood_row := -8.0
var move_cd := 0.0
var last_dir := Vector2i(0, 1)
var shake := 0.0
var volume := 0.7

@onready var cam: Camera2D = $Camera2D
@onready var label: Label = $UI/Score
@onready var title: Label = $UI/Title
@onready var best_label: Label = $UI/Best

@onready var sfx_dig: AudioStreamPlayer = $SfxDig
@onready var sfx_gem: AudioStreamPlayer = $SfxGem
@onready var sfx_blast: AudioStreamPlayer = $SfxBlast
@onready var sfx_death: AudioStreamPlayer = $SfxDeath


func _ready() -> void:
	load_settings()
	apply_volume()
	for l in [label, title, best_label]:
		l.add_theme_color_override("font_color", C_TEXT)
		l.add_theme_color_override("font_outline_color", C_BG)
		l.add_theme_constant_override("outline_size", 4)
	generate_to(VIEW_ROWS + 10)


# --- Settings ----------------------------------------------------

func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	# linear_to_db(0) is -inf, which misbehaves; mute instead.
	AudioServer.set_bus_mute(bus, volume <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(max(volume, 0.001)))


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


# --- World -------------------------------------------------------

func stratum(row: int) -> Dictionary:
	var s: Dictionary = STRATA[0]
	for e in STRATA:
		if row >= e["at"]:
			s = e
	return s


func generate_to(row: int) -> void:
	while generated_to < row:
		generated_to += 1
		var st := stratum(generated_to)
		for x in COLS:
			var t := DIRT
			if x == 0 or x == COLS - 1:
				t = STONE
			elif generated_to < 3:
				t = EMPTY
			elif randf() < st["stone"]:
				t = STONE
			elif randf() < st["gem"]:
				t = GEM
			world[Vector2i(x, generated_to)] = t


func _draw() -> void:
	for y in range(max(0, player.y - VIEW_ROWS), player.y + VIEW_ROWS):
		var st := stratum(y)
		for x in COLS:
			var t: int = world.get(Vector2i(x, y), DIRT)
			var px := x * TILE
			var py := y * TILE

			if t == EMPTY:
				draw_rect(Rect2(px, py, TILE, TILE), C_BG)
				continue

			# Gems sit embedded in the surrounding dirt.
			var base: Color = st["dirt"]
			var hi: Color = st["dirt_hi"]
			var lo: Color = st["dirt_lo"]
			if t == STONE:
				base = st["rock"]
				hi = st["rock_hi"]
				lo = st["rock_lo"]

			draw_rect(Rect2(px, py, TILE, TILE), base)

			# Bevel only faces open space, so tunnels get outlined
			# instead of the whole field turning into stripes.
			if world.get(Vector2i(x, y - 1), DIRT) == EMPTY:
				draw_rect(Rect2(px, py, TILE, 2), hi)
			if world.get(Vector2i(x, y + 1), DIRT) == EMPTY:
				draw_rect(Rect2(px, py + TILE - 2, TILE, 2), lo)

			if t == DIRT and (x * 7 + y * 13) % 5 == 0:
				draw_rect(Rect2(px + 5, py + 6, 3, 3), lo)

			if t == GEM:
				draw_rect(Rect2(px + 4, py + 4, TILE - 8, TILE - 8), C_GEM)
				draw_rect(Rect2(px + 5, py + 5, 3, 3), C_GEM_HI)

	# Player
	draw_rect(Rect2(player.x * TILE + 3, player.y * TILE + 3, TILE - 6, TILE - 6), C_PLAYER)

	# Flood, with a bright crest so the edge reads clearly
	draw_rect(Rect2(0, -8000, COLS * TILE, flood_row * TILE + 8000), C_FLOOD)
	draw_rect(Rect2(0, flood_row * TILE - 2, COLS * TILE, 2), C_FLOOD_HI)


# --- Actions -----------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit_game"):
		get_tree().quit()
	if event.is_action_pressed("dig"):
		blast()


func try_move(dir: Vector2i) -> void:
	var target := player + dir
	if target.x < 0 or target.x >= COLS or target.y < 0:
		return
	last_dir = dir
	generate_to(target.y + VIEW_ROWS)
	var t: int = world.get(target, DIRT)
	if t == STONE:
		return
	if t == DIRT:
		sfx_dig.pitch_scale = randf_range(0.9, 1.1)
		sfx_dig.play()
	if t == GEM:
		score += 1
		shake = 1.5
		sfx_gem.play()
	world[target] = EMPTY
	player = target
	deepest = max(deepest, player.y)
	queue_redraw()


func blast() -> void:
	if state != State.PLAY or score < BOMB_COST:
		return
	score -= BOMB_COST
	var center := player + last_dir * 2
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := center + Vector2i(dx, dy)
			if p.x <= 0 or p.x >= COLS - 1 or p.y < 0:
				continue
			generate_to(p.y + VIEW_ROWS)
			if world.get(p, DIRT) == GEM:
				score += 1
			world[p] = EMPTY
	shake = 5.0
	sfx_blast.play()
	queue_redraw()


func die() -> void:
	state = State.DEAD
	shake = 0.0
	sfx_death.play()
	if deepest > best:
		best = deepest
		save_settings()


# --- Main loop ---------------------------------------------------

func _process(delta: float) -> void:
	match state:
		State.TITLE:
			title.visible = true
			var filled := int(round(volume * 10.0))
			var bar := "#".repeat(filled) + ".".repeat(10 - filled)
			title.text = "DWARVEN DEPTHS\n\nARROWS dig · Z blast (3)\nESC quit\n\nVOL %s  < >\n\nPress Enter / START" % bar
			label.text = ""
			best_label.text = ""
			cam.position = Vector2(COLS * TILE * 0.5, VIEW_ROWS * TILE * 0.4)
			cam.offset = Vector2.ZERO

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

			if Input.is_action_just_pressed("start_game"):
				restart()
			return

		State.DEAD:
			title.visible = true
			# die() updates best before this runs, so a record run compares equal.
			var tag := "NEW BEST!" if deepest >= best else "BEST %d" % best
			title.text = "DEPTH %d\nGEMS %d\n%s\n\nPress Enter / START" % [deepest, score, tag]
			label.text = ""
			best_label.text = ""
			cam.offset = Vector2.ZERO
			if Input.is_action_just_pressed("start_game"):
				restart()
			return

	title.visible = false
	best_label.text = "BEST %d" % best

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

	flood_row += (0.6 + deepest * 0.01) * delta
	flood_row = max(flood_row, float(deepest) - FLOOD_LEAD)

	if float(player.y) <= flood_row:
		die()
		return

	queue_redraw()

	cam.position = Vector2(COLS * TILE * 0.5, player.y * TILE + TILE * 0.5)
	if shake > 0.0:
		shake = max(0.0, shake - delta * 14.0)
		cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		cam.offset = Vector2.ZERO

	label.text = "Depth %d   Gems %d   [Z] %d" % [deepest, score, BOMB_COST]


func restart() -> void:
	world.clear()
	generated_to = -1
	player = Vector2i(10, 2)
	score = 0
	deepest = 0
	flood_row = -8.0
	move_cd = 0.0
	last_dir = Vector2i(0, 1)
	shake = 0.0
	state = State.PLAY
	generate_to(VIEW_ROWS + 10)
	queue_redraw()
