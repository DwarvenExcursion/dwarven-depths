extends SceneTree

## Screenshot runner.
##
##   godot --path . --script res://tools/capture.gd
##
## Loads the real main scene, drives it by calling the game's own methods
## instead of synthesising keystrokes (which lose to whatever window steals
## focus), and writes PNGs to shots/. Each shot names the window size it was
## taken at, so the set doubles as the proof that the layout survives being
## resized -- handheld 4:3, desktop 16:9 and a nasty ultrawide.

const OUT := "res://shots"

var main: Node2D
var _frame := 0
var _script: Array = []
var _step := 0
var _wait := 0
var _pending := ""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)

	# [window size, action, shot name]  --  action is a Callable or null.
	_script = [
		[Vector2i(640, 480), null, "01-title-640x480"],
		[Vector2i(1280, 720), null, "02-title-1280x720"],
		[Vector2i(640, 480), _begin, ""],
		[Vector2i(640, 480), _dig.bind(26), "03-digging-640x480"],
		[Vector2i(1280, 720), _dig.bind(30), "04-deeper-1280x720"],
		[Vector2i(1720, 620), _dig.bind(20), "05-ultrawide-1720x620"],
		[Vector2i(640, 480), _blast, "06-after-blast"],
		[Vector2i(640, 480), _gallery, "07-side-gallery"],
		[Vector2i(640, 480), _idle, "08-water-arriving"],
		[Vector2i(640, 480), _idle, "09-water-closer"],
		[Vector2i(640, 480), _drown, "10-drowned"],
	]


## Deliberately a frame counter and not `await process_frame`: awaiting turns
## SceneTree._process into a coroutine, its bool return is discarded, and the
## runner silently does nothing at all.
func _process(_delta: float) -> bool:
	_frame += 1

	if _wait > 0:
		_wait -= 1
		return false

	if not _pending.is_empty():
		_save(_pending)
		_pending = ""
		_wait = 2
		return false

	if _step >= _script.size():
		print("captured to %s" % OUT)
		return true

	var entry: Array = _script[_step]
	_step += 1

	var size: Vector2i = entry[0]
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)

	var action: Variant = entry[1]
	if action != null:
		(action as Callable).call()

	_pending = entry[2]
	_wait = 4          # let the resize settle before reading the frame back
	return false


func _save(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	var err := img.save_png(path)
	print("%s  %dx%d  %s" % [name, img.get_width(), img.get_height(),
		"ok" if err == OK else "FAILED %d" % err])


# --- Scripted play ------------------------------------------------

func _begin() -> void:
	main.restart()


## Sidesteps stone the way a player would. A dwarf who only presses Down gets
## pinned at depth 11 by the first boulder and every shot looks the same.
func _dig(rows: int) -> void:
	for i in rows:
		var before: Vector2i = main.player
		main.try_move(Vector2i(0, 1))
		if main.player == before:
			main.try_move(Vector2i(1 if (i % 2) == 0 else -1, 0))
		_pump(0.12)


## Blast needs gems, and the scripted dwarf may not have found any, so give
## him exactly the cost rather than digging until luck provides.
func _blast() -> void:
	main.gems = main.BOMB_COST
	main.last_dir = Vector2i(0, 1)
	main.blast()
	_pump(0.3)


## Cut sideways for a while. This is the shot that has to show water spilling
## into a side tunnel instead of tracking straight down the shaft.
func _gallery() -> void:
	for i in 8:
		main.try_move(Vector2i(1, 0))
		_pump(0.12)
	for i in 3:
		main.try_move(Vector2i(0, 1))
		_pump(0.12)


func _idle() -> void:
	_pump(3.0)


func _drown() -> void:
	for i in 400:
		_pump(0.05)
		if main.state == main.State.DEAD:
			break


## Advance the simulation without waiting for real frames.
func _pump(seconds: float) -> void:
	var dt := 1.0 / 60.0
	var n := int(seconds / dt)
	for i in n:
		if main.state == main.State.PLAY:
			main.flood.step(main.mine, main.player.y, dt)
			if main.flood.is_lethal(main.player):
				main.die()
				return
