param([string]$DartPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $DartPath) { $DartPath = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter/bin/cache/dart-sdk/bin/dart.exe' }
$previousPubCache = $env:PUB_CACHE
Push-Location $projectRoot
try {
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    & $DartPath pub get --offline --directory dart/device_readout
    if ($LASTEXITCODE -ne 0) { throw 'Dart dependency resolution failed.' }
    New-Item -ItemType Directory -Force -Path '.tools/dart-checks' | Out-Null
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Browser worker build failed.' }
    & $DartPath compile js dart/device_readout/test/browser_contracts.dart -o .tools/dart-checks/browser-contracts.js
    if ($LASTEXITCODE -ne 0) { throw 'Dart browser consumer compilation failed.' }
    node --test tools/test-dart-browser.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Dart browser contracts failed.' }
} finally { $env:PUB_CACHE = $previousPubCache; Pop-Location }
