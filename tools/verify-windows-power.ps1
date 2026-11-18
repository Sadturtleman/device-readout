$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$power = [System.Windows.Forms.SystemInformation]::PowerStatus
[pscustomobject]@{
    powerLineStatus = [int]$power.PowerLineStatus
} | ConvertTo-Json -Compress
