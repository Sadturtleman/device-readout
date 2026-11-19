#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then echo 'The native CPU identity fixture requires macOS.' >&2; exit 1; fi
configuration=${CONFIGURATION:-debug}
case "$configuration" in debug|release) ;; *) echo 'Invalid configuration' >&2; exit 1;; esac
swift_bin=${SWIFT_BIN:-swift}
fixture_root="$repo_root/.tools/swift-cpu-identity-fixture-$configuration"
mkdir -p "$fixture_root"
xcrun clang -dynamiclib -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$repo_root/tools/swift-native-consumer/Fixtures/cpu-identity.c" -o "$fixture_root/cpu-identity.dylib"
bin_path=$("$swift_bin" build --package-path "$repo_root/tools/swift-native-consumer" \
    --scratch-path "$repo_root/.tools/swift-consumer-build" -c "$configuration" --show-bin-path)
test -x "$bin_path/NativeConsumer"
for scenario in known unicode shrink limit model-failure vendor-failure read-failure size-zero size-one \
    size-too-large size-overflow empty missing-nul short-write invalid-utf8 reported-growth held-get held-watch; do
    trace="$fixture_root/$scenario.log"
    gate="$fixture_root/$scenario.gate"
    : > "$trace"
    rm -f -- "$gate"
    trap 'cat "$trace"' EXIT
    DEVICE_READOUT_IDENTITY_CASE="$scenario" DEVICE_READOUT_IDENTITY_TRACE="$trace" \
        DEVICE_READOUT_IDENTITY_GATE="$gate" \
        python3 - "$bin_path/NativeConsumer" "$fixture_root/cpu-identity.dylib" <<'PY'
import os
import subprocess
import sys
environment = os.environ.copy()
environment["DYLD_INSERT_LIBRARIES"] = sys.argv[2]
subprocess.run([sys.argv[1], "--cpu-identity-consumer"], env=environment, check=True, timeout=15)
PY
    cat "$trace"
done
trap - EXIT
