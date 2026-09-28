import AppKit
import OpusBarCore
import OpusBarWire

/// Composition root: paths, session store, socket server, status item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = OpusBarPaths.current()
    private var server: SocketServer?
    private var statusItem: StatusItemController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = SessionStore()
        let server = SocketServer(path: paths.socket.path) { event in
            #if DEBUG
            NSLog("OpusBar event: %@ %@ pid=%d tool=%@ type=%@", event.e.event.rawValue, event.e.sessionId,
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
        statusItem = StatusItemController(store: store)
    }


    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
