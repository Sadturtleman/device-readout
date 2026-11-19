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
trace="$fixture_root/cleanup-trace.log"
: > "$trace"
trap 'cat "$trace"' EXIT
DEVICE_READOUT_POWER_TRACE="$trace" DYLD_INSERT_LIBRARIES="$fixture_root/power-cleanup.dylib" \
    "$bin_path/NativeConsumer" --power-cleanup-fixture
