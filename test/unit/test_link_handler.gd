extends GutTest
## Setting links up changes the current user's registry. Those tests only run when asked for, with
## CHRONOS_TEST_REGISTRY=1 in the environment, and then use a made-up kind of link,
## chronos-test://, which nobody else uses, and take it away again afterwards.

const TEST_SCHEME := "chronos-test"
const NOT_ASKED := "changes the Windows registry for a moment: set CHRONOS_TEST_REGISTRY=1 to run it"


func _registry_tests_asked_for() -> bool:
	return OS.get_environment("CHRONOS_TEST_REGISTRY") == "1"


func after_each() -> void:
	if _registry_tests_asked_for():
		LinkHandler.new(TEST_SCHEME).unregister()


func test_the_command_opens_this_game_with_the_link_after_two_dashes() -> void:
	var command := LinkHandler.new().command()
	assert_true(command.begins_with("\""), "the program's path is quoted, for spaces in it")
	assert_true(command.ends_with("-- \"%1\""), "the link goes after --, so the game does not take it for a scene")
	if OS.has_feature("editor"):
		assert_string_contains(command, "--path", "from the editor it names the project")


func test_the_registry_entries_are_written_with_the_quotes_escaped() -> void:
	var text := LinkHandler.new(TEST_SCHEME)._reg_file_text()
	assert_string_contains(text, "[HKEY_CURRENT_USER\\Software\\Classes\\chronos-test]")
	assert_string_contains(text, "\"URL Protocol\"=\"\"")
	assert_string_contains(text, "[HKEY_CURRENT_USER\\Software\\Classes\\chronos-test\\shell\\open\\command]")
	assert_string_contains(text, "-- \\\"%1\\\"\"", "quotes inside the command are escaped for a .reg file")
	assert_false(text.contains("\\\\\\\\"), "backslashes are doubled once, not twice")


func test_links_are_set_up_and_taken_away_again() -> void:
	var handler := LinkHandler.new(TEST_SCHEME)
	if not handler.is_supported():
		pending("only Windows is handled")
		return
	if not _registry_tests_asked_for():
		pending(NOT_ASKED)
		return
	assert_false(handler.is_registered())
	assert_eq(handler.register(), OK)
	assert_true(handler.is_registered(), "now links open this game")
	assert_eq(handler.register(), OK, "doing it twice is fine")
	assert_eq(handler.unregister(), OK)
	assert_false(handler.is_registered())


func test_a_link_for_another_game_is_not_ours() -> void:
	var handler := LinkHandler.new(TEST_SCHEME)
	if not handler.is_supported():
		pending("only Windows is handled")
		return
	if not _registry_tests_asked_for():
		pending(NOT_ASKED)
		return
	handler.register()
	# The same kind of link, but set up for some other program.
	OS.execute("reg", ["add", "HKCU\\Software\\Classes\\%s\\shell\\open\\command" % TEST_SCHEME, "/ve", "/d", "other", "/f"], [])
	assert_false(handler.is_registered(), "links that open something else are not set up for this game")
