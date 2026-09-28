@testable import OpusBarWire
import XCTest

final class HookForwarderTests: XCTestCase {
    private func pipe(_ data: Data) -> FileHandle {
        let pipe = Pipe()
        let writer = pipe.fileHandleForWriting
        // Write on another thread so large inputs cannot deadlock against the pipe buffer.
        Thread.detachNewThread {
            writer.write(data)
            try? writer.close()
        }
        return pipe.fileHandleForReading
    }

    private func run(_ input: Data, home: String = "/tmp/obh-none-\(UUID().uuidString.prefix(6))") -> (code: Int32, seconds: Double) {
        let start = Date()
        let code = HookForwarder.run(
            stdin: pipe(input),
            environment: [:],
            parentPID: 1,
            nowMs: { 0 },
            paths: OpusBarPaths(home: URL(filePath: home, directoryHint: .isDirectory))
        )
        return (code, Date().timeIntervalSince(start))
    }

    func testForwarderExitsZeroQuicklyWhenNoSocket() {
        let result = run(Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8))
        XCTAssertEqual(result.code, 0)
        XCTAssertLessThan(result.seconds, 0.3)
    }

    func testForwarderExitsZeroOnGarbageStdin() {
        XCTAssertEqual(run(Data("not json at all".utf8)).code, 0)
        XCTAssertEqual(run(Data()).code, 0)
    }

    func testForwarderDrainsAndDropsOversizeInput() {
        let big = Data(repeating: 0x20, count: 3 * HookForwarder.stdinCapBytes)
        let result = run(big)
        XCTAssertEqual(result.code, 0)
        XCTAssertLessThan(result.seconds, 2)
    }

    func testReadCappedKeepsInputUnderCap() {
        let input = Data(#"{"session_id":"s"}"#.utf8)
        XCTAssertEqual(HookForwarder.readCapped(pipe(input)), input)
    }

    func testSlimKeepsOnlyWhitelistedFields() throws {
        let payload = """
        {"session_id":"s","hook_event_name":"UserPromptSubmit","cwd":"/p",
         "prompt":"my secret plan","tool_input":{"command":"cat .env"},"tool_output":"API_KEY=123",
         "last_assistant_message":"here is the key"}
        """
        let encoded = try WireEvent(ts: 1, e: SlimEvent.slim(hookJSON: Data(payload.utf8))).encodedLine()
        let text = String(decoding: encoded, as: UTF8.self)
        for leaked in ["my secret plan", "cat .env", "API_KEY", "here is the key", "prompt", "tool_output"] {
            XCTAssertFalse(text.contains(leaked), "leaked \(leaked)")
        }
    }

    func testSlimThrowsWithoutSessionId() {
        XCTAssertThrowsError(try SlimEvent.slim(hookJSON: Data(#"{"hook_event_name":"Stop"}"#.utf8)))
    }

    func testTermInfoReadsOnlyFourVars() throws {
        let env = ["TERM_PROGRAM": "iTerm.app", "TMUX": "/tmp/tmux-1/default", "SECRET_TOKEN": "x", "HOME": "/Users/me"]
        let info = try XCTUnwrap(TermInfo.from(environment: env))
        let text = String(decoding: try JSONEncoder().encode(info), as: UTF8.self)
        XCTAssertEqual(info.termProgram, "iTerm.app")
        XCTAssertFalse(text.contains("SECRET"))
        XCTAssertFalse(text.contains("/Users/me"))
        XCTAssertNil(TermInfo.from(environment: ["PATH": "/bin"]))
    }

    func testPathsFallBackWhenSocketPathTooLong() {
        let longHome = "/Users/" + String(repeating: "x", count: 80)
        let paths = OpusBarPaths(home: URL(filePath: longHome, directoryHint: .isDirectory))
        XCTAssertEqual(paths.socket.path, longHome + "/.opusbar/events.sock")
        let normal = OpusBarPaths(home: URL(filePath: "/Users/me", directoryHint: .isDirectory))
        XCTAssertEqual(normal.socket.path, "/Users/me/Library/Application Support/OpusBar/events.sock")
    }

    func testWireRejectsOversizeLine() {
        let big = Data(repeating: 0x20, count: WireEvent.maxLineBytes + 1)
        XCTAssertThrowsError(try WireEvent.decode(line: big))
    }

    func testWireRejectsUnknownVersion() throws {
        let line = try WireEvent(v: 99, ts: 1, e: SlimEvent(sessionId: "s", event: .stop)).encodedLine()
        XCTAssertThrowsError(try WireEvent.decode(line: line)) { error in
            XCTAssertEqual(error as? WireEvent.DecodeError, .unsupportedVersion(99))
        }
    }
}
