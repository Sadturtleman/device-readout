param([string]$VisualStudioRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $VisualStudioRoot) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $VisualStudioRoot = & $vswhere -latest -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $VisualStudioRoot) { throw 'Visual Studio 2022 C++ tools are required for the independent Windows test probe.' }
}
$VisualStudioRoot = (Resolve-Path -LiteralPath $VisualStudioRoot).Path
$cmake = Join-Path $VisualStudioRoot 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
$source = Join-Path $PSScriptRoot 'windows-memory-probe'
$build = Join-Path $projectRoot '.tools/windows-memory-probe'
& $cmake -S $source -B $build -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_GENERATOR_INSTANCE=$VisualStudioRoot"
if ($LASTEXITCODE -ne 0) { throw 'Windows memory probe configuration failed.' }
& $cmake --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw 'Windows memory probe compilation failed.' }
