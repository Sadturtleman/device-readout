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
if ($LASTEXITCODE -ne 0 -or $identity[0].Trim() -ne $AvdName -or -not $AvdName.StartsWith('DeviceReadout_')) {throw 'Cellular fixture requires the exact project-owned AVD.'}
$initial = (& $adbPath -P $ServerPort -s $Serial emu gsm status) -join "`n"
if ($LASTEXITCODE -ne 0 -or $initial -notmatch 'gsm voice state:\s+home' -or $initial -notmatch 'gsm data state:\s+home') {throw 'This fixture requires both original GSM registration states to be home.'}
$component = 'dev.devicereadout.android.test/dev.devicereadout.android.ContractInstrumentation'
$resultPath = Join-Path $projectRoot ".tools/$AvdName-cellularEvents-results.txt"
$instrumentation = $null
function Set-FixtureRegistration([string]$state) {
    foreach ($domain in @('voice','data')) {
        $response = (& $adbPath -P $ServerPort -s $Serial emu gsm $domain $state) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $response -notmatch '\bOK\b' -or $response -match '\bKO\b') {throw "GSM $domain fixture request failed."}
    }
}
try {
    $instrumentation = Start-Process -FilePath $adbPath -ArgumentList @('-P',$ServerPort,'-s',$Serial,'shell','am','instrument','-w','-e','mode','cellularEvents',$component) -WindowStyle Hidden -PassThru -RedirectStandardOutput $resultPath -RedirectStandardError "$resultPath.stderr"
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    $roamed = $false
    $returned = $false
    while (-not $instrumentation.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $output = Get-Content -LiteralPath $resultPath -Raw
        if (-not $roamed -and $output -match 'deviceReadoutAwaiting=cellularRoaming') {
            Set-FixtureRegistration 'roaming'
            $roamed = $true
        }
        if ($roamed -and -not $returned -and $output -match 'deviceReadoutAwaiting=cellularHome') {
            Set-FixtureRegistration 'home'
            $returned = $true
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $instrumentation.WaitForExit(1000)) {throw 'Cellular instrumentation did not finish.'}
    Get-Content -LiteralPath $resultPath
} finally {
    if ($instrumentation -and -not $instrumentation.HasExited) {$instrumentation.Kill()}
    Set-FixtureRegistration 'home'
    $restored = (& $adbPath -P $ServerPort -s $Serial emu gsm status) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $restored -notmatch 'gsm voice state:\s+home' -or $restored -notmatch 'gsm data state:\s+home') {throw 'GSM fixture state was not restored.'}
}
