<#
.SYNOPSIS  Thin wrapper around the Godot console binary for this project.
.EXAMPLE   ./scripts/dev/godot.ps1 --version
.EXAMPLE   ./scripts/dev/godot.ps1 -e          # open editor (GUI binary)
Resolution order: $env:GODOT_BIN, ~/Tools/Godot/*/ (newest), PATH.
#>
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot/../.."

function Find-Godot([bool]$gui) {
    $pattern = if ($gui) { 'Godot_*_win64.exe' } else { 'Godot_*_win64_console.exe' }
    if ($env:GODOT_BIN) { return $env:GODOT_BIN }
    $hit = Get-ChildItem "$env:USERPROFILE/Tools/Godot" -Recurse -Filter $pattern -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "Godot not found. Set `$env:GODOT_BIN or install to ~/Tools/Godot/<version>/"
}

$gui = $args -contains '-e' -or $args -contains '--editor'
& (Find-Godot $gui) --path $root @args
exit $LASTEXITCODE
