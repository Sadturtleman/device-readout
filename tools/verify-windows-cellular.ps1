$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-cellular.ps1'
}
# Read-only independent WinRT projection. Account/SIM identifiers are never logged.
$accountType = [Windows.Networking.NetworkOperators.MobileBroadbandAccount,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
$identifiers = @($accountType::AvailableNetworkAccountIds)
$accountStates = @($identifiers | ForEach-Object {
    $account = $accountType::CreateFromNetworkAccountId($_)
    $profiles = @($account.GetConnectionProfiles())
    $activeWwan = @($profiles | Where-Object { $_.IsWwanConnectionProfile -and [int]$_.GetNetworkConnectivityLevel() -gt 0 })
    [pscustomobject]@{
        HasDevice = $null -ne $account.CurrentDeviceInformation
        HasNetwork = $null -ne $account.CurrentNetwork
        HasProviderName = $null -ne $account.ServiceProviderName
        Profiles = $profiles.Count
        ActiveWwanProfiles = $activeWwan.Count
        CurrentDataClasses = @($activeWwan | ForEach-Object { [uint32]$_.WwanConnectionProfileDetails.GetCurrentDataClass() })
    }
})
[pscustomobject]@{ Accounts = $identifiers.Count; States = $accountStates } | ConvertTo-Json -Depth 4 -Compress
