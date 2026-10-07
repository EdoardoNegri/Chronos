<#
.SYNOPSIS  Run the game (or one scene) with the GUI binary, or headless for N frames.
.EXAMPLE   ./scripts/dev/run.ps1                       # main scene, windowed
.EXAMPLE   ./scripts/dev/run.ps1 res://scenes/x.tscn   # specific scene
.EXAMPLE   ./scripts/dev/run.ps1 -Headless -Frames 120 # smoke test; surfaces runtime errors
#>
param([string]$Scene = '', [switch]$Headless, [int]$Frames = 120)
$a = @()
if ($Headless) { $a += '--headless', '--quit-after', $Frames }
if ($Scene) { $a += $Scene }
& "$PSScriptRoot/godot.ps1" @a
exit $LASTEXITCODE
