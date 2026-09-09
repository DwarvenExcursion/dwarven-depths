extends CanvasLayer

## The update notice, drawn the same way as everything else here: draw_rect
## and TinyFont, Apollo colours only, sized for the 320x240 canvas.
##
## Driven by the d-pad and the existing actions -- this game has no mouse, so
## neither does this panel. Up/down moves the selection, DIG or START confirms,
## ESC/QUIT dismisses.
##
## The tree is paused while the panel is open. main.gd polls input rather than
## consuming events, so hiding the panel behind a pause is the only reliable
## way to stop the dwarf digging while someone reads patch notes.
##
## SETUP: autoload as `UpdatePanel`, after `UpdateChecker`. Then from the
## title screen:
##     UpdateChecker.update_available.connect(UpdatePanel.show_update)
##     UpdateChecker.check_for_update()

enum State { HIDDEN, PROMPT, WORKING, FAILED }

const MARGIN := 8.0        # panel edge to content
const LINE := 7.0          # 5px glyph + 2px leading, at scale 1
const OPTION_LINE := 9.0
const MAX_NOTE_LINES := 6  # past this the panel outgrows the short edge

var _state: int = State.HIDDEN
var _version := ""
var _note_lines: PackedStringArray = []
var _options: PackedStringArray = []
var _selected := 0
var _status := ""
var _progress := 0.0       # 0..1
var _can_install := false

var _surface: Control


## The Control that actually paints. Kept as an inner class so this whole
## feature stays one file, matching how the rest of the UI is organised.
class _Surface extends Control:
	var host: CanvasLayer

	func _draw() -> void:
		host._paint(self)

	func _unhandled_input(event: InputEvent) -> void:
		host._handle(event)


func _ready() -> void:
	layer = 128
	# Must keep running while the tree is paused, or the panel it just put up
	# would stop accepting input.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_surface = _Surface.new()
	_surface.host = self
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	_surface.hide()

	get_viewport().size_changed.connect(_surface.queue_redraw)


# ---------------------------------------------------------------------
# Public
# ---------------------------------------------------------------------

func show_update(info: Dictionary) -> void:
	_version = str(info.get("version", "?"))
	_can_install = UpdateChecker.can_self_install() \
		and not (info.get("build", {}) as Dictionary).is_empty()

	_note_lines = _build_notes(info.get("notes", []))

	if _can_install:
		_options = PackedStringArray(["DOWNLOAD UPDATE", "LATER"])
	else:
		# Nothing to run on this platform, so the address is the whole answer.
		_options = PackedStringArray(["LATER"])

	_selected = 0
	_status = ""
	_progress = 0.0
	_state = State.PROMPT

	get_tree().paused = true
	_surface.show()
	_surface.queue_redraw()


func dismiss() -> void:
	_state = State.HIDDEN
	_surface.hide()
	get_tree().paused = false


# ---------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------

func _handle(event: InputEvent) -> void:
	if _state == State.HIDDEN:
		return

	# Nothing is cancellable mid-download; the installer is already on its way.
	if _state == State.WORKING:
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_down") or event.is_action_pressed("move_up"):
		if _options.size() > 1:
			var step := 1 if event.is_action_pressed("move_down") else -1
			_selected = wrapi(_selected + step, 0, _options.size())
			_surface.queue_redraw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("start_game") or event.is_action_pressed("dig"):
		get_viewport().set_input_as_handled()
		_confirm()
		return

	# Swallow quit while the panel is up, or ESC would close the game outright.
	if event.is_action_pressed("quit_game"):
		get_viewport().set_input_as_handled()
		dismiss()


func _confirm() -> void:
	if _options[_selected] == "LATER":
		dismiss()
		return

	_state = State.WORKING
	_status = "HAULING IT UP THE SHAFT"
	_progress = 0.0

	UpdateChecker.download_progress.connect(_on_progress)
	UpdateChecker.download_failed.connect(_on_failed, CONNECT_ONE_SHOT)
	UpdateChecker.ready_to_install.connect(_on_ready, CONNECT_ONE_SHOT)
	UpdateChecker.download_update()

	_surface.queue_redraw()


# ---------------------------------------------------------------------
# Download callbacks
# ---------------------------------------------------------------------

func _on_progress(received: int, total: int) -> void:
	_progress = (float(received) / float(total)) if total > 0 else 0.0
	var mb := received / 1048576.0
	_status = "HAULING IT UP THE SHAFT  %.1f MB" % mb
	_surface.queue_redraw()


func _on_ready(_path: String) -> void:
	_disconnect_progress()
	_progress = 1.0
	_status = "SEAL VERIFIED. CLOSING TO INSTALL"
	_surface.queue_redraw()
	await get_tree().create_timer(1.2).timeout
	get_tree().paused = false
	UpdateChecker.install_and_restart()


func _on_failed(reason: String) -> void:
	_disconnect_progress()
	_state = State.FAILED
	_status = reason.to_upper()
	_options = PackedStringArray(["LATER"])
	_selected = 0
	_surface.queue_redraw()


func _disconnect_progress() -> void:
	if UpdateChecker.download_progress.is_connected(_on_progress):
		UpdateChecker.download_progress.disconnect(_on_progress)


