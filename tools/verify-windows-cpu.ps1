$ErrorActionPreference = 'Stop'
$processors = @(Get-CimInstance Win32_Processor)
$registryCpu = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
[pscustomobject]@{
    logicalProcessorCount = ($processors | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    physicalCoreCount = ($processors | Measure-Object NumberOfCores -Sum).Sum
    processorPackageCount = $processors.Count
    model = $registryCpu.ProcessorNameString
    manufacturer = $registryCpu.VendorIdentifier
} | ConvertTo-Json -Compress
