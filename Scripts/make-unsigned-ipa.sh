#!/bin/bash
#
# Build an unsigned / ad-hoc signed iOS app bundle and wrap it as an IPA.
#
# Why this exists:
# Xcode 15.2 cannot deploy to iOS 18+ devices because the required personalized
# developer disk image is unavailable. This script builds the app for arm64
# iPhoneOS 17.2 without Xcode's device installation step. The resulting IPA can
# be signed on the Mac with Sideloadly or AltStore using a free Apple ID.
#
# Output: build/ZAZARA-RACING-unsigned.ipa
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
IPA="$BUILD_DIR/ZAZARA-RACING-unsigned.ipa"
PAYLOAD="$BUILD_DIR/Payload"
APP="$PAYLOAD/ZAZARA RACING.app"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
ICON_SOURCE="$ROOT/Design/zazara-racing-icon.png"

if [[ ! -f "$ICON_SOURCE" ]]; then
    ICON_SOURCE="$ROOT/ZAZARA RACING/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "App icon source not found." >&2
    exit 1
fi

echo "Using SDK: $SDK"

rm -rf "$PAYLOAD" "$IPA"
mkdir -p "$APP"

echo "Compiling arm64 app..."
SDKROOT="$SDK" xcrun swiftc \
    -parse-as-library \
    -O \
    -module-name ZAZARA_RACING \
    -target arm64-apple-ios17.2 \
    -sdk "$SDK" \
    -Xlinker -syslibroot -Xlinker "$SDK" \
    -framework SwiftUI \
    -framework CoreBluetooth \
    -framework Combine \
    -o "$APP/ZAZARA_RACING" \
    "$ROOT/ZAZARA RACING/Localization.swift" \
    "$ROOT/ZAZARA RACING/DesignSystem.swift" \
    "$ROOT/ZAZARA RACING/GPSLinkManager.swift" \
    "$ROOT/ZAZARA RACING/ConnectGPSView.swift" \
    "$ROOT/ZAZARA RACING/LinkedView.swift" \
    "$ROOT/ZAZARA RACING/AppShellView.swift" \
    "$ROOT/ZAZARA RACING/ContentView.swift" \
    "$ROOT/ZAZARA RACING/ZAZARA_RACINGApp.swift"

# Sideload-only workaround for iPhone Duo:
# iOS uses the SDK stamp in LC_BUILD_VERSION to decide whether an app gets the
# native foldable window. We compile with the available iOS 17.2 SDK, then stamp
# the binary as built with iOS 27.1 so iPhone Duo can offer the full inner display.
# A proper Xcode 27.1 build is still the supported long-term solution.
echo "Stamping iOS 27.1 SDK version for iPhone Duo..."
BINARY="$APP/ZAZARA_RACING"
STAMPED="$BINARY.stamped"
xcrun vtool     -set-build-version ios 17.2 27.1 -tool ld 1022.1 -replace \
    "$BINARY" -output "$STAMPED"
mv "$STAMPED" "$BINARY"

echo "Adding app icons..."
sips -z 120 120 "$ICON_SOURCE" --out "$APP/AppIcon60x60@2x.png" >/dev/null
sips -z 180 180 "$ICON_SOURCE" --out "$APP/AppIcon60x60@3x.png" >/dev/null
sips -z 152 152 "$ICON_SOURCE" --out "$APP/AppIcon76x76@2x~ipad.png" >/dev/null
sips -z 167 167 "$ICON_SOURCE" --out "$APP/AppIcon83x83@2x~ipad.png" >/dev/null

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>ZAZARA RACING</string>
    <key>CFBundleExecutable</key>
    <string>ZAZARA_RACING</string>
    <key>CFBundleIconFiles</key>
    <array>
        <string>AppIcon60x60</string>
        <string>AppIcon76x76</string>
        <string>AppIcon83x83</string>
    </array>
    <key>CFBundleIcons</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon60x60</string>
            </array>
        </dict>
    </dict>
    <key>CFBundleIcons~ipad</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon76x76</string>
                <string>AppIcon83x83</string>
            </array>
        </dict>
    </dict>
    <key>CFBundleIdentifier</key>
    <string>com.zazara.racing</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ZAZARA RACING</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.9</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
    <key>CFBundleVersion</key>
    <string>10</string>
    <key>DTCompiler</key>
    <string>com.apple.compilers.llvm.clang.1_0</string>
    <key>DTPlatformBuild</key>
    <string>27A9275</string>
    <key>DTPlatformName</key>
    <string>iphoneos</string>
    <key>DTPlatformVersion</key>
    <string>27.1</string>
    <key>DTSDKBuild</key>
    <string>27A9275</string>
    <key>DTSDKName</key>
    <string>iphoneos27.1</string>
    <key>DTXcode</key>
    <string>2710</string>
    <key>DTXcodeBuild</key>
    <string>27A9275</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>17.2</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>ZAZARA RACING uses Bluetooth to find and link your track GPS receiver.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>ZAZARA RACING uses Bluetooth to find and link your track GPS receiver.</string>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <true/>
        <key>UISceneConfigurations</key>
        <dict/>
    </dict>
    <key>UIApplicationSupportsIndirectInputEvents</key>
    <true/>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UIStatusBarStyle</key>
    <string>UIStatusBarStyleDarkContent</string>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIUserInterfaceStyle</key>
    <string>Light</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
</dict>
</plist>
PLIST

plutil -lint "$APP/Info.plist" >/dev/null
plutil -convert binary1 "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"

xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP" >/dev/null

if ! codesign --verify --deep --strict "$APP"; then
    echo "Ad-hoc code signature verification failed." >&2
    exit 1
fi

echo "Packaging IPA..."
(
    cd "$BUILD_DIR"
    zip -qry "$IPA" Payload
)

echo
echo "Built: $IPA"
echo "Size:  $(du -h "$IPA" | awk '{print $1}')"
echo
echo "Install with Sideloadly:"
echo "  1. Connect iPhone, trust the Mac, enable Developer Mode."
echo "  2. Drag the IPA into Sideloadly."
echo "  3. Sign with your free Apple ID, then trust the developer profile on iPhone."
echo
echo "Free Apple ID signatures expire after 7 days."
