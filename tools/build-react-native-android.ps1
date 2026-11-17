param([string]$SdkRoot = 'C:/Users/rugsn/AppData/Local/Android/Sdk')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskNames = @('GRADLE_USER_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_USER_HOME','ANDROID_SDK_HOME','DEVICE_READOUT_REACT_NATIVE_ROOT')
$taskPrevious = @{}
foreach ($taskName in $taskNames) {$taskPrevious[$taskName] = [Environment]::GetEnvironmentVariable($taskName,'Process')}
try {
    & node (Join-Path $taskRoot 'packages/react-native/scripts/prepare-package.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Shared source preparation failed.' }
    $env:GRADLE_USER_HOME = Join-Path $taskRoot '.tools/gradle-home'
    $env:ANDROID_HOME = (Resolve-Path -LiteralPath $SdkRoot).Path
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    $env:ANDROID_SDK_HOME = Join-Path $taskRoot '.tools/android-legacy'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    $env:DEVICE_READOUT_REACT_NATIVE_ROOT = Join-Path $taskRoot '.tools/react-native-0.88/node_modules/react-native'
    & (Join-Path $taskRoot 'flutter/device_readout_flutter/example/android/gradlew.bat') -p (Join-Path $taskRoot 'packages/react-native/android') compileDebugKotlin compileDebugJavaWithJavac --no-daemon --console=plain
    if ($LASTEXITCODE -ne 0) {throw 'React Native Android binding compilation failed.'}
} finally {
    foreach ($taskName in $taskNames) {[Environment]::SetEnvironmentVariable($taskName,$taskPrevious[$taskName],'Process')}
}
