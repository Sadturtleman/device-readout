#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift_bin=${SWIFT_BIN:-swift}
mkdir -p "$repo_root/.tools/swift-build" "$repo_root/.tools/swift-cache" "$repo_root/.tools/swift-module-cache"
exec "$swift_bin" test --package-path "$repo_root/swift" \
    --scratch-path "$repo_root/.tools/swift-build" --cache-path "$repo_root/.tools/swift-cache" \
    -Xswiftc -module-cache-path -Xswiftc "$repo_root/.tools/swift-module-cache" "$@"
