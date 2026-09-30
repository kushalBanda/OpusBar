#!/usr/bin/env bash
# Builds a release of OpusBar into dist/ (ADR 23). Nothing leaves this Mac unless --publish is given.
#   scripts/release.sh 0.2.0             build, sign the zip, write checksums
#   scripts/release.sh 0.2.0 --publish   then create GitHub release v0.2.0 with those files (asks first)
# Needs the update signing key (swift scripts/update-key.swift generate, once per owner).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: scripts/release.sh <version> [--publish]}"
PUBLISH="${2:-}"
REPO="kushalBanda/OpusBar"
DIST="$ROOT/dist"
APP="$ROOT/build/OpusBar.app"
ZIP="OpusBar-$VERSION.zip"
DMG="OpusBar-$VERSION.dmg"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Version must look like 0.2.0" >&2; exit 1; }
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
cd "$ROOT"

# Build number: commits so far, so every release counts up.
BUILD_NUMBER="$(git rev-list --count HEAD)"
ARCHES="arm64 x86_64" CONFIG=release VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" scripts/bundle.sh

echo "Checking the bundle…"
for binary in "$APP/Contents/MacOS/OpusBar" "$APP/Contents/Helpers/opusbar-hook"; do
  archs="$(lipo -archs "$binary")"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "$binary is not universal ($archs)" >&2; exit 1; }
done
codesign --verify --deep --strict "$APP"
# The hook must exit 0 at once with OpusBar not listening (it never blocks an agent).
echo '{}' | HOME="$(mktemp -d)" "$APP/Contents/Helpers/opusbar-hook" || { echo "hook failed" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$DIST/$ZIP"
swift scripts/update-key.swift sign "$DIST/$ZIP" > "$DIST/$ZIP.sig"
# An unversioned copy, so https://github.com/$REPO/releases/latest/download/OpusBar.zip always works (install.sh).
cp "$DIST/$ZIP" "$DIST/OpusBar.zip"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "OpusBar" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$DMG"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 "$ZIP" "OpusBar.zip" "$DMG" > checksums.txt)
cp scripts/install.sh "$DIST/install.sh"

echo
echo "Release $VERSION in $DIST:"
ls -1 "$DIST"

if [[ "$PUBLISH" == "--publish" ]]; then
  echo
  read -r -p "Create GitHub release v$VERSION on $REPO and upload these files? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Not published."; exit 0; }
  NOTES="$DIST/notes.md"
  awk -v v="## $VERSION" '$0==v{on=1;next} /^## /{on=0} on' CHANGELOG.md > "$NOTES" 2>/dev/null || true
  [[ -s "$NOTES" ]] || echo "OpusBar $VERSION" > "$NOTES"
  gh release create "v$VERSION" --repo "$REPO" --title "OpusBar $VERSION" --notes-file "$NOTES" \
    "$DIST/$ZIP" "$DIST/$ZIP.sig" "$DIST/OpusBar.zip" "$DIST/$DMG" "$DIST/checksums.txt" "$DIST/install.sh"
  echo "Published: https://github.com/$REPO/releases/tag/v$VERSION"
fi
