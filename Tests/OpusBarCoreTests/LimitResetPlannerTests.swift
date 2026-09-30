@testable import OpusBarCore
import OpusBarWire
import XCTest

final class LimitResetPlannerTests: XCTestCase {
    private let now = UsageTimestamp.parse("2026-09-30T12:00:00Z")!

    private func limits(_ agent: AgentKind, account: String, label: String? = nil,
                        _ windows: [(id: String, kind: UsageLimitWindow.Kind, minutes: Int, used: Double, resets: String?)]) -> UsageLimits {
        UsageLimits(agent: agent, account: account, label: label, windows: windows.map {
            UsageLimitWindow(id: $0.id, kind: $0.kind, minutes: $0.minutes, usedPercent: $0.used, resetsAt: $0.resets.flatMap(UsageTimestamp.parse))
        }, observedAt: now, source: .claudeCode)
    }

    private var accounts: [UsageLimits] {
        [limits(.claude, account: "me", label: "me@example.com", [
            ("claude.five_hour", .session, 300, 35, "2026-09-30T14:00:00Z"),
            ("claude.seven_day", .weekly, 10_080, 0, "2026-10-04T18:00:00Z"),     // nothing spent: nothing to announce
        ]),
         limits(.claude, account: "work", label: "work@example.com", [
            ("claude.seven_day", .weekly, 10_080, 46, "2026-10-02T16:00:00Z"),
            ("claude.five_hour", .session, 300, 80, "2026-09-30T11:00:00Z"),      // renewed already
         ]),
         limits(.codex, account: "codex", [("codex.43200", .other, 43_200, 10, "2026-10-25T00:00:00Z")])]
    }

    func testUsedWindowsAheadOnlySoonestFirst() {
        let plan = LimitResetPlanner.plan(accounts, muted: [], enabled: true, now: now)
        XCTAssertEqual(plan.map(\.id), ["limit.claude:me.claude.five_hour", "limit.claude:work.claude.seven_day", "limit.codex:codex.codex.43200"])
        XCTAssertEqual(plan[0].date, UsageTimestamp.parse("2026-09-30T14:00:00Z"))
        XCTAssertEqual(plan[0].title, "Claude Code limit reset")
        XCTAssertEqual(plan[0].body, "Your 5 h limit (me) is back to 100%.")
        XCTAssertEqual(plan[1].body, "Your week limit (work) is back to 100%.")
        XCTAssertEqual(plan[2].body, "Your 30 d limit is back to 100%.", "one Codex account needs no name")
    }

    func testMutedAccountAndMainSwitch() {
        XCTAssertEqual(LimitResetPlanner.plan(accounts, muted: ["claude:work"], enabled: true, now: now).map(\.id),
                       ["limit.claude:me.claude.five_hour", "limit.codex:codex.codex.43200"])
        XCTAssertTrue(LimitResetPlanner.plan(accounts, muted: [], enabled: false, now: now).isEmpty)
    }

    @MainActor
    func testPreferencesPersist() {
        let defaults = UserDefaults(suiteName: "limit-resets-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.notifyLimitReset, "on by default")
        XCTAssertTrue(preferences.limitResetMuted.isEmpty)
        preferences.notifyLimitReset = false
        preferences.limitResetMuted = ["claude:work"]
        let again = Preferences(defaults: defaults)
        XCTAssertFalse(again.notifyLimitReset)
        XCTAssertEqual(again.limitResetMuted, ["claude:work"])
    }
}

final class LimitWarningPlannerTests: XCTestCase {
    private let now = UsageTimestamp.parse("2026-09-30T12:00:00Z")!

    private func limits(account: String, label: String?, used: Double, resets: String? = "2026-09-30T14:00:00Z") -> UsageLimits {
        UsageLimits(agent: .claude, account: account, label: label,
                    windows: [UsageLimitWindow(id: "claude.five_hour", kind: .session, minutes: 300, usedPercent: used,
                                               resetsAt: resets.flatMap(UsageTimestamp.parse))],
                    observedAt: now, source: .claudeCode)
    }

    func testHighestThresholdOnceAndLowerOnesSettled() {
        let jump = LimitWarningPlanner.due([limits(account: "me", label: "me@example.com", used: 96)], muted: [], enabled: true,
                                           sent: [], now: now)
        XCTAssertEqual(jump.count, 1, "70 to 96 warns once, at 95")
        XCTAssertEqual(jump[0].notice.title, "Claude Code limit 95% used")
        XCTAssertEqual(jump[0].notice.body, "Your 5 h limit is 96% used. It resets in 2h.")
        XCTAssertEqual(jump[0].keys.count, 2)
        XCTAssertTrue(LimitWarningPlanner.due([limits(account: "me", label: nil, used: 97)], muted: [], enabled: true,
                                              sent: Set(jump[0].keys), now: now).isEmpty, "never twice in one period")
    }

    func testEightyThenNinetyFiveAndNamesAccounts() {
        let accounts = [limits(account: "me", label: "me@example.com", used: 82), limits(account: "work", label: "work@example.com", used: 50)]
        let first = LimitWarningPlanner.due(accounts, muted: [], enabled: true, sent: [], now: now)
        XCTAssertEqual(first.map(\.notice.title), ["Claude Code limit 80% used"])
        XCTAssertEqual(first[0].notice.body, "Your 5 h limit (me) is 82% used. It resets in 2h.")
        let later = LimitWarningPlanner.due([limits(account: "me", label: "me@example.com", used: 95)], muted: [], enabled: true,
                                            sent: Set(first[0].keys), now: now)
        XCTAssertEqual(later.map(\.notice.title), ["Claude Code limit 95% used"])
    }

    func testMutedDisabledAndNextPeriod() {
        let hot = [limits(account: "me", label: nil, used: 90)]
        XCTAssertTrue(LimitWarningPlanner.due(hot, muted: ["claude:me"], enabled: true, sent: [], now: now).isEmpty)
        XCTAssertTrue(LimitWarningPlanner.due(hot, muted: [], enabled: false, sent: [], now: now).isEmpty)
        let keys = Set(LimitWarningPlanner.due(hot, muted: [], enabled: true, sent: [], now: now).flatMap(\.keys))
        let next = [limits(account: "me", label: nil, used: 90, resets: "2026-09-30T19:00:00Z")]
        XCTAssertEqual(LimitWarningPlanner.due(next, muted: [], enabled: true, sent: keys, now: now).count, 1, "a new period warns again")
        XCTAssertEqual(LimitWarningPlanner.unexpired(keys, now: now), keys)
        XCTAssertTrue(LimitWarningPlanner.unexpired(keys, now: UsageTimestamp.parse("2026-09-30T15:00:00Z")!).isEmpty)
    }
}
