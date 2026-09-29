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

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BrandFont.register()
        let preferences = Preferences()
        #if DEBUG
        // `--pro` shows the app as Pro, for screenshots until a key can be checked.
        let entitlements = Entitlements(isPro: ProcessInfo.processInfo.arguments.contains("--pro"))
        #else
        let entitlements = Entitlements()
        #endif
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
