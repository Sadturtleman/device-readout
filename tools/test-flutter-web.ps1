param([string]$FlutterRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$buildArguments = @{}
if ($FlutterRoot) { $buildArguments.FlutterRoot = $FlutterRoot }
Push-Location $projectRoot
try {
    & (Join-Path $PSScriptRoot 'build-flutter-web.ps1') @buildArguments
    & (Join-Path $PSScriptRoot 'build-flutter-web.ps1') @buildArguments -Target test_support/web_contracts.dart -OutputName web-contracts -BaseHref /contracts/
    node --test tools/test-flutter-browser.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter browser verification failed.' }
} finally {
    Pop-Location
}
