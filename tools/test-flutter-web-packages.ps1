param([string]$FlutterRoot, [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
$previous = $env:DEVICE_READOUT_FLUTTER_INSTALLED
try {
    if (-not $SkipBuild) {
        $arguments = @{Platform = 'Web'}
        if ($FlutterRoot) { $arguments.FlutterRoot = $FlutterRoot }
        & (Join-Path $PSScriptRoot 'build-flutter-packages.ps1') @arguments
    }
    $env:DEVICE_READOUT_FLUTTER_INSTALLED = '1'
    node --test tools/test-flutter-browser.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Installed Flutter web consumer failed.' }
} finally {
    $env:DEVICE_READOUT_FLUTTER_INSTALLED = $previous
    Pop-Location
}
