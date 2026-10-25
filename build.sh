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
# Ad-hoc signatures change with every build, and macOS binds the Accessibility
# grant to that signature. A code-signing identity named CopyOver in the login
# keychain keeps the grant across builds. COPYOVER_SIGN_IDENTITY overrides it.
COPYOVER_IDENTITY="${COPYOVER_SIGN_IDENTITY:-}"
if [ -z "$COPYOVER_IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"CopyOver"'; then
    COPYOVER_IDENTITY="CopyOver"
fi
codesign --force -s "${COPYOVER_IDENTITY:--}" "$COPYOVER_APP"
printf 'Signed with %s\n' "${COPYOVER_IDENTITY:-an ad-hoc signature}"
printf 'Built %s\n' "$COPYOVER_APP"
