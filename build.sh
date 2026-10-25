#!/bin/bash
set -euo pipefail

ROGER_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
"$ROGER_ROOT/scripts/swift-package.sh" build -c release
ROGER_BIN="$("$ROGER_ROOT/scripts/swift-package.sh" build -c release --show-bin-path)"
ROGER_APP="$ROGER_ROOT/dist/Roger.app"
mkdir -p "$ROGER_APP/Contents/MacOS" "$ROGER_APP/Contents/Resources"
cp "$ROGER_BIN/Roger" "$ROGER_APP/Contents/MacOS/Roger"
# The icons are drawn by scripts/make-icon.swift; rerun it after changing the mark.
cp "$ROGER_ROOT/Resources/AppIcon.icns" "$ROGER_ROOT/Resources/MenuBarIcon.png" "$ROGER_ROOT/Resources/MenuBarIcon@2x.png" "$ROGER_APP/Contents/Resources/"
cat > "$ROGER_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>Roger</string>
    <key>CFBundleIdentifier</key><string>com.george.roger</string>
    <key>CFBundleName</key><string>Roger</string>
    <key>CFBundleDisplayName</key><string>Roger</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
ROGER_IDENTITY="${ROGER_SIGN_IDENTITY:-CopyOver Local Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$ROGER_IDENTITY\""; then
    codesign --force --deep -s "$ROGER_IDENTITY" "$ROGER_APP"
    printf 'Signed with %s\n' "$ROGER_IDENTITY"
else
    codesign --force --deep -s - "$ROGER_APP"
    printf 'No "%s" identity in the keychain: signed ad-hoc, so macOS will ask for Accessibility again after each build.\n' "$ROGER_IDENTITY"
fi
printf 'Built %s\n' "$ROGER_APP"
