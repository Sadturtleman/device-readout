$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-sensors.ps1' }
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$information = [Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime]
$collection = [Windows.Devices.Enumeration.DeviceInformationCollection,Windows.Devices.Enumeration,ContentType=WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
$awaitCollection = $asTask.MakeGenericMethod($collection)
$acceleration = [Windows.Devices.Sensors.Accelerometer,Windows.Devices.Sensors,ContentType=WindowsRuntime]
$accelerationKind = [Windows.Devices.Sensors.AccelerometerReadingType,Windows.Devices.Sensors,ContentType=WindowsRuntime]
$selectors = [ordered]@{
    Illuminance = [Windows.Devices.Sensors.LightSensor,Windows.Devices.Sensors,ContentType=WindowsRuntime]::GetDeviceSelector()
    Pressure = [Windows.Devices.Sensors.Barometer,Windows.Devices.Sensors,ContentType=WindowsRuntime]::GetDeviceSelector()
    Gyroscope = [Windows.Devices.Sensors.Gyrometer,Windows.Devices.Sensors,ContentType=WindowsRuntime]::GetDeviceSelector()
    Magnetometer = [Windows.Devices.Sensors.Magnetometer,Windows.Devices.Sensors,ContentType=WindowsRuntime]::GetDeviceSelector()
    Accelerometer = $acceleration::GetDeviceSelector($accelerationKind::Standard)
    LinearAcceleration = $acceleration::GetDeviceSelector($accelerationKind::Linear)
    Gravity = $acceleration::GetDeviceSelector($accelerationKind::Gravity)
}
$counts = [ordered]@{}
foreach ($kind in $selectors.Keys) {
    $operation = $information::FindAllAsync($selectors[$kind])
    $task = $awaitCollection.Invoke($null, @($operation))
    if (-not $task.Wait(10000)) { throw 'Independent sensor enumeration timed out.' }
    $devices = $task.GetAwaiter().GetResult()
    $counts[$kind] = @($devices).Count
}
# Passive enumeration only. No identifiers, permission requests, subscriptions or setting changes.
$counts | ConvertTo-Json -Compress
