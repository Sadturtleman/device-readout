param([string]$DartPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $DartPath) {
    $DartPath = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter/bin/cache/dart-sdk/bin/dart.exe'
}
if (-not (Test-Path -LiteralPath $DartPath -PathType Leaf)) {
    throw 'Supply -DartPath from Flutter 3.47.x (Dart 3.13.x).'
}
$DartPath = (Resolve-Path -LiteralPath $DartPath).Path
$previousPubCache = $env:PUB_CACHE
Push-Location $projectRoot
try {
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    & $DartPath --version
    if ($LASTEXITCODE -ne 0) { throw 'Unable to run Dart.' }
    node tools/generate-dart.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Dart generation failed.' }
    & $DartPath pub get --offline --directory dart/device_readout
    if ($LASTEXITCODE -ne 0) { throw 'Dart dependency resolution failed.' }
    & $DartPath analyze dart/device_readout
    if ($LASTEXITCODE -ne 0) { throw 'Dart analysis failed.' }
    & $DartPath run dart/device_readout/test/contracts.dart
    if ($LASTEXITCODE -ne 0) { throw 'Dart JIT contract checks failed.' }
    $artifacts = Join-Path $projectRoot '.tools/dart-checks'
    New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
    $executable = Join-Path $artifacts 'contracts.exe'
    & $DartPath compile exe dart/device_readout/test/contracts.dart -o $executable
    if ($LASTEXITCODE -ne 0) { throw 'Dart native compilation failed.' }
    & $executable
    if ($LASTEXITCODE -ne 0) { throw 'Dart compiled contract checks failed.' }
    & $DartPath compile js dart/device_readout/test/web_boundary.dart -o (Join-Path $artifacts 'web-boundary.js')
    if ($LASTEXITCODE -ne 0) { throw 'Dart web compilation failed.' }
    node tools/test-dart-web-boundary.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Dart web boundary check failed.' }
} finally {
    $env:PUB_CACHE = $previousPubCache
    Pop-Location
}
