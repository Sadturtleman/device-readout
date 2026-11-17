param([string]$FlutterRoot, [string]$SdkRoot, [ValidateSet('Android','Web')][string]$Platform = 'Android')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $FlutterRoot) { $FlutterRoot = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter' }
if (-not $SdkRoot) { $SdkRoot = Join-Path $projectRoot '.tools/android-sdk' }
$names = @('FLUTTER_ROOT','PUB_CACHE','GRADLE_USER_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_USER_HOME','ANDROID_SDK_HOME')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:FLUTTER_ROOT = (Resolve-Path -LiteralPath $FlutterRoot).Path
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.tools/gradle-home'
    Push-Location $projectRoot
    try {
        npm run build
        if ($LASTEXITCODE -ne 0) { throw 'Collection worker build failed.' }
    } finally { Pop-Location }
    if ($Platform -eq 'Android') {
        $env:ANDROID_HOME = (Resolve-Path -LiteralPath $SdkRoot).Path
        $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
        $env:ANDROID_SDK_HOME = Join-Path $projectRoot '.tools/android-legacy'
        $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    }
    node (Join-Path $PSScriptRoot 'build-flutter-installed.mjs') "--platform=$($Platform.ToLowerInvariant())"
    if ($LASTEXITCODE -ne 0) { throw 'Installed Flutter package build failed.' }
} finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') } }
