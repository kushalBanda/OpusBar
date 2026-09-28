import OpusBarCore
import OpusBarWire
import XCTest

final class SessionPrunerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 10_000)

    private func state(_ sessions: Session...) -> SessionsState {
        SessionsState(byId: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    private func session(_ id: String, _ s: SessionState, since: TimeInterval, pid: Int32? = nil) -> Session {
        Session(id: id, cwd: "/p/\(id)", state: s, startedAt: t0, stateSince: t0.addingTimeInterval(since), pid: pid)
    }

    private func prune(_ s: SessionsState, at offset: TimeInterval, alive: Set<Int32> = []) -> Set<String> {
        Set(SessionPruner.prune(s, now: t0.addingTimeInterval(offset), finishedTTL: 600, isAlive: { alive.contains($0) }).byId.keys)
    }

    func testPruneRemovesDoneAndErrorAfterTTL() {
        let s = state(session("done", .done, since: 0), session("err", .error, since: 0), session("fresh", .done, since: 300))
        XCTAssertEqual(prune(s, at: 599), ["done", "err", "fresh"])
        XCTAssertEqual(prune(s, at: 600), ["fresh"])
    }

    func testPruneKeepsWorkingPastTTL() {
        let s = state(session("work", .working, since: 0), session("wait", .needsAttention, since: 0))
        XCTAssertEqual(prune(s, at: 86_400), ["work", "wait"])
    }

    func testPruneRemovesDeadPid() {
        let s = state(session("alive", .working, since: 0, pid: 10), session("dead", .working, since: 0, pid: 11))
        XCTAssertEqual(prune(s, at: 1, alive: [10]), ["alive"])
    }

    func testPruneKeepsSessionWithoutPid() {
        XCTAssertEqual(prune(state(session("nopid", .thinking, since: 0)), at: 1), ["nopid"])
    }
}

final class SessionStoreTimerTests: XCTestCase {
    @MainActor func testPruneTimerOnlyWhileSessionsExist() {
        let store = SessionStore(now: { Date(timeIntervalSince1970: 0) }, isAlive: { _ in true })
        XCTAssertFalse(store.isPruneTimerRunning)
        store.apply(WireEvent(ts: 1, pid: 5, e: SlimEvent(sessionId: "a", event: .userPromptSubmit, cwd: "/p")))
        XCTAssertTrue(store.isPruneTimerRunning)
        store.apply(WireEvent(ts: 2, pid: 5, e: SlimEvent(sessionId: "a", event: .sessionEnd)))
        XCTAssertFalse(store.isPruneTimerRunning)
    }

    @MainActor func testStorePruneRemovesDeadSessionAndStopsTimer() {
        var alive = true
        let store = SessionStore(now: { Date(timeIntervalSince1970: 0) }, isAlive: { _ in alive })
        store.apply(WireEvent(ts: 1, pid: 5, e: SlimEvent(sessionId: "a", event: .preToolUse, cwd: "/p", toolName: "Edit")))
        alive = false
        store.prune()
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.isPruneTimerRunning)
    }

    @MainActor func testTimerFiresAndPrunes() async throws {
        var clock = Date(timeIntervalSince1970: 0)
        let store = SessionStore(finishedTTL: 1, pruneInterval: 0.05, now: { clock }, isAlive: { _ in true })
        store.apply(WireEvent(ts: 1, e: SlimEvent(sessionId: "a", event: .stop, cwd: "/p")))
        clock = clock.addingTimeInterval(5)
        // Yield the main actor so the run-loop timer can fire; no manual prune() call.
        for _ in 0..<100 where !store.sessions.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(store.isPruneTimerRunning)
    }

    @MainActor func testProcessIsAliveForSelfAndNotForBogusPid() {
        XCTAssertTrue(SessionStore.processIsAlive(getpid()))
        XCTAssertFalse(SessionStore.processIsAlive(99_999_999))
    }
}
