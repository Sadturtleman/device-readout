$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Shared SDK build failed.' }
    node tools/build-react-native-web.mjs
    if ($LASTEXITCODE -ne 0) { throw 'React Native Web application build failed.' }
} finally { Pop-Location }
