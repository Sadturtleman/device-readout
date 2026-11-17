$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtime = Join-Path $projectRoot '.tools/react-native-web-0.21'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
foreach ($file in @('package.json', 'package-lock.json')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "react-native-web-runtime/$file") -Destination (Join-Path $runtime $file)
}
& npm ci --prefix $runtime --cache (Join-Path $projectRoot '.tools/npm-cache') --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'React Native Web verification runtime installation failed.' }
