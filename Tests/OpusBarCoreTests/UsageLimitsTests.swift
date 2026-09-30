@testable import OpusBarCore
import OpusBarWire
import XCTest

private func date(_ text: String) -> Date { UsageTimestamp.parse(text)! }

final class CodexLimitsTests: XCTestCase {
    static func limitsLine(id: String = "codex", time: String = "2026-09-30T10:00:06.000Z", primary: String, secondary: String = "null") -> String {
        #"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"\#(id)","primary":\#(primary),"secondary":\#(secondary),"plan_type":"plus"}}}"#
    }

    private func state(_ lines: [String]) -> CodexUsageParser.State {
        var state = CodexUsageParser.State()
        for line in lines { _ = CodexUsageParser.parse(Data(line.utf8), state: &state) }
        return state
    }

    func testMainAllowanceWindowsByLength() {
        let line = Self.limitsLine(primary: #"{"used_percent":35.0,"window_minutes":300,"resets_at":1790000000}"#,
                                   secondary: #"{"used_percent":10.0,"window_minutes":10080,"resets_in_seconds":3600}"#)
        let limits = state([line]).limits
        XCTAssertEqual(limits?.agent, .codex)
        XCTAssertEqual(limits?.source, .sessionLog)
        XCTAssertEqual(limits?.windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(limits?.windows.map(\.usedPercent), [35, 10])
        XCTAssertEqual(limits?.windows.first?.resetsAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(limits?.windows.last?.resetsAt, date("2026-09-30T11:00:06Z"), "resets_in_seconds counts from the line's time")
        XCTAssertEqual(limits?.windows.map(\.label), ["5 h", "Week"])
    }

    func testModelAllowanceAndNewerReadingRules() {
        let main = Self.limitsLine(time: "2026-09-30T10:00:06.000Z", primary: #"{"used_percent":20,"window_minutes":43200}"#)
        let model = Self.limitsLine(id: "codex_spark", time: "2026-09-30T10:05:00.000Z", primary: #"{"used_percent":90,"window_minutes":300}"#)
        let older = Self.limitsLine(time: "2026-09-30T09:00:00.000Z", primary: #"{"used_percent":5,"window_minutes":43200}"#)
        let limits = state([main, model, older]).limits
        XCTAssertEqual(limits?.windows.map(\.usedPercent), [20], "a model's own allowance and an older reading never replace the main one")
        XCTAssertEqual(limits?.windows.first?.kind, .other)
        XCTAssertEqual(limits?.windows.first?.label, "30 d")
    }

    func testLimitsLineStillCountsUsage() {
        var state = CodexUsageParser.State()
        _ = CodexUsageParser.parse(Data(CodexLine.meta().utf8), state: &state)
        let reply = CodexUsageParser.parse(Data(CodexLine.count(total: CodexLine.usage(100, output: 10), last: nil).utf8), state: &state)
        XCTAssertEqual(reply?.record.tokens.total, 110)
    }

    func testStoreKeepsNewestAcrossRollouts() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "opusbar-limits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        func write(_ line: String, _ name: String) throws {
            let url = home.appending(path: ".codex/sessions/2026/09/30/\(name)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((CodexLine.meta() + "\n" + line + "\n").utf8).write(to: url)
        }
        try write(Self.limitsLine(time: "2026-09-30T10:00:00.000Z", primary: #"{"used_percent":40,"window_minutes":300}"#), "rollout-a.jsonl")
        try write(Self.limitsLine(time: "2026-09-30T11:00:00.000Z", primary: #"{"used_percent":55,"window_minutes":300}"#), "rollout-b.jsonl")
        let roots = UsageStore.codexRoots(environment: ["HOME": home.path])
        let store = UsageStore(claudeRoots: { [] }, codexRoots: { roots }, prices: .empty)
        store.refresh(now: date("2026-09-30T12:00:00Z"))
        XCTAssertEqual(store.codexLimits?.windows.first?.usedPercent, 55)
    }
}

final class ClaudeCodeLimitsTests: XCTestCase {
    static func profile(account: String = "acct-1", email: String? = "me@example.com", oauthAccount: String? = nil,
                        fetched: String = "2026-09-30T10:00:00Z", fiveHour: String = #"{"utilization":35,"resets_at":"2026-09-30T13:59:59.735608+00:00"}"#,
                        sevenDay: String = #"{"utilization":12,"resets_at":"2026-10-04T17:59:59.735627+00:00"}"#) -> Data {
        let ms = Int(date(fetched).timeIntervalSince1970 * 1_000)
        let emailField = email.map { #","emailAddress":"\#($0)""# } ?? ""
        return Data(#"""
        {"numStartups":3,"oauthAccount":{"accountUuid":"\#(oauthAccount ?? account)"\#(emailField),"organizationUuid":"org"},
         "cachedUsageUtilization":{"fetchedAtMs":\#(ms),"accountUuid":"\#(account)","utilization":{
           "five_hour":\#(fiveHour),"seven_day":\#(sevenDay),"seven_day_opus":null,
           "iguana_necktie":{"utilization":0.25,"resets_at":null,"limit_dollars":100},
           "extra_usage":{"is_enabled":false,"utilization":46.9}}}}
        """#.utf8)
    }

    func testReadsKnownWindowsOnly() throws {
        let limits = try XCTUnwrap(ClaudeCodeLimits.limits(profile: Self.profile()))
        XCTAssertEqual(limits.agent, .claude)
        XCTAssertEqual(limits.account, "acct-1")
        XCTAssertEqual(limits.label, "me@example.com")
        XCTAssertEqual(limits.source, .claudeCode)
        XCTAssertEqual(limits.observedAt, date("2026-09-30T10:00:00Z"))
        XCTAssertEqual(limits.windows.map(\.id), ["claude.five_hour", "claude.seven_day"], "unknown and null windows are left out")
        XCTAssertEqual(limits.windows.map(\.usedPercent), [35, 12])
        XCTAssertEqual(limits.windows[0].resetsAt?.timeIntervalSince1970 ?? 0, date("2026-09-30T13:59:59Z").timeIntervalSince1970 + 0.735608,
                       accuracy: 0.001)
        XCTAssertEqual(limits.windows.map(\.label), ["5 h", "Week"])
    }

    func testNoCacheOrOtherSignInGivesNoLabel() {
        XCTAssertNil(ClaudeCodeLimits.limits(profile: Data(#"{"oauthAccount":{"accountUuid":"a"}}"#.utf8)))
        XCTAssertNil(ClaudeCodeLimits.limits(profile: Data("not json".utf8)))
        XCTAssertNil(ClaudeCodeLimits.limits(profile: Self.profile(oauthAccount: "someone-else"))?.label,
                     "the email names the account only when the sign-in is the cache's account")
    }

    func testReaderOneReadingPerAccountNewestWins() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "opusbar-claude-limits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appending(path: ".claude-work"), withIntermediateDirectories: true)
        let personalOld = home.appending(path: ".claude.json")
        let personalNew = home.appending(path: ".claude/.claude.json")
        let work = home.appending(path: ".claude-work/.claude.json")
        try FileManager.default.createDirectory(at: personalNew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.profile(account: "me", fetched: "2026-09-30T08:00:00Z").write(to: personalOld)
        try Self.profile(account: "me", email: nil, fetched: "2026-09-30T09:00:00Z",
                         fiveHour: #"{"utilization":60,"resets_at":null}"#).write(to: personalNew)
        try Self.profile(account: "work", email: "work@example.com").write(to: work)
        let reader = ClaudeCodeLimitsReader(files: { [personalOld, personalNew, work, home.appending(path: "missing.json")] })
        let limits = reader.read()
        XCTAssertEqual(limits.map(\.account), ["me", "work"])
        XCTAssertEqual(limits[0].windows.first?.usedPercent, 60, "newest reading for the account")
        XCTAssertEqual(limits[0].label, "me@example.com", "label kept from the older file that has one")
        XCTAssertEqual(limits[1].label, "work@example.com")
    }

    func testDetectsClaudeProfilesInHome() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "opusbar-profiles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for dir in [".claude", ".claude-kb48", ".claude-mem/logs"] {
            try FileManager.default.createDirectory(at: home.appending(path: dir), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: home.appending(path: ".claude-kb48/.claude.json"))
        let profiles = ClaudeProfiles.all(environment: ["HOME": home.path], userAdded: [])
        XCTAssertEqual(profiles.map(\.root.lastPathComponent), [".claude", ".claude-kb48"], "a folder without .claude.json is not a profile")
        XCTAssertEqual(profiles.map(\.origin), [.standard, .detected])
        XCTAssertEqual(profiles[0].accountFiles(home: home).map(\.path),
                       [home.appending(path: ".claude/.claude.json").path, home.appending(path: ".claude.json").path])
        XCTAssertEqual(profiles[1].accountFiles(home: home).map(\.lastPathComponent), [".claude.json"])
    }
}

final class UsageLimitsSelectionTests: XCTestCase {
    private let now = date("2026-09-30T12:00:00Z")

    private func limits(_ agent: AgentKind, _ used: Double, resets: String? = "2026-09-30T15:00:00Z") -> UsageLimits {
        UsageLimits(agent: agent, account: "\(agent)", windows: [UsageLimitWindow(id: "\(agent).a", kind: .session, minutes: 300, usedPercent: used,
                                                             resetsAt: resets.map(date))],
                    observedAt: now, source: .sessionLog)
    }

    func testTightestAndTieGoesToClaude() {
        XCTAssertEqual(UsageLimits.tightest([limits(.claude, 35), limits(.codex, 82)], at: now)?.limits.agent, .codex)
        XCTAssertEqual(UsageLimits.tightest([limits(.codex, 50), limits(.claude, 50)], at: now)?.limits.agent, .claude)
        XCTAssertNil(UsageLimits.tightest([], at: now))
    }

    func testRenewedWindowReadsEmpty() {
        let renewed = limits(.codex, 90, resets: "2026-09-30T11:00:00Z")
        XCTAssertEqual(renewed.binding(at: now)?.usedPercent, 0)
        XCTAssertNotEqual(renewed.asOf(now), renewed, "a renewal publishes as a change")
        XCTAssertNil(renewed.asOf(now).windows.first?.resetsAt)
    }

    func testShownIsSessionAndTightestLonger() {
        let limits = UsageLimits(agent: .claude, account: "a", windows: [
            UsageLimitWindow(id: "s", kind: .session, minutes: 300, usedPercent: 10, resetsAt: nil),
            UsageLimitWindow(id: "w", kind: .weekly, minutes: 10_080, usedPercent: 20, resetsAt: nil),
            UsageLimitWindow(id: "o", kind: .weekly, minutes: 10_080, scope: "Opus", usedPercent: 70, resetsAt: nil)],
            observedAt: now, source: .claudeCode)
        XCTAssertEqual(limits.shown(at: now).map(\.id), ["s", "o"])
    }

    func testElapsedAndCountdown() {
        let window = UsageLimitWindow(id: "s", kind: .session, minutes: 300, usedPercent: 10, resetsAt: date("2026-09-30T13:00:00Z"))
        XCTAssertEqual(window.elapsed(at: now) ?? 0, 0.8, accuracy: 1e-9, "4 of 5 hours gone")
        XCTAssertEqual(UsageFormat.countdown(to: date("2026-09-30T13:00:00Z"), now: now), "1h")
        XCTAssertEqual(UsageFormat.countdown(to: date("2026-09-30T12:45:00Z"), now: now), "45m")
        XCTAssertEqual(UsageFormat.countdown(to: date("2026-10-02T16:10:00Z"), now: now), "2d 4h")
    }

    func testPercentText() {
        XCTAssertEqual(UsageFormat.percent(0.824), "82%")
        XCTAssertEqual(UsageFormat.percent(1.4), "100%")
        XCTAssertEqual(UsageFormat.percent(-1), "0%")
    }
}
