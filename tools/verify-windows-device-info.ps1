$ErrorActionPreference = 'Stop'
# Read only the fields needed by this independent fixture; no identifiers/serials.
$system = @(Get-CimInstance -ClassName Win32_ComputerSystem -Property Manufacturer,Model -OperationTimeoutSec 5)
$boards = @(Get-CimInstance -ClassName Win32_BaseBoard -Property Product -OperationTimeoutSec 5)
if ($system.Count -ne 1) { throw 'The independent system query must return one running system.' }
[ordered]@{
    manufacturer = $system[0].Manufacturer
    modelName = $system[0].Model
    boardCount = $boards.Count
    board = if ($boards.Count -eq 1) { $boards[0].Product } else { $null }
} | ConvertTo-Json -Compress