# ---------------------------------------------------------------------
# Text
# ---------------------------------------------------------------------

## Patch notes arrive as one string per bullet. Wrap each to the panel width
## and cap the total, so a chatty release cannot push the panel off-screen.
func _build_notes(notes: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var budget := MAX_NOTE_LINES

	for note in notes:
		if budget <= 0:
			break
		var wrapped := _wrap("- " + str(note).to_upper(), _note_columns())
		for i in mini(wrapped.size(), budget):
			out.append(wrapped[i])
			budget -= 1

	return out


## How many glyphs fit across the panel. TinyFont advances 4px per glyph at
## scale 1 and the last one needs no trailing gap.
func _note_columns() -> int:
	return int((_panel_width() - MARGIN * 2.0 + 1.0) / TinyFont.ADVANCE)


## Failure messages come from the checker and can be any length, so they get
## wrapped like the notes rather than running past the border.
func _status_lines() -> PackedStringArray:
	if _status == "":
		return PackedStringArray()
	return _wrap(_status, _note_columns())


func _wrap(text: String, columns: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""

	for word in text.split(" ", false):
		var candidate := word if line.is_empty() else line + " " + word
		if candidate.length() <= columns:
			line = candidate
		else:
			if not line.is_empty():
				out.append(line)
			line = word

	if not line.is_empty():
		out.append(line)
	return out


# ---------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------

func _panel_width() -> float:
	# 288 is the widest that still leaves a margin on a 320px canvas.
	return minf(_surface.size.x - 24.0, 288.0)


func _panel_height() -> float:
	var h := MARGIN                      # top pad
	h += TinyFont.height(2) + 4.0        # title
	h += 1.0 + 4.0                       # rule
	h += TinyFont.height(1) + 5.0        # version line
	h += float(_note_lines.size()) * LINE
	h += 5.0
	var status_count := _status_lines().size()
	if status_count > 0:
		h += float(status_count) * LINE + 3.0
	if _state == State.WORKING:
		h += 2.0 + 3.0 + 6.0             # leading, bar, trailing
	h += float(_options.size()) * OPTION_LINE
	h += 4.0
	h += TinyFont.height(1)              # url
	h += MARGIN                          # bottom pad
	return h


func _paint(ci: CanvasItem) -> void:
	var w := _surface.size.x
	var h := _surface.size.y

	# Drop the game back so the panel reads as the only thing on screen.
	ci.draw_rect(Rect2(0.0, 0.0, w, h), Color(Apollo.VOID, 0.88))

	var pw := _panel_width()
	var ph := _panel_height()
	var px := roundf((w - pw) * 0.5)
	var py := roundf((h - ph) * 0.5)
	var cx := px + pw * 0.5

	ci.draw_rect(Rect2(px, py, pw, ph), Apollo.SLATE_XD)
	ci.draw_rect(Rect2(px, py, pw, ph), Apollo.BRONZE, false, 1.0)

	var y := py + MARGIN

	TinyFont.draw_centered(ci, cx, y, "NEW VERSION", Apollo.GOLD, Apollo.BARK_XD, 2)
	y += TinyFont.height(2) + 4.0

	# The inlay: a gold seam across the face of the slab.
	ci.draw_rect(Rect2(px + MARGIN, y, pw - MARGIN * 2.0, 1.0), Apollo.BRONZE)
	y += 1.0 + 4.0

	var have := "V%s  YOU HAVE V%s" % [_version, UpdateChecker.current_version]
	TinyFont.draw_centered(ci, cx, y, have, Apollo.SLATE_XL, Apollo.INK, 1)
	y += TinyFont.height(1) + 5.0

	for line in _note_lines:
		TinyFont.draw_text(ci, Vector2(px + MARGIN, y), line, Apollo.MIST, 1)
		y += LINE
	y += 5.0

	var status_lines := _status_lines()
	if status_lines.size() > 0:
		var tone := Apollo.FLOOD_HI if _state == State.FAILED else Apollo.AMBER
		for line in status_lines:
			TinyFont.draw_centered(ci, cx, y, line, tone, Apollo.INK, 1)
			y += LINE
		y += 3.0

	if _state == State.WORKING:
		y += 2.0
		var bw := pw - MARGIN * 2.0
		ci.draw_rect(Rect2(px + MARGIN, y, bw, 3.0), Apollo.SLATE_D)
		ci.draw_rect(Rect2(px + MARGIN, y, roundf(bw * _progress), 3.0), Apollo.GOLD)
		y += 3.0 + 6.0

	for i in _options.size():
		if i == _selected and _state != State.WORKING:
			TinyFont.draw_centered(ci, cx, y, "> " + _options[i] + " <",
				Apollo.GOLD, Apollo.BARK_XD, 1)
		else:
			TinyFont.draw_centered(ci, cx, y, _options[i],
				Apollo.SLATE_L, Apollo.INK, 1)
		y += OPTION_LINE
	y += 4.0

	# Always visible. On the handheld this is the only way off the device.
	TinyFont.draw_centered(ci, cx, y, "DWARVENENGINEERING.COM/DWARVEN-DEPTHS",
		Apollo.SLATE_L, Apollo.VOID, 1)
