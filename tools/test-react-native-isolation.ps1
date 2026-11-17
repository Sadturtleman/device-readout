param([string]$SdkRoot = "$env:LOCALAPPDATA/Android/Sdk", [string]$Serial = 'emulator-5584', [int]$ServerPort = 5047, [switch]$InstalledPackage)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskAdb = Join-Path (Resolve-Path -LiteralPath $SdkRoot).Path 'platform-tools/adb.exe'
$taskPackage = 'dev.devicereadout.verification.isolation'
$taskComponent = "$taskPackage/dev.devicereadout.verification.MainActivity"
$taskReceiver = "$taskPackage/dev.devicereadout.verification.IsolationReleaseReceiver"
function Invoke-IsolationAdb {
    param([string[]]$Arguments)
    $output = & $taskAdb -P $ServerPort -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) {throw "adb failed: $Arguments"}
    return $output
}
if ($Serial -notmatch '^emulator-\d+$') {throw 'Use a project-owned emulator.'}
$taskAvd = ((Invoke-IsolationAdb @('emu','avd','name')) | Select-Object -First 1).Trim()
if ($taskAvd -notmatch '^DeviceReadout_API(26|36)$' -or -not (Test-Path -LiteralPath (Join-Path $taskRoot ".tools/android-avd/$taskAvd.avd/config.ini"))) {throw 'The AVD is not a supported project fixture.'}
if (((Invoke-IsolationAdb @('shell','getprop','sys.boot_completed')) -join '').Trim() -ne '1') {throw 'AVD has not booted.'}
$taskPrefix = Join-Path $taskRoot ".tools/rn-isolation-$taskAvd"
$taskApk = Join-Path $taskRoot 'packages/react-native/example/android/app/build/outputs/apk/isolation/app-isolation.apk'
if ($InstalledPackage) {
    $taskPrefix = Join-Path $taskRoot ".tools/rn-installed-isolation-$taskAvd"
    $taskApk = Join-Path $taskRoot '.tools/rn-installed/android/app/build/outputs/apk/isolation/app-isolation.apk'
}
$script:isolationLog = ''
$script:isolationCase = ''
function Read-IsolationLog {
    $script:isolationLog = (Invoke-IsolationAdb @('logcat','-d','-v','brief','-s','ReactNativeJS:I','DRIsolation:I','AndroidRuntime:E')) -join "`n"
    $script:isolationLog | Set-Content -LiteralPath "$taskPrefix-$script:isolationCase.log" -Encoding utf8
    if ($script:isolationLog -match '"status":"failed"|FATAL EXCEPTION|"type":"expired"') {throw "Isolation app failed; see $taskPrefix-$script:isolationCase.log"}
    return $script:isolationLog
}
function Read-IsolationEvents {
    param([string]$Log)
    return @([regex]::Matches($Log, 'DEVICE_READOUT_ISOLATION_(NATIVE|CLOSED|RESULT) (\{[^\r\n]*\})') | ForEach-Object {
        [pscustomobject]@{channel = $_.Groups[1].Value; value = ($_.Groups[2].Value | ConvertFrom-Json); offset = $_.Index}
    })
}
function Wait-IsolationState {
    param([scriptblock]$Condition, [string]$Description, [int]$TimeoutSeconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {if (& $Condition) {return};Start-Sleep -Milliseconds 100} while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description"
}
function Clear-IsolationLog {
    # A successful clear is required: previous runs must not satisfy this run.
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        $output = & $taskAdb -P $ServerPort -s $Serial logcat -c 2>&1
        if ($LASTEXITCODE -eq 0) {return}
        Start-Sleep -Milliseconds 250
    }
    throw "Could not clear logcat before verification: $output"
}
$taskResults = @()
try {
    Invoke-IsolationAdb @('install','-r',$taskApk) | Out-Null
    foreach ($case in @('get','watch','close')) {
        $script:isolationCase = $case
        Invoke-IsolationAdb @('shell','am','force-stop',$taskPackage) | Out-Null
        Clear-IsolationLog
        Invoke-IsolationAdb @('shell','am','start','-W','-n',$taskComponent,'--es','isolationCase',$case) | Out-Null
        Wait-IsolationState { (Read-IsolationLog) -match 'DEVICE_READOUT_ISOLATION_RESULT ' } "$case JS result"
        $events = @(Read-IsolationEvents (Read-IsolationLog))
        $factory = @($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -eq 'factory'})
        $entered = @($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -eq 'entered'})
        $closed = @($events | Where-Object channel -eq 'CLOSED')
        $results = @($events | Where-Object channel -eq 'RESULT')
        if ($factory.Count -ne 1 -or $entered.Count -ne 1 -or $closed.Count -ne 1 -or $results.Count -ne 1) {throw "Missing or duplicate events for $case"}
        if ($factory[0].value.mainThread -ne $false -or $entered[0].value.mainThread -ne $false) {throw 'Factory or collection ran on Android main thread.'}
        if ($closed[0].value.case -ne $case -or $results[0].value.case -ne $case -or $results[0].value.status -ne 'passed') {throw 'Incorrect scenario result.'}
        if ($entered[0].offset -ge $closed[0].offset -or $closed[0].offset -ge $results[0].offset) {throw 'Collection did not stay pending through close.'}
        if (@($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -in @('returned','released','workerStopped')}).Count -ne 0) {throw 'Collector finished before external release.'}
        $ui = @($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -eq 'ui' -and $_.offset -gt $entered[0].offset -and $_.offset -lt $results[0].offset})
        $uiAfterClose = @($ui | Where-Object {$_.offset -gt $closed[0].offset})
        if ($ui.Count -lt 3 -or $uiAfterClose.Count -lt 1) {throw 'Android UI loop did not progress during blocked collection and after close.'}
        $result = $results[0].value
        $expectedCode = if ($case -eq 'close') {'EntityRemoved'} else {'ReadTimeout'}
        if ($result.code -ne $expectedCode -or $result.closeMs -ge 250 -or $result.jsTicksDuringRead -lt 3 -or $result.jsTicksAfterClose -lt 3) {throw 'JS progress/deadline/close result is invalid.'}
        if ($result.elapsedMs -ge 5000 -or ($case -ne 'close' -and $result.elapsedMs -lt 650)) {throw 'Read did not settle within the expected deadline window.'}
        Invoke-IsolationAdb @('shell','am','broadcast','-n',$taskReceiver,'-a','dev.devicereadout.verification.RELEASE_ISOLATION') | Out-Null
        Wait-IsolationState { (Read-IsolationLog) -match '"type":"workerStopped"' } "$case collector worker termination" 8
        $events = @(Read-IsolationEvents (Read-IsolationLog))
        $released = @($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -eq 'released'})
        $returned = @($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -eq 'returned'})
        $stopped = @($events | Where-Object {$_.channel -eq 'NATIVE' -and $_.value.type -eq 'workerStopped'})
        if ($released.Count -ne 1 -or $returned.Count -ne 1 -or $stopped.Count -ne 1 -or $stopped[0].value.stopped -ne $true) {throw 'Collector worker did not stop after release.'}
        if ($released[0].offset -le $results[0].offset -or $returned[0].offset -le $released[0].offset -or $stopped[0].offset -le $returned[0].offset) {throw 'Unexpected external-release/worker-cleanup ordering.'}
        if (@($events | Where-Object channel -eq 'RESULT').Count -ne 1) {throw 'A late result escaped after termination.'}
        $taskResults += [ordered]@{
            case = $case; result = $result; factoryOffMainThread = $true; collectionOffMainThread = $true
            androidUiTicksWhileHeld = $ui.Count; androidUiTicksAfterCloseWhileHeld = $uiAfterClose.Count
            settledBeforeExternalRelease = $true; workerStoppedAfterRelease = $true
            nativeHoldMs = $returned[0].value.uptimeMs - $entered[0].value.uptimeMs
        }
        Write-Output "Passed blocked-native $case on $taskAvd; elapsed=$($result.elapsedMs)ms, close=$($result.closeMs)ms, UI ticks=$($ui.Count)."
    }
    [ordered]@{
        avd = $taskAvd; api = ((Invoke-IsolationAdb @('shell','getprop','ro.build.version.sdk')) -join '').Trim()
        apkSha256 = (Get-FileHash -LiteralPath $taskApk -Algorithm SHA256).Hash.ToLowerInvariant()
        installedConsumer = [bool]$InstalledPackage
        scenarios = $taskResults
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$taskPrefix.json" -Encoding utf8
} finally {
    Invoke-IsolationAdb @('shell','am','force-stop',$taskPackage) | Out-Null
}
