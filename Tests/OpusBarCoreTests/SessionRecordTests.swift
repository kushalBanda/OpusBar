@testable import OpusBarCore
import OpusBarWire
import XCTest

final class SessionRecordReaderTests: XCTestCase {
    private var root: URL!
    private let now = Date()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "opusbar-rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private func write(_ text: String, _ path: String, modified: Date? = nil) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    func testClaudeFolderNameEscapesEveryNonAlphanumeric() {
        XCTAssertEqual(SessionRecordReader.claudeProjectFolderName(for: "/Users/me/Git_hub/Opus.Bar"), "-Users-me-Git-hub-Opus-Bar")
    }

    func testClaudeTranscriptsNewestFirstWithIdFromFileName() throws {
        let folder = SessionRecordReader.claudeProjectFolderName(for: "/p/api")
        try write("{}", "projects/\(folder)/old-id.jsonl", modified: now.addingTimeInterval(-600))
        try write("{}", "projects/\(folder)/new-id.jsonl", modified: now.addingTimeInterval(-5))
        try write("{}", "projects/\(folder)/notes.txt")
        var budget = ScanBudget()
        let records = SessionRecordReader.claudeTranscripts(cwd: "/p/api", projectRoots: [root.appending(path: "projects")], now: now, budget: &budget)
        XCTAssertEqual(records.map(\.id), ["new-id", "old-id"])
        XCTAssertEqual(records.first?.cwd, "/p/api")
    }

    func testCodexRolloutFromTodayParsesSessionMeta() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd"
        let day = formatter.string(from: now)
        try write(#"{"type":"session_meta","payload":{"id":"cx-1","cwd":"/p/api","instructions":"long text"}}"# + "\n{\"type\":\"x\"}\n",
                  "codex/sessions/\(day)/rollout-2026-a.jsonl")
        try write(#"{"type":"other"}"# + "\n", "codex/sessions/\(day)/rollout-2026-b.jsonl")
        try write("{}", "codex/sessions/\(day)/history.jsonl")
        var budget = ScanBudget()
        let records = SessionRecordReader.codexRollouts(codexHome: root.appending(path: "codex"), now: now, budget: &budget)
        XCTAssertEqual(records.map(\.id), ["cx-1"])
        XCTAssertEqual(records.first?.cwd, "/p/api")
    }

    func testCodexMetaAcceptsSessionIdKey() {
        let meta = SessionRecordReader.codexSessionMeta(Data(#"{"type":"session_meta","payload":{"session_id":"s2"}}"#.utf8))
        XCTAssertEqual(meta?.id, "s2")
        XCTAssertNil(meta?.cwd)
    }

    func testPiFamilyHeaders() {
        let v3 = Data(#"{"type":"session","version":3,"id":"pi-1","timestamp":"t","cwd":"/p"}"#.utf8)
        let v2 = Data(#"{"type":"session","version":2,"id":"old","cwd":"/p"}"#.utf8)
        let title = Data(#"{"type":"title","title":"Fix"}"#.utf8)
        let omp = Data(#"{"type":"session","id":"omp-1","cwd":"/q"}"#.utf8)
        XCTAssertEqual(SessionRecordReader.piFamilyHeader([v3], dialect: .pi)?.id, "pi-1")
        XCTAssertNil(SessionRecordReader.piFamilyHeader([v2], dialect: .pi))
        XCTAssertEqual(SessionRecordReader.piFamilyHeader([title, omp], dialect: .omp)?.cwd, "/q")
    }

    func testPiFamilyRecordsSkipBucketsOlderThanProcesses() throws {
        let header = #"{"type":"session","version":3,"id":"ID","cwd":"/p/blog"}"#
        try write(header.replacingOccurrences(of: "ID", with: "fresh") + "\n", "pi/--p-blog--/a.jsonl")
        try write(header.replacingOccurrences(of: "ID", with: "stale") + "\n", "pi/--p-old--/b.jsonl", modified: now.addingTimeInterval(-7200))
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)],
                                              ofItemAtPath: root.appending(path: "pi/--p-old--").path)
        var budget = ScanBudget()
        let records = SessionRecordReader.piFamilyRecords(roots: [root.appending(path: "pi")], dialect: .pi,
                                                          since: now.addingTimeInterval(-60), now: now, budget: &budget)
        XCTAssertEqual(records.map(\.id), ["fresh"])
    }

    func testFirstLinesStopsAtCap() throws {
        let url = try write(String(repeating: "x", count: 400_000), "big.jsonl")
        XCTAssertTrue(SessionRecordReader.firstLines(of: url, count: 1).isEmpty, "a header longer than the cap is ignored")
    }
}

final class SessionCorrelatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func record(_ id: String, _ agent: AgentKind, cwd: String, at offset: TimeInterval) -> SessionRecord {
        SessionRecord(id: id, agent: agent, cwd: cwd, modifiedAt: t0.addingTimeInterval(offset), path: "/r/\(id)")
    }

    func testClaudeMatchesNewestRecordChangedAfterStart() {
        let process = DiscoveredProcess(pid: 1, agent: .claude, cwd: "/p/api", startedAt: t0)
        let matches = SessionCorrelator.match([process], records: [
            record("before", .claude, cwd: "/p/api", at: -10),
            record("after", .claude, cwd: "/p/api", at: 30),
            record("other-dir", .claude, cwd: "/p/web", at: 60),
        ])
        XCTAssertEqual(matches[1]?.id, "after")
    }

    func testClaudeSkipsCwdWithSeveralProcesses() {
        let a = DiscoveredProcess(pid: 1, agent: .claude, cwd: "/p/api", startedAt: t0)
        let b = DiscoveredProcess(pid: 2, agent: .claude, cwd: "/p/api/", startedAt: t0)
        XCTAssertTrue(SessionCorrelator.match([a, b], records: [record("x", .claude, cwd: "/p/api", at: 5)]).isEmpty)
    }

    func testCodexIgnoresStartTimeAndUsesEachRecordOnce() {
        let older = DiscoveredProcess(pid: 1, agent: .codex, cwd: "/p", startedAt: t0)
        let newer = DiscoveredProcess(pid: 2, agent: .codex, cwd: "/p", startedAt: t0.addingTimeInterval(10))
        let matches = SessionCorrelator.match([older, newer], records: [
            record("r1", .codex, cwd: "/p", at: -100), record("r2", .codex, cwd: "/p", at: -50),
        ])
        XCTAssertEqual(matches[2]?.id, "r2")
        XCTAssertEqual(matches[1]?.id, "r1")
    }

    func testAgentsNeverCrossMatch() {
        let pi = DiscoveredProcess(pid: 1, agent: .pi, cwd: "/p", startedAt: t0)
        XCTAssertTrue(SessionCorrelator.match([pi], records: [record("o", .omp, cwd: "/p", at: 5)]).isEmpty)
    }
}

final class DiscoveryStoreTests: XCTestCase {
    private func found(_ pid: Int32, id: String?, at: Date?) -> DiscoveredProcess {
        DiscoveredProcess(pid: pid, agent: .pi, cwd: "/p/blog", startedAt: Date(timeIntervalSince1970: 0),
                          record: id.map { SessionRecord(id: $0, agent: .pi, cwd: "/p/blog", modifiedAt: at!, path: "/r/\($0)") })
    }

    @MainActor func testRecordGivesRealIdAndActiveThenIdle() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = SessionStore(now: { clock }, isAlive: { _ in true }, branchReader: { _ in nil })
        store.applyDiscovery([found(5, id: nil, at: nil)])
        XCTAssertEqual(store.sessions.map(\.id), ["pid:5"])
        store.applyDiscovery([found(5, id: "pi-1", at: clock.addingTimeInterval(-10))])
        XCTAssertEqual(store.sessions.map(\.id), ["pi-1"], "pid row upgraded to the real id")
        XCTAssertEqual(store.sessions.first?.state, .working)
        clock = clock.addingTimeInterval(300)
        store.applyDiscovery([found(5, id: "pi-1", at: Date(timeIntervalSince1970: 990))])
        XCTAssertEqual(store.sessions.first?.state, .idle)
        XCTAssertEqual(store.aggregate.state, .idle)
    }

    @MainActor func testHookEventTakesOverDiscoveredRowWithSameId() {
        let store = SessionStore(now: { Date(timeIntervalSince1970: 1_000) }, isAlive: { _ in true }, branchReader: { _ in nil })
        store.applyDiscovery([DiscoveredProcess(pid: 5, agent: .claude, cwd: "/p/api", startedAt: nil,
                                                record: SessionRecord(id: "uuid-1", agent: .claude, cwd: "/p/api",
                                                                      modifiedAt: Date(timeIntervalSince1970: 995), path: "/r"))])
        store.apply(WireEvent(ts: 1, pid: 5, e: SlimEvent(sessionId: "uuid-1", event: .permissionRequest, cwd: "/p/api", toolName: "Bash")))
        XCTAssertEqual(store.sessions.map(\.id), ["uuid-1"])
        XCTAssertEqual(store.sessions.first?.isDiscovered, false)
        XCTAssertEqual(store.sessions.first?.state, .needsAttention)
        store.applyDiscovery([DiscoveredProcess(pid: 5, agent: .claude, cwd: "/p/api", startedAt: nil,
                                                record: SessionRecord(id: "uuid-1", agent: .claude, cwd: "/p/api",
                                                                      modifiedAt: Date(timeIntervalSince1970: 999), path: "/r"))])
        XCTAssertEqual(store.sessions.first?.state, .needsAttention, "discovery never overrides hook state")
    }
}
