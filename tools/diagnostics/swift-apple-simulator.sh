#!/bin/bash
# Diagnostic runner: all failures stay visible; this does not replace the full CI gate.
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
log_root="$repo_root/.tools/apple-diagnostics"
mkdir -p "$log_root"
{
    git -C "$repo_root" rev-parse HEAD
    sw_vers
    uname -m
    xcodebuild -version
    xcrun swift --version
} 2>&1 | tee "$log_root/toolchain.log"
xcrun simctl list devices available --json > "$log_root/devices.json"
simulator_id=$(python3 - "$log_root/devices.json" "$(xcrun --sdk iphonesimulator --show-sdk-version)" <<'PY'
import json, sys, uuid
from pathlib import Path
sdk_version = tuple(map(int, sys.argv[2].split('.')[:2]))
for runtime, candidates in sorted(json.loads(Path(sys.argv[1]).read_text())['devices'].items()):
    if '.iOS-' not in runtime:
        continue
    if tuple(map(int, runtime.rsplit('.iOS-', 1)[1].split('-')[:2])) != sdk_version:
        continue
    for device in candidates:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            uuid.UUID(device['udid'])
            print(device['udid'])
            sys.exit(0)
raise SystemExit('No matching iPhone simulator.')
PY
)
cd "$repo_root/swift"
common=(-scheme DeviceReadout -sdk iphonesimulator
    -destination "platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)"
    -destination-timeout 60 -configuration Debug -parallel-testing-enabled NO
    -derivedDataPath "$repo_root/.tools/swift-apple-diagnostics"
    IPHONEOS_DEPLOYMENT_TARGET=16.0 CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)
xcodebuild "${common[@]}" build-for-testing 2>&1 | tee "$log_root/build.log"
result=0
for scope in handoff-case handoff-class watch-class all; do
    selection=()
    case "$scope" in
        handoff-case) selection=(-only-testing:DeviceReadoutTests/WatchHandoffTests/testLateNativeValuesAndErrorsCannotFollowAppHandoff) ;;
        handoff-class) selection=(-only-testing:DeviceReadoutTests/WatchHandoffTests) ;;
        watch-class) selection=(-only-testing:DeviceReadoutTests/WatchTests) ;;
    esac
    set +e
    xcodebuild "${common[@]}" "${selection[@]}" test-without-building 2>&1 | tee "$log_root/$scope.log"
    exit_code=$?
    set -e
    printf '%s exit=%s\n' "$scope" "$exit_code" | tee -a "$log_root/outcomes.log"
    if [[ $exit_code != 0 ]]; then result=1; fi
done
exit "$result"
