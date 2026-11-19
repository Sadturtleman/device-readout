#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then echo 'The native RAM fixture requires macOS.' >&2; exit 1; fi
configuration=${CONFIGURATION:-debug}
case "$configuration" in debug|release) ;; *) echo 'Invalid configuration' >&2; exit 1;; esac
swift_bin=${SWIFT_BIN:-swift}
fixture_root="$repo_root/.tools/swift-memory-fixture-$configuration"
mkdir -p "$fixture_root"
xcrun clang -dynamiclib -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    "$repo_root/tools/swift-native-consumer/Fixtures/ram-free.c" -o "$fixture_root/ram-free.dylib"
bin_path=$("$swift_bin" build --package-path "$repo_root/tools/swift-native-consumer" \
    --scratch-path "$repo_root/.tools/swift-consumer-build" -c "$configuration" --show-bin-path)
test -x "$bin_path/NativeConsumer"
for scenario in known large-page zero page-failure statistics-failure short-response invalid-page overflow; do
    trace="$fixture_root/$scenario.log"
    : > "$trace"
    trap 'cat "$trace"' EXIT
    DEVICE_READOUT_RAM_CASE="$scenario" DEVICE_READOUT_RAM_TRACE="$trace" \
        DYLD_INSERT_LIBRARIES="$fixture_root/ram-free.dylib" "$bin_path/NativeConsumer" --ram-free-consumer
    cat "$trace"
done
trap - EXIT
