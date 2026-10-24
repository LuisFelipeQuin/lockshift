#!/usr/bin/env bash
#
# Wrap the debug build in a minimal LockShift.app for development.
#
# macOS grants Location Services to a registered application bundle, not to a
# bare executable: `swift run` produces the latter, so locationd never shows the
# permission prompt. This bundle carries the production CFBundleIdentifier, so
# approving it once also covers later `swift run` builds.
#
# No Python runtime is bundled — AppConfig falls back to the dev runtime in
# ~/.lockshift when Resources/runtime is absent.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/dist/LockShift-dev.app"

cd "$REPO/macapp"
swift build
BIN="$(swift build --show-bin-path)/LockShift"
test -x "$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LockShift"

if [ -f "$REPO/assets/AppIcon.icns" ]; then
  cp "$REPO/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LockShift</string>
  <key>CFBundleDisplayName</key><string>LockShift</string>
  <key>CFBundleExecutable</key><string>LockShift</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>io.github.luisfelipequin.lockshift</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.0-dev</string>
  <key>CFBundleVersion</key><string>0.0.0-dev</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocationUsageDescription</key><string>Use this Mac’s location as the approximate starting position of your USB-connected iPhone on the map.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Use this Mac’s location as the approximate starting position of your USB-connected iPhone on the map.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "    (codesign failed — the location prompt may not appear)"

# Register with LaunchServices so tccutil and System Settings can see it.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null || true

echo "Built: $APP"
echo "Run:   open \"$APP\""
