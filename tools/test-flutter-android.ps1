param(
    [string]$SdkRoot = "$env:LOCALAPPDATA/Android/Sdk",
    [string]$Serial = 'emulator-5584',
    [int]$ServerPort = 5047,
    [switch]$InstalledPackage
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$adb = Join-Path (Resolve-Path -LiteralPath $SdkRoot).Path 'platform-tools/adb.exe'
$package = 'dev.devicereadout.device_readout_example'
function Invoke-TestAdb {
    param([string[]]$AdbArguments)
    $output = & $adb -P $ServerPort -s $Serial @AdbArguments
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $AdbArguments" }
    return $output
}
if ($Serial -notmatch '^emulator-\d+$') { throw 'Use a project-owned emulator, not a physical device.' }
$avd = ((Invoke-TestAdb -AdbArguments @('emu', 'avd', 'name')) | Select-Object -First 1).Trim()
if ($avd -notmatch '^DeviceReadout_API(26|28|36)(_Hinge)?$' -or
    -not (Test-Path -LiteralPath (Join-Path $projectRoot ".tools/android-avd/$avd.avd/config.ini"))) {
    throw 'The selected AVD is not a project test fixture.'
}
if (((Invoke-TestAdb -AdbArguments @('shell', 'getprop', 'sys.boot_completed')) -join '').Trim() -ne '1') { throw 'The test AVD has not booted.' }
$apk = Join-Path $projectRoot 'flutter/device_readout_flutter/example/build/app/outputs/flutter-apk/app-debug.apk'
$artifactPrefix = "flutter-android-$avd"
if ($InstalledPackage) {
    $apk = Join-Path $projectRoot '.tools/flutter-installed/build/app/outputs/flutter-apk/app-debug.apk'
    $artifactPrefix = "flutter-installed-android-$avd"
}
if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'Build the Android sensor test APK first.' }
$reportPath = Join-Path $projectRoot ".tools/$artifactPrefix-sensors.json"
$report = $null
$batteryOverridden = $false
try {
    Invoke-TestAdb -AdbArguments @('install', '-r', $apk) | Out-Null
    Invoke-TestAdb -AdbArguments @('shell', 'am', 'force-stop', $package) | Out-Null
    Invoke-TestAdb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$package/.MainActivity") | Out-Null
    $appProcess = ((Invoke-TestAdb -AdbArguments @('shell', 'pidof', $package)) -join '').Trim()
    if ($appProcess -notmatch '^\d+$') { throw 'Could not identify the owned test process.' }
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    $activeSeen = $false
    $sentHome = $false
    $requestedResume = $false
    $resumedSeen = $false
    $powerChanged = $false
    $resultParts = @{}
    $resultPartCount = $null
    function Read-ActiveSensors {
        $dump = (Invoke-TestAdb -AdbArguments @('shell', 'dumpsys', 'sensorservice')) -join "`n"
        if ($dump -notmatch '\d+ (active connections|open event connections)' -or $dump -notmatch 'Previous Registrations:') {
            throw 'Unexpected native SensorManager diagnostic format.'
        }
        return ($dump -split 'Previous Registrations:', 2)[0]
    }
    do {
        $lines = @(Invoke-TestAdb -AdbArguments @('logcat', '-d', "--pid=$appProcess", '-v', 'raw'))
        $powerLine = $lines | Where-Object { $_.Contains('DEVICE_READOUT_ANDROID_STATE_POWER_READY:') } | Select-Object -Last 1
        if (-not $powerChanged -and $powerLine) {
            $power = $powerLine.Substring($powerLine.IndexOf('DEVICE_READOUT_ANDROID_STATE_POWER_READY:') + 'DEVICE_READOUT_ANDROID_STATE_POWER_READY:'.Length) | ConvertFrom-Json
            $battery = (Invoke-TestAdb -AdbArguments @('shell', 'dumpsys', 'battery')) -join "`n"
            if ($battery -match 'UPDATES STOPPED') { throw 'An existing battery override is present; leaving it unchanged.' }
            $battery | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-power-before.txt")
            Start-Sleep -Milliseconds 700
            if ($power.source -notin @('external', 'battery')) { throw 'Unexpected initial native power source.' }
            $batteryOverridden = $true
            if ($power.source -eq 'external') {
                Invoke-TestAdb -AdbArguments @('shell', 'dumpsys', 'battery', 'unplug') | Out-Null
            } else {
                Invoke-TestAdb -AdbArguments @('shell', 'dumpsys', 'battery', 'set', 'ac', '1') | Out-Null
            }
            $powerChanged = $true
        }
        if (-not $sentHome -and ($lines | Where-Object { $_.Contains('DEVICE_READOUT_ANDROID_LIFECYCLE_READY') })) {
            $native = Read-ActiveSensors
            if ($native -notmatch 'dev\.devicereadout\.') { throw 'The lifecycle fixture has no active native sensor.' }
            $native | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-lifecycle-before.txt")
            Invoke-TestAdb -AdbArguments @('shell', 'input', 'keyevent', 'KEYCODE_HOME') | Out-Null
            $sentHome = $true
        }
        if ($sentHome -and -not $requestedResume -and ($lines | Where-Object { $_.Contains('DEVICE_READOUT_ANDROID_LIFECYCLE_PAUSED') })) {
            $releaseDeadline = [DateTime]::UtcNow.AddSeconds(5)
            do {
                $native = Read-ActiveSensors
                if ($native -notmatch 'dev\.devicereadout\.') { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $releaseDeadline)
            $native | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-lifecycle-paused.txt")
            if ($native -match 'dev\.devicereadout\.') { throw 'Sensors remained registered after the real Activity paused.' }
            Start-Sleep -Milliseconds 500
            Invoke-TestAdb -AdbArguments @('shell', 'am', 'start', '-W', '-n', "$package/.MainActivity", '-f', '0x10020000') | Out-Null
            $requestedResume = $true
        }
        if ($requestedResume -and -not $resumedSeen -and ($lines | Where-Object { $_.Contains('DEVICE_READOUT_ANDROID_LIFECYCLE_RESUMED') })) {
            $native = Read-ActiveSensors
            if ($native -notmatch 'dev\.devicereadout\.') { throw 'Sensor registration did not resume with the Activity.' }
            $native | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-lifecycle-resumed.txt")
            $resumedSeen = $true
        }
        if (-not $activeSeen -and ($lines | Where-Object { $_.Contains('DEVICE_READOUT_ANDROID_ACTIVE') })) {
            $native = Read-ActiveSensors
            if ($native -match 'dev\.devicereadout\.') {
                $activeSeen = $true
                $native | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-active-sensors.txt")
            }
        }
        foreach ($line in $lines) {
            if ($line -match 'DEVICE_READOUT_ANDROID_RESULT_PART:(\d+)/(\d+):([A-Za-z0-9+/=]+)') {
                $part = [int]$Matches[1]
                $total = [int]$Matches[2]
                $payload = $Matches[3]
                if ($total -lt 1 -or $total -gt 64 -or $part -ge $total -or
                    ($null -ne $resultPartCount -and $total -ne $resultPartCount) -or
                    ($resultParts.ContainsKey($part) -and $resultParts[$part] -cne $payload)) {
                    throw 'Invalid or conflicting test result fragments.'
                }
                $resultPartCount = $total
                $resultParts[$part] = $payload
            }
        }
        if ($null -ne $resultPartCount -and $resultParts.Count -eq $resultPartCount) {
            $payload = (0..($resultPartCount - 1) | ForEach-Object { $resultParts[$_] }) -join ''
            $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
            $report = $json | ConvertFrom-Json
            Set-Content -LiteralPath $reportPath -Value $json -Encoding utf8
            if (-not $report.passed -or $report.checks.Count -ne 29) { throw "Android state/sensor verification failed; see $reportPath" }
            $locale = $report.nativeState.appLocale
            if (($locale.resolvedLocales -join ',') -cne 'zh-Hant-TW,fr-FR' -or
                -not $locale.nativeRestored -or $locale.detachError -cne 'readFailed') {
                throw 'App locale observation or native restoration evidence is incomplete.'
            }
            if (-not $powerChanged) { throw 'A native power transition was not exercised.' }
            $api = ((Invoke-TestAdb -AdbArguments @('shell', 'getprop', 'ro.build.version.sdk')) -join '').Trim()
            $model = ((Invoke-TestAdb -AdbArguments @('shell', 'getprop', 'ro.product.model')) -join '').Trim()
            $memory = (Invoke-TestAdb -AdbArguments @('shell', 'cat', '/proc/meminfo')) -join "`n"
            if ($memory -notmatch 'MemTotal:\s+(\d+)\s+kB') { throw 'No independent kernel memory total.' }
            $memoryBytes = ([long]::Parse($Matches[1]) * 1024).ToString([Globalization.CultureInfo]::InvariantCulture)
            if ([string]$report.nativeState.apiLevel -cne $api -or $report.nativeState.modelName -cne $model -or
                $report.nativeState.kernelAccessibleBytes -cne $memoryBytes) { throw 'Native state fields disagree with independent Android OS reads.' }
            $report.checks = @($report.checks) + 'native state fields agree with independent Android OS reads'
            $present = ((Invoke-TestAdb -AdbArguments @('shell', 'cat', '/sys/devices/system/cpu/present')) -join '').Trim()
            $cpuIndices = @()
            foreach ($range in $present.Split(',')) {
                if ($range -notmatch '^(\d+)(?:-(\d+))?$') { throw 'Invalid independent kernel CPU inventory.' }
                $first = [int]$Matches[1]
                $last = if ($Matches[2]) { [int]$Matches[2] } else { $first }
                if ($last -lt $first -or $last - $first -gt 4096) { throw 'Excessive kernel CPU range.' }
                $cpuIndices += $first..$last
            }
            if (($cpuIndices -join ',') -cne (($report.nativeState.cpuIndices | Sort-Object) -join ',')) {
                throw 'Discovered CPU indices disagree with the independent kernel inventory.'
            }
            # API 26 denies adb shell stat access through /sys/class/net links.
            # The kernel's interface table is independently readable without root.
            $nativeNames = @(Invoke-TestAdb -AdbArguments @('shell', 'cat', '/proc/net/dev') | ForEach-Object {
                if ($_ -match '^\s*([^\s:]+):\s+\d+') { $Matches[1] }
            })
            if ($nativeNames.Count -eq 0) { throw 'No independent kernel network inventory.' }
            foreach ($name in $report.nativeState.interfaceNames) {
                if ($name -cnotin $nativeNames) { throw 'A discovered interface is absent from the independent kernel inventory.' }
            }
            $report.checks = @($report.checks) + 'discovered CPU and interface identities agree with independent kernel reads'
            if (-not $activeSeen) { throw 'Native sensor registration was not independently observed.' }
            if (-not $resumedSeen) { throw 'Native lifecycle suspension and resumption were not observed.' }
            $report.checks = @($report.checks) + 'native lifecycle removes and restores sensor registrations'
            $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(5)
            do {
                $native = Read-ActiveSensors
                if ($native -notmatch 'dev\.devicereadout\.') { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $cleanupDeadline)
            $native | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-released-sensors.txt")
            if ($native -match 'dev\.devicereadout\.') { throw 'A native sensor listener remains after adapter disposal.' }
            $report.checks = @($report.checks) + 'native SensorManager registration and release'
            # The result can precede late platform replies. A dead Dart reply
            # port formerly aborted the whole app after disposal on API 26.
            Start-Sleep -Seconds 2
            $survivingProcess = ((Invoke-TestAdb -AdbArguments @('shell', 'pidof', $package)) -join '').Trim()
            if ($survivingProcess -ne $appProcess) { throw 'The test app did not survive deferred native replies.' }
            $lateLog = @(Invoke-TestAdb -AdbArguments @('logcat', '-d', "--pid=$appProcess", '-v', 'raw'))
            if ($lateLog -match 'Fatal signal|\[FATAL:') { throw 'A fatal native failure followed sensor disposal.' }
            $report.checks = @($report.checks) + 'test process survives late native replies'
            Invoke-TestAdb -AdbArguments @('shell', 'dumpsys', 'battery', 'reset') | Out-Null
            $batteryOverridden = $false
            $report | Add-Member -NotePropertyName installedConsumer -NotePropertyValue ([bool]$InstalledPackage) -Force
            $report | Add-Member -NotePropertyName apkSha256 -NotePropertyValue ((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()) -Force
            $json = $report | ConvertTo-Json -Depth 6 -Compress
            Set-Content -LiteralPath $reportPath -Value $json -Encoding utf8
            Write-Output $json
            Write-Output "34/34 Flutter Android state and sensor scenarios passed on $avd."
            return
        }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    $lines | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$artifactPrefix-timeout.log")
    throw 'The owned Android test process did not publish a result within 45 seconds.'
} catch {
    if ($null -eq $report) { $report = [pscustomobject]@{ passed = $false; checks = @() } }
    $report.passed = $false
    $report | Add-Member -NotePropertyName error -NotePropertyValue $_.Exception.Message -Force
    $report | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $reportPath -Encoding utf8
    throw
} finally {
    try {
        if ($batteryOverridden) { Invoke-TestAdb -AdbArguments @('shell', 'dumpsys', 'battery', 'reset') | Out-Null }
    } finally {
        Invoke-TestAdb -AdbArguments @('shell', 'am', 'force-stop', $package) | Out-Null
    }
}
