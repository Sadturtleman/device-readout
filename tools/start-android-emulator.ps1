param(
    [Parameter(Mandatory)][string]$SdkRoot,
    [Parameter(Mandatory)][string]$ImageDirectory,
    [Parameter(Mandatory)][ValidateRange(26, 99)][int]$ApiLevel,
    [ValidateRange(5554, 5682)][int]$Port = 5580,
    [switch]$HingeFixture
)
$ErrorActionPreference = 'Stop'
if ($Port % 2 -ne 0) {throw 'The emulator console port must be even.'}
# Check both console/adb ports before creating or launching an AVD. Existing devices are never stopped.
$portChecks = @()
try {
    foreach ($number in @($Port, ($Port + 1))) {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Any, $number)
        $listener.Server.DualMode = $true
        $listener.ExclusiveAddressUse = $true
        $portChecks += $listener
        try {$listener.Start()} catch {throw "Emulator port $number is occupied or unavailable; select a different even port."}
    }
} finally {foreach ($listener in $portChecks) {$listener.Stop()}}
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$avdHome = Join-Path $projectRoot '.tools/android-avd'
if ($HingeFixture -and $ApiLevel -lt 30) {throw 'The hinge fixture requires Android API 30+.'}
$avdName = "DeviceReadout_API$ApiLevel"
if ($HingeFixture) {$avdName += '_Hinge'}
$avdDirectory = Join-Path $avdHome "$avdName.avd"
$imagePath = (Resolve-Path -LiteralPath $ImageDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $imagePath 'system.img'))) { throw 'An installed x86_64 Google APIs system image is required.' }
New-Item -ItemType Directory -Force -Path $avdDirectory | Out-Null
$config = Join-Path $avdDirectory 'config.ini'
if (-not (Test-Path -LiteralPath $config)) {
    $sensorFixtureConfig = if ($HingeFixture) {
        @'
hw.sensor.hinge=yes
hw.sensor.hinge.count=1
hw.sensor.hinge.type=1
hw.sensor.hinge.sub_type=1
hw.sensor.hinge.ranges=0-180
hw.sensor.hinge.defaults=180
hw.sensor.hinge.areas=50-0
'@
    } else {''}
    @"
AvdId=$avdName
avd.ini.displayname=$avdName
avd.ini.encoding=UTF-8
abi.type=x86_64
hw.cpu.arch=x86_64
hw.cpu.ncore=2
hw.ramSize=2048
hw.lcd.width=320
hw.lcd.height=640
hw.lcd.density=160
hw.gpu.enabled=yes
hw.gpu.mode=swiftshader_indirect
hw.battery=yes
hw.accelerometer=yes
hw.gyroscope=yes
$sensorFixtureConfig
disk.dataPartition.size=4G
image.sysdir.1=$imagePath
tag.id=google_apis
tag.display=Google APIs
target=android-$ApiLevel
"@ | Set-Content -LiteralPath $config -Encoding utf8
}
@"
avd.ini.encoding=UTF-8
path=$avdDirectory
target=android-$ApiLevel
"@ | Set-Content -LiteralPath (Join-Path $avdHome "$avdName.ini") -Encoding utf8
$environmentNames = @('ANDROID_AVD_HOME','ANDROID_USER_HOME','ANDROID_EMULATOR_HOME','ANDROID_SDK_HOME','ANDROID_ADB_SERVER_PORT','ADB_SERVER_SOCKET')
$previous = @{}
foreach ($name in $environmentNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:ANDROID_AVD_HOME = $avdHome
    $env:ANDROID_SDK_HOME = Join-Path $projectRoot '.tools/android-legacy'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    $env:ANDROID_EMULATOR_HOME = $env:ANDROID_USER_HOME
    $env:ANDROID_ADB_SERVER_PORT = '5047'
    $env:ADB_SERVER_SOCKET = 'tcp:localhost:5047'
    New-Item -ItemType Directory -Force -Path $env:ANDROID_USER_HOME | Out-Null
    & (Join-Path $SdkRoot 'emulator/emulator.exe') -avd $avdName -port $Port -no-window -no-audio -no-snapshot -gpu swiftshader_indirect -no-boot-anim -camera-back none -camera-front none -no-metrics *> (Join-Path $projectRoot ".tools/$avdName-emulator.log")
    exit $LASTEXITCODE
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
