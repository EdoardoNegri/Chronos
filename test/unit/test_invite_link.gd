extends GutTest


func test_a_link_says_where_and_which_room_and_nothing_secret() -> void:
	var link := InviteLink.make("wss://quick-words.trycloudflare.com", &"room_2", "Friend's “room”", true)
	assert_true(link.begins_with("chronos://join?d="))
	assert_false(link.contains(" "), "it can be pasted anywhere")
	assert_false(link.contains("="  + "="), "no padding characters that chat apps may eat")
	var invite := InviteLink.parse(link)
	assert_eq(invite["address"], "wss://quick-words.trycloudflare.com")
	assert_eq(invite["room_id"], "room_2")
	assert_eq(invite["room_name"], "Friend's “room”", "names with quotes and symbols survive")
	assert_true(invite["locked"])
	assert_eq(InviteLink.parse(InviteLink.make("ws://1.2.3.4:9080", &"r", "x", false))["locked"], false)


func test_links_made_for_the_same_room_are_the_same_and_differ_for_other_rooms() -> void:
	assert_eq(InviteLink.make("ws://a", &"r1", "n", false), InviteLink.make("ws://a", &"r1", "n", false))
	assert_ne(InviteLink.make("ws://a", &"r1", "n", false), InviteLink.make("ws://a", &"r2", "n", false))


func test_a_link_is_read_with_spaces_around_it_and_inside_a_web_address() -> void:
	var link := InviteLink.make("ws://192.168.0.5:9080", &"room_7", "Test", false)
	assert_eq(InviteLink.parse("  " + link + "\n")["room_id"], "room_7")
	var packed := link.trim_prefix("chronos://join?d=")
	assert_eq(InviteLink.parse("https://example.pages.dev/join.html#" + packed)["room_id"], "room_7", "a web link works too")
	assert_eq(InviteLink.parse("chronos://join?d=" + packed + "&other=1")["room_id"], "room_7", "extra parts are ignored")


func test_things_that_are_not_links_are_not_read_as_links() -> void:
	assert_eq(InviteLink.parse(""), {})
	assert_eq(InviteLink.parse("hello"), {})
	assert_eq(InviteLink.parse("chronos://join"), {})
	assert_eq(InviteLink.parse("chronos://join?d="), {})
	assert_eq(InviteLink.parse("chronos://join?d=!!!notbase64!!!"), {})
	assert_eq(InviteLink.parse("https://example.com/page"), {}, "a web address with nothing after # is not one")
	var no_room := Marshalls.utf8_to_base64(JSON.stringify({"a": "ws://x"})).replace("=", "")
	assert_eq(InviteLink.parse("chronos://join?d=" + no_room), {}, "a link without a room is no use")


func test_a_link_is_found_among_command_line_arguments() -> void:
	var link := InviteLink.make("ws://x:1", &"room_3", "n", false)
	var args := PackedStringArray(["--path", "C:/game", "--", link])
	assert_eq(InviteLink.find_in(args)["room_id"], "room_3")
	assert_eq(InviteLink.find_in(PackedStringArray(["--headless", "res://a.tscn"])), {})
	assert_eq(InviteLink.find_in(PackedStringArray()), {})


func test_the_best_link_is_the_plain_one_until_there_is_a_web_page() -> void:
	var plain := InviteLink.make("ws://x:1", &"r", "n", false)
	if InviteLink.PAGE_URL.is_empty():
		assert_eq(InviteLink.make_web("ws://x:1", &"r", "n", false), "")
		assert_eq(InviteLink.make_best("ws://x:1", &"r", "n", false), plain)
	else:
		assert_true(InviteLink.make_best("ws://x:1", &"r", "n", false).begins_with(InviteLink.PAGE_URL))
