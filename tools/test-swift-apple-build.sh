#!/bin/bash
set -euo pipefail
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
    echo 'Apple SDK verification requires macOS with Xcode.' >&2
    exit 1
fi
log_root="$repo_root/.tools/apple-ci-logs"
mkdir -p "$log_root"
{
    git -C "$repo_root" rev-parse HEAD
    sw_vers
    uname -m
    xcodebuild -version
    xcrun swift --version
    xcrun --sdk iphoneos --show-sdk-version
    xcrun --sdk iphonesimulator --show-sdk-version
} 2>&1 | tee "$log_root/ios-toolchain.log"
cd "$repo_root/swift"
xcodebuild -list -json 2>&1 | tee "$log_root/ios-schemes.log"
for sdk in iphoneos iphonesimulator; do
    destination='generic/platform=iOS'
    if [[ $sdk == iphonesimulator ]]; then destination='generic/platform=iOS Simulator'; fi
    for configuration in Debug Release; do
        xcodebuild -scheme DeviceReadout -sdk "$sdk" -destination "$destination" \
            -configuration "$configuration" \
            -derivedDataPath "$repo_root/.tools/swift-apple-$sdk" \
            IPHONEOS_DEPLOYMENT_TARGET=16.0 CODE_SIGNING_ALLOWED=NO \
            SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build 2>&1 | \
            tee "$log_root/$sdk-$configuration.log"
    done
done
