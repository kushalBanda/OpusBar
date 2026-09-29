import Foundation
import OpusBarCore

/// Runs process discovery at launch, every 30 s, and when the dropdown opens.
/// Each pass runs off the main thread; overlapping requests collapse into the running one.
@MainActor
final class DiscoveryScheduler {
    static let interval: TimeInterval = 30

    private let store: SessionStore
    private let discovery: SessionDiscovery
    private var timer: Timer?
    private var isScanning = false

    init(store: SessionStore, discovery: SessionDiscovery = SessionDiscovery()) {
        self.store = store
        self.discovery = discovery
    }

    func start() {
        scanNow()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.scanNow() }
        }
        timer.tolerance = Self.interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func finish(_ found: [DiscoveredProcess]) {
        store.applyDiscovery(found)
        #if DEBUG
        for session in store.sessions {
            NSLog("OpusBar row: %@ %@ %@ %@ discovered=%d", session.agent.rawValue, session.id, session.projectName,
                  session.state.rawValue, session.isDiscovered ? 1 : 0)
        }
        #endif
        isScanning = false
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        let discovery = discovery
        Task.detached(priority: .utility) {
            #if DEBUG
            let started = Date()
            #endif
            let found = discovery.scan()
            #if DEBUG
            NSLog("OpusBar discovery: %d agent process(es) in %.0f ms", found.count, Date().timeIntervalSince(started) * 1000)
            #endif
            await self.finish(found)
        }
    }
}
