param(
    [Parameter(Mandatory)][string]$SdkRoot,
    [Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$AvdName,
    [Parameter(Mandatory)][ValidateSet('wifiAuthorized','cellularContracts','cellularDenied','cellularRestricted','cellularEvents','identityContracts','identityDenied')][string]$Mode,
    [int]$ServerPort = 5047
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adbPath = Join-Path $SdkRoot 'platform-tools/adb.exe'
$identity = & $adbPath -P $ServerPort -s $Serial emu avd name
if ($LASTEXITCODE -ne 0 -or $identity[0].Trim() -ne $AvdName -or -not $AvdName.StartsWith('DeviceReadout_')) {throw 'Permission fixture requires the exact project-owned AVD.'}
$userId = (& $adbPath -P $ServerPort -s $Serial shell am get-current-user).Trim()
if ($userId -ne '0') {throw 'Permission fixture is restricted to the project AVD owner profile.'}
$package = 'dev.devicereadout.android.test'
function Read-PermissionState {
    $state = (& $adbPath -P $ServerPort -s $Serial shell am instrument -w -e mode permissionState "$package/dev.devicereadout.android.ContractInstrumentation") -join "`n"
    if ($LASTEXITCODE -ne 0 -or $state -notmatch 'INSTRUMENTATION_RESULT: deviceReadoutStatus=passed') {throw 'Unable to read test APK permission state.'}
    return $state
}
$packageState = Read-PermissionState
$permissions = @(if ($Mode -eq 'wifiAuthorized') {@('android.permission.ACCESS_COARSE_LOCATION','android.permission.ACCESS_FINE_LOCATION')} else {@('android.permission.READ_PHONE_STATE')})
$original = @{}
foreach ($permission in $permissions) {
    $matchesFound = [regex]::Matches($packageState, ('INSTRUMENTATION_RESULT: ' + [regex]::Escape($permission) + '=(true|false)'))
    if ($matchesFound.Count -ne 1) {throw "Cannot establish original grant for $permission."}
    $original[$permission] = $matchesFound[0].Groups[1].Value -eq 'true'
}
$desired = $Mode -notin @('cellularDenied','identityDenied')
$priorAppOp = $null
$priorUidAppOp = $null
$phoneOperation = 'android:read_phone_state'
if ($Mode.StartsWith('cellular') -or $Mode.StartsWith('identity')) {
    $state = (& $adbPath -P $ServerPort -s $Serial shell appops get $package $phoneOperation) -join "`n"
    if ($LASTEXITCODE -ne 0) {throw 'Cannot read original phone-state app-op.'}
    if ($state -match '(?m)^(?:OP_)?READ_PHONE_STATE:\s+(allow|ignore|deny|default|foreground)') {$priorAppOp = $Matches[1]}
    elseif ($state -match 'No operations') {$priorAppOp = 'default'}
    else {throw 'Cannot safely restore this phone-state app-op.'}
    $deviceApi = [int](& $adbPath -P $ServerPort -s $Serial shell getprop ro.build.version.sdk)
    if ($deviceApi -ge 29) {
        # Runtime grants on modern Android set a UID mode which takes precedence over package mode.
        $priorUidAppOp = if ($state -match 'Uid mode:\s+READ_PHONE_STATE:\s+(allow|ignore|deny|default|foreground)') {$Matches[1]} else {'default'}
    }
}
try {
    foreach ($permission in $permissions) {
        if ($original[$permission] -ne $desired) {
            $action = if ($desired) {'grant'} else {'revoke'}
            & $adbPath -P $ServerPort -s $Serial shell pm $action --user 0 $package $permission | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Test APK permission setup failed.'}
        }
    }
    if ($priorAppOp) {
        $fixtureAppOp = if ($Mode -eq 'cellularRestricted' -or -not $desired) {'ignore'} else {'allow'}
        & $adbPath -P $ServerPort -s $Serial shell appops set $package $phoneOperation $fixtureAppOp | Out-Null
        if ($LASTEXITCODE -ne 0) {throw 'Test app-op setup failed.'}
        if ($priorUidAppOp) {
            & $adbPath -P $ServerPort -s $Serial shell appops set --uid $package $phoneOperation $fixtureAppOp | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Test UID app-op setup failed.'}
        }
    }
    $result = if ($Mode -eq 'cellularEvents') {
        & (Join-Path $PSScriptRoot 'test-android-cellular-events.ps1') -SdkRoot $SdkRoot -Serial $Serial -AvdName $AvdName -ServerPort $ServerPort
    } else {
        & $adbPath -P $ServerPort -s $Serial shell am instrument -w -e mode $Mode "$package/dev.devicereadout.android.ContractInstrumentation"
    }
    $result | Set-Content -LiteralPath (Join-Path $projectRoot ".tools/$AvdName-$Mode-results.txt")
    $result
} finally {
    for ($index = $permissions.Count - 1; $index -ge 0; $index--) {
        $permission = $permissions[$index]
        if ($original[$permission] -ne $desired) {
            $action = if ($original[$permission]) {'grant'} else {'revoke'}
            & $adbPath -P $ServerPort -s $Serial shell pm $action --user 0 $package $permission | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Test APK permission restoration failed.'}
        }
    }
    if ($priorAppOp) {
        & $adbPath -P $ServerPort -s $Serial shell appops set $package $phoneOperation $priorAppOp | Out-Null
        if ($LASTEXITCODE -ne 0) {throw 'Test app-op restoration failed.'}
    }
    if ($priorUidAppOp) {
        & $adbPath -P $ServerPort -s $Serial shell appops set --uid $package $phoneOperation $priorUidAppOp | Out-Null
        if ($LASTEXITCODE -ne 0) {throw 'Test UID app-op restoration failed.'}
    }
    $restored = Read-PermissionState
    foreach ($permission in $permissions) {
        $expected = $original[$permission].ToString().ToLowerInvariant()
        if ($restored -notmatch ('INSTRUMENTATION_RESULT: ' + [regex]::Escape($permission) + '=' + $expected)) {throw "Permission restoration did not persist: $permission."}
    }
}
