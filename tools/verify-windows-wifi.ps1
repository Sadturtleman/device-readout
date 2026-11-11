$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-wifi.ps1'
}
# Independent WinRT projection; no SDK, handwritten ABI, BSSID query, scan or permission request.
$networkType = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]
$profiles = @($networkType::GetConnectionProfiles())
$connected = @($profiles | Where-Object { $_.IsWlanConnectionProfile -and [int]$_.GetNetworkConnectivityLevel() -gt 0 })
$preferred = $networkType::GetInternetConnectionProfile()
$fields = @($connected | ForEach-Object {
    $ssid = $_.WlanConnectionProfileDetails.GetConnectedSsid()
    [pscustomobject]@{
        SsidReadable = $null -ne $ssid
        SsidLength = if ($null -ne $ssid) { $ssid.Length } else { $null }
        Authentication = [int]$_.NetworkSecuritySettings.NetworkAuthenticationType
        Encryption = [int]$_.NetworkSecuritySettings.NetworkEncryptionType
        AdapterIdentityAvailable = $null -ne $_.NetworkAdapter -and $_.NetworkAdapter.NetworkAdapterId -ne [guid]::Empty
        NetworkIdentityAvailable = $null -ne $_.NetworkAdapter.NetworkItem -and $_.NetworkAdapter.NetworkItem.NetworkId -ne [guid]::Empty
    }
})
[pscustomobject]@{
    KnownProfiles = $profiles.Count
    ConnectedWifi = $connected.Count
    PreferredWifi = $null -ne $preferred -and $preferred.IsWlanConnectionProfile -and [int]$preferred.GetNetworkConnectivityLevel() -gt 0
    Fields = $fields
} | ConvertTo-Json -Depth 4 -Compress
