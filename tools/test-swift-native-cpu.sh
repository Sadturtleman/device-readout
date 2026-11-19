#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then echo 'The native CPU fixture requires macOS.' >&2; exit 1; fi
configuration=${CONFIGURATION:-debug}
case "$configuration" in debug|release) ;; *) echo 'Invalid configuration' >&2; exit 1;; esac
swift_bin=${SWIFT_BIN:-swift}
fixture_root="$repo_root/.tools/swift-cpu-fixture-$configuration"
mkdir -p "$fixture_root"
xcrun clang -dynamiclib -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$repo_root/tools/swift-native-consumer/Fixtures/cpu-topology.c" -o "$fixture_root/cpu-topology.dylib"
bin_path=$("$swift_bin" build --package-path "$repo_root/tools/swift-native-consumer" \
    --scratch-path "$repo_root/.tools/swift-consumer-build" -c "$configuration" --show-bin-path)
test -x "$bin_path/NativeConsumer"
for scenario in known physical-failure package-failure zero negative short-response oversized-response held-get held-watch; do
    trace="$fixture_root/$scenario.log"
    gate="$fixture_root/$scenario.gate"
    : > "$trace"
    # Remove only this fixture's single gate file from a previous invocation.
    rm -f -- "$gate"
    trap 'cat "$trace"' EXIT
    DEVICE_READOUT_CPU_CASE="$scenario" DEVICE_READOUT_CPU_TRACE="$trace" DEVICE_READOUT_CPU_GATE="$gate" \
        python3 - "$bin_path/NativeConsumer" "$fixture_root/cpu-topology.dylib" <<'PY'
import os
import subprocess
import sys
environment = os.environ.copy()
environment["DYLD_INSERT_LIBRARIES"] = sys.argv[2]
subprocess.run([sys.argv[1], "--cpu-topology-consumer"], env=environment, check=True, timeout=15)
PY
    cat "$trace"
done
trap - EXIT
