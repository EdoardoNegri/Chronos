extends GutTest
## Listing a hosted room: posting it, keeping it in the list, taking it off.

const FakeGitHub := preload("res://test/helpers/fake_github.gd")


func _listing(github: FakeGitHub) -> RoomListing:
	var board := github.make_board()
	add_child_autofree(board)
	var listing := RoomListing.new(board)
	listing.find_public_address = false
	add_child_autoqfree(listing)
	return listing


func _room() -> RoomInfo:
	return RoomInfo.new(&"room_2", "Home room", "Aeon", 1, 2)


func test_a_room_is_posted_with_its_address_on_this_network() -> void:
	var github := FakeGitHub.new()
	var listing := _listing(github)
	watch_signals(listing)
	listing.start(_room(), 9080)
	assert_gt(listing.issue, 0)
	assert_true(github.is_open(listing.issue))
	var entry := RoomBoard.read_issue(github.issues[0])
	assert_true(entry["local"])
	assert_true(str(entry["address"]).ends_with(":9080"))
	assert_string_contains(listing.note, "own network")
	assert_signal_emitted(listing, "note_changed")
	await listing.close()


func test_the_heartbeat_keeps_the_room_and_brings_it_back_if_it_was_closed() -> void:
	var github := FakeGitHub.new()
	var listing := _listing(github)
	listing.start(_room(), 9080)
	var issue := listing.issue
	var before := int(RoomBoard.read_issue(github.issues[0])["alive"])
	github.issues[0]["state"] = "closed"
	github.issues[0]["body"] = RoomBoard.write_issue_body(_room(), "ws://x:1", true, 0)
	await listing._beat()
	assert_true(github.is_open(issue), "a room wrongly taken off the list comes back")
	assert_gte(int(RoomBoard.read_issue(github.issues[0])["alive"]), before, "saying it is still there")
	await listing.close()


func test_closing_takes_the_room_off_the_list_and_frees_the_listing() -> void:
	var github := FakeGitHub.new()
	var listing := _listing(github)
	listing.start(_room(), 9080)
	var issue := listing.issue
	await listing.close()
	assert_false(github.is_open(issue))
	assert_eq(listing.issue, 0)
	await get_tree().process_frame
	assert_false(is_instance_valid(listing), "it frees itself")


func test_a_room_that_cannot_be_posted_says_why() -> void:
	var github := FakeGitHub.new()
	github.down = true
	var listing := _listing(github)
	listing.start(_room(), 9080)
	assert_eq(listing.issue, 0)
	assert_string_contains(listing.note, "could not be added")
	await listing.close()
