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
if ($LASTEXITCODE -ne 0 -or $identity[0].Trim() -ne $AvdName -or -not $AvdName.StartsWith('DeviceReadout_')) {throw 'Hinge fixture requires the exact project-owned AVD.'}
$initial = (& $adbPath -P $ServerPort -s $Serial emu sensor get hinge-angle0) -join "`n"
if ($LASTEXITCODE -ne 0 -or $initial -notmatch 'hinge-angle0 = ([0-9]+(?:\.[0-9]+)?)' -or $initial -match '\bKO\b') {throw 'Cannot read the original hinge angle.'}
$original = $Matches[1]
if ([double]::Parse($original, [Globalization.CultureInfo]::InvariantCulture) -gt 360) {throw 'The original angle is outside the native range.'}
$component = 'dev.devicereadout.android.test/dev.devicereadout.android.ContractInstrumentation'
$resultPath = Join-Path $projectRoot ".tools/$AvdName-hingeContracts-results.txt"
$instrumentation = $null
function Set-FixtureHinge([string]$angle) {
    $response = (& $adbPath -P $ServerPort -s $Serial emu sensor set hinge-angle0 $angle) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $response -notmatch '\bOK\b' -or $response -match '\bKO\b') {throw 'Hinge fixture request failed.'}
}
try {
    Set-FixtureHinge '90'
    $instrumentation = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode','hingeContracts',$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    $moved = $false
    while (-not $instrumentation.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        if (-not $moved -and (Get-Content -LiteralPath $resultPath -Raw) -match 'deviceReadoutAwaiting=hingeMove') {
            Set-FixtureHinge '180'
            $moved = $true
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $instrumentation.WaitForExit(1000)) {throw 'Hinge instrumentation did not finish.'}
    Get-Content -LiteralPath $resultPath
} finally {
    if ($instrumentation -and -not $instrumentation.HasExited) {$instrumentation.Kill()}
    Set-FixtureHinge $original
    $restored = (& $adbPath -P $ServerPort -s $Serial emu sensor get hinge-angle0) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $restored -notmatch 'hinge-angle0 = ([0-9]+(?:\.[0-9]+)?)' -or $Matches[1] -ne $original) {throw 'The hinge fixture was not restored.'}
}
