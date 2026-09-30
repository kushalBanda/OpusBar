@testable import OpusBarCore
import OpusBarWire
import XCTest

/// One assistant line as Claude Code writes it, with only the fields usage reading looks at.
func claudeAssistantLine(id: String = "msg_1", request: String? = "req_1", session: String = "s1",
                         model: String = "claude-opus-5-5", time: String = "2026-09-30T10:00:00.000Z",
                         cwd: String = "/p/quant", input: Int = 10, output: Int = 100, cacheWrite: Int = 1_000,
                         cacheWrite1h: Int = 0, cacheRead: Int = 10_000, sidechain: Bool = false) -> String {
    let requestField = request.map { #""requestId":"\#($0)","# } ?? ""
    return #"{"type":"assistant","isSidechain":\#(sidechain),"sessionId":"\#(session)","cwd":"\#(cwd)",\#(requestField)"timestamp":"\#(time)","message":{"id":"\#(id)","model":"\#(model)","content":[{"type":"text","text":"secret reply"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"cache_creation":{"ephemeral_1h_input_tokens":\#(cacheWrite1h),"ephemeral_5m_input_tokens":\#(cacheWrite - cacheWrite1h)}}}}"#
}

final class ClaudeUsageParserTests: XCTestCase {
    func testAssistantLineGivesRecord() throws {
        let parsed = try XCTUnwrap(ClaudeUsageParser.parse(Data(claudeAssistantLine(cacheWrite1h: 400).utf8)))
        XCTAssertEqual(parsed.key, "claude:msg_1:req_1")
        let record = parsed.record
        XCTAssertEqual(record.agent, .claude)
        XCTAssertEqual(record.model, "claude-opus-5-5")
        XCTAssertEqual(record.project, "/p/quant", "the store turns the folder into a project name")
        XCTAssertEqual(record.session, "s1")
        XCTAssertEqual(record.date, Date(timeIntervalSince1970: 1_790_762_400))
        XCTAssertEqual(record.tokens, UsageTokens(input: 10, cacheWrite: 1_000, cacheWrite1h: 400, cacheRead: 10_000, output: 100))
        XCTAssertEqual(record.tokens.total, 11_110)
    }

    func testBillingExtrasRead() throws {
        let line = claudeAssistantLine().replacingOccurrences(
            of: #""usage":{"#, with: #""usage":{"speed":"fast","inference_geo":"us","server_tool_use":{"web_search_requests":3},"#)
        let record = try XCTUnwrap(ClaudeUsageParser.parse(Data(line.utf8))).record
        XCTAssertTrue(record.fast)
        XCTAssertTrue(record.usOnly)
        XCTAssertEqual(record.webSearches, 3)
        XCTAssertNil(record.cost, "the parser never prices; the ledger does")
    }

    func testOtherLinesAndSyntheticModelsSkipped() {
        XCTAssertNil(ClaudeUsageParser.parse(Data(#"{"type":"user","message":{"content":"hi"}}"#.utf8)))
        XCTAssertNil(ClaudeUsageParser.parse(Data(claudeAssistantLine(model: "<synthetic>").utf8)))
        XCTAssertNil(ClaudeUsageParser.parse(Data(claudeAssistantLine(input: 0, output: 0, cacheWrite: 0, cacheRead: 0).utf8)),
                     "a line with no tokens is not a billed reply")
        XCTAssertNil(ClaudeUsageParser.parse(Data("not json".utf8)))
    }

    func testKeyWithoutRequestIdFallsBackToSession() throws {
        let parsed = try XCTUnwrap(ClaudeUsageParser.parse(Data(claudeAssistantLine(request: nil).utf8)))
        XCTAssertEqual(parsed.key, "claude:s1:msg_1")
    }

    func testWorktreeCountsAsItsRepository() {
        XCTAssertEqual(ClaudeUsageParser.projectFolder("/p/quant/.claude/worktrees/fix-x"), "/p/quant")
        XCTAssertEqual(ClaudeUsageParser.projectFolder("/p/quant/"), "/p/quant")
    }
}

final class UsageLedgerTests: XCTestCase {
    private func record(_ line: String) -> (key: String, record: UsageRecord) {
        ClaudeUsageParser.parse(Data(line.utf8))!
    }

    private let prices = UsagePriceListTests.bundled

    func testStreamedCopiesOfOneReplyCountOnceWithLargestValues() {
        var ledger = UsageLedger(prices: prices)
        let early = record(claudeAssistantLine(output: 5))
        let final = record(claudeAssistantLine(output: 100))
        ledger.add(early.record, key: early.key)
        ledger.add(final.record, key: final.key)
        ledger.add(early.record, key: early.key)
        XCTAssertEqual(ledger.records.count, 1)
        XCTAssertEqual(ledger.records.first?.tokens.output, 100)
    }

    func testTotalsSinceSumTokensAndPricedCost() {
        var ledger = UsageLedger(prices: prices)
        for line in [
            claudeAssistantLine(id: "a", time: "2026-09-30T10:00:00.000Z", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0),
            claudeAssistantLine(id: "b", time: "2026-09-30T11:00:00.000Z", input: 0, output: 1_000_000, cacheWrite: 0, cacheRead: 0),
            claudeAssistantLine(id: "c", model: "claude-mystery-9", time: "2026-09-30T11:30:00.000Z"),
            claudeAssistantLine(id: "old", time: "2026-09-28T10:00:00.000Z"),
        ] {
            let parsed = record(line)
            ledger.add(parsed.record, key: parsed.key)
        }
        let since = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
        let totals = ledger.totals(since: since)
        XCTAssertEqual(totals.replies, 3)
        XCTAssertEqual(totals.unpriced, 1)
        XCTAssertEqual(totals.tokens.total, 2_011_110)
        XCTAssertEqual(totals.cost, 4 + 20, accuracy: 0.000_001, "Opus 5.5: $4 per M input, $20 per M output")
    }
}

final class UsageFormatTests: XCTestCase {
    func testCostAndTokens() {
        XCTAssertEqual(UsageFormat.cost(0), "$0.00")
        XCTAssertEqual(UsageFormat.cost(12.346), "$12.35")
        XCTAssertEqual(UsageFormat.cost(1_234.6), "$1,235")
        XCTAssertEqual(UsageFormat.tokens(950), "950")
        XCTAssertEqual(UsageFormat.tokens(12_400), "12.4K")
        XCTAssertEqual(UsageFormat.tokens(3_250_000), "3.3M")
        XCTAssertEqual(UsageFormat.tokens(2_000_000_000), "2B")
    }
}
