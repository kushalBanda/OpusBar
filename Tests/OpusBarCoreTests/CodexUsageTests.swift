@testable import OpusBarCore
import OpusBarWire
import XCTest

/// Codex rollout lines as Codex 0.155 writes them, with only the fields usage reading looks at.
enum CodexLine {
    static func meta(id: String = "t1", cwd: String = "/p/quant") -> String {
        #"{"timestamp":"2026-09-30T10:00:00.000Z","ordinal":0,"type":"session_meta","payload":{"id":"\#(id)","cwd":"\#(cwd)","cli_version":"0.155.1"}}"#
    }

    static func context(model: String = "gpt-5.4", tier: String? = nil, cwd: String = "/p/quant") -> String {
        let tierField = tier.map { #""\#($0)""# } ?? "null"
        return #"{"timestamp":"2026-09-30T10:00:01.000Z","type":"turn_context","payload":{"cwd":"\#(cwd)","model":"\#(model)","service_tier":\#(tierField),"effort":"high"}}"#
    }

    static func usage(_ input: Int, cached: Int = 0, write: Int = 0, output: Int, reasoning: Int = 0) -> String {
        #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"cache_write_input_tokens":\#(write),"output_tokens":\#(output),"reasoning_output_tokens":\#(reasoning),"total_tokens":\#(input + output)}"#
    }

    static func record(response: String, time: String = "2026-09-30T10:00:05.000Z", _ usage: String) -> String {
        #"{"timestamp":"\#(time)","type":"token_usage_record","payload":{"thread_id":"t1","session_id":"t1","response_id":"\#(response)","usage":\#(usage),"turn_token_usage":\#(usage)}}"#
    }

    static func count(total: String, last: String?, time: String = "2026-09-30T10:00:06.000Z") -> String {
        let lastField = last.map { #","last_token_usage":\#($0)"# } ?? ""
        return #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(total)\#(lastField),"model_context_window":258400},"rate_limits":{"limit_id":"codex","plan_type":"plus"}}}"#
    }

    static func threadSettings(tier: String) -> String {
        #"{"timestamp":"2026-09-30T10:00:02.000Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"\#(tier)"}}}"#
    }

    static let message = #"{"timestamp":"2026-09-30T10:00:03.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"secret"}]}}"#
}

final class CodexUsageParserTests: XCTestCase {
    private func parse(_ lines: [String]) -> [(key: String, record: UsageRecord)] {
        var state = CodexUsageParser.State()
        return lines.compactMap { CodexUsageParser.parse(Data($0.utf8), state: &state) }
    }

    func testUsageRecordsGiveOneReplyEach() throws {
        let replies = parse([
            CodexLine.meta(), CodexLine.context(), CodexLine.message,
            CodexLine.record(response: "resp_1", CodexLine.usage(17_539, cached: 6_912, output: 96)),
            CodexLine.count(total: CodexLine.usage(17_539, cached: 6_912, output: 96), last: CodexLine.usage(17_539, cached: 6_912, output: 96)),
            CodexLine.record(response: "resp_2", CodexLine.usage(20_000, cached: 17_000, write: 1_000, output: 400, reasoning: 300)),
        ])
        XCTAssertEqual(replies.map(\.key), ["codex:resp_1", "codex:resp_2"], "token_count adds nothing once records exist")
        let first = try XCTUnwrap(replies.first?.record)
        XCTAssertEqual(first.agent, .codex)
        XCTAssertEqual(first.model, "gpt-5.4")
        XCTAssertEqual(first.project, "/p/quant")
        XCTAssertEqual(first.session, "t1")
        XCTAssertEqual(first.tokens, UsageTokens(input: 10_627, cacheRead: 6_912, output: 96), "cached input is not new input")
        XCTAssertEqual(first.date, UsageTimestamp.parse("2026-09-30T10:00:05.000Z"))
        XCTAssertEqual(replies[1].record.tokens, UsageTokens(input: 2_000, cacheWrite: 1_000, cacheRead: 17_000, output: 400),
                       "reasoning is already inside output")
    }

    func testOlderLogsFallBackToRunningTotals() {
        let a = CodexLine.usage(1_000, cached: 200, output: 50)
        let ab = CodexLine.usage(3_000, cached: 1_200, output: 150)
        let replies = parse([
            CodexLine.meta(), CodexLine.context(model: "gpt-5.2-codex"),
            CodexLine.count(total: a, last: a),
            CodexLine.count(total: a, last: a),
            CodexLine.count(total: ab, last: nil),
        ])
        XCTAssertEqual(replies.count, 2, "a repeated total (only limits changed) is not a new reply")
        XCTAssertEqual(replies[0].record.tokens, UsageTokens(input: 800, cacheRead: 200, output: 50))
        XCTAssertEqual(replies[1].record.tokens, UsageTokens(input: 1_000, cacheRead: 1_000, output: 100),
                       "without last_token_usage the reply is what the total grew by")
        XCTAssertEqual(replies[0].record.model, "gpt-5.2-codex")
    }

    func testFastTierFromTurnContextAndThreadSettings() {
        let usage = CodexLine.usage(100, output: 10)
        let replies = parse([
            CodexLine.meta(), CodexLine.context(tier: "priority"),
            CodexLine.record(response: "r1", usage),
            CodexLine.threadSettings(tier: "default"),
            CodexLine.record(response: "r2", usage),
            CodexLine.context(tier: "fast"),
            CodexLine.record(response: "r3", usage),
        ])
        XCTAssertEqual(replies.map(\.record.fast), [true, false, true])
    }

    func testOtherLinesIgnored() {
        var state = CodexUsageParser.State()
        XCTAssertNil(CodexUsageParser.parse(Data(CodexLine.message.utf8), state: &state))
        XCTAssertNil(CodexUsageParser.parse(Data("garbage".utf8), state: &state))
        XCTAssertNil(CodexUsageParser.parse(Data(CodexLine.meta().utf8), state: &state))
        XCTAssertEqual(state.session, "t1")
    }
}

final class CodexUsageStoreTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "opusbar-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func write(_ lines: [String], to path: String) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    func testCodexRootsAndArchivedCopyCountedOnce() throws {
        let rollout = [CodexLine.meta(), CodexLine.context(),
                       CodexLine.record(response: "resp_1", CodexLine.usage(100_000, output: 100_000))]
        try write(rollout, to: ".codex/sessions/2026/09/30/rollout-a.jsonl")
        try write(rollout, to: ".codex/archived_sessions/rollout-a.jsonl")
        let roots = UsageStore.codexRoots(environment: ["HOME": home.path])
        XCTAssertEqual(roots.map(\.lastPathComponent), ["sessions", "archived_sessions"])
        let store = UsageStore(claudeRoots: { [] }, codexRoots: { roots }, prices: UsagePriceListTests.bundled)
        store.refresh(now: UsageTimestamp.parse("2026-09-30T12:00:00Z")!)
        let totals = store.totals(since: .distantPast)
        XCTAssertEqual(totals.replies, 1)
        XCTAssertEqual(totals.cost, 0.25 + 1.5, accuracy: 1e-9, "gpt-5.4: $2.50 in, $15 out per million")
        XCTAssertEqual(store.records.first?.agent, .codex)
    }

