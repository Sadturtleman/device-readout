param([string]$Filter)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$localDotnet = Join-Path $projectRoot '.tools/dotnet/dotnet.exe'
$dotnet = if (Test-Path -LiteralPath $localDotnet) { $localDotnet } else { (Get-Command dotnet -ErrorAction Stop).Source }
$names = @('DOTNET_CLI_HOME', 'NUGET_PACKAGES', 'DOTNET_CLI_TELEMETRY_OPTOUT', 'DOTNET_GENERATE_ASPNET_CERTIFICATE', 'DOTNET_ADD_GLOBAL_TOOLS_TO_PATH')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:DOTNET_CLI_HOME = Join-Path $projectRoot '.tools/dotnet-home'
    $env:NUGET_PACKAGES = Join-Path $projectRoot '.tools/nuget'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
    $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
    & node (Join-Path $projectRoot 'tools/generate-csharp.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'C# generation failed.' }
    & $dotnet build (Join-Path $projectRoot 'dotnet/DeviceReadout.Tests') -m:1 -p:BuildInParallel=false -p:UseSharedCompilation=false --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw '.NET build failed.' }
    $testArguments = if ($Filter) { @('--filter', $Filter) } else { @() }
    & $dotnet (Join-Path $projectRoot 'dotnet/DeviceReadout.Tests/bin/Debug/net10.0/DeviceReadout.Tests.dll') @testArguments
    if ($LASTEXITCODE -ne 0) { throw '.NET contract verification failed.' }
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
