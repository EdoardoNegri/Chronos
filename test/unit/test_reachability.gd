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
	reachability.program = "cmd.exe"
	reachability.arguments = PackedStringArray(["/c", "echo no address here 1>&2"])
	add_child_autofree(reachability)
	watch_signals(reachability)
	reachability.start(9999)
	await wait_for_signal(reachability.failed, 8.0)
	assert_signal_emitted(reachability, "failed")
	assert_signal_not_emitted(reachability, "address_found")
