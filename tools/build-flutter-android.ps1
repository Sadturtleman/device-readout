param(
    [string]$FlutterRoot,
    [string]$SdkRoot = "$env:LOCALAPPDATA/Android/Sdk",
    [string]$Target = 'test_support/android_sensors.dart',
    [switch]$NativeUnitOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $FlutterRoot) { $FlutterRoot = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter' }
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$SdkRoot = (Resolve-Path -LiteralPath $SdkRoot).Path
$dartExecutable = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$toolSnapshot = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$names = @('FLUTTER_ROOT', 'PUB_CACHE', 'GRADLE_USER_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_USER_HOME', 'ANDROID_SDK_HOME')
$old = @{}
foreach ($name in $names) { $old[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
function Invoke-LocalFlutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
    & $dartExecutable $toolSnapshot --suppress-analytics --no-version-check @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: $FlutterArguments" }
}
Push-Location (Join-Path $projectRoot 'flutter/device_readout_flutter/example')
try {
    $env:FLUTTER_ROOT = $FlutterRoot
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.tools/gradle-home'
    $env:ANDROID_HOME = $SdkRoot
    $env:ANDROID_SDK_ROOT = $SdkRoot
    $env:ANDROID_SDK_HOME = Join-Path $projectRoot '.tools/android-legacy'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    Invoke-LocalFlutter pub get --offline
    & $dartExecutable analyze .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android example analysis failed.' }
    if ($NativeUnitOnly) {
        & './android/gradlew.bat' -p android :device_readout_flutter:testDebugUnitTest --no-daemon --console=plain
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Android bridge contract tests failed.' }
    } else {
        Invoke-LocalFlutter build apk --debug --target-platform=android-x64 --no-pub "--target=$Target"
    }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $old[$name], 'Process') }
    Pop-Location
}
