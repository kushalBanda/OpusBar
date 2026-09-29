import Foundation
@testable import OpusBarCore
import XCTest

final class SessionSectionsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func s(_ id: String, _ state: SessionState, started: TimeInterval, since: TimeInterval = 0) -> Session {
        Session(id: id, cwd: "/p/\(id)", state: state, startedAt: t0.addingTimeInterval(started),
                stateSince: t0.addingTimeInterval(since))
    }

    func testSectionsAndStableOrder() {
        let sections = SessionSections([
            s("old-working", .working, started: 0), s("new-thinking", .thinking, started: 50),
            s("done", .done, started: 20), s("idle-a", .idle, started: 5), s("idle-b", .idle, started: 9),
            s("needs-late", .needsAttention, started: 1, since: 90), s("err-early", .error, started: 2, since: 10),
        ])
        XCTAssertEqual(sections.loud.map(\.id), ["err-early", "needs-late"], "waiting longest first")
        XCTAssertEqual(sections.active.map(\.id), ["new-thinking", "done", "old-working"], "newest session first")
        XCTAssertEqual(sections.idle.map(\.id), ["idle-b", "idle-a"])
    }

    func testThinkingWorkingFlipKeepsPosition() {
        let before = SessionSections([s("a", .working, started: 10), s("b", .thinking, started: 5)])
        let after = SessionSections([s("a", .thinking, started: 10), s("b", .working, started: 5)])
        XCTAssertEqual(before.active.map(\.id), after.active.map(\.id))
    }

    func testSummaryAndGrouping() {
        let few = SessionSections([s("a", .needsAttention, started: 0), s("b", .working, started: 1)])
        XCTAssertEqual(few.summary, "1 needs you · 1 active")
        XCTAssertFalse(few.isGrouped)
        let many = SessionSections((0..<3).map { s("n\($0)", .needsAttention, started: Double($0)) }
            + [s("e", .error, started: 9)] + (0..<9).map { s("i\($0)", .idle, started: Double($0)) })
        XCTAssertEqual(many.summary, "3 need you · 1 error · 9 idle")
        XCTAssertTrue(many.isGrouped)
        XCTAssertEqual(SessionSections([]).summary, "No sessions")
    }
}
