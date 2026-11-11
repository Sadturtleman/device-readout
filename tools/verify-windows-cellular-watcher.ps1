$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run with Windows PowerShell: powershell.exe -NoProfile -File tools/verify-windows-cellular-watcher.ps1'
}
# Independent OS projection; only observation is started/stopped. No account IDs or settings are read or changed.
$watcherType = [Windows.Networking.NetworkOperators.MobileBroadbandAccountWatcher,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]
Add-Type -TypeDefinition 'public static class CellularWatcherVerificationCallbacks { public static void Ignore(object sender, object args) {} }'
$watcher = New-Object -TypeName Windows.Networking.NetworkOperators.MobileBroadbandAccountWatcher
$event = $watcherType.GetEvent('EnumerationCompleted')
$callback = [System.Delegate]::CreateDelegate($event.EventHandlerType, [CellularWatcherVerificationCallbacks].GetMethod('Ignore'))
$registration = $event.AddMethod.Invoke($watcher, @($callback))
$watcherStarted = $false
try {
    $watcher.Start()
    $watcherStarted = $true
    $startedStatus = [int]$watcher.Status
} finally {
    if ($watcherStarted) {
        $watcher.Stop()
        $stoppedStatus = [int]$watcher.Status
    }
    $event.RemoveMethod.Invoke($watcher, @($registration)) | Out-Null
}
[pscustomobject]@{ StartedStatus = $startedStatus; StoppedStatus = $stoppedStatus } | ConvertTo-Json -Compress
