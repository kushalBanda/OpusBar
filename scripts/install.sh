#!/bin/bash
# Installs or updates OpusBar from its latest GitHub release (ADR 23).
#   curl -fsSL https://raw.githubusercontent.com/kushalBanda/OpusBar/main/scripts/install.sh | bash
# Downloads the zip with curl, checks its SHA-256 against the release's checksums.txt, puts OpusBar.app
# in /Applications (or ~/Applications when that isn't writable) and opens it. Nothing else is changed.
set -euo pipefail

REPO="kushalBanda/OpusBar"
BASE="${OPUSBAR_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf 'OpusBar install failed: %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "OpusBar is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "OpusBar needs macOS 14 (Sonoma) or later."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "Downloading OpusBar…"
curl -fsSL --retry 2 -o "$work/OpusBar.zip" "$BASE/OpusBar.zip" || fail "couldn't download the release."
curl -fsSL --retry 2 -o "$work/checksums.txt" "$BASE/checksums.txt" || fail "couldn't download checksums.txt."

expected="$(awk '$2 == "OpusBar.zip" { print $1 }' "$work/checksums.txt")"
actual="$(shasum -a 256 "$work/OpusBar.zip" | cut -d' ' -f1)"
[[ -n "$expected" && "$expected" == "$actual" ]] || fail "the download doesn't match its checksum."

ditto -x -k "$work/OpusBar.zip" "$work" || fail "couldn't unzip."
[[ -d "$work/OpusBar.app" ]] || fail "the zip has no OpusBar.app."

target="${OPUSBAR_APPS_DIR:-/Applications}"
[[ -w "$target" ]] || { target="$HOME/Applications"; mkdir -p "$target"; }

# Quit only the copy being replaced.
running="$target/OpusBar.app/Contents/MacOS/OpusBar"
if pgrep -f "$running" >/dev/null; then
  say "Quitting the running OpusBar…"
  pkill -f "$running" || true
  for _ in $(seq 1 25); do pgrep -f "$running" >/dev/null || break; sleep 0.2; done
fi

rm -rf "$target/OpusBar.app"
mv "$work/OpusBar.app" "$target/OpusBar.app"
say "Installed $(defaults read "$target/OpusBar.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo OpusBar) in $target."
open "$target/OpusBar.app"
say "OpusBar is in your menu bar. Open Settings > Agents to connect Claude Code and Codex."
