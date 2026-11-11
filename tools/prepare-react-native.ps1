$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRuntime = Join-Path $taskRoot '.tools/react-native-0.88'
New-Item -ItemType Directory -Force -Path $taskRuntime | Out-Null
foreach ($taskFile in @('package.json','package-lock.json')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "react-native-runtime/$taskFile") -Destination (Join-Path $taskRuntime $taskFile)
}
& npm ci --prefix $taskRuntime --cache (Join-Path $taskRoot '.tools/npm-cache') --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) {throw 'React Native verification runtime installation failed.'}
