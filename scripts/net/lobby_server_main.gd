extends Node
## Runs this game as a lobby server instead of a game: no window is needed.
##
##   godot --headless --path <project> res://scenes/lobby_server.tscn -- --port 9080
##
## (scripts/dev/server.ps1 does this.) The `Online` autoload becomes the server (see Lobby). Players
## connect with the address of this computer; for someone far away, a tunnel such as
## `cloudflared tunnel --url http://localhost:9080` gives a public address that leads here.


func _ready() -> void:
	var port := Lobby.DEFAULT_PORT
	var args := OS.get_cmdline_user_args()
	var at := args.find("--port")
	if at >= 0 and at + 1 < args.size() and args[at + 1].is_valid_int():
		port = int(args[at + 1])
	var error: Error = Online.start_server(port)
	if error != OK:
		printerr("Could not listen on port %d: %s" % [port, error_string(error)])
		get_tree().quit(1)
		return
	print("Lobby server listening on port %d. Players connect to ws://<this computer>:%d" % [port, port])
