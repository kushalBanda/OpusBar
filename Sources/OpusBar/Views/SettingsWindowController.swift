import AppKit
import OpusBarCore
import SwiftUI

/// Owns the one Settings window. An AppKit window, not the SwiftUI `Settings` scene:
/// an accessory app has no app menu, and on macOS 14 the scene only opens through `SettingsLink`.
/// While the window is open OpusBar is a regular app: it gets a Dock icon (so a minimized window has
/// the app to return to), the app menu and ⌘M/⌘W/⌘Q. Closing the window makes it menu bar only again.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private let hooks: AgentHooksModel
    private let preferences: Preferences
    private let launchAtLogin = LaunchAtLogin()
    private let notifier: SessionNotifier
    private let store: SessionStore
    private let entitlements: Entitlements
    private let usage: UsageModel

    init(hooks: AgentHooksModel, preferences: Preferences, notifier: SessionNotifier, store: SessionStore,
         entitlements: Entitlements, usage: UsageModel) {
        self.entitlements = entitlements
        self.usage = usage
        self.hooks = hooks
        self.preferences = preferences
        self.notifier = notifier
        self.store = store
        super.init()
    }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        if window == nil {
            let root = SettingsView(navigation: navigation, preferences: preferences, hooks: hooks,
                                    launchAtLogin: launchAtLogin, notifier: notifier, store: store,
                                    entitlements: entitlements, usage: usage)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "OpusBar"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // The minimized tile in the Dock shows the app icon, not a snapshot of the page.
            window.miniwindowImage = NSApp.applicationIconImage
            window.delegate = self
            window.center()
            self.window = window
        }
        hooks.refresh()
        launchAtLogin.refresh()
        notifier.refreshAccess()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Minimized to the Dock: Settings… from the menu brings it back.
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// Renders a pane offscreen to a PNG without showing or activating anything (`--dump-settings <pane> <png>`).
    func dump(_ pane: SettingsPane, to path: String) {
        let navigation = SettingsNavigation()
        navigation.pane = pane
        let view = NSHostingView(rootView: SettingsView(navigation: navigation, preferences: preferences, hooks: hooks,
                                                        launchAtLogin: launchAtLogin, notifier: notifier, store: store,
                                                        entitlements: entitlements, usage: usage))
        let size = view.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: max(size.width, 760), height: max(size.height, 600)),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            window.orderOut(nil)
            NSLog("OpusBar dumped settings to %@", path)
        }
    }
    #endif

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
