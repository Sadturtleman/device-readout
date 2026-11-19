#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
probe_root="$repo_root/.tools/power-probe"
mkdir -p "$probe_root"
xcrun clang -dynamiclib -fblocks -std=c11 -Wall -Wextra -Werror \
    -mmacosx-version-min=13.0 -framework IOKit -framework CoreFoundation \
    "$repo_root/tools/swift-native-consumer/Fixtures/power-cleanup.c" -o "$probe_root/fixture.dylib"
xcrun clang -fblocks -std=c11 -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -framework IOKit "$repo_root/tools/swift-native-consumer/Fixtures/probe-notify.c" -o "$probe_root/notify"
"$probe_root/notify"
: > "$probe_root/trace.log"
set +e
DEVICE_READOUT_POWER_TRACE="$probe_root/trace.log" DYLD_INSERT_LIBRARIES="$probe_root/fixture.dylib" "$probe_root/notify"
result=$?
set -e
cat "$probe_root/trace.log"
exit "$result"
