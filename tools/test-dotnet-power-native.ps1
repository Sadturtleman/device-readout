$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'build-windows-memory-probe.ps1')
$fixture = Join-Path $projectRoot '.tools/windows-memory-probe/Release/device_readout_power_fixture.dll'
if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) { throw 'Native power fixture missing.' }
& (Join-Path $PSScriptRoot 'test-dotnet.ps1') -PowerFixture $fixture
