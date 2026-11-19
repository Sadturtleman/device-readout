#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift_bin=${SWIFT_BIN:-swift}
mkdir -p "$repo_root/.tools/swift-consumer-build" "$repo_root/.tools/swift-cache" "$repo_root/.tools/swift-module-cache"
exec "$swift_bin" run --package-path "$repo_root/tools/swift-native-consumer" \
    --scratch-path "$repo_root/.tools/swift-consumer-build" --cache-path "$repo_root/.tools/swift-cache" \
    -Xswiftc -module-cache-path -Xswiftc "$repo_root/.tools/swift-module-cache" \
    -Xswiftc -warnings-as-errors "$@" NativeConsumer
