param(
    [string]$FlutterRoot,
    [string]$Target = 'lib/main.dart',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$OutputName = 'web',
    [string]$BaseHref = '/'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $FlutterRoot) { $FlutterRoot = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter' }
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$dartExecutable = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$toolSnapshot = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$exampleRoot = Join-Path $projectRoot 'flutter/device_readout_flutter/example'
$oldFlutterRoot = $env:FLUTTER_ROOT
$oldPubCache = $env:PUB_CACHE
function Invoke-LocalFlutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
    & $dartExecutable $toolSnapshot --suppress-analytics --no-version-check @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: $FlutterArguments" }
}
Push-Location $projectRoot
try {
    $env:FLUTTER_ROOT = $FlutterRoot
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Browser worker build failed.' }
    Set-Location -LiteralPath $exampleRoot
    Invoke-LocalFlutter pub get --offline
    & $dartExecutable analyze .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter example analysis failed.' }
    Invoke-LocalFlutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run "--target=$Target" "--output=build/$OutputName" "--base-href=$BaseHref"
    $outputPath = Join-Path $exampleRoot "build/$OutputName"
    Copy-Item -LiteralPath (Join-Path $projectRoot 'packages/web/dist/dart-worker.js') -Destination (Join-Path $outputPath 'device-readout-dart-worker.js')
    Write-Output "Flutter web application and DeviceReadout worker: $outputPath"
} finally {
    $env:FLUTTER_ROOT = $oldFlutterRoot
    $env:PUB_CACHE = $oldPubCache
    Pop-Location
}
