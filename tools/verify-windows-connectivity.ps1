$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this independent WinRT projection probe with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-connectivity.ps1'
}
$connectionProfile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($null -eq $connectionProfile) {
    [pscustomobject]@{ HasProfile = $false; Connectivity = $null; Cost = $null } | ConvertTo-Json -Compress
} else {
    [pscustomobject]@{
        HasProfile = $true
        Connectivity = [int]$connectionProfile.GetNetworkConnectivityLevel()
        Cost = [int]($connectionProfile.GetConnectionCost()).NetworkCostType
    } | ConvertTo-Json -Compress
}
