# 1. SwiftPM package, Xcode 15.4 toolchain via DEVELOPER_DIR

- Status: Accepted
- Date: 2026-09-28

## Context
The brief asked for an Xcode project. The machine had only the Command Line Tools (no XCTest). Xcode 15.4 was later found at `/Applications/Xcode.app` but is not `xcode-select`'ed.

## Decision
- One Swift package (tools 5.10, macOS 14): targets `OpusBarWire`, `opusbar-hook`, `OpusBarCore`, `OpusBar`, plus `OpusBarWireTests`, `OpusBarCoreTests`. No third-party dependencies.
- Build and test with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build|test`. No sudo, no global toolchain switch.
- `StrictConcurrency` on Wire, Core and the hook.
- `scripts/bundle.sh` assembles `build/OpusBar.app` (generated Info.plist, `LSUIElement`, hook in `Contents/Helpers/`, ad-hoc signed).

## Consequences
- Plain XCTest works; an Xcode project can be generated later if needed.
- Every build command must carry `DEVELOPER_DIR` (or the user runs `sudo xcode-select -s`).
- Developer ID signing and notarization are M5 work in `bundle.sh`.
