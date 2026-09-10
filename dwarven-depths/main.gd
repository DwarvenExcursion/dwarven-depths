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

## Drop a track at any of these and it plays. Several extensions because the
## point is that supplying music is one file copy, not a conversion step.
const MUSIC_PATHS := [
	"res://audio/music/theme.ogg",
	"res://audio/music/theme.mp3",
	"res://audio/music/theme.wav",
]

# --- Falling ------------------------------------------------------
#
# A fall resolves over several ticks instead of in one frame, so a long drop
# reads as a drop rather than a teleport. Everything here is rows and seconds.
#
# This is also what defines "a tick" for anything that moves: one row of fall
# at FALL_MAX is 1/15 s, and MOVE_DELAY is 0.11 s, so terminal velocity is
# roughly 1.6x a walking step. Fast enough to feel like gravity, slow enough
# to read on a 3.5" screen.
const GRAVITY      := 26.0     # rows per second squared
const FALL_START   := 4.0      # speed a fall begins at, rows per second
const FALL_MAX     := 15.0     # terminal speed
const AIR_DRIFT    := 0.40     # seconds between steerable sideways steps
const STUN_FREE    := 3        # rows you may drop before any stun at all
const STUN_PER_ROW := 0.022
const STUN_MAX     := 0.45

enum State { TITLE, PLAY, DEAD, PAUSE }

var state := State.TITLE
var mine := Mine.new()
var flood := Flood.new()

var player := Vector2i(10, 2)
var gems := 0
var deepest := 0
var best := 0

var vol_sfx := 0.7
var vol_music := 0.7
var vol_sel := 0               # which title-screen volume line is selected

var move_cd := 0.0
var last_dir := Vector2i(0, 1)
var facing := 1
var swing := 0.0
var shake := 0.0
var band := ""

var falling := false
var fall_v := 0.0
var fall_acc := 0.0            # whole rows owed, carried between frames
var fall_from := 0             # row the current fall started at
var drift_cd := 0.0
var stun := 0.0

var pause_sel := 0

var bits: Array[Dictionary] = []   # dig debris

@onready var cam: Camera2D = $Camera2D
@onready var hud: Control = $UI/Hud

@onready var sfx_dig: AudioStreamPlayer = $SfxDig
@onready var sfx_gem: AudioStreamPlayer = $SfxGem
@onready var sfx_blast: AudioStreamPlayer = $SfxBlast
@onready var sfx_death: AudioStreamPlayer = $SfxDeath
@onready var music: AudioStreamPlayer = $Music


func _ready() -> void:
	load_settings()
	apply_volume()
	_start_music()
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()
	mine.generate_to(VIEW_ROWS + Flood.WINDOW_DOWN)
	band = Apollo.stratum(0)["name"]
	push_hud()

	# Ask the hold whether a newer build exists. The request is non-blocking
	# and times out on its own, so a player with no connection never waits and
	# never sees anything -- the panel only appears if there is news.
	UpdateChecker.update_available.connect(UpdatePanel.show_update)
	UpdateChecker.check_for_update()


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
	_set_bus("SFX", vol_sfx)
	_set_bus("Music", vol_music)


func _set_bus(bus_name: String, v: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		# No bus layout. Better to leave the mixer alone than to silently
		# reach for Master and dim everything again.
		return
	# linear_to_db(0) is -inf, which misbehaves; mute instead.
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.001)))


func _bump_volume(d: float) -> void:
	if vol_sel == 0:
		vol_sfx = clampf(vol_sfx + d, 0.0, 1.0)
	else:
		vol_music = clampf(vol_music + d, 0.0, 1.0)


