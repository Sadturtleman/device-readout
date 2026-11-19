#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
    echo 'The native power fixture requires macOS.' >&2
    exit 1
fi
configuration=${CONFIGURATION:-debug}
case "$configuration" in debug|release) ;; *) echo 'Invalid configuration' >&2; exit 1;; esac
swift_bin=${SWIFT_BIN:-swift}
fixture_root="$repo_root/.tools/swift-power-fixture-$configuration"
mkdir -p "$fixture_root"
xcrun clang -dynamiclib -fblocks -std=c11 -Wall -Wextra -Werror \
    -mmacosx-version-min=13.0 -framework IOKit -framework CoreFoundation \
    "$repo_root/tools/swift-native-consumer/Fixtures/power-cleanup.c" -o "$fixture_root/power-cleanup.dylib"
bin_path=$("$swift_bin" build --package-path "$repo_root/tools/swift-native-consumer" \
    --scratch-path "$repo_root/.tools/swift-consumer-build" -c "$configuration" --show-bin-path)
test -x "$bin_path/NativeConsumer"
for scenario in close held-retry; do
    trace="$fixture_root/$scenario-trace.log"
    : > "$trace"
    trap 'cat "$trace"' EXIT
    if [[ $scenario == held-retry ]]; then
        gate="$fixture_root/retry-gate-$$-$RANDOM"
        test ! -e "$gate"
        DEVICE_READOUT_POWER_RETRY_GATE="$gate" DEVICE_READOUT_POWER_TRACE="$trace" \
            DYLD_INSERT_LIBRARIES="$fixture_root/power-cleanup.dylib" \
            "$bin_path/NativeConsumer" --power-cleanup-fixture
    else
        DEVICE_READOUT_POWER_TRACE="$trace" DYLD_INSERT_LIBRARIES="$fixture_root/power-cleanup.dylib" \
            "$bin_path/NativeConsumer" --power-cleanup-fixture
    fi
done
