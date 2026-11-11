$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this independent WinRT projection probe with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-network-performance.ps1'
}
$connectionProfile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
$planStatus = $null
$inboundBps = $null
$outboundBps = $null
if ($null -ne $connectionProfile) { $planStatus = $connectionProfile.GetDataPlanStatus() }
if ($null -ne $planStatus) {
    if ($null -ne $planStatus.InboundBitsPerSecond) { $inboundBps = [string]$planStatus.InboundBitsPerSecond }
    if ($null -ne $planStatus.OutboundBitsPerSecond) { $outboundBps = [string]$planStatus.OutboundBitsPerSecond }
}
[pscustomobject]@{
    HasProfile = $null -ne $connectionProfile
    HasPlan = $null -ne $planStatus
    InboundBps = $inboundBps
    OutboundBps = $outboundBps
} | ConvertTo-Json -Compress
