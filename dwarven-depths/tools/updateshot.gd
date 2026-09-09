extends SceneTree

## Screenshot runner for the update panel.
##
##   godot --path . --script res://tools/updateshot.gd
##
## The panel is the one screen a player sees before they have decided to
## trust this build, so it gets the same treatment as the game: shots at the
## handheld size and at desktop sizes, in every state it can reach.
##
## States are set by poking UpdatePanel directly rather than by running a real
## download -- the point is the layout, and a real download would need a
## published release to exist first.

const OUT := "res://shots"

var panel: Node
var main: Node2D

var _script: Array = []
var _step := 0
var _wait := 0
var _pending := ""

const INFO := {
	"version": "0.2.0",
	"released": "2026-09-09",
	"mandatory": false,
	"notes": [
		"Cave-ins now propagate through unsupported ceilings.",
		"Lantern oil drains at half rate while standing still.",
		"Fixed the audio crackle on the handheld build at low battery.",
	],
	"build": {"url": "https://example.invalid/setup.exe", "size": 103115040},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	# The panel draws over the game, so the game has to be there to draw over.
	main = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)

	panel = get_root().get_node("UpdatePanel")

	_script = [
		[Vector2i(640, 480), _prompt_download, "u1-prompt-640x480"],
		[Vector2i(1280, 720), _prompt_download, "u2-prompt-1280x720"],
		[Vector2i(640, 480), _prompt_link_only, "u3-linkonly-640x480"],
		[Vector2i(640, 480), _working, "u4-downloading-640x480"],
		[Vector2i(640, 480), _failed, "u5-failed-640x480"],
	]


func _process(_delta: float) -> bool:
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
	var path := "%s/%s.png" % [OUT, name]
	var err := img.save_png(path)
	print("%s  %dx%d  %s" % [name, img.get_width(), img.get_height(),
		"ok" if err == OK else "FAILED %d" % err])


# --- States -------------------------------------------------------

## What a Windows player sees: the panel can install for them.
func _prompt_download() -> void:
	panel.show_update(INFO)
	panel._options = PackedStringArray(["DOWNLOAD UPDATE", "LATER"])
	panel._selected = 0
	panel._surface.queue_redraw()


## What the handheld sees: nothing to run here, so the address is the answer.
func _prompt_link_only() -> void:
	panel.show_update(INFO)
	panel._options = PackedStringArray(["LATER"])
	panel._selected = 0
	panel._surface.queue_redraw()


func _working() -> void:
	panel.show_update(INFO)
	panel._state = panel.State.WORKING
	panel._progress = 0.42
	panel._status = "HAULING IT UP THE SHAFT  43.3 MB"
	panel._surface.queue_redraw()


func _failed() -> void:
	panel.show_update(INFO)
	panel._state = panel.State.FAILED
	panel._status = "THE SEAL DID NOT MATCH. THE FILE WAS DISCARDED."
	panel._options = PackedStringArray(["LATER"])
	panel._surface.queue_redraw()
