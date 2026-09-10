extends SceneTree

## Goblin harness: population, the standing invariant, and the mugging.
##
##   godot --path . --script res://tools/goblintest.gd
##
## The things worth checking are the ones that would be unfair if wrong: that a
## goblin never floats or occupies solid rock, that it can always be dug out in
## one hit, and that it can only take a gem from directly beside you.

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
	_script = [[1600, "g-01600"], [4600, "g-04600"]]


func _report() -> void:
	print("--- goblin population ---")
	print("   depth  band          alive  bad-tile  floating")
	for depth in [100, 400, 1000, 2000, 3500, 5000]:
		var m := Mine.new()
		var ent = main.entities.get_script().new()
		m.generate_to(depth + 400)
		# Start the spawner AT this band, or the cap fills with goblins from
		# every row above and the table measures nothing.
		ent._spawned_to = depth
		ent.spawn_ahead(m, depth + 400)

		var bad := 0
		var floating := 0
		for g in ent.list:
			var p: Vector2i = g["p"]
			if not m.is_open(p):
				bad += 1
			if m.is_open(p + Vector2i(0, 1)):
				floating += 1
		print("  %6d  %-12s  %4d  %8d  %8d"
			% [depth, Apollo.stratum(depth)["name"], ent.list.size(), bad, floating])

	# Movement: they should actually walk, and stay legal while doing it.
	var m2 := Mine.new()
	var e2 = main.entities.get_script().new()
	m2.generate_to(3400)
	e2._spawned_to = 3000
	e2.spawn_ahead(m2, 3400)
	var before: Array[Vector2i] = []
	for g in e2.list:
		before.append(g["p"])

	for i in 40:
		e2.step(m2, main.flood, Vector2i(-99, -99), 0, 0.1)

	var moved := 0
	var illegal := 0
	for i in e2.list.size():
		if i < before.size() and e2.list[i]["p"] != before[i]:
			moved += 1
		elif i >= before.size():
			pass
		var p: Vector2i = e2.list[i]["p"]
		if not m2.is_open(p) or m2.is_open(p + Vector2i(0, 1)):
			illegal += 1
	print("  after 4s: %d/%d moved, %d in an illegal tile"
		% [moved, e2.list.size(), illegal])

	# The mugging. A goblin facing the dwarf from an adjacent tile takes one
	# gem per tick and turns away; one two tiles off takes nothing.
	print("--- theft ---")
	print("  adjacent, facing player : %d gem(s) in one tick" % _steal_test(1))
	print("  two tiles away          : %d gem(s) in one tick" % _steal_test(2))

	# And it must always be diggable.
	var e4 = main.entities.get_script().new()
	e4.list.append({"kind": 0, "p": Vector2i(5, 5), "dir": 1, "bob": 0.0})
	var blocked_before: bool = e4.blocks(Vector2i(5, 5))
	var hit: bool = e4.clear_at(Vector2i(5, 5))
	print("  blocks tile=%s, one dig clears=%s, remaining=%d"
		% [blocked_before, hit, e4.list.size()])


func _steal_test(gap: int) -> int:
	var m := Mine.new()
	m.generate_to(60)
	var e = main.entities.get_script().new()
	var player := Vector2i(10, 20)
	e.list.append({"kind": 0, "p": player + Vector2i(gap, 0), "dir": -1, "bob": 0.0})
	return e.step(m, main.flood, player, 0, e.GOBLIN_TICK)


# --- Shots --------------------------------------------------------

func _place(depth: int) -> void:
	main.mine.reset()
	main.flood.reset()
	main.entities.reset()
	main.state = main.State.PLAY
	main.hud.mode = main.hud.Mode.PLAY
	main.deepest = depth
	main.band = Apollo.stratum(depth)["name"]
	main.mine.generate_to(depth + 60)
	main.entities._spawned_to = depth - 25
	main.entities.spawn_ahead(main.mine, depth + 20)

	# Guarantee the encounter rather than hoping one spawns in frame. Cut a
	# short gallery with a floor, stand the dwarf at one end and put a goblin
	# two tiles along it, facing him.
	var y := depth
	for x in range(6, 15):
		main.mine.carve(Vector2i(x, y))
		main.mine.tiles[Vector2i(x, y + 1)] = Mine.STONE
	main.player = Vector2i(8, y)
	main.entities.list.append({
		"kind": 0, "p": Vector2i(10, y), "dir": -1, "bob": 0.0,
	})
	main.falling = false
	main.gems = 4
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
	if DisplayServer.window_get_size() != Vector2i(640, 480):
		DisplayServer.window_set_size(Vector2i(640, 480))
	_place(entry[0])
	_pending = entry[1]
	_wait = 5
	return false


func _save(name: String) -> void:
	var img := get_root().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT, name])
	print("%s  %dx%d  %s" % [name, img.get_width(), img.get_height(),
		"ok" if err == OK else "FAILED %d" % err])
