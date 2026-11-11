$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousGradleHome = $env:GRADLE_USER_HOME
$previousAndroidSdkHome = $env:ANDROID_SDK_HOME
$previousAndroidUserHome = $env:ANDROID_USER_HOME
try {
    $env:GRADLE_USER_HOME = Join-Path $projectRoot '.tools/gradle-home'
    $env:ANDROID_SDK_HOME = Join-Path $projectRoot '.tools/android-legacy'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    New-Item -ItemType Directory -Force -Path $env:ANDROID_USER_HOME | Out-Null
    & node (Join-Path $projectRoot 'tools/generate-kotlin.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'Kotlin generation failed.' }
    & (Join-Path $projectRoot 'kotlin/gradlew.bat') -p (Join-Path $projectRoot 'kotlin') :core:test --no-daemon --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Kotlin verification failed.' }
} finally {
    $env:GRADLE_USER_HOME = $previousGradleHome
    $env:ANDROID_SDK_HOME = $previousAndroidSdkHome
    $env:ANDROID_USER_HOME = $previousAndroidUserHome
}
