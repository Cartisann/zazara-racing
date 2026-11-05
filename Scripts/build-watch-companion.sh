#!/bin/bash
# Builds the standalone Watch app, builds the iPhone app with the watch app
# embedded (Workaround for Xcode 27 CopyAndPreserveArchs), and installs it.
#
# Usage:
#   Scripts/build-watch-companion.sh [phoneDerivedData] [deviceID] [device|simulator]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PHONE_DD="${1:-/tmp/zazara-dd-device}"
DEVICE_ID="${2:-00008160-000915911A080036}"
MODE="${3:-device}"

if [ "$MODE" = "simulator" ]; then
  WATCH_BUILD_DIR="/tmp/zazara-watch-build"
  xcodebuild -project "ZAZARA RACING Watch.xcodeproj" \
    -target "ZAZARA RACING Watch" -sdk watchsimulator -configuration Debug \
    CONFIGURATION_BUILD_DIR="$WATCH_BUILD_DIR" build
  xcodebuild -project "ZAZARA RACING.xcodeproj" -scheme "ZAZARA RACING" \
    -configuration Debug -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$PHONE_DD" build
else
  WATCH_BUILD_DIR="/tmp/zazara-watch-build-device"
  xcodebuild -project "ZAZARA RACING Watch.xcodeproj" \
    -target "ZAZARA RACING Watch" -sdk watchos -configuration Debug \
    CONFIGURATION_BUILD_DIR="$WATCH_BUILD_DIR" -allowProvisioningUpdates build
  xcodebuild -project "ZAZARA RACING.xcodeproj" -scheme "ZAZARA RACING" \
    -configuration Debug -destination "platform=iOS,id=${DEVICE_ID}" \
    -derivedDataPath "$PHONE_DD" -allowProvisioningUpdates build
  xcrun devicectl device install app --device "$DEVICE_ID" \
    "$PHONE_DD/Build/Products/Debug-iphoneos/ZAZARA RACING.app"
fi

echo "embedded watch app:"
ls -d "$PHONE_DD"/Build/Products/Debug-*/ZAZARA\ RACING.app/Watch/ZAZARA\ RACING\ Watch.app 2>/dev/null || true
