#!/usr/bin/env bash
# Builds OpusBar.app from the SwiftPM package.
#   scripts/bundle.sh            release build into build/OpusBar.app
#   CONFIG=debug scripts/bundle.sh
# Ad-hoc signed for local runs. Developer ID signing and notarization come in M5.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-dev.opusbar.OpusBar}"
APP="$ROOT/build/OpusBar.app"

# XCTest-free builds work with the Command Line Tools, but prefer full Xcode when it isn't selected.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "$ROOT"
swift build -c "$CONFIG" --product OpusBar
swift build -c "$CONFIG" --product opusbar-hook
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/OpusBar" "$APP/Contents/MacOS/OpusBar"
cp "$BIN/opusbar-hook" "$APP/Contents/Helpers/opusbar-hook"
# Flat copies so Bundle.main finds them; the SwiftPM resource bundle is only for `swift run`.
cp Sources/OpusBar/Resources/oneko-classic.png Sources/OpusBar/Resources/CREDITS.md \
   Sources/OpusBar/Resources/InterVariable.ttf Sources/OpusBar/Resources/Inter-LICENSE.txt "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>OpusBar</string>
  <key>CFBundleDisplayName</key><string>OpusBar</string>
  <key>CFBundleExecutable</key><string>OpusBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 OpusBar</string>
</dict>
</plist>
PLIST

# Inner code first, then the app.
codesign --force --sign - "$APP/Contents/Helpers/opusbar-hook"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "Built $APP ($CONFIG, $VERSION)"
echo "Hook binary: $APP/Contents/Helpers/opusbar-hook"
