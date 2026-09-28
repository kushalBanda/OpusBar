# 5. NSStatusItem + transient NSPopover; AppKit Settings window

- Status: Accepted
- Date: 2026-09-28

## Context
The menu bar needs a frame-animated, full-color sprite with a badge. SwiftUI `MenuBarExtra` can't animate the label frame by frame. The app is an accessory app (`LSUIElement`), so it has no app menu, and on macOS 14 the SwiftUI `Settings` scene only opens through `SettingsLink`.

## Decision
- `NSStatusItem` drawn by `StatusItemController`: composed non-template `NSImage` (cat 16 pt + optional badge), cached per frame.
- Dropdown: transient `NSPopover` hosting SwiftUI `SessionListView`. Outside click closes (transient). Esc closes via a local key monitor installed only while shown. The app activates on open so the popover can take keys. Popover animation follows Reduce Motion.
- Settings: `SettingsWindowController` owns one AppKit `NSWindow` hosting SwiftUI. The SwiftUI `Settings` scene stays as `Settings { EmptyView() }` only because an `App` needs a scene.

## Consequences
- Full control of sprite drawing and dropdown layout; all content is still SwiftUI.
- An `NSPanel` remains possible later if the popover arrow or sizing becomes a problem.
