import AppKit
import OpusBarCore
import SwiftUI

/// Owns the one Settings window. An AppKit window, not the SwiftUI `Settings` scene:
/// an accessory app has no app menu, and on macOS 14 the scene only opens through `SettingsLink`.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private let hooks: AgentHooksModel
    private let preferences: Preferences
    private let launchAtLogin = LaunchAtLogin()
    private let notifier: SessionNotifier
    private let store: SessionStore

    init(hooks: AgentHooksModel, preferences: Preferences, notifier: SessionNotifier, store: SessionStore) {
        self.hooks = hooks
        self.preferences = preferences
        self.notifier = notifier
        self.store = store
    }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        if window == nil {
            let root = SettingsView(navigation: navigation, preferences: preferences, hooks: hooks,
                                    launchAtLogin: launchAtLogin, notifier: notifier, store: store)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "OpusBar Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        hooks.refresh()
        launchAtLogin.refresh()
        notifier.refreshAccess()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
