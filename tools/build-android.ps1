param(
    [string]$SdkRoot = "$env:LOCALAPPDATA/Android/Sdk",
    [ValidateRange(26,35)][int]$TestTargetSdk = 35,
    [switch]$UnitOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousGradleHome = $env:GRADLE_USER_HOME
$previousAndroidHome = $env:ANDROID_HOME
$previousAndroidUserHome = $env:ANDROID_USER_HOME
$previousAndroidSdkHome = $env:ANDROID_SDK_HOME
try {
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.tools/gradle-home'
    $env:ANDROID_HOME = $SdkRoot
    $env:ANDROID_SDK_HOME = Join-Path $projectRoot '.tools/android-legacy'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    New-Item -ItemType Directory -Force -Path $env:ANDROID_USER_HOME,$env:ANDROID_SDK_HOME | Out-Null
    & node (Join-Path $projectRoot 'tools/generate-kotlin.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Kotlin generation failed.' }
    [string[]]$androidBuildTasks = if ($UnitOnly) {@(':android:testDebugUnitTest')} else {@(':core:test',':android:testDebugUnitTest',':android:assembleDebug',':android:assembleDebugAndroidTest',':android:lintDebug')}
    & (Join-Path $projectRoot 'kotlin/gradlew.bat') -p (Join-Path $projectRoot 'kotlin') "-PdeviceReadoutTestTargetSdk=$TestTargetSdk" @androidBuildTasks --no-daemon --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android build verification failed.' }
} finally {
    $env:GRADLE_USER_HOME = $previousGradleHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:ANDROID_USER_HOME = $previousAndroidUserHome
    $env:ANDROID_SDK_HOME = $previousAndroidSdkHome
}
