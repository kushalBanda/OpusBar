#!/usr/bin/env bash
# Builds OpusBar.app from the SwiftPM package.
#   scripts/bundle.sh            release build into build/OpusBar.app
#   CONFIG=debug scripts/bundle.sh
#   ARCHES="arm64 x86_64" scripts/bundle.sh   universal binary (release.sh does this)
# Ad-hoc signed: OpusBar ships without an Apple Developer ID (ADR 23).
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
build() {  # build <extra swift build flags...>; prints the bin path
  swift build -c "$CONFIG" "$@" --product OpusBar >&2
  swift build -c "$CONFIG" "$@" --product opusbar-hook >&2
  swift build -c "$CONFIG" "$@" --show-bin-path
}

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
if [[ -z "${ARCHES:-}" ]]; then
  BIN="$(build)"
  cp "$BIN/OpusBar" "$APP/Contents/MacOS/OpusBar"
  cp "$BIN/opusbar-hook" "$APP/Contents/Helpers/opusbar-hook"
else
  # One build per arch, joined with lipo: a multi-arch `swift build` needs Xcode's xcbuild, this doesn't.
  apps=() hooks=()
  for arch in $ARCHES; do
    BIN="$(build --triple "$arch-apple-macosx14.0")"
    apps+=("$BIN/OpusBar") hooks+=("$BIN/opusbar-hook")
  done
  lipo -create "${apps[@]}" -output "$APP/Contents/MacOS/OpusBar"
  lipo -create "${hooks[@]}" -output "$APP/Contents/Helpers/opusbar-hook"
fi
# Flat copies so Bundle.main finds them; the SwiftPM resource bundle is only for `swift run`.
cp -R Sources/OpusBar/Resources/Coats "$APP/Contents/Resources/"
cp Sources/OpusBar/Resources/Catppuccineko-LICENSE.txt Sources/OpusBar/Resources/spicetify-oneko-LICENSE.txt \
   Sources/OpusBar/Resources/0xdhrv-oneko-LICENSE.txt \
   Sources/OpusBar/Resources/InterVariable.ttf Sources/OpusBar/Resources/Inter-LICENSE.txt \
   Sources/OpusBar/Resources/PixelifySans.ttf Sources/OpusBar/Resources/PixelifySans-LICENSE.txt \
   Sources/OpusBar/Resources/usage-prices.json "$APP/Contents/Resources/"

# App icon (also shown on notifications): original pixel cat, rendered from scripts/make-icon.swift.
swift scripts/make-icon.swift "$ROOT/build/icon" >/dev/null
cp "$ROOT/build/icon/OpusBar.icns" "$APP/Contents/Resources/OpusBar.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>OpusBar</string>
  <key>CFBundleDisplayName</key><string>OpusBar</string>
  <key>CFBundleExecutable</key><string>OpusBar</string>
  <key>CFBundleIconFile</key><string>OpusBar</string>
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
