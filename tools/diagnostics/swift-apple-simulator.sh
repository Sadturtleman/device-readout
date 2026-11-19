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
package_root="$repo_root/.tools/swift-scheduling-diagnostics"
python3 - "$repo_root/swift" "$package_root" <<'PY'
import shutil, sys
from pathlib import Path
source, destination = map(Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=False)
shutil.copy2(source / 'Package.swift', destination / 'Package.swift')
for directory in ('Sources', 'Tests'):
    shutil.copytree(source / directory, destination / directory)
PY
cd "$package_root"
common=(-scheme DeviceReadout -sdk iphonesimulator
    -destination "platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)"
    -destination-timeout 60 -configuration Debug -parallel-testing-enabled NO
    -derivedDataPath "$repo_root/.tools/swift-apple-diagnostics"
    IPHONEOS_DEPLOYMENT_TARGET=16.0 CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)
result=0
for variant in baseline probe; do
    if [[ $variant == probe ]]; then
        python3 - "$package_root" "$repo_root/tools/diagnostics/SchedulingProbe.swift" <<'PY'
import re, shutil, sys
from pathlib import Path
tests = Path(sys.argv[1]) / 'Tests/DeviceReadoutTests'
count = 0
for path in tests.glob('*.swift'):
    original = path.read_text()
    updated, matches = re.subn(r'(final class \w+: XCTestCase \{)',
        r'\1\n    override class func setUp() { super.setUp(); SchedulingProbe.install() }', original)
    if matches:
        path.write_text(updated)
        count += matches
if count != 15:
    raise SystemExit(f'Unexpected test class count: {count}')
shutil.copy2(sys.argv[2], tests / 'SchedulingProbe.swift')
print(f'[DEBUG-ios-scheduling] Installed observer in {count} test classes; SDK sources unchanged.')
PY
    fi
    xcodebuild "${common[@]}" build-for-testing 2>&1 | tee "$log_root/$variant-build.log"
    for scope in handoff-class all; do
        # Bash 3.2 treats an empty array as unbound under nounset.
        invocation=("${common[@]}" test-without-building)
        if [[ $scope == handoff-class ]]; then
            invocation+=(-only-testing:DeviceReadoutTests/WatchHandoffTests)
        fi
        set +e
        xcodebuild "${invocation[@]}" 2>&1 | tee "$log_root/$variant-$scope.log"
        exit_code=$?
        set -e
        printf '%s-%s exit=%s\n' "$variant" "$scope" "$exit_code" | tee -a "$log_root/outcomes.log"
        if [[ $exit_code != 0 ]]; then result=1; fi
    done
done
exit "$result"
