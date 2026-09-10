extends SceneTree

## Phase 1 harness: fall physics, and shots of the two new screens.
##
##   godot --path . --script res://tools/falltest.gd
##
## The acceptance criteria for falling are about feel on a d-pad, which no
## harness can judge. What this checks is the part that is objective: that a
## drop resolves over many frames instead of one, that it accelerates to a
## cap, that air control moves the dwarf a column at a time, and that landing
## stun scales with distance and stays under STUN_MAX.

const OUT := "res://shots"
const DT := 1.0 / 60.0

var main: Node2D
var _pending := ""
var _wait := 0
var _step := 0
var _script: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)

	# The scene is only fully wired after the first frame --  vars
	# (hud, the audio players) are still null during _initialize.
	_script = [
		[Vector2i(640, 480), _title, "p1-title-640x480"],
		[Vector2i(640, 480), _paused, "p1-pause-640x480"],
		[Vector2i(320, 240), _paused, "p1-pause-320x240"],
	]


# --- Fall physics -------------------------------------------------

## Cut a clean shaft and drop the dwarf down it, stepping the real _step_fall
## at a fixed rate and recording what happens.
func _drop(shaft_rows: int, drift: int = 0) -> Dictionary:
	main.restart()

	var top := 40
	var col := 10
	main.mine.generate_to(top + shaft_rows + 40)
	for i in range(shaft_rows + 2):
		main.mine.carve(Vector2i(col, top + i))
		for dx in range(1, drift + 1):
			main.mine.carve(Vector2i(col + dx, top + i))
	# Floor to land on.
	main.mine.tiles[Vector2i(col, top + shaft_rows + 1)] = Mine.STONE
	for dx in range(1, drift + 1):
		main.mine.tiles[Vector2i(col + dx, top + shaft_rows + 1)] = Mine.STONE

	main.player = Vector2i(col, top)
	main.falling = false
	main.stun = 0.0

	var frames := 0
	var rows_per_frame: Array[int] = []
	var last: int = main.player.y
	var peak_v := 0.0

	while frames < 2000:
		main._step_fall(DT)
		frames += 1
		peak_v = maxf(peak_v, main.fall_v)
		rows_per_frame.append(main.player.y - last)
		last = main.player.y
		if not main.falling:
			break

	return {
		"frames": frames,
		"seconds": frames * DT,
		"rows": main.player.y - top,
		"max_rows_in_one_frame": rows_per_frame.max(),
		"peak_speed": peak_v,
		"stun": main.stun,
	}


func _report_fall() -> void:
	print("--- fall physics ---")
	for rows in [3, 6, 13, 30]:
		var r := _drop(rows)
		print("  drop %2d rows: %4.2f s over %3d frames, max %d row/frame, peak %.1f rows/s, stun %.3f s"
			% [rows, r["seconds"], r["frames"], r["max_rows_in_one_frame"],
			r["peak_speed"], r["stun"]])

	# Air control: hold right for the whole fall and see how far it drifts.
	Input.action_press("move_right")
	var d := _drop(13, 6)
	Input.action_release("move_right")
	print("  13-row drop holding right: drifted %d column(s), of 6 available" % (main.player.x - 10))
	print("  (stun cap is %.2f s)" % main.STUN_MAX)


# --- Shots --------------------------------------------------------

func _title() -> void:
	# The fall tests left the dwarf deep and the flood window with him; without
	# resetting, the drowned mass above sim_top paints over the title screen.
	main.mine.reset()
	main.flood.reset()
	main.player = Vector2i(10, 2)
	main.mine.generate_to(main.VIEW_ROWS + Flood.WINDOW_DOWN)
	main.state = main.State.TITLE
	main.hud.mode = main.hud.Mode.TITLE
	main.push_hud()
	main.queue_redraw()
	main.hud.queue_redraw()


func _paused() -> void:
	main.restart()
	main.player = Vector2i(10, 30)
	main.mine.generate_to(60)
	main._pause()
	main.pause_sel = 1
	main.hud.pause_sel = 1
	main.push_hud()
	main.hud.queue_redraw()


var _reported := false


func _process(_delta: float) -> bool:
	if not _reported:
		_reported = true
		_report_fall()
		return false

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
	(entry[1] as Callable).call()

	_pending = entry[2]
	_wait = 4
	return false


func _save(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT, name])
	print("%s  %dx%d  %s" % [name, img.get_width(), img.get_height(),
		"ok" if err == OK else "FAILED %d" % err])
