$ErrorActionPreference = 'Stop'
# Independent OS-provider reference; DeviceReadout is neither imported nor called.
$facts = @(Get-CimInstance -ClassName Win32_OperatingSystem -Property Version,BuildNumber -OperationTimeoutSec 5)
if ($facts.Count -ne 1 -or -not $facts[0].Version -or -not $facts[0].BuildNumber) {
    throw 'The independent Windows OS provider did not return a version and build.'
}
[ordered]@{
    version = $facts[0].Version
    build = $facts[0].BuildNumber
} | ConvertTo-Json -Compress
