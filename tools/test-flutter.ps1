param([string]$FlutterRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $FlutterRoot) {
    $FlutterRoot = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter'
}
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$dartExecutable = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$toolSnapshot = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
if (-not (Test-Path -LiteralPath $toolSnapshot -PathType Leaf)) {
    throw 'Supply a complete Flutter 3.47.x SDK with a prepared tool snapshot.'
}
$oldFlutterRoot = $env:FLUTTER_ROOT
$oldPubCache = $env:PUB_CACHE
function Invoke-LocalFlutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
    & $dartExecutable $toolSnapshot --suppress-analytics --no-version-check @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: $FlutterArguments" }
}
Push-Location (Join-Path $projectRoot 'flutter/device_readout_flutter')
try {
    $env:FLUTTER_ROOT = $FlutterRoot
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    Invoke-LocalFlutter --version
    Invoke-LocalFlutter pub get --offline
    # Use the SDK analyzer directly; the Flutter language-server wrapper attempts
    # to write a user-global telemetry log in this environment despite suppression.
    & $dartExecutable analyze .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter package analysis failed.' }
    Invoke-LocalFlutter test --no-pub --reporter expanded --concurrency=1 --timeout=30s
} finally {
    $env:FLUTTER_ROOT = $oldFlutterRoot
    $env:PUB_CACHE = $oldPubCache
    Pop-Location
}
