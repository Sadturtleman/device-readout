param([string]$FlutterRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $FlutterRoot) { $FlutterRoot = Join-Path $projectRoot '.tools/flutter-3.47.9/flutter' }
$FlutterRoot = (Resolve-Path -LiteralPath $FlutterRoot).Path
$dartExecutable = Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$toolSnapshot = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$exampleRoot = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'flutter/device_readout_flutter/example')).Path
$buildRoot = [IO.Path]::GetFullPath((Join-Path $exampleRoot 'build'))
if (-not $buildRoot.StartsWith($exampleRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Generated build outputs must remain inside the example directory.'
}
$oldFlutterRoot = $env:FLUTTER_ROOT
$oldPubCache = $env:PUB_CACHE
$oldTestHost = $env:DEVICE_READOUT_WINDOWS_TEST
& (Join-Path $PSScriptRoot 'build-windows-memory-probe.ps1')
$memoryProbe = Join-Path $projectRoot '.tools/windows-memory-probe/Release/device_readout_memory_probe.dll'
if (-not (Test-Path -LiteralPath $memoryProbe -PathType Leaf)) { throw 'Independent process-memory probe missing.' }
function Invoke-LocalFlutter {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)
    & $dartExecutable $toolSnapshot --suppress-analytics --no-version-check @FlutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter command failed: $FlutterArguments" }
}
Push-Location $exampleRoot
try {
    $env:FLUTTER_ROOT = $FlutterRoot
    $env:PUB_CACHE = Join-Path $projectRoot '.tools/dart-pub-cache'
    Invoke-LocalFlutter pub get --offline
    & $dartExecutable analyze .
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows example analysis failed.' }
    $env:DEVICE_READOUT_WINDOWS_TEST = '1'
    Invoke-LocalFlutter build windows --release --no-pub --target=test_support/viewport_windows.dart
    $executable = Join-Path $buildRoot 'windows/x64/runner/Release/device_readout_example.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Windows test host binary missing.' }
    $reportPath = Join-Path $projectRoot ('.tools/flutter-windows-viewport-' + [Guid]::NewGuid().ToString('N') + '.json')
    $testProcess = Start-Process -FilePath $executable -WorkingDirectory (Split-Path $executable -Parent) `
        -ArgumentList ('"' + $reportPath + '" "' + $memoryProbe + '"') -WindowStyle Hidden -PassThru
    try {
        if (-not $testProcess.WaitForExit(55000)) {
            # This is a fixture-owned process with a retained handle, never a name-based kill.
            $testProcess.Refresh()
            if (-not $testProcess.HasExited) {
                $testProcess.Kill()
                $testProcess.WaitForExit()
            }
            throw 'The verification host exceeded its 55-second execution limit.'
        }
        if ($testProcess.ExitCode -ne 0) { throw "Windows test host exited $($testProcess.ExitCode)." }
    } finally { $testProcess.Dispose() }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw 'Windows test host produced no report.' }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Write-Output (Get-Content -LiteralPath $reportPath -Raw)
    if (-not $report.passed -or $report.checks.Count -ne 14) { throw "Windows verification failed; see $reportPath" }
    # Leave a regular example executable after verification. It has no test channel
    # and uses the original application entrypoint.
    $env:DEVICE_READOUT_WINDOWS_TEST = $null
    Invoke-LocalFlutter build windows --release --no-pub --target=lib/main.dart
    Write-Output "14/14 native Windows screen, memory, runtime, OS, power, locale, time-zone and device scenarios passed. Report: $reportPath"
} finally {
    $env:FLUTTER_ROOT = $oldFlutterRoot
    $env:PUB_CACHE = $oldPubCache
    $env:DEVICE_READOUT_WINDOWS_TEST = $oldTestHost
    Pop-Location
}
