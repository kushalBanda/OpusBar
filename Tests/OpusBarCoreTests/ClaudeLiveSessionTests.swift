@testable import OpusBarCore
import OpusBarWire
import XCTest

final class ClaudeLiveSessionTests: XCTestCase {
    private var root: URL!
    /// Sun Sep 27 16:38:37 2026 UTC.
    private let started = Date(timeIntervalSince1970: 1_790_527_117)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "opusbar-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "sessions"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeSession(pid: Int32, id: String = "36291872-ed7f", procStart: String = "Sun Sep 27 16:38:37 2026",
                              status: String = "idle", name: String = "quant-8d", cwd: String = "/p/quant") throws {
        let json: [String: Any] = ["pid": pid, "sessionId": id, "cwd": cwd, "procStart": procStart,
                                   "status": status, "name": name, "updatedAt": 1_790_653_926_753]
        try JSONSerialization.data(withJSONObject: json).write(to: root.appending(path: "sessions/\(pid).json"))
    }

    func testReadsIdNameStatusForMatchingProcess() throws {
        try writeSession(pid: 32016, status: "busy")
        let found = SessionRecordReader.claudeLiveSessions(processes: [(32016, started)], configRoots: [root])
        XCTAssertEqual(found[32016]?.id, "36291872-ed7f")
        XCTAssertEqual(found[32016]?.title, "quant-8d")
        XCTAssertEqual(found[32016]?.status, .busy)
        XCTAssertEqual(found[32016]?.cwd, "/p/quant")
        XCTAssertEqual(found[32016]?.modifiedAt, Date(timeIntervalSince1970: 1_790_653_926.753))
    }

    func testTranscriptPathAndNewerMtimeWin() throws {
        try writeSession(pid: 7)
        let transcript = root.appending(path: "projects/-p-quant/36291872-ed7f.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{}".write(to: transcript, atomically: true, encoding: .utf8)
        let recent = Date(timeIntervalSince1970: 1_790_700_000)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: transcript.path)
        let found = SessionRecordReader.claudeLiveSessions(processes: [(7, started)], configRoots: [root])
        XCTAssertEqual(found[7]?.path, transcript.path)
        XCTAssertEqual(found[7]?.modifiedAt, recent)
    }

    func testReusedPidIsRejected() throws {
        try writeSession(pid: 67678, procStart: "Thu Sep 24 02:31:04 2026")
        XCTAssertTrue(SessionRecordReader.claudeLiveSessions(processes: [(67678, started)], configRoots: [root]).isEmpty)
    }

    func testPidInsideFileMustMatchName() throws {
        try writeSession(pid: 5)
        try FileManager.default.moveItem(at: root.appending(path: "sessions/5.json"), to: root.appending(path: "sessions/6.json"))
        XCTAssertTrue(SessionRecordReader.claudeLiveSessions(processes: [(6, started)], configRoots: [root]).isEmpty)
    }

    func testUnknownStatusIsNil() throws {
        try writeSession(pid: 9, status: "shell")
        XCTAssertNil(SessionRecordReader.claudeLiveSessions(processes: [(9, started)], configRoots: [root])[9]?.status)
    }

    func testProcStartWithPaddedDay() {
        XCTAssertEqual(SessionRecordReader.parseProcStart("Fri Sep  4 17:14:00 2026"),
                       ISO8601DateFormatter().date(from: "2026-09-04T17:14:00Z"))
    }

    func testExactMatchesWinAndLeaveTheLastProcessToCwdRules() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = DiscoveredProcess(pid: 1, agent: .claude, cwd: "/p/quant", startedAt: t0)
        let b = DiscoveredProcess(pid: 2, agent: .claude, cwd: "/p/quant", startedAt: t0)
        let c = DiscoveredProcess(pid: 3, agent: .claude, cwd: "/p/quant", startedAt: t0)
        let rec = { (id: String, at: TimeInterval) in
            SessionRecord(id: id, agent: .claude, cwd: "/p/quant", modifiedAt: t0.addingTimeInterval(at), path: "/r/\(id).jsonl")
        }
        let matches = SessionCorrelator.match([a, b, c], records: [rec("s1", 50), rec("s2", 40), rec("s3", 30)],
                                              exact: [1: rec("s1", 50), 2: rec("s2", 40)])
        XCTAssertEqual(matches[1]?.id, "s1")
        XCTAssertEqual(matches[2]?.id, "s2")
        XCTAssertEqual(matches[3]?.id, "s3", "only one unmatched process left in the folder, so cwd matching is safe")
    }

    @MainActor
    func testStoreUsesLiveStatusAndTitle() {
        let clock = Date(timeIntervalSince1970: 10_000)
        let store = SessionStore(now: { clock }, isAlive: { _ in true }, branchReader: { _ in nil })
        let stale = clock.addingTimeInterval(-3_600)
        store.applyDiscovery([DiscoveredProcess(pid: 1, agent: .claude, cwd: "/p/quant", startedAt: nil,
                                                record: SessionRecord(id: "s1", agent: .claude, cwd: "/p/quant", modifiedAt: stale,
                                                                      path: "/r", title: "quant-8d", status: .busy))])
        XCTAssertEqual(store.sessions.first?.state, .working, "busy wins over an old file time")
        XCTAssertEqual(store.sessions.first?.title, "quant-8d")
    }

    @MainActor
    func testHookedSessionBorrowsTitleOnly() {
        let store = SessionStore(now: { Date(timeIntervalSince1970: 1_000) }, isAlive: { _ in true }, branchReader: { _ in nil })
        store.apply(WireEvent(ts: 1, pid: 5, e: SlimEvent(sessionId: "s1", event: .permissionRequest, cwd: "/p/quant", toolName: "Bash")))
        store.applyDiscovery([DiscoveredProcess(pid: 5, agent: .claude, cwd: "/p/quant", startedAt: nil,
                                                record: SessionRecord(id: "s1", agent: .claude, cwd: "/p/quant",
                                                                      modifiedAt: Date(timeIntervalSince1970: 999), path: "/r",
                                                                      title: "quant-8d", status: .idle))])
        XCTAssertEqual(store.sessions.map(\.id), ["s1"])
        XCTAssertEqual(store.sessions.first?.state, .needsAttention)
        XCTAssertEqual(store.sessions.first?.title, "quant-8d")
    }
}
