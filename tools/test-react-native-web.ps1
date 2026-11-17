$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & (Join-Path $PSScriptRoot 'build-react-native-web.ps1')
    node --test .tools/test/react-native-web-server.test.mjs tools/test-react-native-web.mjs
    if ($LASTEXITCODE -ne 0) { throw 'React Native Web contracts failed.' }
} finally { Pop-Location }
