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
    private var settings: SettingsWindowController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BrandFont.register()
        let preferences = Preferences()
        let entitlements = Self.makeEntitlements()
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
            piFamilyFolders: { PiFamilyFolders.folders(for: $0) }))
        discovery.start()
        self.discovery = discovery
        let hooks = AgentHooksModel(paths: paths, environment: environment)
        let notifier = SessionNotifier(store: store, preferences: preferences,
                                       isMenuShown: { [weak self] in self?.statusItem?.isMenuShown ?? false },
                                       openMenu: { [weak self] in self?.statusItem?.showMenu() })
        self.notifier = notifier
        let settings = SettingsWindowController(hooks: hooks, preferences: preferences, notifier: notifier, store: store,
                                                entitlements: entitlements)
        self.settings = settings
        NSApp.mainMenu = Self.makeMainMenu()
        statusItem = StatusItemController(store: store, preferences: preferences, hooks: hooks,
                                          entitlements: entitlements, settings: settings) {
            discovery.scanNow()
            hooks.refresh() // the first-run card reflects hooks connected outside OpusBar too
        }
        #if DEBUG
        // `--settings <pane>` opens Settings on launch, for screenshots without UI scripting.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--settings"), index + 1 < arguments.count {
            settings.show(SettingsPane(rawValue: arguments[index + 1]))
        }
        if arguments.contains("--menu") {
            // `--menu-delay <s>` waits first, so test sessions can arrive before the screenshot.
            let delay = arguments.firstIndex(of: "--menu-delay").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.statusItem?.showMenu() }
        }
        #endif
    }

    /// Shown only while Settings is open (the app is regular then): the standard app, Edit and Window
    /// menus, so ⌘Q, ⌘W, ⌘M and copy/paste in the license key field work.
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

    /// Live Polar and the login Keychain. Debug builds: `--pro` shows Pro without a key, and
    /// `--polar-sandbox <organization id>` checks keys against Polar's sandbox, kept in a separate Keychain item.
    @MainActor
    private static func makeEntitlements() -> Entitlements {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--pro") { return Entitlements(isPro: true) }
        if let index = arguments.firstIndex(of: "--polar-sandbox"), index + 1 < arguments.count {
            let store = PolarStore(apiBase: PolarStore.sandboxAPI, organizationId: arguments[index + 1],
                                   checkoutURL: URL(string: "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_lhhOin1IJlKBJzHlBzAUOHhcvS9x7C5D6FbBP0CjZic/redirect"))
            return Entitlements(provider: PolarLicenseProvider(store: store),
                                cache: SandboxLicenseCache(), checkoutURL: store.checkoutURL)
        }
        #endif
        return Entitlements(provider: PolarLicenseProvider(store: .live), cache: KeychainLicenseCache(),
                            checkoutURL: PolarStore.live.checkoutURL)
    }

    #if DEBUG
    /// Sandbox keys in UserDefaults: debug builds are re-signed on every build, and the Keychain asks
    /// for the login password each time a differently signed app reads its item. Sandbox keys buy nothing.
    private struct SandboxLicenseCache: LicenseCache {
        private static let defaultsKey = "debugSandboxLicense"

        func load() -> StoredLicense? {
            UserDefaults.standard.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(StoredLicense.self, from: $0) }
        }

        func save(_ license: StoredLicense) throws {
            UserDefaults.standard.set(try JSONEncoder().encode(license), forKey: Self.defaultsKey)
        }

        func clear() {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }
    #endif

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
