#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
    echo 'iOS simulator verification requires macOS with Xcode.' >&2
    exit 1
fi
log_root="$repo_root/.tools/apple-ci-logs"
mkdir -p "$log_root"
{
    git -C "$repo_root" rev-parse HEAD
    sw_vers
    uname -m
    xcodebuild -version
    xcrun swift --version
} 2>&1 | tee "$log_root/simulator-toolchain.log"
xcrun simctl list devices available --json > "$log_root/simulator-devices.json"
simulator_id=$(python3 - "$log_root/simulator-devices.json" \
    "$(xcrun --sdk iphonesimulator --show-sdk-version)" "$log_root/simulator-selection.log" <<'PY'
import json, sys, uuid
from pathlib import Path
devices = json.loads(Path(sys.argv[1]).read_text())['devices']
sdk_version = tuple(map(int, sys.argv[2].split('.')[:2]))
for runtime, candidates in sorted(devices.items()):
    if '.iOS-' not in runtime:
        continue
    version = tuple(map(int, runtime.rsplit('.iOS-', 1)[1].split('-')[:2]))
    if version != sdk_version:
        continue
    for device in candidates:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            identifier = str(uuid.UUID(device['udid']))
            Path(sys.argv[3]).write_text(json.dumps({'runtime': runtime, 'device': device}, indent=2))
            print(identifier)
            sys.exit(0)
raise SystemExit('No available iPhone simulator matches the selected Xcode SDK.')
PY
)
cat "$log_root/simulator-selection.log"
cd "$repo_root/swift"
result=0
for configuration in Debug Release; do
    if xcodebuild -scheme DeviceReadout -sdk iphonesimulator \
        -destination "platform=iOS Simulator,id=$simulator_id" -destination-timeout 180 \
        -configuration "$configuration" -parallel-testing-enabled NO \
        -derivedDataPath "$repo_root/.tools/swift-apple-tests" \
        -resultBundlePath "$repo_root/.tools/swift-apple-results-$configuration-$(date +%s).xcresult" \
        IPHONEOS_DEPLOYMENT_TARGET=16.0 CODE_SIGNING_ALLOWED=NO \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES test 2>&1 | tee "$log_root/simulator-$configuration.log"; then
        :
    else
        result=1
    fi
done
exit "$result"
