import Darwin
import Foundation
import Observation
import OpusBarWire

/// Observable home of all sessions. UI reads it; the socket server feeds it.
@MainActor @Observable
public final class SessionStore {
    public private(set) var state = SessionsState()
    /// How long done and errored sessions stay listed.
    public var finishedTTL: TimeInterval

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let isAlive: (Int32) -> Bool
    @ObservationIgnored private let pruneInterval: TimeInterval
    @ObservationIgnored private let branchReader: (String) -> String?
    @ObservationIgnored private var pruneTimer: Timer?

    public init(
        finishedTTL: TimeInterval = 10 * 60,
        pruneInterval: TimeInterval = 30,
        now: @escaping () -> Date = Date.init,
        isAlive: @escaping (Int32) -> Bool = SessionStore.processIsAlive,
        branchReader: @escaping (String) -> String? = GitBranchReader.branch(atPath:)
    ) {
        self.branchReader = branchReader
        self.finishedTTL = finishedTTL
        self.pruneInterval = pruneInterval
        self.now = now
        self.isAlive = isAlive
    }

    public var sessions: [Session] { state.sorted }
    public var aggregate: Aggregate { Aggregate.of(state.byId.values) }

    /// True while a prune timer is scheduled. There is none when no sessions exist, so an idle app does no work.
    public var isPruneTimerRunning: Bool { pruneTimer != nil }

    public func apply(_ event: WireEvent) {
        var next = SessionReducer.reduce(state, event, now: now())
        let id = event.e.sessionId
        if var session = next.byId[id], Self.shouldReadBranch(event.e.event, old: state.byId[id], new: session) {
            session.branch = branchReader(session.cwd)
            next.byId[id] = session
        }
        set(next)
    }

    /// Branch can change between turns, so re-read it at turn edges and whenever the cwd moves. A few small file reads.
    static func shouldReadBranch(_ event: HookEventName, old: Session?, new: Session) -> Bool {
        guard let old else { return true }
        if old.cwd != new.cwd { return true }
        switch event {
        case .sessionStart, .userPromptSubmit, .stop: return true
        default: return false
        }
    }

    public func prune() {
        set(SessionPruner.prune(state, now: now(), finishedTTL: finishedTTL, isAlive: isAlive))
    }

    private func set(_ next: SessionsState) {
        if next != state { state = next }
        updatePruneTimer()
    }

    private func updatePruneTimer() {
        if state.byId.isEmpty {
            pruneTimer?.invalidate()
            pruneTimer = nil
        } else if pruneTimer == nil {
            let timer = Timer(timeInterval: pruneInterval, repeats: true) { _ in
                Task { @MainActor [weak self] in self?.prune() }
            }
            timer.tolerance = pruneInterval / 5
            RunLoop.main.add(timer, forMode: .common)
            pruneTimer = timer
        }
    }

    /// `kill(pid, 0)` succeeds, or fails only for lack of permission: the process exists.
    public nonisolated static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