## Point the music player at the track, if there is one. There deliberately is
## not: nothing here generates or ships audio of unclear provenance. A missing
## file has to be silent and uneventful, not an error every frame.
func _start_music() -> void:
	for path in MUSIC_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var stream: Resource = load(path)
		if stream == null or not (stream is AudioStream):
			push_warning("music at %s is not an AudioStream" % path)
			continue
		# Only some stream types expose `loop`; setting it blind would throw.
		# WAV uses a loop *mode* enum rather than a bool.
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		elif "loop" in stream:
			stream.set("loop", true)
		music.stream = stream
		music.play()
		print_verbose("music: playing %s" % path)
		return

	# No track supplied. Silent and uneventful is the correct outcome -- this
	# is not an error, and it must not spam the console every launch.
	print_verbose("music: no track found, running silent")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx", vol_sfx)
	cfg.set_value("audio", "music", vol_music)
	cfg.set_value("run", "best", best)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("settings save failed: %d" % err)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	# Configs written before the bus split hold a single "volume" key. Use it
	# as the default for both, so an existing player keeps the level they set
	# rather than being reset to 0.7.
	var legacy: float = clampf(cfg.get_value("audio", "volume", 0.7), 0.0, 1.0)
	vol_sfx = clampf(cfg.get_value("audio", "sfx", legacy), 0.0, 1.0)
	vol_music = clampf(cfg.get_value("audio", "music", legacy), 0.0, 1.0)
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
	# quit_game is state-dependent now -- it pauses during a run and only quits
	# outright from the title or the death screen, so it is handled per state.
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
	_note_depth()
	queue_redraw()


## deepest, and the stratum banner that follows from it. try_move() used to own
## this outright; the fall path has to record depth too, or the flood leash
## reads a stale row all the way down a shaft.
func _note_depth() -> void:
	if player.y <= deepest:
		return
	deepest = player.y
	var band_name: String = Apollo.stratum(deepest)["name"]
	if band_name != band:
		band = band_name
		hud.announce(band_name)


## Move into a tile that is already open, without digging. Falling and air
## drift both go through here; try_move() is for deliberate digging.
func _slide_to(target: Vector2i) -> bool:
	if not mine.in_bounds_x(target.x) or target.y < 0:
		return false
	mine.generate_to(target.y + VIEW_ROWS + Flood.WINDOW_DOWN)
	if not mine.is_open(target):
		return false
	player = target
	_note_depth()
	return true


## Nothing solid under the dwarf.
func _unsupported() -> bool:
	var below := player + Vector2i(0, 1)
	mine.generate_to(below.y + VIEW_ROWS + Flood.WINDOW_DOWN)
	return mine.is_open(below)


func _step_fall(delta: float) -> void:
	if not falling:
		if _unsupported():
			falling = true
			fall_v = FALL_START
			fall_acc = 0.0
			fall_from = player.y
			# Charge the first drift too, or stepping off a ledge grants a free
			# sideways move and short hops become steerable in a way long falls
			# are not.
			drift_cd = AIR_DRIFT
		return

	fall_v = minf(fall_v + GRAVITY * delta, FALL_MAX)
	fall_acc += fall_v * delta

	# Air control. Steerable, but a column at a time -- enough to pick which
	# side of a pillar you land on, not enough to fly.
	drift_cd -= delta
	if drift_cd <= 0.0:
		var dx := 0
		if Input.is_action_pressed("move_left"):
			dx = -1
		elif Input.is_action_pressed("move_right"):
			dx = 1
		if dx != 0 and _slide_to(player + Vector2i(dx, 0)):
			facing = dx
			last_dir = Vector2i(dx, 0)
			drift_cd = AIR_DRIFT

	while fall_acc >= 1.0:
		fall_acc -= 1.0
		if not _slide_to(player + Vector2i(0, 1)):
			_land()
			return

	# Drifting sideways can put ground under you between steps.
	if not _unsupported():
		_land()


