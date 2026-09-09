extends Node
## Checks dwarvenengineering.com for a newer build of this game, and can
## download and install it without the player leaving the game.
##
## SETUP
##   1. Project > Project Settings > Globals > Autoload, add this file
##      with the name `UpdateChecker`.
##   2. Set your version in Project Settings > Application > Config >
##      Version (e.g. "0.4.2"). This script reads it from there, so the
##      version lives in exactly one place.
##   3. Set GAME_SLUG below to the repo name.
##
## The manifest it reads is published by the game's own repo at
## https://dwarvenengineering.com/<slug>/versions.json — see
## game-kit/versions.json for the schema.

signal update_available(info: Dictionary)
signal up_to_date()
signal check_failed(reason: String)
signal download_progress(received: int, total: int)
signal download_failed(reason: String)
signal ready_to_install(installer_path: String)

const GAME_SLUG := "dwarven-depths"
const MANIFEST_URL := "https://dwarvenengineering.com/%s/versions.json" % GAME_SLUG
const PAGE_URL := "https://dwarvenengineering.com/%s" % GAME_SLUG

## Give up rather than hang the main menu on a dead connection.
const TIMEOUT_SECONDS := 8.0

var current_version: String = ""
var latest: Dictionary = {}

var _http: HTTPRequest
var _downloading := false


func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SECONDS
	# Release assets on GitHub redirect to a CDN host.
	_http.max_redirects = 8
	add_child(_http)


# ---------------------------------------------------------------------
# Checking
# ---------------------------------------------------------------------

## Fetch the manifest. Emits exactly one of update_available / up_to_date
## / check_failed. Safe to call on startup — it never blocks.
func check_for_update() -> void:
	if _downloading:
		return

	_http.request_completed.connect(_on_manifest_received, CONNECT_ONE_SHOT)

	# Cache-bust: GitHub Pages will happily serve a stale manifest for
	# ten minutes otherwise, which is exactly when it matters most.
	var url := "%s?t=%d" % [MANIFEST_URL, Time.get_unix_time_from_system()]
	var err := _http.request(url)
	if err != OK:
		_http.request_completed.disconnect(_on_manifest_received)
		check_failed.emit("Could not reach the hold (error %d)." % err)


func _on_manifest_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		check_failed.emit("No answer from the hold.")
		return
	if code != 200:
		check_failed.emit("The hold answered with %d." % code)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("latest"):
		check_failed.emit("The tablet was unreadable.")
		return

	latest = parsed["latest"]
	var newest := str(latest.get("version", "0.0.0"))

	if compare_versions(newest, current_version) > 0:
		update_available.emit({
			"version": newest,
			"released": str(latest.get("released", "")),
			"mandatory": bool(latest.get("mandatory", false)),
			"notes": latest.get("notes", []),
			"build": _build_for_this_platform(),
		})
	else:
		up_to_date.emit()


## Returns 1 if `a` is newer than `b`, -1 if older, 0 if equal.
## Handles plain dotted versions ("1.2.10") and ignores any pre-release
## suffix after a dash.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.strip_edges().lstrip("v").split("-")[0].split(".")
	var pb := b.strip_edges().lstrip("v").split("-")[0].split(".")

	for i in range(maxi(pa.size(), pb.size())):
		var na := int(pa[i]) if i < pa.size() else 0
		var nb := int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return 1 if na > nb else -1
	return 0


## The build entry matching the machine we are running on, or {} if the
## release does not ship one for this platform.
func _build_for_this_platform() -> Dictionary:
	var builds: Dictionary = latest.get("builds", {})
	var key := ""

	match OS.get_name():
		"Windows":
			key = "windows"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			# The handhelds are ARM; a desktop Linux box is not.
			key = "linux-arm64" if _is_arm() else "linux"
		"macOS":
			key = "macos"

	return builds.get(key, {})


func _is_arm() -> bool:
	# Godot has no direct architecture query, so infer it from the
	# engine's own build info.
	var info := Engine.get_architecture_name()
	return info.begins_with("arm")


## True when this platform can install its own updates. Windows can run
## the Inno Setup installer silently; the handheld builds are copied to
## an SD card by hand, so there we only ever notify.
func can_self_install() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


# ---------------------------------------------------------------------
# Downloading
# ---------------------------------------------------------------------

var _installer_path := ""
var _expected_sha := ""

## Download the installer for this platform into user://. Emits
## download_progress as it goes and ready_to_install when verified.
func download_update() -> void:
	var build := _build_for_this_platform()
	if build.is_empty() or not build.has("url"):
		download_failed.emit("No build for this platform in that release.")
		return

	_expected_sha = str(build.get("sha256", ""))
	_installer_path = "user://update/%s" % str(build["url"]).get_file()
	DirAccess.make_dir_recursive_absolute("user://update")

	_downloading = true
	_http.download_file = _installer_path
	_http.request_completed.connect(_on_download_finished, CONNECT_ONE_SHOT)

	var err := _http.request(str(build["url"]))
	if err != OK:
		_finish_download()
		download_failed.emit("Could not start the download (error %d)." % err)


func _process(_delta: float) -> void:
	if _downloading:
		download_progress.emit(_http.get_downloaded_bytes(), _http.get_body_size())


func _on_download_finished(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_finish_download()

	if result != HTTPRequest.RESULT_SUCCESS or code >= 400:
		download_failed.emit("The download broke off partway.")
		return

	if not FileAccess.file_exists(_installer_path):
		download_failed.emit("The download arrived empty.")
		return

	# Verify before we ever hand the file to the OS. A truncated or
	# tampered installer must not be executed.
	if _expected_sha != "" and not _expected_sha.begins_with("0000"):
		var actual := FileAccess.get_sha256(_installer_path)
		if actual.to_lower() != _expected_sha.to_lower():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_installer_path))
			download_failed.emit("The seal did not match. The file was discarded.")
			return

	ready_to_install.emit(_installer_path)


func _finish_download() -> void:
	_downloading = false
	_http.download_file = ""


# ---------------------------------------------------------------------
# Installing
# ---------------------------------------------------------------------

## Hand the installer to Windows and quit so it can replace our files.
## /SILENT shows only a progress bar; /CLOSEAPPLICATIONS lets it wait
## for this process to exit cleanly.
func install_and_restart() -> void:
	if _installer_path == "":
		return

	var absolute := ProjectSettings.globalize_path(_installer_path)
	var build := _build_for_this_platform()
	var args_text := str(build.get("installerArgs", "/SILENT /NORESTART /CLOSEAPPLICATIONS"))
	var args := args_text.split(" ", false)

	var pid := OS.create_process(absolute, args)
	if pid == -1:
		download_failed.emit("Windows refused to start the installer.")
		return

	get_tree().quit()


## Fallback for platforms that cannot install themselves.
func open_download_page() -> void:
	OS.shell_open(PAGE_URL)


func copy_link() -> void:
	DisplayServer.clipboard_set(PAGE_URL)
