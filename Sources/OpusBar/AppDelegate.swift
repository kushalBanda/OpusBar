import AppKit
import OpusBarCore
import OpusBarWire

/// Composition root: paths, session store, socket server, status item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = OpusBarPaths.current()
    private var server: SocketServer?
    private var statusItem: StatusItemController?
    private var discovery: DiscoveryScheduler?
    private var preferences: Preferences?
    private var store: SessionStore?
    private var notifier: SessionNotifier?
    private var limitResets: LimitResetNotifier?
    private var settings: SettingsWindowController?
    private var updater: Updater?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BrandFont.register()
        let preferences = Preferences()
        let store = SessionStore(finishedTTL: preferences.retention.seconds)
        self.preferences = preferences
        self.store = store
        followRetention()
        let server = SocketServer(path: paths.socket.path) { event in
            #if DEBUG
            NSLog("OpusBar event: %@ %@ %@ pid=%d tool=%@ type=%@", event.agent?.rawValue ?? "claude(default)", event.e.event.rawValue, event.e.sessionId,
                  event.pid ?? -1, event.e.toolName ?? "-", event.e.notificationType ?? "-")
            #endif
            Task { @MainActor in store.apply(event) }
        }
        do {
            try server.start()
        } catch {
            NSLog("OpusBar: socket server failed to start: \(error)")
        }
        self.server = server
        let environment = ProcessInfo.processInfo.environment
        let discovery = DiscoveryScheduler(store: store, discovery: SessionDiscovery(
            environment: environment,
            claudeProjectRoots: { AgentHooksModel.claudeProjectRoots(environment: environment) },
            codexHomes: { AgentHooksModel.codexHomes(environment: environment).map(\.root) }))
        discovery.start()
        self.discovery = discovery
        let hooks = AgentHooksModel(paths: paths, environment: environment)
        let usage = UsageModel(claudeRoots: { AgentHooksModel.claudeProjectRoots(environment: environment) },
                               codexRoots: { UsageStore.codexRoots(homes: AgentHooksModel.codexHomes(environment: environment)) },
                               claudeAccountFiles: { AgentHooksModel.claudeAccountFiles(environment: environment) })
        usage.start()
        let notifier = SessionNotifier(store: store, preferences: preferences,
                                       isMenuShown: { [weak self] in self?.statusItem?.isMenuShown ?? false },
                                       openMenu: { [weak self] in self?.statusItem?.showMenu() })
        self.notifier = notifier
        limitResets = LimitResetNotifier(usage: usage, preferences: preferences)
        let updater = Updater(preferences: preferences)
        self.updater = updater
        let settings = SettingsWindowController(hooks: hooks, preferences: preferences, notifier: notifier, store: store,
                                                usage: usage, updater: updater)
        self.settings = settings
        NSApp.mainMenu = Self.makeMainMenu()
        statusItem = StatusItemController(store: store, preferences: preferences, hooks: hooks,
                                          usage: usage, updater: updater, settings: settings) {
            discovery.scanNow()
            usage.refresh()
            hooks.refresh() // the first-run card reflects hooks connected outside OpusBar too
        }
        #if DEBUG
        // `--settings <pane>` opens Settings on launch, for screenshots without UI scripting.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--settings"), index + 1 < arguments.count {
            settings.show(SettingsPane(rawValue: arguments[index + 1]))
        }
        if let index = arguments.firstIndex(of: "--dump-settings"), index + 2 < arguments.count,
           let pane = SettingsPane(rawValue: arguments[index + 1]) {
            let path = arguments[index + 2]
            // After the first usage read, so account rows are in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.settings?.dump(pane, to: path) }
        }
        if arguments.contains("--menu") {
            // `--menu-delay <s>` waits first, so test sessions can arrive before the screenshot.
            let delay = arguments.firstIndex(of: "--menu-delay").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.statusItem?.showMenu() }
        }
        #endif
    }

    /// Shown only while Settings is open (the app is regular then): the standard app, Edit and Window
    /// menus, so ⌘Q, ⌘W, ⌘M and copy/paste in text fields work.
    @MainActor
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem()
            holder.submenu = menu
            main.addItem(holder)
            return menu
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        _ = submenu("OpusBar", [
            item("Hide OpusBar", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item("Quit OpusBar", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        NSApp.windowsMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }

    /// Clicking the Dock icon (there while Settings is open) brings a minimized Settings window back.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return true
    }

    /// Keeps the store's finished-session TTL in step with Settings, and prunes right away on a change.
    @MainActor
    private func followRetention() {
        guard let preferences, let store else { return }
        let seconds = withObservationTracking { preferences.retention.seconds } onChange: {
            Task { @MainActor [weak self] in self?.followRetention() }
        }
        if store.finishedTTL != seconds {
            store.finishedTTL = seconds
            store.prune()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
