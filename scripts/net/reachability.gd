class_name Reachability
extends Node
## Works out an address that someone far away can use to reach a server running on this computer,
## which a home computer normally cannot be reached on. It tries, in order:
##
## 1. A tunnel: the `cloudflared` program comes with the game (bin/cloudflared.exe), so it is
##    started and gives a public https address that leads here. It needs no router settings and no
##    firewall changes.
## 2. The router: it asks the router to open the port (UPnP). Many home routers do; some do not, and
##    internet providers that share one address between customers cannot.
##
## `address_found` says the address (a ws:// or wss:// one) and how it was made; `failed` says why
## neither worked. Call stop() when the server stops, which closes the tunnel and the port.

signal address_found(address: String, how: String)
signal failed(reason: String)

const TUNNEL_SECONDS := 25.0
const TUNNEL_PROGRAM := "cloudflared"
## The tunnel program that comes with the game (Windows only), and where an exported game unpacks
## it: a program cannot be run from inside the game's packed files.
const BUNDLED_PROGRAM := "res://bin/cloudflared.exe"
const UNPACKED_PROGRAM := "user://bin/cloudflared.exe"

## The tunnel program is run with these arguments (a test can run something else in its place).
var program := ""
var arguments := PackedStringArray()
## Whether to ask the router to open the port when there is no tunnel. (A test turns it off, so it
## never changes anyone's router.)
var try_router := true

var _port := 0
var _pid := -1
var _tunnel_thread: Thread
var _tunnel_mutex := Mutex.new()
var _tunnel_address := ""
var _stop_reading := false
var _waited := 0.0
var _trying_tunnel := false
var _upnp_thread: Thread
var _upnp_result: Dictionary = {}
var _upnp: UPNP
var _done := false


## Starts looking for an address for the server listening on `port`.
func start(port: int) -> void:
	_port = port
	_done = false
	if program.is_empty():
		program = find_tunnel_program()
		arguments = PackedStringArray(["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:%d" % port])
	if not program.is_empty():
		_start_tunnel()
	else:
		_start_upnp("There is no tunnel program next to the game, and ")


## Closes the tunnel and the port that were opened.
func stop() -> void:
	_done = true
	_trying_tunnel = false
	_stop_reading = true
	if _pid > 0:
		_kill_process_tree(_pid)
		_pid = -1
	if _tunnel_thread != null and _tunnel_thread.is_started():
		_tunnel_thread.wait_to_finish()
		_tunnel_thread = null
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp != null and _port > 0:
		_upnp.delete_port_mapping(_port, "TCP")
		_upnp = null


func _exit_tree() -> void:
	stop()


## The tunnel program: one put next to the game or in the project folder, else the one that comes
## with the game, else one on the PATH. "" if there is none.
static func find_tunnel_program() -> String:
	var file_name := TUNNEL_PROGRAM + (".exe" if OS.get_name() == "Windows" else "")
	for folder in [OS.get_executable_path().get_base_dir(), ProjectSettings.globalize_path("res://")]:
		var candidate := (folder as String).path_join(file_name)
		if FileAccess.file_exists(candidate):
			return candidate
	var bundled := bundled_program()
	if not bundled.is_empty():
		return bundled
	var found: Array = []
	var command := "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(command, [TUNNEL_PROGRAM], found) == 0 and not found.is_empty():
		var first := str(found[0]).strip_edges().split("\n")[0].strip_edges()
		if not first.is_empty():
			return first
	return ""


## The tunnel program that comes with the game, as a file that can be run, or "" if there is none
## (or it cannot be unpacked). Run from the editor it is used where it is; an exported game has it
## inside its packed files, and unpacks it the first time.
static func bundled_program() -> String:
	if OS.get_name() != "Windows" or not FileAccess.file_exists(BUNDLED_PROGRAM):
		return ""
	var on_disk := ProjectSettings.globalize_path(BUNDLED_PROGRAM)
	if on_disk.is_absolute_path() and FileAccess.file_exists(on_disk):
		return on_disk
	return unpack(BUNDLED_PROGRAM, UNPACKED_PROGRAM)


## Copies `source` to `destination` (unless the same file is already there) and returns where it is
## on disk, or "" if it could not be copied.
static func unpack(source: String, destination: String) -> String:
	var target := ProjectSettings.globalize_path(destination)
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return ""
	var size := input.get_length()
	if FileAccess.file_exists(destination):
		var existing := FileAccess.open(destination, FileAccess.READ)
		if existing != null and existing.get_length() == size:
			return target
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	# Written next to it first, so a copy cut short is never taken for the program.
	var partial := destination + ".part"
	var output := FileAccess.open(partial, FileAccess.WRITE)
	if output == null:
		return ""
	while input.get_position() < size:
		output.store_buffer(input.get_buffer(1 << 20))
	output.close()
	DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(partial), target) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(partial))
		return ""
	return target


