extends GutTest

const TEST_PATH := "user://test_profile/profile.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	DirAccess.remove_absolute(TEST_PATH.get_base_dir())


func _profile() -> PlayerProfile:
	DirAccess.make_dir_recursive_absolute(TEST_PATH.get_base_dir())
	return autofree(PlayerProfile.new(TEST_PATH))


func test_there_is_no_account_until_a_name_is_picked() -> void:
	var profile := _profile()
	assert_false(profile.has_account())
	assert_eq(profile.player_name, "")


func test_a_name_is_all_the_account_needs_and_is_kept() -> void:
	var profile := _profile()
	watch_signals(profile)
	assert_eq(profile.set_player_name("  Aeon  "), "", "accepted")
	assert_eq(profile.player_name, "Aeon", "spaces around it are dropped")
	assert_true(profile.has_account())
	assert_signal_emitted_with_parameters(profile, "name_changed", ["Aeon"])
	assert_eq(autofree(PlayerProfile.new(TEST_PATH)).player_name, "Aeon", "still there the next time the game starts")


func test_the_name_can_be_changed() -> void:
	var profile := _profile()
	profile.set_player_name("Aeon")
	watch_signals(profile)
	assert_eq(profile.set_player_name("Kairos"), "")
	assert_eq(autofree(PlayerProfile.new(TEST_PATH)).player_name, "Kairos")
	assert_signal_emit_count(profile, "name_changed", 1)
	assert_eq(profile.set_player_name("Kairos"), "")
	assert_signal_emit_count(profile, "name_changed", 1, "the same name is not a change")


func test_a_name_must_be_there_and_not_too_long() -> void:
	var profile := _profile()
	assert_ne(profile.set_player_name("   "), "")
	assert_ne(profile.set_player_name("x".repeat(PlayerProfile.MAX_NAME_LENGTH + 1)), "")
	assert_false(profile.has_account(), "a refused name is not kept")
	assert_eq(profile.set_player_name("x".repeat(PlayerProfile.MAX_NAME_LENGTH)), "")
	profile.set_player_name("Keeper")
	assert_ne(profile.set_player_name(""), "")
	assert_eq(profile.player_name, "Keeper", "and a refused change leaves the name as it was")


func test_the_name_survives_other_settings_in_the_file() -> void:
	var profile := _profile()
	profile.set_player_name("Aeon")
	profile._file.set_value("online", "server", "wss://old.example")
	profile._save()
	profile.set_player_name("Kairos")
	assert_eq(autofree(PlayerProfile.new(TEST_PATH)).player_name, "Kairos", "a file from an older game still loads")
