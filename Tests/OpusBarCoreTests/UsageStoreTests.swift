@testable import OpusBarCore
import OpusBarWire
import XCTest

final class UsageStoreTests: XCTestCase {
    private var root: URL!
    private let now = ISO8601DateFormatter().date(from: "2026-09-30T12:00:00Z")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "opusbar-usage-\(UUID().uuidString)/projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private func store() -> UsageStore {
        UsageStore(claudeRoots: { [root] in [root!] }, prices: UsagePriceListTests.bundled)
    }

    @discardableResult
    private func write(_ text: String, to path: String, append: Bool = false, modified: Date? = nil) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if append, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try handle.close()
        } else {
            try Data(text.utf8).write(to: url)
        }
        try FileManager.default.setAttributes([.modificationDate: modified ?? now], ofItemAtPath: url.path)
        return url
    }

    private func lines(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

    func testReadsSessionsSubagentsAndMergesCopies() throws {
        try write(lines(#"{"type":"user","message":{"content":"hi"}}"#,
                        claudeAssistantLine(id: "a", output: 5),
                        claudeAssistantLine(id: "a", output: 50),
                        claudeAssistantLine(id: "b", sidechain: true)), to: "-p-quant/s1.jsonl")
        try write(lines(claudeAssistantLine(id: "sub")), to: "-p-quant/s1/subagents/agent-1.jsonl")
        let store = store()
        store.refresh(now: now)
        let totals = store.totals(since: .distantPast)
        XCTAssertEqual(totals.replies, 3, "a (merged), b (sidechain), sub (subagent)")
        XCTAssertTrue(store.records.contains { $0.tokens.output == 50 })
    }

    func testAppendedLinesCountedOnceAndPartialLineWaits() throws {
        let url = try write(lines(claudeAssistantLine(id: "a")), to: "-p/s.jsonl")
        let store = store()
        store.refresh(now: now)
        XCTAssertEqual(store.totals(since: .distantPast).replies, 1)

        let next = claudeAssistantLine(id: "b")
        let cut = next.index(next.startIndex, offsetBy: 40)
        try write(String(next[..<cut]), to: "-p/s.jsonl", append: true)
        store.read(paths: [url.path], now: now)
        XCTAssertEqual(store.totals(since: .distantPast).replies, 1, "half a line waits for its end")

        try write(String(next[cut...]) + "\n", to: "-p/s.jsonl", append: true)
        store.read(paths: [url.path], now: now)
        store.refresh(now: now)
        XCTAssertEqual(store.totals(since: .distantPast).replies, 2)
        XCTAssertEqual(store.bytesRead, try Data(contentsOf: url).count, "every byte read exactly once")
    }

    func testReplacedOrShorterFileIsReadAgainWithoutDoubleCounting() throws {
        let url = try write(lines(claudeAssistantLine(id: "a"), claudeAssistantLine(id: "b")), to: "-p/s.jsonl")
        let store = store()
        store.refresh(now: now)
        try FileManager.default.removeItem(at: url)
        try write(lines(claudeAssistantLine(id: "a")), to: "-p/s.jsonl")
        store.read(paths: [url.path], now: now)
        XCTAssertEqual(store.totals(since: .distantPast).replies, 2, "b stays: it was billed; a is not counted twice")
    }

    func testOversizedLineSkippedAndNextLineRead() throws {
        let huge = #"{"type":"user","x":""# + String(repeating: "x", count: 2_000) + "\"}"
        try write(lines(huge, claudeAssistantLine(id: "a")), to: "-p/s.jsonl")
        let store = UsageStore(claudeRoots: { [root] in [root!] }, prices: UsagePriceListTests.bundled, maxLineBytes: 1_000)
        store.refresh(now: now)
        XCTAssertEqual(store.totals(since: .distantPast).replies, 1)
    }

    func testHistoryKeepsNinetyDays() throws {
        try write(lines(claudeAssistantLine(id: "new", time: "2026-09-29T10:00:00.000Z"),
                        claudeAssistantLine(id: "old", time: "2026-06-01T10:00:00.000Z")), to: "-p/s.jsonl")
        try write(lines(claudeAssistantLine(id: "ancient", time: "2026-05-01T10:00:00.000Z")), to: "-p/old.jsonl",
                  modified: now.addingTimeInterval(-120 * 86_400))
        let store = store()
        store.refresh(now: now)
        XCTAssertEqual(store.records.map(\.session).count, 1, "records older than 90 days dropped, old files not read")
    }

    func testReadIgnoresPathsOutsideRootsAndNonLogs() throws {
        let outside = FileManager.default.temporaryDirectory.appending(path: "opusbar-outside-\(UUID().uuidString).jsonl")
        try Data(lines(claudeAssistantLine(id: "x")).utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let store = store()
        store.read(paths: [outside.path, root.appending(path: "notes.txt").path], now: now)
        XCTAssertTrue(store.records.isEmpty)
    }
}

final class UsageTimestampTests: XCTestCase {
    func testFastPathMatchesFormatter() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for text in ["2026-09-30T10:00:00.000Z", "2026-02-28T23:59:59.999Z", "2024-02-29T00:00:00.5Z", "1999-12-31T12:34:56.123456Z"] {
            let fast = UsageTimestamp.parse(text)!
            XCTAssertEqual(fast.timeIntervalSince1970, formatter.date(from: text)!.timeIntervalSince1970, accuracy: 0.001, text)
        }
        XCTAssertEqual(UsageTimestamp.parse("2026-09-30T10:00:00Z"), ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z"))
        XCTAssertEqual(UsageTimestamp.parse("2026-09-30T12:00:00+02:00"), ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z"))
        XCTAssertNil(UsageTimestamp.parse("yesterday"))
        XCTAssertNil(UsageTimestamp.parse("2026-13-30T10:00:00Z"))
    }
}

final class UsageLogWatcherTests: XCTestCase {
    func testReportsWrittenFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "opusbar-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let seen = expectation(description: "file event")
        seen.assertForOverFulfill = false
        let queue = DispatchQueue(label: "test.watch")
        let watcher = UsageLogWatcher(queue: queue, latency: 0.1) { paths, _ in
            if paths.contains(where: { $0.hasSuffix("s.jsonl") }) { seen.fulfill() }
        }
        XCTAssertTrue(watcher.start([dir.path]))
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.3)
        try Data("x\n".utf8).write(to: dir.appending(path: "s.jsonl"))
        wait(for: [seen], timeout: 5)
    }
}

final class UsageProjectsTests: XCTestCase {
    func testSubfoldersCountTowardTheirRepository() {
        let repos: Set<String> = ["/Users/me/Github/OpusBar", "/Users/me/Github/OpusBar/docs/resources/vorssaint-utils"]
        let projects = UsageProjects(isRepository: { repos.contains($0.path) })
        XCTAssertEqual(projects.name(for: "/Users/me/Github/OpusBar"), "OpusBar")
        XCTAssertEqual(projects.name(for: "/Users/me/Github/OpusBar/Sources/OpusBarCore"), "OpusBar")
        XCTAssertEqual(projects.name(for: "/Users/me/Github/OpusBar/docs/resources/vorssaint-utils/Sources"), "vorssaint-utils",
                       "a nested repository is its own project")
        XCTAssertEqual(projects.name(for: "/tmp/scratch"), "scratch", "no repository: the folder's own name")
        XCTAssertEqual(projects.name(for: ""), "")
    }
}
