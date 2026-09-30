@testable import OpusBarCore
import OpusBarWire
import XCTest

final class UsageSummaryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")! // +05:30: local days differ from UTC days
        return calendar
    }()
    /// 2026-09-30 17:30 in Kolkata.
    private let now = UsageTimestamp.parse("2026-09-30T12:00:00Z")!

    private func record(_ time: String, agent: AgentKind = .claude, model: String = "claude-opus-5-5",
                        project: String = "quant", cost: Double? = 1, output: Int = 100) -> UsageRecord {
        UsageRecord(agent: agent, date: UsageTimestamp.parse(time)!, model: model, project: project, session: "s",
                    tokens: UsageTokens(input: 10, cacheRead: 30, output: output), cost: cost)
    }

    func testRangeStarts() {
        XCTAssertEqual(UsageRange.day.start(now: now, calendar: calendar), now.addingTimeInterval(-86_400), "24 h rolls")
        // 7 local days including today: from 2026-09-24 00:00 Kolkata = 2026-09-23 18:30 UTC.
        XCTAssertEqual(UsageRange.week.start(now: now, calendar: calendar), UsageTimestamp.parse("2026-09-23T18:30:00Z"))
        XCTAssertEqual(UsageRange.quarter.start(now: now, calendar: calendar),
                       UsageTimestamp.parse("2026-07-02T18:30:00Z"), "90 local days including today")
    }

    func testOnlyTwentyFourHoursIsFree() {
        XCTAssertEqual(UsageRange.allCases.filter { $0.isAvailable(isPro: false) }, [.day])
        XCTAssertEqual(UsageRange.allCases.filter { $0.isAvailable(isPro: true) }, UsageRange.allCases)
    }

    func testTotalsAndBreakdownsRankedByCost() {
        let records = [
            record("2026-09-30T10:00:00Z", project: "quant", cost: 3),
            record("2026-09-30T11:00:00Z", agent: .codex, model: "gpt-5.4", project: "web", cost: 5),
            record("2026-09-29T10:00:00Z", model: "claude-sonnet-5", project: "quant", cost: 1),
            record("2026-09-29T11:00:00Z", model: "claude-mystery-9", project: "quant", cost: nil),
            record("2026-09-01T10:00:00Z", cost: 100),
        ]
        let summary = UsageSummary.make(records: records, range: .week, now: now, calendar: calendar)
        XCTAssertEqual(summary.total.replies, 4, "the September 1 reply is outside 7 days")
        XCTAssertEqual(summary.total.cost, 9, accuracy: 1e-9)
        XCTAssertEqual(summary.total.unpriced, 1)
        XCTAssertEqual(summary.byAgent.map(\.name), ["Codex", "Claude Code"])
        XCTAssertEqual(summary.byModel.map(\.name), ["GPT-5.4", "Opus 5.5", "Sonnet 5", "Mystery 9"])
        XCTAssertEqual(summary.byProject.map(\.name), ["web", "quant"])
        XCTAssertEqual(summary.byProject.last?.totals.replies, 3)
    }

    func testDailyBucketsOnLocalDays() {
        let records = [
            record("2026-09-29T18:29:00Z", cost: 1), // 23:59 on the 29th in Kolkata
            record("2026-09-29T18:31:00Z", cost: 2), // 00:01 on the 30th
            record("2026-09-24T00:00:00Z", cost: 4), // 05:30 on the 24th
        ]
        let summary = UsageSummary.make(records: records, range: .week, now: now, calendar: calendar)
        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.days.map(\.totals.cost), [4, 0, 0, 0, 0, 1, 2])
        XCTAssertEqual(summary.days.first?.start, UsageTimestamp.parse("2026-09-23T18:30:00Z"))
    }

    func testProjectsPastTheTopEightFoldIntoOther() {
        let records = (0..<10).map { record("2026-09-30T10:00:00Z", project: "p\($0)", cost: Double(10 - $0)) }
        let summary = UsageSummary.make(records: records, range: .day, now: now, calendar: calendar)
        XCTAssertEqual(summary.byProject.count, 9)
        XCTAssertEqual(summary.byProject.last?.name, "Other")
        XCTAssertEqual(summary.byProject.last?.totals.cost ?? 0, 2 + 1, accuracy: 1e-9)
        XCTAssertNil(summary.byProject.last?.agent)
    }

    func testCacheHitRate() {
        let summary = UsageSummary.make(records: [record("2026-09-30T10:00:00Z")], range: .day, now: now, calendar: calendar)
        XCTAssertEqual(summary.total.tokens.cacheHitRate ?? 0, 0.75, accuracy: 1e-9, "30 read of 40 prompt tokens")
        XCTAssertNil(UsageTokens().cacheHitRate)
    }
}

final class UsageModelNameTests: XCTestCase {
    func testReadableNames() {
        XCTAssertEqual(UsageFormat.modelName("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(UsageFormat.modelName("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(UsageFormat.modelName("claude-sonnet-5"), "Sonnet 5")
        XCTAssertEqual(UsageFormat.modelName("claude-3-5-haiku"), "Haiku 3.5")
        XCTAssertEqual(UsageFormat.modelName("gpt-5.2-codex"), "GPT-5.2 Codex")
        XCTAssertEqual(UsageFormat.modelName("gpt-6-luna"), "GPT-6 Luna")
        XCTAssertEqual(UsageFormat.modelName("codex-mini-latest"), "codex-mini-latest")
        XCTAssertEqual(UsageFormat.modelName(""), "Unknown model")
    }
}
