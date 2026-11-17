$ErrorActionPreference = 'Stop'
$zone = [TimeZoneInfo]::Local
$now = [DateTimeOffset]::UtcNow
[ordered]@{
    windowsId = $zone.Id
    utcOffsetSeconds = [int]$zone.GetUtcOffset($now).TotalSeconds
    daylightSavingTime = $zone.IsDaylightSavingTime($now)
} | ConvertTo-Json -Compress
