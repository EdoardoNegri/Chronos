<#
.SYNOPSIS  Runs the lobby server, so players can find each other.
.EXAMPLE   ./scripts/dev/server.ps1              # listens on port 9080
.EXAMPLE   ./scripts/dev/server.ps1 -Port 9100
Players on this computer connect to ws://127.0.0.1:9080 (the default). For someone far away, run a
tunnel in a second window, e.g. `cloudflared tunnel --url http://localhost:9080`, and give them the
address it prints (https://....trycloudflare.com) to put in Settings > Online > Server.
Uses the Godot console binary like godot.ps1 does. Stop it with Ctrl+C.
#>
param([int]$Port = 9080)
$ErrorActionPreference = 'Stop'
# The "--" tells Godot that what follows is for the game, not for Godot. It goes in an array so
# PowerShell passes it on instead of using it itself.
$godotArgs = @('--headless', 'res://scenes/lobby_server.tscn', '--', '--port', "$Port")
& "$PSScriptRoot/godot.ps1" @godotArgs
exit $LASTEXITCODE
