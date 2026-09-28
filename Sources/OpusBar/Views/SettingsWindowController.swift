import AppKit
import SwiftUI

/// Owns the one Settings window. An AppKit window, not the SwiftUI `Settings` scene:
/// an accessory app has no app menu, and on macOS 14 the scene only opens through `SettingsLink`.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsStubView()))
            window.title = "OpusBar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// M1 placeholder. The real panes (General, Hooks, Notifications, License, About) arrive in M2.
struct SettingsStubView: View {
    var body: some View {
        VStack(spacing: 10) {
            CatView(state: .idle, points: 64)
            Text("Settings arrive in M2").font(.headline)
            Text("Hooks, notifications and launch at login live here next.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(width: 420)
    }
}
