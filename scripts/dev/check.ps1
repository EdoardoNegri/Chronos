<#
.SYNOPSIS  Fast validation loop: import, parse-check every script, lint, format check.
Exit code is non-zero if any step fails.
#>
$ErrorActionPreference = 'Continue'
$root = Resolve-Path "$PSScriptRoot/../.."
$godot = "$PSScriptRoot/godot.ps1"
$fail = 0

# pip --user installs land outside PATH; add them for this session only.
foreach ($d in Get-ChildItem "$env:APPDATA/Python/*/Scripts" -ErrorAction SilentlyContinue) { $env:PATH = "$($d.FullName);$env:PATH" }

Write-Host "== import (headless) =="
& $godot --headless --import --quit 2>&1 | Where-Object { $_ -match 'ERROR|SCRIPT ERROR|WARNING' }

Write-Host "== parse check =="
$scripts = Get-ChildItem $root -Recurse -Filter *.gd |
    Where-Object { $_.FullName -notmatch '[\/](addons|\.godot)[\/]' }
foreach ($s in $scripts) {
    $rel = "res://" + ($s.FullName.Substring($root.Path.Length + 1) -replace '\', '/')
    $out = & $godot --headless --check-only --script $rel 2>&1
    if ($LASTEXITCODE -ne 0 -or ($out -match 'SCRIPT ERROR|Parse Error')) {
        Write-Host "FAIL $rel"; $out | Write-Host; $fail++
    }
}
Write-Host ("{0} script(s) checked" -f @($scripts).Count)

$paths = @('scripts', 'scenes') | Where-Object { Test-Path "$root/$_" }
if (Get-Command gdlint -ErrorAction SilentlyContinue) {
    Write-Host "== gdlint =="; gdlint @paths; if ($LASTEXITCODE -ne 0) { $fail++ }
    Write-Host "== gdformat --check =="; gdformat --check @paths; if ($LASTEXITCODE -ne 0) { $fail++ }
} else { Write-Host "(gdtoolkit not on PATH; skipping lint/format)" }

if ($fail) { Write-Host "FAILED ($fail)"; exit 1 } else { Write-Host "OK" }
