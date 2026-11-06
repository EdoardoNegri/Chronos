extends GutTest

## What cloudflared prints when it makes a quick tunnel (shortened).
const TUNNEL_OUTPUT := """2026-11-06T16:01:00Z INF Thank you for trying Cloudflare Tunnel.
2026-11-06T16:01:02Z INF Requesting new quick Tunnel on trycloudflare.com...
2026-11-06T16:01:04Z INF +--------------------------------------------------------------------------------------------+
2026-11-06T16:01:04Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
2026-11-06T16:01:04Z INF |  https://quick-words-here.trycloudflare.com                                                |
2026-11-06T16:01:04Z INF +--------------------------------------------------------------------------------------------+
"""


func test_the_tunnel_address_is_found_in_what_the_program_prints() -> void:
	assert_eq(Reachability.parse_tunnel_address(TUNNEL_OUTPUT), "wss://quick-words-here.trycloudflare.com")
	assert_eq(Reachability.parse_tunnel_address("INF Requesting new quick Tunnel..."), "", "not yet")
	assert_eq(Reachability.parse_tunnel_address("see https://www.cloudflare.com/ for more"), "", "only a tunnel address counts")
	assert_eq(Reachability.parse_tunnel_address(""), "")


func test_addresses_that_only_work_inside_a_network_are_told_apart() -> void:
	for ip in ["10.0.0.4", "192.168.1.20", "172.16.5.5", "172.31.255.1", "127.0.0.1", "100.64.3.3", "169.254.1.1"]:
		assert_true(Reachability.is_private_address(ip), "%s is private" % ip)
	for ip in ["8.8.8.8", "203.0.113.9", "172.32.0.1", "100.128.0.1", "192.169.0.1", "not an address", ""]:
		assert_false(Reachability.is_private_address(ip), "%s is not" % ip)


func test_a_tunnel_program_gives_the_address_it_prints() -> void:
	if OS.get_name() != "Windows":
		pending("uses a Windows command to stand in for the tunnel program")
		return
	var reachability := Reachability.new()
	reachability.try_router = false
	reachability.verify = false
	# Stands in for cloudflared: prints an address, then keeps running like a tunnel does.
	reachability.program = "cmd.exe"
	reachability.arguments = PackedStringArray(["/c", "echo https://fake-words.trycloudflare.com 1>&2 & ping -n 30 127.0.0.1 > nul"])
	add_child_autofree(reachability)
	watch_signals(reachability)
	reachability.start(9999)
	await wait_for_signal(reachability.address_found, 8.0)
	assert_signal_emitted_with_parameters(reachability, "address_found", ["wss://fake-words.trycloudflare.com", "a tunnel"])
	reachability.stop()


func test_without_a_tunnel_and_without_asking_the_router_it_says_why() -> void:
	var reachability := Reachability.new()
	reachability.try_router = false
	reachability.verify = false
	reachability.program = "C:/no/such/folder/tunnel-program.exe"
	add_child_autofree(reachability)
	watch_signals(reachability)
	reachability.start(9999)
	assert_signal_emitted(reachability, "failed")
	var reason: String = get_signal_parameters(reachability, "failed")[0]
	assert_string_contains(reason, "tunnel program is missing")
	assert_string_contains(reason, "router was not asked")


func test_a_tunnel_program_that_ends_without_an_address_is_given_up_on() -> void:
	if OS.get_name() != "Windows":
		pending("uses a Windows command to stand in for the tunnel program")
		return
	var reachability := Reachability.new()
	reachability.try_router = false
	reachability.verify = false
	reachability.program = "cmd.exe"
	reachability.arguments = PackedStringArray(["/c", "echo no address here 1>&2"])
	add_child_autofree(reachability)
	watch_signals(reachability)
	reachability.start(9999)
	await wait_for_signal(reachability.failed, 8.0)
	assert_signal_emitted(reachability, "failed")
	assert_signal_not_emitted(reachability, "address_found")


func test_the_game_comes_with_the_tunnel_program_and_finds_it() -> void:
	if OS.get_name() != "Windows":
		pending("the tunnel program that comes with the game is the Windows one")
		return
	assert_true(FileAccess.file_exists(Reachability.BUNDLED_PROGRAM), "bin/cloudflared.exe is part of the game")
	var found := Reachability.bundled_program()
	assert_true(found.is_absolute_path(), "it is a file on disk that can be run")
	assert_true(FileAccess.file_exists(found))
	assert_ne(Reachability.find_tunnel_program(), "", "so there is always a tunnel to try")


func test_a_packed_program_is_unpacked_once_to_a_file_that_can_be_run() -> void:
	var folder := "user://test_unpack"
	var source := folder + "/packed.bin"
	var destination := folder + "/out/program.bin"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var bytes := PackedByteArray()
	bytes.resize(3 * 1024 * 1024 + 7)  # more than one piece is copied at a time
	for i in bytes.size():
		bytes[i] = i % 251
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var unpacked := Reachability.unpack(source, destination)
	assert_eq(unpacked, ProjectSettings.globalize_path(destination), "it says where the file is on disk")
	assert_eq(FileAccess.get_file_as_bytes(destination), bytes, "the copy is whole")
	assert_false(FileAccess.file_exists(destination + ".part"), "nothing half-written is left")
	var modified := FileAccess.get_modified_time(destination)
	assert_eq(Reachability.unpack(source, destination), unpacked, "the next time it is used as it is")
	assert_eq(FileAccess.get_modified_time(destination), modified, "without copying it again")
	assert_eq(Reachability.unpack(folder + "/missing.bin", destination), "", "a missing file is not unpacked")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))


func test_a_tunnel_left_running_by_an_earlier_game_is_stopped() -> void:
	if OS.get_name() != "Windows":
		pending("uses Windows commands")
		return
	# Something that is not the tunnel program, written down as if it were: it must be left alone.
	var other := OS.create_process("cmd.exe", ["/c", "ping -n 20 127.0.0.1 > nul"])
	var file := FileAccess.open(Reachability.PID_FILE, FileAccess.WRITE)
	file.store_string(str(other))
	file.close()
	Reachability.stop_leftover_tunnel()
	assert_true(OS.is_process_running(other), "only the tunnel program is ever stopped")
	assert_false(FileAccess.file_exists(Reachability.PID_FILE), "and the note is gone")
	OS.kill(other)