func _land() -> void:
	var dropped: int = player.y - fall_from
	falling = false
	fall_v = 0.0
	fall_acc = 0.0
	if dropped > STUN_FREE:
		stun = minf(float(dropped - STUN_FREE) * STUN_PER_ROW, STUN_MAX)
		shake = maxf(shake, minf(float(dropped) * 0.25, 4.0))


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
			elif Input.is_action_just_pressed("quit_game"):
				get_tree().quit()
			return
		State.PAUSE:
			_pause_step()
			return

	# Pausing has to come before anything is simulated, so the flood does not
	# advance on the frame the menu opens.
	if Input.is_action_just_pressed("quit_game") or Input.is_action_just_pressed("start_game"):
		_pause()
		return

	stun = maxf(0.0, stun - delta)
	_step_fall(delta)

	# Falling owns the dwarf: no digging in mid-air, and no input at all while
	# the landing stun runs.
	if not falling and stun <= 0.0:
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


## Pause is a state branch rather than get_tree().paused. The game is already a
## single _process loop driven by this enum, so a branch keeps the whole thing
## in one place -- and it means the flood, generation and timers stop because
## they are simply never reached, not because a process mode was set.
func _pause() -> void:
	state = State.PAUSE
	pause_sel = 0
	shake = 0.0
	cam.offset = Vector2.ZERO
	hud.mode = hud.Mode.PAUSE
	hud.pause_sel = pause_sel
	queue_redraw()


func _resume() -> void:
	state = State.PLAY
	hud.mode = hud.Mode.PLAY
	# Falls survive a pause: fall_v and fall_acc are untouched, so resuming
	# continues the drop from exactly where it stopped.
	queue_redraw()


func _pause_step() -> void:
	queue_redraw()

	if Input.is_action_just_pressed("move_up"):
		pause_sel = wrapi(pause_sel - 1, 0, 3)
		hud.pause_sel = pause_sel
	elif Input.is_action_just_pressed("move_down"):
		pause_sel = wrapi(pause_sel + 1, 0, 3)
		hud.pause_sel = pause_sel
	elif Input.is_action_just_pressed("quit_game"):
		_resume()
	elif Input.is_action_just_pressed("start_game") or Input.is_action_just_pressed("dig"):
		match pause_sel:
			0: _resume()
			1: restart()
			2: get_tree().quit()


func _title_step() -> void:
	# 0.5 puts the top of the view exactly on row 0, so no part of the title
	# screen looks at empty space above the world.
	cam.position = Vector2(Mine.COLS * TILE * 0.5, VIEW_ROWS * TILE * 0.5)
	cam.offset = Vector2.ZERO
	# _draw() reads the camera, so it has to be reissued after the camera
	# moves. Without this the title screen keeps whatever the very first
	# frame drew, and the world below the fold is simply never painted.
	queue_redraw()

	# Up/down picks a line, left/right moves it.
	if Input.is_action_just_pressed("move_up"):
		vol_sel = 0
		push_hud()
	elif Input.is_action_just_pressed("move_down"):
		vol_sel = 1
		push_hud()

	var changed := false
	if Input.is_action_just_pressed("move_left"):
		_bump_volume(-VOL_STEP)
		changed = true
	elif Input.is_action_just_pressed("move_right"):
		_bump_volume(VOL_STEP)
		changed = true
	if changed:
		apply_volume()
		save_settings()
		if vol_sel == 0:
			sfx_gem.play()   # doubles as a preview of the new level
		push_hud()

	if Input.is_action_just_pressed("start_game"):
		restart()
	elif Input.is_action_just_pressed("quit_game"):
		get_tree().quit()


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
	hud.vol_sfx = vol_sfx
	hud.vol_music = vol_music
	hud.vol_sel = vol_sel
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
	falling = false
	fall_v = 0.0
	fall_acc = 0.0
	fall_from = 0
	drift_cd = 0.0
	stun = 0.0
	band = Apollo.stratum(0)["name"]
	state = State.PLAY
	hud.mode = hud.Mode.PLAY
	hud.danger = 0.0
	hud.banner_t = 0.0
	mine.generate_to(VIEW_ROWS + Flood.WINDOW_DOWN)
	push_hud()
	queue_redraw()
