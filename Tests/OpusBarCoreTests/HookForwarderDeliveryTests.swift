import OpusBarCore
import OpusBarWire
import XCTest

/// Hook binary logic against the real server: the full path minus Claude Code.
final class HookForwarderDeliveryTests: XCTestCase {
    func testForwarderDeliversSlimLineToListeningServer() throws {
        let home = URL(filePath: "/tmp/obd-\(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = OpusBarPaths(home: home)

        let received = expectation(description: "delivered")
        let box = EventBox()
        let server = SocketServer(path: paths.socket.path) { event in
            box.set(event)
            received.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data(#"{"session_id":"live","hook_event_name":"PreToolUse","cwd":"/p","tool_name":"Edit","tool_input":{"x":1}}"#.utf8))
        try pipe.fileHandleForWriting.close()

        let code = HookForwarder.run(
            stdin: pipe.fileHandleForReading,
            arguments: ["--agent", "codex"],
            environment: ["TERM_PROGRAM": "Apple_Terminal"],
            parentPID: 321,
            nowMs: { 77 },
            paths: paths
        )
        XCTAssertEqual(code, 0)
        wait(for: [received], timeout: 1)
        let event = try XCTUnwrap(box.get())
        XCTAssertEqual(event.ts, 77)
        XCTAssertEqual(event.pid, 321)
        XCTAssertEqual(event.agent, .codex)
        XCTAssertEqual(event.term?.termProgram, "Apple_Terminal")
        XCTAssertEqual(event.e, SlimEvent(sessionId: "live", event: .preToolUse, cwd: "/p", toolName: "Edit"))
    }

    func testLeftoverPiExtensionIsNeverReportedAsClaude() throws {
        let home = URL(filePath: "/tmp/obp-\(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = OpusBarPaths(home: home)
        let received = expectation(description: "nothing delivered")
        received.isInverted = true
        let server = SocketServer(path: paths.socket.path) { _ in received.fulfill() }
        try server.start()
        defer { server.stop() }

        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data(#"{"session_id":"pi-1","hook_event_name":"Stop","cwd":"/p"}"#.utf8))
        try pipe.fileHandleForWriting.close()
        let code = HookForwarder.run(stdin: pipe.fileHandleForReading, arguments: ["--agent", "pi"], environment: [:],
                                     parentPID: 1, nowMs: { 1 }, paths: paths)
        XCTAssertEqual(code, 0)
        wait(for: [received], timeout: 0.3)
    }

    func testServerDropsMalformedLineAndKeepsServing() throws {
        let path = "/tmp/obm-\(UUID().uuidString.prefix(6))/events.sock"
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let received = expectation(description: "valid event after garbage")
        let server = SocketServer(path: path) { _ in received.fulfill() }
        try server.start()
        defer { server.stop() }

        XCTAssertTrue(SocketClient.send(Data("garbage\n".utf8), toSocketAt: path, timeoutMs: 200))
        let good = WireEvent(ts: 1, e: SlimEvent(sessionId: "ok", event: .stop))
        XCTAssertTrue(SocketClient.send(try good.encodedLine(), toSocketAt: path, timeoutMs: 200))
        wait(for: [received], timeout: 1)
    }

    func testServerStartRemovesStaleSocketFile() throws {
        let dir = "/tmp/obs-\(UUID().uuidString.prefix(6))"
        let path = dir + "/events.sock"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))
        let server = SocketServer(path: path) { _ in }
        XCTAssertNoThrow(try server.start())
        server.stop()
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: WireEvent?
    func set(_ event: WireEvent) { lock.withLock { value = event } }
    func get() -> WireEvent? { lock.withLock { value } }
}
