extends SceneTree

## Strata harness: the curves, generation validity, and one shot per tier.
##
##   godot --path . --script res://tools/stratashot.gd
##
## Checks the three things the table can get wrong: that every tier is
## reachable and named, that generation past the last tier clamps instead of
## running off the end, and that the deep tiers are still passable rather than
## a solid wall of stone.

const OUT := "res://shots"

var main: Node2D
var _reported := false
var _pending := ""
var _wait := 0
var _step := 0
var _script: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)

	# One shot per tier would be seventeen images; these are the ones where the
	# look changes most, plus the clamp case well past the table.
	_script = []
	for d in [0, 310, 980, 1580, 2460, 3740, 5000, 9000]:
		_script.append([d, "s-%05d" % d])


# --- Numbers ------------------------------------------------------

func _report() -> void:
	print("--- strata curves ---")
	print("   depth  tier          stone    gem   cave   open%  solid-run")
	for e in Apollo.STRATA:
		var d: int = e["at"]
		var m := _measure(d)
		print("  %6d  %-12s  %.3f  %.3f  %.3f  %5.1f  %d"
			% [d, e["name"], e["stone"], e["gem"], e["cave"],
			m["open_pct"], m["longest_solid_row_run"]])

	# Past the end of the table.
	var clamp_tier: Dictionary = Apollo.stratum(99999)
	print("  depth 99999 clamps to %s (last tier is %s)"
		% [clamp_tier["name"], Apollo.STRATA[-1]["name"]])

	var t0 := Time.get_ticks_msec()
	var m2 := Mine.new()
	m2.generate_to(5200)
	print("  generated 5200 rows in %d ms, %d tiles"
		% [Time.get_ticks_msec() - t0, m2.tiles.size()])


## Sample a band of rows and report how open it is, and the worst case: the
## longest run of rows with no diggable dirt anywhere across the shaft.
func _measure(depth: int) -> Dictionary:
	var m := Mine.new()
	m.generate_to(depth + 120)

	var open := 0
	var total := 0
	var run := 0
	var worst := 0
	for y in range(depth + 10, depth + 110):
		var diggable := 0
		for x in Mine.COLS:
			var t: int = m.at(Vector2i(x, y))
			total += 1
			if t == Mine.EMPTY:
				open += 1
			if t == Mine.DIRT or t == Mine.GEM or t == Mine.EMPTY:
				diggable += 1
		if diggable == 0:
			run += 1
			worst = maxi(worst, run)
		else:
			run = 0

	return {
		"open_pct": 100.0 * float(open) / float(total),
		"longest_solid_row_run": worst,
	}


# --- Shots --------------------------------------------------------

func _place(depth: int) -> void:
	main.mine.reset()
	main.flood.reset()
	main.state = main.State.PLAY
	main.hud.mode = main.hud.Mode.PLAY
	main.deepest = depth
	main.band = Apollo.stratum(depth)["name"]
	main.mine.generate_to(depth + main.VIEW_ROWS + Flood.WINDOW_DOWN)
	main.player = Vector2i(10, depth)
	main.mine.carve(main.player)
	main.falling = false
	main.stun = 0.0
	main.push_hud()
	main.queue_redraw()


func _process(_delta: float) -> bool:
	if not _reported:
		_reported = true
		_report()
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
	if DisplayServer.window_get_size() != Vector2i(320, 240):
		DisplayServer.window_set_size(Vector2i(320, 240))
	_place(entry[0])
	_pending = entry[1]
	_wait = 5
	return false


func _save(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT, name])
	print("%s  %dx%d  %s" % [name, img.get_width(), img.get_height(),
		"ok" if err == OK else "FAILED %d" % err])
