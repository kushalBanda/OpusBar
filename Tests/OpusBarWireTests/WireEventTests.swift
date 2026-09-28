import OpusBarWire
import XCTest

final class WireEventTests: XCTestCase {
    func testWireRoundTrip() throws {
        let event = WireEvent(
            ts: 1_727_000_000_123,
            pid: 4242,
            term: TermInfo(termProgram: "iTerm.app"),
            e: SlimEvent(sessionId: "abc", event: .preToolUse, cwd: "/tmp/proj", toolName: "Edit")
        )
        let line = try event.encodedLine()
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(try WireEvent.decode(line: line), event)
    }

    func testSlimMapsFieldsFromHookPayload() throws {
        let payload = """
        {"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/Users/me/api",
         "transcript_path":"/t.jsonl","permission_mode":"default","tool_name":"Bash",
         "tool_input":{"command":"npm test"},"tool_use_id":"toolu_1"}
        """
        let slim = try SlimEvent.slim(hookJSON: Data(payload.utf8))
        XCTAssertEqual(slim.sessionId, "s1")
        XCTAssertEqual(slim.event, .preToolUse)
        XCTAssertEqual(slim.cwd, "/Users/me/api")
        XCTAssertEqual(slim.toolName, "Bash")
        XCTAssertEqual(slim.permissionMode, "default")
    }

    func testUnknownEventNameDecodesAsUnknown() throws {
        let slim = try SlimEvent.slim(hookJSON: Data(#"{"session_id":"s","hook_event_name":"PreCompact"}"#.utf8))
        XCTAssertEqual(slim.event, .unknown("PreCompact"))
        XCTAssertEqual(slim.event.rawValue, "PreCompact")
    }

    /// Captured from Claude Code 2.1.283: SessionStart carries `source`, SessionEnd carries `reason`.
    func testSlimKeepsSessionStartSourceAndSessionEndReason() throws {
        let start = try SlimEvent.slim(hookJSON: Data(#"{"session_id":"s","hook_event_name":"SessionStart","source":"startup"}"#.utf8))
        XCTAssertEqual(start.source, "startup")
        let end = try SlimEvent.slim(hookJSON: Data(#"{"session_id":"s","hook_event_name":"SessionEnd","prompt_id":"p","reason":"other"}"#.utf8))
        XCTAssertEqual(end.reason, "other")
    }
}
