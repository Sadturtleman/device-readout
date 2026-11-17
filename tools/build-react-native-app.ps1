param([string]$SdkRoot, [string]$GradleHome, [ValidateSet('Debug','Isolation')][string]$Variant = 'Debug')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
if (-not $SdkRoot) {$SdkRoot = Join-Path $taskRoot '.tools/android-sdk'}
if (-not $GradleHome) {$GradleHome = Join-Path $taskRoot '.tools/gradle-home'}
$taskNames = @('GRADLE_USER_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_USER_HOME','ANDROID_SDK_HOME','NODE_PATH')
$taskPrevious = @{}
foreach ($taskName in $taskNames) {$taskPrevious[$taskName] = [Environment]::GetEnvironmentVariable($taskName,'Process')}
try {
    & node (Join-Path $taskRoot 'packages/react-native/scripts/prepare-package.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Shared source preparation failed.' }
    $env:GRADLE_USER_HOME = [System.IO.Path]::GetFullPath($GradleHome)
    $env:ANDROID_HOME = (Resolve-Path -LiteralPath $SdkRoot).Path
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    $env:ANDROID_SDK_HOME = Join-Path $taskRoot '.tools/android-legacy'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    $env:NODE_PATH = Join-Path $taskRoot '.tools/react-native-0.88/node_modules'
    & node (Join-Path $taskRoot 'node_modules/typescript/bin/tsc') -p (Join-Path $taskRoot 'packages/core/tsconfig.json')
    if ($LASTEXITCODE -ne 0) {throw 'Core TypeScript compilation failed.'}
    & node (Join-Path $taskRoot '.tools/react-native-0.88/node_modules/typescript/bin/tsc') -p (Join-Path $taskRoot 'packages/react-native/example/tsconfig.json')
    if ($LASTEXITCODE -ne 0) {throw 'React Native verification app type checking failed.'}
    $taskAndroid = Join-Path $taskRoot 'packages/react-native/example/android'
    & (Join-Path $taskAndroid 'gradlew.bat') -p $taskAndroid ":app:assemble$Variant" --no-daemon --console=plain
    if ($LASTEXITCODE -ne 0) {throw 'React Native verification APK build failed.'}
} finally {
    foreach ($taskName in $taskNames) {[Environment]::SetEnvironmentVariable($taskName,$taskPrevious[$taskName],'Process')}
}