## The public address in what a tunnel program printed ("wss://...") or "" if there is none yet.
static func parse_tunnel_address(text: String) -> String:
	var pattern := RegEx.create_from_string("https://[A-Za-z0-9-]+\\.trycloudflare\\.com")
	var found := pattern.search(text)
	return "" if found == null else "wss://" + found.get_string().trim_prefix("https://")


## Whether an address is one that only works inside a home or provider network.
static func is_private_address(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	var first := int(parts[0])
	var second := int(parts[1])
	return (
		first == 10
		or first == 127
		or (first == 172 and second >= 16 and second <= 31)
		or (first == 192 and second == 168)
		or (first == 100 and second >= 64 and second <= 127)
		or (first == 169 and second == 254)
	)


func _process(delta: float) -> void:
	if _done:
		return
	if _trying_tunnel:
		_tunnel_mutex.lock()
		var address := _tunnel_address
		_tunnel_mutex.unlock()
		_waited += delta
		if not address.is_empty():
			_trying_tunnel = false
			_done = true
			address_found.emit(address, "a tunnel")
		elif _waited > TUNNEL_SECONDS or (_pid > 0 and not OS.is_process_running(_pid)):
			_trying_tunnel = false
			_stop_tunnel()
			_start_upnp("The tunnel program did not give an address, and ")
	elif _upnp_thread != null and _upnp_thread.is_started() and not _upnp_thread.is_alive():
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
		_done = true
		if _upnp_result.has("address"):
			_upnp = _upnp_result["upnp"]
			address_found.emit(_upnp_result["address"], "the router")
		else:
			failed.emit(str(_upnp_result.get("error", "No address could be made.")))


func _stop_tunnel() -> void:
	if _pid > 0:
		_kill_process_tree(_pid)
		_pid = -1


func _start_tunnel() -> void:
	# A program given with a folder must be there (one without is looked for on the PATH).
	if (program.contains("/") or program.contains("\\")) and not FileAccess.file_exists(program):
		_start_upnp("The tunnel program is missing, and ")
		return
	var started := OS.execute_with_pipe(program, arguments, false)
	if started.is_empty():
		_start_upnp("The tunnel program could not be started, and ")
		return
	_pid = int(started["pid"])
	_trying_tunnel = true
	_waited = 0.0
	_tunnel_address = ""
	_stop_reading = false
	_tunnel_thread = Thread.new()
	_tunnel_thread.start(_read_tunnel_output.bind(started["stderr"], started["stdio"], _pid))


## Reads what the tunnel program prints (until it ends), so it never stops for a full pipe, and
## remembers the address as soon as it shows up.
func _read_tunnel_output(error_pipe: FileAccess, output_pipe: FileAccess, pid: int) -> void:
	# A pipe does not say it has ended, so an empty read is checked against the program running.
	while not _stop_reading:
		var line := error_pipe.get_line()
		if line.is_empty():
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(50)
			continue
		var address := parse_tunnel_address(line)
		if not address.is_empty():
			_tunnel_mutex.lock()
			_tunnel_address = address
			_tunnel_mutex.unlock()
	if output_pipe != null:
		output_pipe.close()


func _start_upnp(because: String) -> void:
	if not try_router:
		_done = true
		failed.emit(because + "the router was not asked to open a port.")
		return
	_upnp_result = {}
	_upnp_thread = Thread.new()
	_upnp_thread.start(_open_port_on_router.bind(_port, because))


## Asks the router to forward the port here. Runs on its own thread, since looking for a router
## takes a moment.
func _open_port_on_router(port: int, because: String) -> void:
	var upnp := UPNP.new()
	var discovered := upnp.discover(2000, 2, "InternetGatewayDevice")
	var gateway := upnp.get_gateway() if discovered == UPNP.UPNP_RESULT_SUCCESS else null
	if gateway == null or not gateway.is_valid_gateway():
		_upnp_result = {"error": because + "no router answered a request to open a port."}
		return
	if upnp.add_port_mapping(port, port, "Chronos", "TCP", 0) != UPNP.UPNP_RESULT_SUCCESS:
		_upnp_result = {"error": because + "the router refused to open the port."}
		return
	var ip := upnp.query_external_address()
	if ip.is_empty() or is_private_address(ip):
		upnp.delete_port_mapping(port, "TCP")
		_upnp_result = {"error": because + "your internet provider shares one address between many customers, so a port cannot be opened."}
		return
	_upnp_result = {"address": "ws://%s:%d" % [ip, port], "upnp": upnp}


## Stops a program and anything it started, so its output pipe closes. (On Windows, stopping the
## program alone leaves what it started running.)
static func _kill_process_tree(pid: int) -> void:
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"], [])
	else:
		OS.kill(pid)
