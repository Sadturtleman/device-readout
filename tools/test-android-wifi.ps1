param(
    [Parameter(Mandatory)][string]$SdkRoot,
    [Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$AvdName,
    [int]$ServerPort = 5047
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adbPath = Join-Path $SdkRoot 'platform-tools/adb.exe'
$identity = & $adbPath -P $ServerPort -s $Serial emu avd name
if ($LASTEXITCODE -ne 0 -or $identity[0].Trim() -ne $AvdName -or -not $AvdName.StartsWith('DeviceReadout_')) {throw 'Wi-Fi fixture requires the exact project-owned AVD.'}
$original = (& $adbPath -P $ServerPort -s $Serial shell settings get global wifi_on).Trim()
if ($original -notin @('1','2')) {throw 'This Wi-Fi fixture requires initially enabled Wi-Fi.'}
$deviceApi = [int](& $adbPath -P $ServerPort -s $Serial shell getprop ro.build.version.sdk)
$component = 'dev.devicereadout.android.test/dev.devicereadout.android.ContractInstrumentation'
$resultPath = Join-Path $projectRoot ".tools/$AvdName-wifiEvents-results.txt"
$instrumentation = $null
try {
    $instrumentation = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode','wifiEvents',$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $disconnected = $false
    $reconnected = $false
    while (-not $instrumentation.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $output = Get-Content -LiteralPath $resultPath -Raw
        if ($deviceApi -ge 29 -and -not $disconnected -and $output -match 'deviceReadoutAwaiting=wifiDisconnect') {
            & $adbPath -P $ServerPort -s $Serial shell svc wifi disable | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Wi-Fi fixture disconnect failed.'}
            $disconnected = $true
        }
        if ($deviceApi -ge 29 -and $disconnected -and -not $reconnected -and $output -match 'deviceReadoutAwaiting=wifiReconnect') {
            & $adbPath -P $ServerPort -s $Serial shell svc wifi enable | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Wi-Fi fixture reconnect failed.'}
            $reconnected = $true
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $instrumentation.WaitForExit(1000)) {throw 'Wi-Fi instrumentation did not finish.'}
    Get-Content -LiteralPath $resultPath
} finally {
    if ($instrumentation -and -not $instrumentation.HasExited) {$instrumentation.Kill()}
    if ($deviceApi -ge 29) {
        & $adbPath -P $ServerPort -s $Serial shell svc wifi enable | Out-Null
    } else {
        # A separate test-only request also restores state after an aborted fixture.
        $restore = (& $adbPath -P $ServerPort -s $Serial shell am instrument -w -e mode wifiRestore $component) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $restore -notmatch 'INSTRUMENTATION_RESULT: deviceReadoutStatus=passed') {throw 'Wi-Fi restoration request failed.'}
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $restored = (& $adbPath -P $ServerPort -s $Serial shell settings get global wifi_on).Trim()
        if ($restored -eq $original) {break}
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($restored -ne $original) {throw 'Wi-Fi setting was not restored.'}
}