    func testCodexHomeFromEnvironment() throws {
        try FileManager.default.createDirectory(at: home.appending(path: "custom/sessions"), withIntermediateDirectories: true)
        let roots = UsageStore.codexRoots(environment: ["HOME": home.path, "CODEX_HOME": home.appending(path: "custom").path])
        XCTAssertEqual(roots.map { $0.deletingLastPathComponent().lastPathComponent }, ["custom"])
    }

    func testWatcherPathUnderCodexRootReadsWithCodexParser() throws {
        let path = ".codex/sessions/2026/09/30/rollout-b.jsonl"
        try write([CodexLine.meta(), CodexLine.context()], to: path)
        let roots = UsageStore.codexRoots(environment: ["HOME": home.path])
        let store = UsageStore(claudeRoots: { [] }, codexRoots: { roots }, prices: UsagePriceListTests.bundled)
        let now = UsageTimestamp.parse("2026-09-30T12:00:00Z")!
        store.refresh(now: now)
        let url = home.appending(path: path)
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data((CodexLine.record(response: "r9", CodexLine.usage(10, output: 1)) + "\n").utf8))
        try handle.close()
        store.read(paths: [url.path], now: now)
        XCTAssertEqual(store.records.map(\.model), ["gpt-5.4"], "model carried from the earlier read of the same file")
    }
}
