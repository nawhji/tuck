#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'Xcode is required. Run this script on a Mac with full Xcode selected.' >&2
    exit 1
fi
bash scripts/setup-local.sh
mkdir -p .build/logs
xcodebuild -version
# Neither build installs an app, signs with a team, nor needs an API key.
xcodebuild -project Tuck.xcodeproj -scheme Tuck -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/simulator CODE_SIGNING_ALLOWED=NO build \
    2>&1 | tee .build/logs/simulator-build.log
xcodebuild -project Tuck.xcodeproj -scheme Tuck -configuration Debug \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath .build/device CODE_SIGNING_ALLOWED=NO build \
    2>&1 | tee .build/logs/device-build.log
# A concrete available Simulator is required to run XCTest; pass its UDID.
if [ -n "${1:-}" ]; then
    xcodebuild -project Tuck.xcodeproj -scheme Tuck -configuration Debug \
        -destination "platform=iOS Simulator,id=$1" \
        -derivedDataPath .build/simulator CODE_SIGNING_ALLOWED=NO test \
        2>&1 | tee .build/logs/tests.log
else
    echo 'Builds finished. To run XCTest cases, use Product > Test on an iPhone Simulator in Xcode.'
fi
