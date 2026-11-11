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
if ($LASTEXITCODE -ne 0 -or $identity[0].Trim() -ne $AvdName -or -not $AvdName.StartsWith('DeviceReadout_')) {throw 'Storage fixture requires the exact project-owned AVD.'}
$priorDisks = @(& $adbPath -P $ServerPort -s $Serial shell sm list-disks | Where-Object {$_ -match '\S'})
$priorVirtual = (& $adbPath -P $ServerPort -s $Serial shell getprop persist.sys.virtual_disk).Trim()
if ($LASTEXITCODE -ne 0 -or $priorDisks.Count -ne 0 -or $priorVirtual -notin @('','false','0')) {throw 'Storage fixture requires no existing removable disks and a disabled virtual disk.'}
$resultPath = Join-Path $projectRoot ".tools/$AvdName-storageHotplug-results.txt"
$instrumentation = $null
try {
    & $adbPath -P $ServerPort -s $Serial shell sm set-virtual-disk true | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Unable to create the disposable virtual disk.'}
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $diskId = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $disks = @(& $adbPath -P $ServerPort -s $Serial shell sm list-disks | Where-Object {$_ -match '\S'})
        if ($disks.Count -eq 1 -and $disks[0].Trim() -match '^disk:7,[0-9]+$') {$diskId = $disks[0].Trim();break}
        Start-Sleep -Milliseconds 100
    }
    if (-not $diskId) {throw 'The newly created disk was not a single Linux loop device; refusing partitioning.'}
    # Only this just-created loop disk in the name-verified disposable AVD is formatted.
    & $adbPath -P $ServerPort -s $Serial shell sm partition $diskId public | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Disposable loop-disk partitioning failed.'}
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $volumeId = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $volumes = @(& $adbPath -P $ServerPort -s $Serial shell sm list-volumes public | Where-Object {$_ -match '\S'})
        if ($volumes.Count -eq 1 -and $volumes[0].Trim() -match '^(public:7,[0-9]+) mounted [A-Fa-f0-9-]+$') {$volumeId = $Matches[1];break}
        Start-Sleep -Milliseconds 100
    }
    if (-not $volumeId) {throw 'Disposable public volume did not mount.'}
    $component = 'dev.devicereadout.android.test/dev.devicereadout.android.ContractInstrumentation'
    $instrumentation = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode','storageHotplug',$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
    $deadline = [DateTime]::UtcNow.AddSeconds(35)
    $unmounted = $false
    $remounted = $false
    while (-not $instrumentation.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $output = Get-Content -LiteralPath $resultPath -Raw
        if (-not $unmounted -and $output -match 'deviceReadoutAwaiting=storageUnmount') {
            & $adbPath -P $ServerPort -s $Serial shell sm unmount $volumeId | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Fixture unmount failed.'}
            $unmounted = $true
        }
        if ($unmounted -and -not $remounted -and $output -match 'deviceReadoutAwaiting=storageRemount') {
            & $adbPath -P $ServerPort -s $Serial shell sm mount $volumeId | Out-Null
            if ($LASTEXITCODE -ne 0) {throw 'Fixture remount failed.'}
            $remounted = $true
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $instrumentation.WaitForExit(1000)) {throw 'Storage instrumentation did not finish.'}
    Get-Content -LiteralPath $resultPath
} finally {
    if ($instrumentation -and -not $instrumentation.HasExited) {$instrumentation.Kill()}
    & $adbPath -P $ServerPort -s $Serial shell sm set-virtual-disk false | Out-Null
}
