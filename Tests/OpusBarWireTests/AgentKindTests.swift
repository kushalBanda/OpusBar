import OpusBarWire
import XCTest

final class AgentKindTests: XCTestCase {
    func testAgentArgumentForms() {
        XCTAssertEqual(AgentKind.fromArguments(["--agent", "codex"]), .codex)
        XCTAssertEqual(AgentKind.fromArguments(["--agent=Codex"]), .codex)
        XCTAssertNil(AgentKind.fromArguments([]))
        XCTAssertNil(AgentKind.fromArguments(["--agent"]))
        XCTAssertNil(AgentKind.fromArguments(["--agent", "opencode"]))
    }

    func testRemovedAgentsAreUnknown() {
        XCTAssertTrue(AgentKind.namesUnknownAgent(["--agent", "pi"]))
        XCTAssertTrue(AgentKind.namesUnknownAgent(["--agent=omp"]))
        XCTAssertFalse(AgentKind.namesUnknownAgent([]), "no agent means Claude Code")
        XCTAssertFalse(AgentKind.namesUnknownAgent(["--agent", "codex"]))
    }

    func testWireRoundTripKeepsAgent() throws {
        let event = WireEvent(ts: 5, pid: 7, agent: .codex, e: SlimEvent(sessionId: "s", event: .stop))
        XCTAssertEqual(try WireEvent.decode(line: event.encodedLine()), event)
    }

    func testWireWithoutAgentDecodesAsNil() throws {
        let line = Data(#"{"v":1,"ts":1,"e":{"sessionId":"s","event":"Stop"}}"#.utf8)
        XCTAssertNil(try WireEvent.decode(line: line).agent)
    }

    func testUnknownAgentStillDecodesEvent() throws {
        let line = Data(#"{"v":1,"ts":1,"agent":"future-agent","e":{"sessionId":"s","event":"Stop"}}"#.utf8)
        let event = try WireEvent.decode(line: line)
        XCTAssertNil(event.agent)
        XCTAssertEqual(event.e.sessionId, "s")
    }
}
