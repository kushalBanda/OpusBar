import OpusBarCore
import OpusBarWire
import XCTest

final class SocketRoundTripTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        // Short path: sun_path is limited to 104 bytes.
        directory = URL(filePath: "/tmp/obt-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSocketRoundTrip() throws {
        let path = directory.appending(path: "events.sock").path
        let received = expectation(description: "event delivered")
        let box = Box()
        let server = SocketServer(path: path) { event in
            box.set(event)
            received.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let sent = WireEvent(ts: 42, pid: 7, e: SlimEvent(sessionId: "rt", event: .stop, cwd: "/tmp/p"))
        XCTAssertTrue(SocketClient.send(try sent.encodedLine(), toSocketAt: path, timeoutMs: 200))

        wait(for: [received], timeout: 1)
        XCTAssertEqual(box.get(), sent)
    }

    func testStopRemovesSocketFile() throws {
        let path = directory.appending(path: "events.sock").path
        let server = SocketServer(path: path) { _ in }
        try server.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var value: WireEvent?
    func set(_ event: WireEvent) { lock.withLock { value = event } }
    func get() -> WireEvent? { lock.withLock { value } }
}
