#!/bin/bash
set -euo pipefail

COPYCOPY_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
"$COPYCOPY_ROOT/scripts/swift-package.sh" build -c release
COPYCOPY_BIN="$("$COPYCOPY_ROOT/scripts/swift-package.sh" build -c release --show-bin-path)"
COPYCOPY_APP="$COPYCOPY_ROOT/dist/CopyCopy.app"
mkdir -p "$COPYCOPY_APP/Contents/MacOS"
cp "$COPYCOPY_BIN/CopyCopy" "$COPYCOPY_APP/Contents/MacOS/CopyCopy"
cat > "$COPYCOPY_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>CopyCopy</string>
    <key>CFBundleIdentifier</key><string>com.capfive.copycopy</string>
    <key>CFBundleName</key><string>CopyCopy</string>
    <key>CFBundleDisplayName</key><string>CopyCopy</string>
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
# grant to that signature. A code-signing identity named CopyCopy in the login
# keychain keeps the grant across builds. COPYCOPY_SIGN_IDENTITY overrides it.
COPYCOPY_IDENTITY="${COPYCOPY_SIGN_IDENTITY:-}"
if [ -z "$COPYCOPY_IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"CopyCopy"'; then
    COPYCOPY_IDENTITY="CopyCopy"
fi
codesign --force -s "${COPYCOPY_IDENTITY:--}" "$COPYCOPY_APP"
printf 'Signed with %s\n' "${COPYCOPY_IDENTITY:-an ad-hoc signature}"
printf 'Built %s\n' "$COPYCOPY_APP"
