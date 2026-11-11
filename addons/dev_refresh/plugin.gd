@tool
extends EditorPlugin
## Restarts the running game when Claude Code has finished and something in the project changed, so
## the open window shows the new version without anyone pressing anything.
##
## The Stop hook in .claude/settings.json writes the time to .godot/claude_done every time Claude
## finishes. This plugin watches that file. When it changes, and the game's own files (scripts,
## scenes, assets...) are not what they were at the last refresh, it has the editor scan them (so new
## scripts and classes are known) and, if the game is running, stops it and starts it again with the
## same scene. When nothing changed, or no game is running, nothing is restarted.
##
## Scenes open in the editor are not reloaded here, because that would throw away changes that were
## not saved yet; the editor offers to reload them itself.

const ProjectWatcher := preload("res://addons/dev_refresh/project_watcher.gd")

const POLL_SECONDS := 1.0
## How long the editor is given to scan the changed files, and to stop the game, in seconds.
const SCAN_SECONDS := 1.5
const STOP_SECONDS := 0.5

var _watcher := ProjectWatcher.new()
var _timer: Timer
## When the signal file was last written, as far as this plugin knows, and what the game's files
## looked like at the last refresh.
var _signal_time := 0
var _fingerprint_at_refresh := 0
var _refreshing := false


func _enter_tree() -> void:
	_signal_time = _watcher.signal_time()
	_fingerprint_at_refresh = _watcher.fingerprint()
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start()


func _exit_tree() -> void:
	if _timer != null:
		_timer.queue_free()
		_timer = null


## Looks at the signal file, and refreshes if Claude finished since last time and the game changed.
func _poll() -> void:
	if _refreshing:
		return
	var written := _watcher.signal_time()
	if written == _signal_time:
		return
	_signal_time = written
	var now := _watcher.fingerprint()
	if now == _fingerprint_at_refresh:
		return
	_fingerprint_at_refresh = now
	_refresh()


func _refresh() -> void:
	_refreshing = true
	EditorInterface.get_resource_filesystem().scan()
	await get_tree().create_timer(SCAN_SECONDS).timeout
	if EditorInterface.is_playing_scene():
		var scene := EditorInterface.get_playing_scene()
		EditorInterface.stop_playing_scene()
		await get_tree().create_timer(STOP_SECONDS).timeout
		if scene.is_empty():
			EditorInterface.play_main_scene()
		else:
			EditorInterface.play_custom_scene(scene)
		print("Dev Refresh: restarted the game, as the project changed.")
	else:
		print("Dev Refresh: the project changed; no game is running, so none was restarted.")
	# The editor writes files of its own while it scans (such as .uid files): they are not changes.
	_fingerprint_at_refresh = _watcher.fingerprint()
	_refreshing = false
