$ErrorActionPreference = 'Stop'
$culture = Get-Culture
$region = [Globalization.RegionInfo]::new($culture.Name)
[ordered]@{
    currentLanguageTag = $culture.Name
    regionCode = $region.TwoLetterISORegionName
    firstWeekday = $culture.DateTimeFormat.FirstDayOfWeek.ToString()
    calendarType = $culture.DateTimeFormat.Calendar.GetType().Name
} | ConvertTo-Json -Compress
