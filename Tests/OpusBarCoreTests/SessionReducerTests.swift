@testable import OpusBarCore
import OpusBarWire
import XCTest

final class SessionReducerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private var ts: Int64 = 0

    /// Applies events in order, each one second and one ms after the previous.
    private func run(_ events: [SlimEvent], from start: SessionsState = SessionsState()) -> SessionsState {
        var state = start
        for (i, e) in events.enumerated() {
            ts += 1
            state = SessionReducer.reduce(state, WireEvent(ts: ts, pid: 99, e: e), now: t0.addingTimeInterval(Double(i)))
        }
        return state
    }

    private func ev(_ name: HookEventName, _ id: String = "s", tool: String? = nil, type: String? = nil) -> SlimEvent {
        SlimEvent(sessionId: id, event: name, cwd: "/Users/me/api-server", toolName: tool, notificationType: type)
    }

    private func only(_ state: SessionsState) throws -> Session {
        XCTAssertEqual(state.byId.count, 1)
        return try XCTUnwrap(state.byId.values.first)
    }

    func testSessionStartCreatesIdle() throws {
        let s = try only(run([ev(.sessionStart)]))
        XCTAssertEqual(s.state, .idle)
        XCTAssertEqual(s.projectName, "api-server")
        XCTAssertEqual(s.pid, 99)
    }

    func testPromptSubmitThinking() throws {
        XCTAssertEqual(try only(run([ev(.sessionStart), ev(.userPromptSubmit)])).state, .thinking)
    }

    func testPreToolUseWorkingWithTool() throws {
        let s = try only(run([ev(.userPromptSubmit), ev(.preToolUse, tool: "Edit")]))
        XCTAssertEqual(s.state, .working)
        XCTAssertEqual(s.detail, "Edit")
    }

    func testPostToolUseBackToThinking() throws {
        let s = try only(run([ev(.preToolUse, tool: "Edit"), ev(.postToolUse, tool: "Edit")]))
        XCTAssertEqual(s.state, .thinking)
        XCTAssertNil(s.detail)
    }

    func testPostToolUseFailureBackToThinking() throws {
        XCTAssertEqual(try only(run([ev(.preToolUse, tool: "Bash"), ev(.postToolUseFailure, tool: "Bash")])).state, .thinking)
    }

    func testPermissionRequestNeedsAttention() throws {
        let s = try only(run([ev(.preToolUse, tool: "Bash"), ev(.permissionRequest, tool: "Bash")]))
        XCTAssertEqual(s.state, .needsAttention)
        XCTAssertEqual(s.detail, "Allow Bash?")
    }

    func testNotificationPermissionPromptNeedsAttention() throws {
        let s = try only(run([ev(.userPromptSubmit), ev(.notification, type: "permission_prompt")]))
        XCTAssertEqual(s.state, .needsAttention)
        XCTAssertEqual(s.detail, "Waiting for permission")
    }

    func testNotificationKeepsPermissionRequestDetail() throws {
        let s = try only(run([ev(.permissionRequest, tool: "Bash"), ev(.notification, type: "permission_prompt")]))
        XCTAssertEqual(s.detail, "Allow Bash?")
    }

    func testNotificationIdlePromptKeepsState() throws {
        XCTAssertEqual(try only(run([ev(.stop), ev(.notification, type: "idle_prompt")])).state, .done)
    }

    func testSubagentCountIncrementsAndFloorsAtZero() throws {
        let up = try only(run([ev(.subagentStart), ev(.subagentStart), ev(.subagentStop)]))
        XCTAssertEqual(up.subagents, 1)
        let floor = try only(run([ev(.subagentStop), ev(.subagentStop)]))
        XCTAssertEqual(floor.subagents, 0)
    }

    func testStopDoneResetsSubagents() throws {
        let s = try only(run([ev(.subagentStart), ev(.stop)]))
        XCTAssertEqual(s.state, .done)
        XCTAssertEqual(s.subagents, 0)
    }

    func testStopFailureError() throws {
        let s = try only(run([ev(.userPromptSubmit), ev(.stopFailure)]))
        XCTAssertEqual(s.state, .error)
        XCTAssertEqual(s.detail, "API error")
    }

    func testSessionEndRemoves() {
        XCTAssertTrue(run([ev(.sessionStart), ev(.sessionEnd)]).byId.isEmpty)
    }

    func testUnknownSessionIsCreatedOnFirstEvent() throws {
        let s = try only(run([ev(.preToolUse, "mid", tool: "Read")]))
        XCTAssertEqual(s.id, "mid")
        XCTAssertEqual(s.state, .working)
    }

    func testOlderTimestampIgnored() throws {
        var state = SessionReducer.reduce(SessionsState(), WireEvent(ts: 10, e: ev(.stop)), now: t0)
        state = SessionReducer.reduce(state, WireEvent(ts: 5, e: ev(.preToolUse, tool: "Edit")), now: t0)
        XCTAssertEqual(try only(state).state, .done)
    }

    func testOlderSessionEndStillRemoves() {
        var state = SessionReducer.reduce(SessionsState(), WireEvent(ts: 10, e: ev(.stop)), now: t0)
        state = SessionReducer.reduce(state, WireEvent(ts: 5, e: ev(.sessionEnd)), now: t0)
        XCTAssertTrue(state.byId.isEmpty)
    }

    func testStateSinceOnlyChangesOnTransition() throws {
        // Two tool calls in a row stay "working": stateSince is the first one's time.
        let s = try only(run([ev(.userPromptSubmit), ev(.preToolUse, tool: "Read"), ev(.preToolUse, tool: "Edit")]))
        XCTAssertEqual(s.stateSince, t0.addingTimeInterval(1))
        XCTAssertEqual(s.detail, "Edit")
    }

    func testUnknownEventTouchesOnlyTimestamps() throws {
        let s = try only(run([ev(.userPromptSubmit), ev(.unknown("PreCompact"))]))
        XCTAssertEqual(s.state, .thinking)
        XCTAssertEqual(s.lastEventAt, t0.addingTimeInterval(1))
    }

    func testSortedByUrgencyThenAge() {
        let state = run([
            ev(.stop, "done"),
            ev(.preToolUse, "work", tool: "Edit"),
            ev(.permissionRequest, "ask-late", tool: "Bash"),
            ev(.userPromptSubmit, "think"),
            ev(.sessionStart, "idle"),
            ev(.stopFailure, "err"),
        ], from: run([ev(.permissionRequest, "ask-early", tool: "Bash")]))
        XCTAssertEqual(state.sorted.map(\.id), ["err", "ask-early", "ask-late", "work", "think", "done", "idle"])
    }

    func testFullSessionScript() throws {
        let s = try only(run([
            ev(.sessionStart),
            ev(.userPromptSubmit),
            ev(.preToolUse, tool: "Read"),
            ev(.postToolUse, tool: "Read"),
            ev(.subagentStart),
            ev(.preToolUse, tool: "Bash"),
            ev(.permissionRequest, tool: "Bash"),
            ev(.notification, type: "permission_prompt"),
            ev(.postToolUse, tool: "Bash"),
            ev(.subagentStop),
            ev(.stop),
        ]))
        XCTAssertEqual(s.state, .done)
        XCTAssertNil(s.detail)
        XCTAssertEqual(s.subagents, 0)
        XCTAssertEqual(s.stateSince, t0.addingTimeInterval(10))
    }
}
