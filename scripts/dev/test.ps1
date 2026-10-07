<#
.SYNOPSIS  Run GUT tests headless. Non-zero exit on failure.
.EXAMPLE   ./scripts/dev/test.ps1
.EXAMPLE   ./scripts/dev/test.ps1 -Select test_player   # only matching script names
#>
param([string]$Select = '')
$a = @('--headless', '-s', 'res://addons/gut/gut_cmdln.gd', '-gexit')
if ($Select) { $a += "-gselect=$Select" }
& "$PSScriptRoot/godot.ps1" @a
exit $LASTEXITCODE
