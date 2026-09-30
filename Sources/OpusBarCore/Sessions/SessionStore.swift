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

    /// The latest hook event per agent since launch, so Settings can show hooks are really working.
    public struct HookActivity: Equatable, Sendable {
        public var lastEventAt: Date
        public var lastEvent: HookEventName
        public var count: Int
    }

    public private(set) var hookActivity: [AgentKind: HookActivity] = [:]

    public var sessions: [Session] { state.sorted }
    public var aggregate: Aggregate { Aggregate.of(state.byId.values) }

    /// True while a prune timer is scheduled. There is none when no sessions exist, so an idle app does no work.
    public var isPruneTimerRunning: Bool { pruneTimer != nil }

    public func apply(_ event: WireEvent) {
        let agent = event.agent ?? .claude
        hookActivity[agent] = HookActivity(lastEventAt: now(), lastEvent: event.e.event,
                                           count: (hookActivity[agent]?.count ?? 0) + 1)
        var next = SessionReducer.reduce(state, event, now: now())
        let id = event.e.sessionId
        // The hook now names this process's session; its discovered placeholder row goes.
        if let pid = event.pid, DiscoveredProcess.sessionId(pid: pid) != id,
           next.byId[DiscoveredProcess.sessionId(pid: pid)]?.isDiscovered == true {
            next.byId[DiscoveredProcess.sessionId(pid: pid)] = nil
        }
        if var session = next.byId[id], Self.shouldReadBranch(event.e.event, old: state.byId[id], new: session) {
            session.branch = branchReader(session.cwd)
            next.byId[id] = session
        }
        set(next)
    }

    /// A discovered session counts as active while its session file changed within this window.
    public static let activeWindow: TimeInterval = 120

    /// Reconciles one discovery pass: adds or refreshes rows for agent processes no hook has reported,
    /// drops discovered rows whose process is gone, and never touches hook-driven sessions.
    public func applyDiscovery(_ found: [DiscoveredProcess]) {
        let now = now()
        var next = state
        let hooked = next.byId.values.filter { !$0.isDiscovered }
        let hookedPIDs = Set(hooked.compactMap(\.pid))
        let hookedIds = Set(hooked.map(\.id))
        // Hooked sessions keep their live states. Discovery lends them the session's name, and corrects
        // one known gap: an interrupted turn (Esc) sends no Stop, so a turn the agent itself reports idle
        // after our last event is over. Needs-you is never cleared this way.
        for process in found {
            guard let id = next.byId.values.first(where: { !$0.isDiscovered && ($0.id == process.sessionId || $0.pid == process.pid) })?.id,
                  var session = next.byId[id]
            else { continue }
            if let host = process.host { session.host = host }
            guard let record = process.record else { next.byId[id] = session; continue }
            if let title = record.title {
                session.title = title
                session.titleIsDerived = record.titleIsDerived
            }
            if Self.turnEndedWithoutStop(session, record: record) {
                session.transition(to: .idle, detail: nil, now: now)
                session.turnStartedAt = nil
            }
            next.byId[id] = session
        }
        let live = found.filter { !hookedPIDs.contains($0.pid) && !hookedIds.contains($0.sessionId) }
        let liveIds = Set(live.map(\.sessionId))
        // Drop rows whose process is gone, or whose id changed (pid row upgraded to the real session id).
        for (id, session) in next.byId where session.isDiscovered && !liveIds.contains(id) {
            next.byId[id] = nil
        }
        for process in live {
            let cwd = process.cwd ?? ""
            var session = next.byId[process.sessionId]
                ?? Session(id: process.sessionId, agent: process.agent, cwd: cwd,
                           startedAt: process.startedAt ?? now, pid: process.pid, isDiscovered: true)
            if session.branch == nil || (!cwd.isEmpty && cwd != session.cwd) {
                session.branch = cwd.isEmpty ? nil : branchReader(cwd)
            }
            if !cwd.isEmpty, cwd != session.cwd {
                session.cwd = cwd
                session.projectName = Session.projectName(for: cwd)
            }
            session.agent = process.agent
            session.pid = process.pid
            session.title = process.record?.title
            session.titleIsDerived = process.record?.titleIsDerived ?? false
            session.host = process.host
            if let record = process.record {
                session.lastEventAt = record.modifiedAt
                // The agent's own status beats guessing from file activity.
                let active = switch record.status {
                case .busy: true
                case .idle: false
                case nil: now.timeIntervalSince(record.modifiedAt) <= Self.activeWindow
                }
                session.transition(to: active ? .working : .idle, detail: nil, now: now)
            }
            next.byId[process.sessionId] = session
        }
        set(next)
    }

    static func turnEndedWithoutStop(_ session: Session, record: SessionRecord) -> Bool {
        guard session.state == .thinking || session.state == .working,
              record.status == .idle, let statusAt = record.statusAt
        else { return false }
        return statusAt > session.lastEventAt
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

    /// Called when the menu closes: every Done that was on screen counts as seen.
    public func acknowledgeDone(seenAt: Date) {
        set(SessionReducer.acknowledgeDone(state, seenAt: seenAt, now: now()))
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
