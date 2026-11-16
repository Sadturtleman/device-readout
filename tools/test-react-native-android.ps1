param([string]$SdkRoot = "$env:LOCALAPPDATA/Android/Sdk", [string]$Serial = 'emulator-5584', [int]$ServerPort = 5047)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskAdb = Join-Path (Resolve-Path -LiteralPath $SdkRoot).Path 'platform-tools/adb.exe'
$taskPackage = 'dev.devicereadout.verification'
function Invoke-RnAdb {
    param([string[]]$Arguments)
    $output = & $taskAdb -P $ServerPort -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) {throw "adb failed: $Arguments"}
    return $output
}
if ($Serial -notmatch '^emulator-\d+$') {throw 'Use a project-owned emulator.'}
$taskAvd = ((Invoke-RnAdb @('emu','avd','name')) | Select-Object -First 1).Trim()
if ($taskAvd -notmatch '^DeviceReadout_API(26|28|36)(_Hinge)?$' -or -not (Test-Path -LiteralPath (Join-Path $taskRoot ".tools/android-avd/$taskAvd.avd/config.ini"))) {throw 'The AVD is not a project fixture.'}
if (((Invoke-RnAdb @('shell','getprop','sys.boot_completed')) -join '').Trim() -ne '1') {throw 'AVD has not booted.'}
$taskPrefix = Join-Path $taskRoot ".tools/rn-android-$taskAvd"
$taskApk = Join-Path $taskRoot 'packages/react-native/example/android/app/build/outputs/apk/debug/app-debug.apk'
$taskWindow = (Invoke-RnAdb @('shell','wm','size')) -join "`n"
if ($taskWindow -match 'Override size:') {throw 'Fixture has an existing window size override; restore it before running.'}
$script:rnLog = ''
$script:rnSensors = ''
$script:rnUid = ''
function Read-RnLog {
    $script:rnLog = (Invoke-RnAdb @('logcat','-d','-v','brief','-s','ReactNativeJS:I','AndroidRuntime:E')) -join "`n"
    $script:rnLog | Set-Content -LiteralPath "$taskPrefix.log" -Encoding utf8
    if ($script:rnLog -match '"status":"failed"' -or $script:rnLog -match 'FATAL EXCEPTION') {throw "RN app failed; see $taskPrefix.log"}
    return $script:rnLog
}
function Read-RnResults {
    $log = Read-RnLog
    return @([regex]::Matches($log, 'DEVICE_READOUT_TEST (\{[^\r\n]*\})') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json})
}
function Has-RnSensor {
    $script:rnSensors = (Invoke-RnAdb @('shell','dumpsys','sensorservice')) -join "`n"
    if ($script:rnSensors -notmatch '\d+ (active connections|open event connections)' -or $script:rnSensors -notmatch 'Previous Registrations:') {throw 'Unknown sensor diagnostic format.'}
    return (($script:rnSensors -split 'Previous Registrations:',2)[0]) -match "dev\.devicereadout\.android\.AndroidSensors\s*\|[^\r\n]*\buid\s+$script:rnUid\b"
}
function Wait-RnState {
    param([scriptblock]$Condition, [string]$Description, [int]$TimeoutSeconds = 30)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {if (& $Condition) {return};Start-Sleep -Milliseconds 250} while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description"
}
$taskResized = $false
$taskPanelExpanded = $false
try {
    Invoke-RnAdb @('install','-r',$taskApk) | Out-Null
    $identity = (Invoke-RnAdb @('shell','pm','list','packages','-U',$taskPackage)) -join "`n"
    # pm's filter is a substring match and also returns the .isolation application.
    $identities = [regex]::Matches($identity, ('(?m)^package:' + [regex]::Escape($taskPackage) + '\s+uid:(\d+)\s*$'))
    if ($identities.Count -ne 1) {throw 'Cannot identify the exact installed app UID.'}
    $script:rnUid = $identities[0].Groups[1].Value
    Invoke-RnAdb @('shell','am','force-stop',$taskPackage) | Out-Null
    # API 26 logd can transiently reject a clear immediately after package installation.
    # Require a successful clear before launch so old runs cannot satisfy the assertions.
    $taskLogCleared = $false
    for ($taskAttempt = 0; $taskAttempt -lt 5; $taskAttempt++) {
        $taskClearOutput = & $taskAdb -P $ServerPort -s $Serial logcat -c 2>&1
        if ($LASTEXITCODE -eq 0) {$taskLogCleared = $true;break}
        Start-Sleep -Milliseconds 250
    }
    if (-not $taskLogCleared) {throw "Could not clear logcat before verification: $taskClearOutput"}
    Invoke-RnAdb @('shell','am','start','-W','-n',"$taskPackage/.MainActivity") | Out-Null
    Wait-RnState { (Read-RnLog) -match 'DEVICE_READOUT_READY ' } 'baseline scenarios'
    $baseline = @(Read-RnResults)
    $expected = @('hermes-runtime','native-ram','immutable-settings-and-native-watch','native-discovery-and-context-ownership','mixed-native-and-app-inventory','app-observed-viewport','observed-exact-integer-roundtrip','app-permission-coordination','independent-failure-sources','app-sensor-source-lifecycle','app-sensor-source-failure-and-close','native-sensor-observation')
    foreach ($name in $expected) {if (@($baseline | Where-Object {$_.name -eq $name -and $_.status -eq 'passed'}).Count -ne 1) {throw "Missing or duplicated baseline: $name"}}
    $memory = (Invoke-RnAdb @('shell','cat','/proc/meminfo')) -join "`n"
    $memory | Set-Content -LiteralPath "$taskPrefix-meminfo.txt" -Encoding utf8
    if ($memory -notmatch 'MemTotal:\s+(\d+)\s+kB') {throw 'Kernel memory evidence unavailable.'}
    $kernelBytes = [System.Numerics.BigInteger]::Parse($Matches[1]) * 1024
    $ram = $baseline | Where-Object name -eq 'native-ram'
    if ([System.Numerics.BigInteger]::Parse($ram.detail.kernelAccessibleBytes) -ne $kernelBytes) {throw 'Native RAM disagrees with /proc/meminfo.'}
    Wait-RnState {Has-RnSensor} 'native foreground sensor registration'
    $script:rnSensors | Set-Content -LiteralPath "$taskPrefix-foreground-sensors.txt" -Encoding utf8
    $taskPanelExpanded = $true
    Invoke-RnAdb @('shell','cmd','statusbar','expand-notifications') | Out-Null
    Wait-RnState {(Read-RnLog) -match 'DEVICE_READOUT_FOCUS .*"state":"blur","appState":"active"'} 'notification-panel focus loss while active'
    Wait-RnState {@((Read-RnResults) | Where-Object name -eq 'actual-focus-loss-keeps-sensors').Count -gt 0} 'fresh sensor sample during focus loss'
    if (-not (Has-RnSensor)) {throw 'Focus loss removed the native sensor registration.'}
    $script:rnSensors | Set-Content -LiteralPath "$taskPrefix-unfocused-sensors.txt" -Encoding utf8
    Invoke-RnAdb @('shell','cmd','statusbar','collapse') | Out-Null
    $taskPanelExpanded = $false
    Invoke-RnAdb @('shell','wm','size','640x320') | Out-Null
    $taskResized = $true
    Wait-RnState { @((Read-RnResults) | Where-Object name -eq 'actual-window-change').Count -gt 0 } 'actual window observation'
    $initial = ($baseline | Where-Object name -eq 'app-observed-viewport').detail.size
    $changed = @(Read-RnResults | Where-Object name -eq 'actual-window-change')[-1].detail.size
    if ($initial.width -eq $changed.width -and $initial.height -eq $changed.height) {throw 'Window did not change.'}
    Invoke-RnAdb @('shell','input','keyevent','KEYCODE_HOME') | Out-Null
    Wait-RnState {(Read-RnLog) -match 'DEVICE_READOUT_LIFECYCLE .*"state":"background"'} 'actual background callback'
    Wait-RnState {-not (Has-RnSensor)} 'native sensor release while backgrounded'
    $script:rnSensors | Set-Content -LiteralPath "$taskPrefix-background-sensors.txt" -Encoding utf8
    Invoke-RnAdb @('shell','am','start','-W','-n',"$taskPackage/.MainActivity") | Out-Null
    Wait-RnState {Has-RnSensor} 'native sensor registration after resume'
    Wait-RnState {@((Read-RnResults) | Where-Object name -eq 'actual-sensor-resume').Count -gt 0} 'fresh sample after actual resume'
    $script:rnSensors | Set-Content -LiteralPath "$taskPrefix-resumed-sensors.txt" -Encoding utf8
    $report = [ordered]@{
        avd = $taskAvd; api = ((Invoke-RnAdb @('shell','getprop','ro.build.version.sdk')) -join '').Trim()
        installedPackageUid = $script:rnUid
        baseline = $baseline; kernelMemoryAgreement = $true; actualWindowChange = $changed
        nativeSensorReleasedInBackground = $true; nativeSensorRestoredOnResume = $true
        nativeSensorRetainedDuringFocusLoss = $true
        appResults = @(Read-RnResults)
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$taskPrefix.json" -Encoding utf8
    Write-Output "Passed RN/Hermes baseline, kernel agreement, actual window change and native pause/resume on $taskAvd."
} finally {
    if ($script:rnSensors) {$script:rnSensors | Set-Content -LiteralPath "$taskPrefix-last-sensors.txt" -Encoding utf8}
    if ($taskPanelExpanded) {Invoke-RnAdb @('shell','cmd','statusbar','collapse') | Out-Null}
    if ($taskResized) {Invoke-RnAdb @('shell','wm','size','reset') | Out-Null}
    Invoke-RnAdb @('shell','am','force-stop',$taskPackage) | Out-Null
}
