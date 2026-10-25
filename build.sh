#!/bin/bash
set -euo pipefail

COPYOVER_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
"$COPYOVER_ROOT/scripts/swift-package.sh" build -c release
COPYOVER_BIN="$("$COPYOVER_ROOT/scripts/swift-package.sh" build -c release --show-bin-path)"
COPYOVER_APP="$COPYOVER_ROOT/dist/CopyOver.app"
mkdir -p "$COPYOVER_APP/Contents/MacOS"
cp "$COPYOVER_BIN/CopyOver" "$COPYOVER_APP/Contents/MacOS/CopyOver"
cat > "$COPYOVER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>CopyOver</string>
    <key>CFBundleIdentifier</key><string>com.george.copyover</string>
    <key>CFBundleName</key><string>CopyOver</string>
    <key>CFBundleDisplayName</key><string>CopyOver</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# macOS binds the Accessibility grant to the signature, so a stable identity
# keeps the grant across builds. Without one the app is ad-hoc signed and the
# grant has to be given again after every rebuild.
COPYOVER_IDENTITY="${COPYOVER_SIGN_IDENTITY:-CopyOver Local Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$COPYOVER_IDENTITY\""; then
    codesign --force --deep -s "$COPYOVER_IDENTITY" "$COPYOVER_APP"
    printf 'Signed with %s\n' "$COPYOVER_IDENTITY"
else
    codesign --force --deep -s - "$COPYOVER_APP"
    printf 'No "%s" identity in the keychain: signed ad-hoc, so macOS will ask for Accessibility again after each build.\n' "$COPYOVER_IDENTITY"
fi
printf 'Built %s\n' "$COPYOVER_APP"
