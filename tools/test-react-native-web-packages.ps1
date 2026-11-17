$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$tarballs = Join-Path $projectRoot '.tools/react-native-web-packages/tarballs'
$consumer = Join-Path $projectRoot '.tools/react-native-web-installed'
Push-Location $projectRoot
try {
    & (Join-Path $PSScriptRoot 'build-react-native-web.ps1')
    node packages/react-native/scripts/prepare-package.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Shared source preparation failed.' }
    New-Item -ItemType Directory -Force -Path $tarballs, (Join-Path $consumer 'app') | Out-Null
    $dependencies = [ordered]@{'react' = '19.3.0'; 'react-dom' = '19.3.0'; 'react-native-web' = '0.21.4'}
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('core', 'web', 'react-native')) {
        Push-Location (Join-Path $projectRoot "packages/$name")
        try {
            $packed = (& npm pack --ignore-scripts --json --pack-destination $tarballs | ConvertFrom-Json)
            if ($LASTEXITCODE -ne 0) { throw "Packing $name failed." }
        } finally { Pop-Location }
        if (@($packed.files | Where-Object { $_.path -match '(^|/)(build|\.gradle|\.cxx|\.tools)(/|$)|(^|/)local\.properties$' }).Count -ne 0) {
            throw "Package $name contains local build output or tool caches."
        }
        if (@($packed.files | Where-Object { $_.path -eq 'LICENSE' }).Count -ne 1) { throw "Package $name is missing its license text." }
        $source = Join-Path $tarballs $packed.filename
        $digest = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        $filename = "device-readout-$name-$($digest.Substring(0, 16)).tgz"
        Copy-Item -LiteralPath $source -Destination (Join-Path $tarballs $filename) -Force
        $dependencies["@device-readout/$name"] = "file:../react-native-web-packages/tarballs/$filename"
        $records.Add(@{name = "@device-readout/$name"; filename = $filename; size = $packed.size; entries = $packed.entryCount; sha256 = $digest})
    }
    @{name = 'device-readout-installed-web-consumer'; version = '0.1.0'; private = $true; type = 'module'; dependencies = $dependencies} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $consumer 'package.json') -Encoding utf8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'react-native-web-runtime/package-lock.json') -Destination (Join-Path $consumer 'package-lock.json') -Force
    foreach ($file in @('App.jsx', 'contracts.js')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "packages/react-native/example/web/$file") -Destination (Join-Path $consumer "app/$file") -Force
    }
    foreach ($file in @('types.ts', 'server.test.mjs')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "packages/react-native/test/web/$file") -Destination (Join-Path $consumer $file) -Force
    }
    npm install --prefix $consumer --workspaces=false --ignore-scripts --no-audit --no-fund --cache (Join-Path $projectRoot '.tools/npm-cache')
    if ($LASTEXITCODE -ne 0) { throw 'Local package consumer installation failed.' }
    if (Test-Path -LiteralPath (Join-Path $consumer 'node_modules/react-native')) { throw 'Web consumption unexpectedly installed React Native mobile.' }
    node tools/build-react-native-web.mjs --installed
    if ($LASTEXITCODE -ne 0) { throw 'Installed package consumer build failed.' }
    node --test .tools/test/react-native-web-server.test.mjs tools/test-react-native-web.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Installed React Native Web consumer failed.' }
    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot '.tools/evidence') | Out-Null
    @{passed = $true; mobileInstalled = $false; packages = $records} | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $projectRoot '.tools/evidence/react-native-web-packages.json') -Encoding utf8
} finally { Pop-Location }
