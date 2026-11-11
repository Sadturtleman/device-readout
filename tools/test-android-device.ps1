param(
    [string]$SdkRoot = "$env:LOCALAPPDATA/Android/Sdk",
    [string]$Serial = 'emulator-5580',
    [string]$AvdName = 'DeviceReadout_API28',
    [int]$ServerPort = 5047,
    [ValidateSet('all','batteryEvents','hingeContracts','sensorAvailability','sensorUnits','sensorLifecycle','orientationFrame','regionalContracts','timeZoneEvents','localeEvents','networkContracts','networkEvents','interfaceHotplug','cpuContracts','storageContracts','storageHotplug','wifiContracts','wifiAuthorized','wifiEvents','cellularContracts','cellularDenied','cellularRestricted','cellularEvents','identityContracts','identityDenied')][string]$Mode = 'all'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adbPath = Join-Path $SdkRoot 'platform-tools/adb.exe'
$identity = & $adbPath -P $ServerPort -s $Serial emu avd name
if ($LASTEXITCODE -ne 0 -or $identity[0].Trim() -ne $AvdName -or -not $AvdName.StartsWith('DeviceReadout_')) {
    throw 'Refusing to install test code on a device other than the named project-owned AVD.'
}
$apk = Join-Path $projectRoot 'kotlin/android/build/outputs/apk/androidTest/debug/android-debug-androidTest.apk'
& $adbPath -P $ServerPort -s $Serial install -t -r $apk
if ($LASTEXITCODE -ne 0) { throw 'Instrumentation installation failed.' }
$component = 'dev.devicereadout.android.test/dev.devicereadout.android.ContractInstrumentation'
$resultPath = Join-Path $projectRoot ".tools/$AvdName-$Mode-results.txt"
if ($Mode -eq 'hingeContracts') {
    $result = & (Join-Path $PSScriptRoot 'test-android-hinge.ps1') -SdkRoot $SdkRoot -Serial $Serial -AvdName $AvdName -ServerPort $ServerPort
} elseif ($Mode -eq 'wifiEvents') {
    $result = & (Join-Path $PSScriptRoot 'test-android-wifi.ps1') -SdkRoot $SdkRoot -Serial $Serial -AvdName $AvdName -ServerPort $ServerPort
} elseif ($Mode -in @('wifiAuthorized','cellularContracts','cellularDenied','cellularRestricted','cellularEvents','identityContracts','identityDenied')) {
    $result = & (Join-Path $PSScriptRoot 'test-android-permissions.ps1') -SdkRoot $SdkRoot -Serial $Serial -AvdName $AvdName -Mode $Mode -ServerPort $ServerPort
} elseif ($Mode -eq 'storageHotplug') {
    $result = & (Join-Path $PSScriptRoot 'test-android-storage.ps1') -SdkRoot $SdkRoot -Serial $Serial -AvdName $AvdName -ServerPort $ServerPort
} elseif ($Mode -eq 'interfaceHotplug') {
    $previousOp = (& $adbPath -P $ServerPort -s $Serial shell appops get dev.devicereadout.android.test ACTIVATE_VPN) -join "`n"
    $previousMode = if ($previousOp -match 'ACTIVATE_VPN:\s+(allow|ignore|deny|default|foreground)') {$Matches[1]} else {'default'}
    try {
        & $adbPath -P $ServerPort -s $Serial shell appops set dev.devicereadout.android.test ACTIVATE_VPN allow | Out-Null
        $result = & $adbPath -P $ServerPort -s $Serial shell am instrument -w -e mode $Mode $component
        $result | Set-Content -LiteralPath $resultPath
    } finally {
        & $adbPath -P $ServerPort -s $Serial shell appops set dev.devicereadout.android.test ACTIVATE_VPN $previousMode | Out-Null
    }
} elseif ($Mode -eq 'networkEvents') {
    $originalWifi = (& $adbPath -P $ServerPort -s $Serial shell settings get global wifi_on).Trim()
    $originalData = (& $adbPath -P $ServerPort -s $Serial shell settings get global mobile_data).Trim()
    if ($originalWifi -notin @('0','1','2') -or $originalData -notin @('0','1')) {throw 'Cannot safely restore this AVD network fixture.'}
    try {
        $process = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode',$Mode,$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            if ((Get-Content -LiteralPath $resultPath -Raw) -match 'deviceReadoutAwaiting=networkEvents') {
                & $adbPath -P $ServerPort -s $Serial shell svc data disable | Out-Null
                & $adbPath -P $ServerPort -s $Serial shell svc wifi disable | Out-Null
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $process.WaitForExit(15000)) {$process.Kill();throw 'Network instrumentation did not finish.'}
        $result = Get-Content -LiteralPath $resultPath
    } finally {
        $wifiState = if ($originalWifi -eq '0') {'disable'} else {'enable'}
        $dataState = if ($originalData -eq '0') {'disable'} else {'enable'}
        & $adbPath -P $ServerPort -s $Serial shell svc wifi $wifiState | Out-Null
        & $adbPath -P $ServerPort -s $Serial shell svc data $dataState | Out-Null
    }
} elseif ($Mode -eq 'timeZoneEvents') {
    $deviceApi = [int](& $adbPath -P $ServerPort -s $Serial shell getprop ro.build.version.sdk)
    if ($deviceApi -lt 30) {throw 'The timezone event fixture requires the Android alarm shell command (API 30+).'}
    $originalZone = (& $adbPath -P $ServerPort -s $Serial shell getprop persist.sys.timezone).Trim()
    $originalAuto = (& $adbPath -P $ServerPort -s $Serial shell settings get global auto_time_zone).Trim()
    try {
        & $adbPath -P $ServerPort -s $Serial shell settings put global auto_time_zone 0 | Out-Null
        & $adbPath -P $ServerPort -s $Serial shell cmd alarm set-timezone Etc/UTC | Out-Null
        $process = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode',$Mode,$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            if ((Get-Content -LiteralPath $resultPath -Raw) -match 'deviceReadoutAwaiting=timeZoneEvents') {
                & $adbPath -P $ServerPort -s $Serial shell cmd alarm set-timezone Asia/Kathmandu | Out-Null
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $process.WaitForExit(15000)) {$process.Kill();throw 'Timezone instrumentation did not finish.'}
        $result = Get-Content -LiteralPath $resultPath
    } finally {
        & $adbPath -P $ServerPort -s $Serial shell cmd alarm set-timezone $originalZone | Out-Null
        if ($originalAuto -eq 'null') { & $adbPath -P $ServerPort -s $Serial shell settings delete global auto_time_zone | Out-Null }
        else { & $adbPath -P $ServerPort -s $Serial shell settings put global auto_time_zone $originalAuto | Out-Null }
    }
} elseif ($Mode -eq 'batteryEvents') {
    $deviceApi = [int](& $adbPath -P $ServerPort -s $Serial shell getprop ro.build.version.sdk)
    try {
        & $adbPath -P $ServerPort -s $Serial shell dumpsys battery reset | Out-Null
        if ($deviceApi -ge 29) { & $adbPath -P $ServerPort -s $Serial shell cmd thermalservice reset | Out-Null }
        foreach ($setting in @(@('ac','1'),@('usb','0'),@('wireless','0'),@('status','2'),@('level','40'))) {
            & $adbPath -P $ServerPort -s $Serial shell dumpsys battery set $setting[0] $setting[1] | Out-Null
        }
        $process = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode',$Mode,$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            if ((Get-Content -LiteralPath $resultPath -Raw) -match 'deviceReadoutAwaiting=batteryEvents') {
                & $adbPath -P $ServerPort -s $Serial shell dumpsys battery set ac 0 | Out-Null
                & $adbPath -P $ServerPort -s $Serial shell dumpsys battery set status 3 | Out-Null
                & $adbPath -P $ServerPort -s $Serial shell dumpsys battery set level 70 | Out-Null
                if ($deviceApi -ge 29) { & $adbPath -P $ServerPort -s $Serial shell cmd thermalservice override-status 3 | Out-Null }
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Instrumentation did not finish.' }
        $result = Get-Content -LiteralPath $resultPath
    } finally {
        & $adbPath -P $ServerPort -s $Serial shell dumpsys battery reset | Out-Null
        if ($deviceApi -ge 29) { & $adbPath -P $ServerPort -s $Serial shell cmd thermalservice reset | Out-Null }
    }
} else {
    if ($Mode -eq 'orientationFrame') {
        foreach ($setting in @(@('acceleration','0:0:9.80665'),@('gyroscope','0:0:0'),@('magnetic-field','50:0:0'))) {
            & $adbPath -P $ServerPort -s $Serial emu sensor set $setting[0] $setting[1] | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Unable to configure the orientation fixture.'}
        }
    }
    if ($Mode -eq 'sensorUnits') {
        foreach ($setting in @(@('acceleration','1:2:9'),@('gyroscope','0.1:0.2:0.3'),@('magnetic-field','10:20:30'),@('pressure','1013.25'),@('humidity','50'),@('temperature','24'),@('light','123'),@('proximity','0.5'))) {
            & $adbPath -P $ServerPort -s $Serial emu sensor set $setting[0] $setting[1] | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Unable to configure the project emulator sensor fixture.'}
        }
    }
    if ($Mode -eq 'sensorUnits') {
        $process = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode',$Mode,$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            if ((Get-Content -LiteralPath $resultPath -Raw) -match 'deviceReadoutAwaiting=temperatureSample') {
                & $adbPath -P $ServerPort -s $Serial emu sensor set temperature 23 | Out-Null
                Start-Sleep -Milliseconds 100
                & $adbPath -P $ServerPort -s $Serial emu sensor set temperature 24 | Out-Null
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw 'Sensor instrumentation did not finish.' }
        $result = Get-Content -LiteralPath $resultPath
    } else {
        $result = & $adbPath -P $ServerPort -s $Serial shell am instrument -w -e mode $Mode $component
        $result | Set-Content -LiteralPath $resultPath
    }
}
$result | Write-Output
if ($LASTEXITCODE -ne 0 -or -not ($result -match '^INSTRUMENTATION_RESULT: deviceReadoutStatus=passed') -or -not ($result -match '^INSTRUMENTATION_CODE: -1')) {
    throw 'Android runtime contract verification failed.'
}
