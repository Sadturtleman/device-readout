$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-battery.ps1'
}
# Independent Windows projection. No SDK collector, device mutation or UI request.
$batteryType = [Windows.Devices.Power.Battery,Windows.Devices.Power,ContentType=WindowsRuntime]
$battery = $batteryType::AggregateBattery
if ($null -eq $battery) { throw 'The OS aggregate endpoint is unavailable.' }
$report = $battery.GetReport()
[pscustomobject]@{
    Status = [int]$report.Status
    ChargeRate = $report.ChargeRateInMilliwatts
    DesignCapacity = $report.DesignCapacityInMilliwattHours
    FullChargeCapacity = $report.FullChargeCapacityInMilliwattHours
    RemainingCapacity = $report.RemainingCapacityInMilliwattHours
} | ConvertTo-Json -Compress
