#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then echo 'The native OS fixture requires macOS.' >&2; exit 1; fi
configuration=${CONFIGURATION:-debug}
case "$configuration" in debug|release) ;; *) echo 'Invalid configuration' >&2; exit 1;; esac
swift_bin=${SWIFT_BIN:-swift}
fixture_root="$repo_root/.tools/swift-os-fixture-$configuration"
mkdir -p "$fixture_root"
bin_path=$("$swift_bin" build --package-path "$repo_root/tools/swift-native-consumer" \
    --scratch-path "$repo_root/.tools/swift-consumer-build" -c "$configuration" --show-bin-path)
test -x "$bin_path/NativeConsumer"
"$bin_path/NativeConsumer" --os-consumer
xcrun clang -dynamiclib -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$repo_root/tools/swift-native-consumer/Fixtures/os-read.c" -o "$fixture_root/os-read.dylib"
for mode in unavailable held; do
    trace="$fixture_root/$mode.log"
    gate="$fixture_root/gate-$$-$RANDOM"
    test ! -e "$gate"
    : > "$trace"
    trap 'cat "$trace"' EXIT
    DEVICE_READOUT_OS_MODE="$mode" DEVICE_READOUT_OS_TRACE="$trace" DEVICE_READOUT_OS_GATE="$gate" \
        DYLD_INSERT_LIBRARIES="$fixture_root/os-read.dylib" "$bin_path/NativeConsumer" --os-consumer
    cat "$trace"
done
trap - EXIT
