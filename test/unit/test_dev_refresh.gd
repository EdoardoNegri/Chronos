extends GutTest
## The part of the Dev Refresh plugin that decides whether the game changed (addons/dev_refresh).

const ProjectWatcher := preload("res://addons/dev_refresh/project_watcher.gd")
const ROOT := "user://test_dev_refresh"


func before_each() -> void:
	_remove_all()
	DirAccess.make_dir_recursive_absolute(ROOT + "/scripts/ui")
	DirAccess.make_dir_recursive_absolute(ROOT + "/test")
	DirAccess.make_dir_recursive_absolute(ROOT + "/signal")
	_write(ROOT + "/scripts/a.gd", "extends Node\n")
	_write(ROOT + "/scripts/ui/b.gd", "extends Control\n")
	_write(ROOT + "/test/t.gd", "extends GutTest\n")
	_write(ROOT + "/project.godot", "config_version=5\n")


func after_each() -> void:
	_remove_all()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_all() -> void:
	if not DirAccess.dir_exists_absolute(ROOT):
		return
	for folder: String in ["scripts/ui", "scripts", "test", "signal"]:
		var path := ROOT + "/" + folder
		for file_name in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path + "/" + file_name)
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ROOT + "/project.godot")
	DirAccess.remove_absolute(ROOT)


func _watcher() -> RefCounted:
	return ProjectWatcher.new(ROOT, ["scripts"] as Array[String], ["project.godot"] as Array[String], ROOT + "/signal/done")


func test_the_same_files_give_the_same_fingerprint() -> void:
	var watcher := _watcher()
	assert_eq(watcher.fingerprint(), watcher.fingerprint())


func test_a_new_or_removed_file_of_the_game_changes_it_even_in_a_folder_inside_a_folder() -> void:
	var watcher := _watcher()
	var before: int = watcher.fingerprint()
	_write(ROOT + "/scripts/ui/c.gd", "extends Control\n")
	var with_new: int = watcher.fingerprint()
	assert_ne(with_new, before, "a new script")
	DirAccess.remove_absolute(ROOT + "/scripts/ui/c.gd")
	assert_eq(watcher.fingerprint(), before, "and back again when it goes")


func test_a_file_saved_again_changes_it() -> void:
	var watcher := _watcher()
	var before: int = watcher.fingerprint()
	# Modification times are in whole seconds.
	await get_tree().create_timer(1.1).timeout
	_write(ROOT + "/scripts/a.gd", "extends Node2D\n")
	assert_ne(watcher.fingerprint(), before)


func test_the_listed_files_count_too() -> void:
	var watcher := _watcher()
	var before: int = watcher.fingerprint()
	DirAccess.remove_absolute(ROOT + "/project.godot")
	assert_ne(watcher.fingerprint(), before, "project.godot is part of the game")


func test_what_is_not_part_of_the_game_does_not_change_it() -> void:
	var watcher := _watcher()
	var before: int = watcher.fingerprint()
	_write(ROOT + "/test/another.gd", "extends GutTest\n")
	_write(ROOT + "/scripts/a.gd.uid", "uid://abc\n")
	_write(ROOT + "/scripts/a.gd.import", "[remap]\n")
	assert_eq(watcher.fingerprint(), before, "the tests and the files the editor makes by itself are not changes")
	for file_name in ["a.gd.uid", "a.gd.import"]:
		DirAccess.remove_absolute(ROOT + "/scripts/" + file_name)
	DirAccess.remove_absolute(ROOT + "/test/another.gd")


func test_the_signal_file_says_when_claude_last_finished() -> void:
	var watcher := _watcher()
	assert_eq(watcher.signal_time(), 0, "never, to begin with")
	_write(ROOT + "/signal/done", "1\n")
	var first: int = watcher.signal_time()
	assert_gt(first, 0)
	await get_tree().create_timer(1.1).timeout
	_write(ROOT + "/signal/done", "2\n")
	assert_gt(watcher.signal_time(), first, "and it moves on each time")


func test_the_stop_hook_is_set_up_to_write_the_file_the_plugin_watches() -> void:
	var text := FileAccess.get_file_as_string("res://.claude/settings.json")
	var settings: Variant = JSON.parse_string(text)
	assert_true(settings is Dictionary, "the project's Claude settings are there")
	var command: String = settings["hooks"]["Stop"][0]["hooks"][0]["command"]
	assert_string_contains(command, ".godot/claude_done", "a Stop hook writes the file")
	assert_eq(ProjectWatcher.DEFAULT_SIGNAL_FILE, "res://.godot/claude_done", "that the plugin watches")
