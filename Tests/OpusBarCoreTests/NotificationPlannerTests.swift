import Foundation
@testable import OpusBarCore
import OpusBarWire
import XCTest

final class NotificationPlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let all = NotificationRules(needsYou: true, error: true, done: true)

    private func state(_ sessions: Session...) -> SessionsState {
        SessionsState(byId: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }))
    }

    private func session(_ id: String, _ s: SessionState, detail: String? = nil, agent: AgentKind = .claude,
                         discovered: Bool = false) -> Session {
        Session(id: id, agent: agent, cwd: "/Users/me/api-server", state: s, detail: detail, startedAt: t0,
                isDiscovered: discovered)
    }

    func testEnteringNeedsYouPostsWithDetail() {
        let plan = NotificationPlanner.plan(old: state(session("a", .working)),
                                            new: state(session("a", .needsAttention, detail: "Allow Bash?")), rules: all)
        XCTAssertEqual(plan.post, [SessionNotice(sessionId: "a", state: .needsAttention, title: "api-server needs you",
                                                 body: "Claude Code · Allow Bash?", thread: "/Users/me/api-server")])
        XCTAssertEqual(plan.clear, [])
    }

    func testStayingInTheSameStateDoesNotRepost() {
        let plan = NotificationPlanner.plan(old: state(session("a", .needsAttention, detail: "x")),
                                            new: state(session("a", .needsAttention, detail: "y")), rules: all)
        XCTAssertEqual(plan, NotificationPlanner.Plan())
    }

    func testDoneAndErrorFollowTheirToggles() {
        let old = state(session("a", .working), session("b", .working))
        let new = state(session("a", .done, agent: .codex), session("b", .error, detail: "API error"))
        let plan = NotificationPlanner.plan(old: old, new: new, rules: all)
        XCTAssertEqual(plan.post.map(\.title), ["api-server is done", "api-server hit an error"])
        XCTAssertEqual(plan.post[0].body, "Codex · Finished its turn")
        XCTAssertEqual(plan.post[1].body, "Claude Code · API error")

        let defaults = NotificationRules(needsYou: true, error: true, done: false)
        XCTAssertEqual(NotificationPlanner.plan(old: old, new: new, rules: defaults).post.map(\.state), [.error])
        let none = NotificationRules(needsYou: false, error: false, done: false)
        XCTAssertEqual(NotificationPlanner.plan(old: old, new: new, rules: none).post, [])
    }

    func testNewSessionAlreadyNeedingYouPosts() {
        let plan = NotificationPlanner.plan(old: state(), new: state(session("a", .needsAttention)), rules: all)
        XCTAssertEqual(plan.post.first?.body, "Claude Code · Waiting for you")
    }

    func testTwoSessionsInOneFolderNameTheSession() {
        var named = session("a", .needsAttention, detail: "Allow Bash?")
        named.title = "fix-login"
        var sameAsFolder = session("b", .needsAttention)
        sameAsFolder.title = "API-Server"
        var madeUp = session("c", .needsAttention)
        madeUp.title = "api-server-8d"
        madeUp.titleIsDerived = true
        let plan = NotificationPlanner.plan(old: state(), new: state(named, sameAsFolder, madeUp), rules: all)
        XCTAssertEqual(plan.post.map(\.body), ["Claude Code · fix-login · Allow Bash?", "Claude Code · Waiting for you",
                                               "Claude Code · Waiting for you"])
        XCTAssertEqual(Set(plan.post.map(\.thread)), ["/Users/me/api-server"])
    }

    func testLeavingNeedsYouClearsItsNotification() {
        let plan = NotificationPlanner.plan(old: state(session("a", .needsAttention)),
                                            new: state(session("a", .working)), rules: all)
        XCTAssertEqual(plan.post, [])
        XCTAssertEqual(plan.clear, ["a"])
    }

    func testRemovedSessionsClearTheirNotifications() {
        let plan = NotificationPlanner.plan(old: state(session("a", .needsAttention), session("b", .error),
                                                       session("c", .done), session("d", .working)),
                                            new: state(), rules: all)
        XCTAssertEqual(plan.clear, ["a", "b", "c"])
    }

    func testRetryAfterErrorClearsTheErrorNotification() {
        let plan = NotificationPlanner.plan(old: state(session("a", .error)), new: state(session("a", .thinking)), rules: all)
        XCTAssertEqual(plan.clear, ["a"])
        XCTAssertEqual(plan.post, [])
    }

    func testDiscoveredSessionsNeverNotify() {
        let plan = NotificationPlanner.plan(old: state(), new: state(session("pid:1", .working, discovered: true)), rules: all)
        XCTAssertEqual(plan, NotificationPlanner.Plan())
    }
}
