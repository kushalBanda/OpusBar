import OpusBarCore
import OpusBarWire
import XCTest

final class AggregateTests: XCTestCase {
    private func session(_ id: String, _ state: SessionState) -> Session {
        Session(id: id, cwd: "/p/\(id)", state: state, startedAt: Date(timeIntervalSince1970: 0))
    }

    func testAggregatePriorityErrorWins() {
        let agg = Aggregate.of([session("a", .working), session("b", .error), session("c", .needsAttention)])
        XCTAssertEqual(agg.state, .error)
    }

    func testAggregateWorkingBeatsThinking() {
        XCTAssertEqual(Aggregate.of([session("a", .thinking), session("b", .working)]).state, .working)
    }

    func testAggregateNeedsYouCount() {
        let agg = Aggregate.of([session("a", .needsAttention), session("b", .needsAttention), session("c", .idle)])
        XCTAssertEqual(agg.needsYouCount, 2)
        XCTAssertEqual(agg.activeCount, 2)
    }

    func testAggregateNilWhenEmpty() {
        XCTAssertEqual(Aggregate.of([Session]()), Aggregate(state: nil, needsYouCount: 0, activeCount: 0))
    }
}

final class SessionStoreTests: XCTestCase {
    @MainActor func testStoreApplyUpdatesAggregate() {
        let store = SessionStore(now: { Date(timeIntervalSince1970: 5) })
        store.apply(WireEvent(ts: 1, e: SlimEvent(sessionId: "x", event: .permissionRequest, cwd: "/p/x", toolName: "Bash")))
        XCTAssertEqual(store.aggregate, Aggregate(state: .needsAttention, needsYouCount: 1, activeCount: 1))
        XCTAssertEqual(store.sessions.map(\.id), ["x"])
    }

    @MainActor func testStoreReadsBranchAtTurnEdgesOnly() {
        var reads: [String] = []
        var branch = "main"
        let store = SessionStore(now: { Date(timeIntervalSince1970: 5) }, branchReader: { reads.append($0); return branch })
        store.apply(WireEvent(ts: 1, e: SlimEvent(sessionId: "x", event: .sessionStart, cwd: "/p/x")))
        XCTAssertEqual(store.sessions.first?.branch, "main")
        branch = "feature"
        store.apply(WireEvent(ts: 2, e: SlimEvent(sessionId: "x", event: .preToolUse, cwd: "/p/x", toolName: "Bash")))
        XCTAssertEqual(store.sessions.first?.branch, "main", "mid-turn events skip the read")
        store.apply(WireEvent(ts: 3, e: SlimEvent(sessionId: "x", event: .stop, cwd: "/p/x")))
        XCTAssertEqual(store.sessions.first?.branch, "feature")
        XCTAssertEqual(reads, ["/p/x", "/p/x"])
    }
}
