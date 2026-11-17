param([switch]$SkipPrepare, [string]$SdkRoot, [string]$GradleHome, [ValidateSet('Debug','Isolation')][string]$Variant = 'Debug')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$consumer = Join-Path $projectRoot '.tools/rn-installed'
$tarballs = Join-Path $projectRoot '.tools/rn-package-tarballs'
if (-not $SdkRoot) { $SdkRoot = Join-Path $projectRoot '.tools/android-sdk' }
if (-not $GradleHome) { $GradleHome = Join-Path $projectRoot '.tools/gradle-home' }
Push-Location $projectRoot
try {
    if (-not $SkipPrepare) {
        npm run build
        if ($LASTEXITCODE -ne 0) { throw 'SDK build failed.' }
        npm run test:react-native
        if ($LASTEXITCODE -ne 0) { throw 'React Native declarations, build or contracts failed.' }
        node packages/react-native/scripts/prepare-package.mjs
        if ($LASTEXITCODE -ne 0) { throw 'Shared source preparation failed.' }
        New-Item -ItemType Directory -Force -Path $tarballs | Out-Null
        $records = [System.Collections.Generic.List[object]]::new()
        foreach ($name in @('core', 'web', 'react-native')) {
            Push-Location (Join-Path $projectRoot "packages/$name")
            try {
                $packed = (& npm pack --ignore-scripts --json --pack-destination $tarballs | ConvertFrom-Json)
                if ($LASTEXITCODE -ne 0) { throw "Packing $name failed." }
            } finally { Pop-Location }
            if (@($packed.files | Where-Object { $_.path -match '(^|/)(build|\.gradle|\.cxx|\.tools)(/|$)|(^|/)local\.properties$' }).Count) { throw 'Package contains build output.' }
            if (@($packed.files | Where-Object path -eq 'LICENSE').Count -ne 1) { throw 'Package is missing LICENSE.' }
            $source = Join-Path $tarballs $packed.filename
            $digest = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
            $target = Join-Path $tarballs "device-readout-$name-$($digest.Substring(0,16)).tgz"
            Copy-Item -LiteralPath $source -Destination $target -Force
            $records.Add(@{name = "@device-readout/$name"; path = $target; sha256 = $digest; entries = $packed.entryCount})
        }
        $records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath .tools/rn-package-records.json -Encoding utf8NoBOM
        node tools/prepare-react-native-android-consumer.mjs
        if ($LASTEXITCODE -ne 0) { throw 'Consumer preparation failed.' }
        npm install --prefix $consumer --workspaces=false --ignore-scripts --no-audit --no-fund --cache (Join-Path $projectRoot '.tools/npm-cache')
        if ($LASTEXITCODE -ne 0) { throw 'Consumer installation failed.' }
    }
    foreach ($name in @('core', 'web', 'react-native')) {
        $item = Get-Item -LiteralPath (Join-Path $consumer "node_modules/@device-readout/$name")
        if ($item.LinkType) { throw 'Installed SDK is a source link.' }
    }
    & node (Join-Path $consumer 'node_modules/typescript/bin/tsc') -p (Join-Path $consumer 'tsconfig.json')
    if ($LASTEXITCODE -ne 0) { throw 'Installed consumer type checking failed.' }
    $names = @('GRADLE_USER_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_USER_HOME','ANDROID_SDK_HOME','NODE_PATH','DEVICE_READOUT_REACT_NATIVE_ROOT')
    $previous = @{}
    foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:GRADLE_USER_HOME = [System.IO.Path]::GetFullPath($GradleHome)
        $env:ANDROID_HOME = (Resolve-Path -LiteralPath $SdkRoot).Path
        $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
        $env:ANDROID_SDK_HOME = Join-Path $projectRoot '.tools/android-legacy'
        $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
        $env:NODE_PATH = $null
        $env:DEVICE_READOUT_REACT_NATIVE_ROOT = $null
        & (Join-Path $consumer 'android/gradlew.bat') -p (Join-Path $consumer 'android') ":app:assemble$Variant" --no-daemon --console=plain
        if ($LASTEXITCODE -ne 0) { throw 'Installed Android package build failed.' }
    } finally { foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') } }
} finally { Pop-Location }
