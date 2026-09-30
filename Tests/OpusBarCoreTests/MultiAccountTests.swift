@testable import OpusBarCore
import OpusBarWire
import XCTest

/// Several Claude profiles and Codex homes: each is its own account for limits and spend.
final class MultiAccountTests: XCTestCase {
    private var home: URL!
    private let now = UsageTimestamp.parse("2026-09-30T12:00:00Z")!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "opusbar-accounts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func write(_ lines: [String], to path: String) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    func testDetectsCodexHomes() throws {
        for dir in [".codex", ".codex-work/sessions", ".codex-cache", "custom", "added"] {
            try FileManager.default.createDirectory(at: home.appending(path: dir), withIntermediateDirectories: true)
        }
        try Data().write(to: home.appending(path: ".codex-cache/notes.txt"))
        let homes = CodexHomes.all(environment: ["HOME": home.path, "CODEX_HOME": home.appending(path: "custom").path],
                                   userAdded: [home.appending(path: "added").path, home.appending(path: ".codex").path, "relative"])
        XCTAssertEqual(homes.map(\.root.lastPathComponent), [".codex", "custom", ".codex-work", "added"],
                       "a ~/.codex-* folder without sessions/ or config.toml is not a home; no duplicates")
        XCTAssertEqual(homes.map(\.origin), [.standard, .environment, .detected, .userAdded])
        XCTAssertEqual(HookTarget.codex(homes[2]).fileURL.lastPathComponent, "hooks.json")
        XCTAssertEqual(HookTarget.codex(environment: ["HOME": home.path, "CODEX_HOME": home.appending(path: "custom").path])?.root.lastPathComponent,
                       "custom", "the app's own CODEX_HOME comes first for the single-home call")
        XCTAssertEqual(AccountFolder.name(home.appending(path: ".codex-work").path), "codex-work")
    }

    func testEachCodexHomeHasItsOwnLimitsAndSpend() throws {
        let rollout = { (response: String, used: Int) in
            [CodexLine.meta(), CodexLine.context(),
             CodexLimitsTests.limitsLine(primary: #"{"used_percent":\#(used),"window_minutes":300}"#),
             CodexLine.record(response: response, CodexLine.usage(100_000, output: 100_000))]
        }
        try write(rollout("resp_a", 20), to: ".codex/sessions/2026/09/30/rollout-a.jsonl")
        try write(rollout("resp_b", 70), to: ".codex-work/sessions/2026/09/30/rollout-b.jsonl")
        let homes = CodexHomes.all(environment: ["HOME": home.path], userAdded: [])
        let roots = UsageStore.codexRoots(homes: homes)
        let store = UsageStore(claudeRoots: { [] }, codexRoots: { roots }, prices: UsagePriceListTests.bundled)
        store.refresh(now: now)

        let limits = store.codexLimits
        XCTAssertEqual(limits.map(\.label), ["codex", "codex-work"])
        XCTAssertEqual(limits.map { $0.windows.first?.usedPercent }, [20, 70])
        XCTAssertEqual(Set(limits.map(\.id)).count, 2, "one id per home, for notification switches")
        XCTAssertEqual(limits.map(\.account), homes.map { UsageLogReader.canonical($0.root.path) })

        let summary = UsageSummary.make(records: store.records, range: .day, now: now)
        XCTAssertTrue(summary.hasSeveralAccounts)
        XCTAssertEqual(summary.byAccount.map(\.name).sorted(), ["codex", "codex-work"])
        XCTAssertEqual(summary.byAccount.map(\.agent), [.codex, .codex])
    }

    func testClaudeProfilesSplitByAccountAndNamedByEmail() throws {
        try write([claudeAssistantLine(id: "a")], to: ".claude/projects/-p/s.jsonl")
        try write([claudeAssistantLine(id: "b"), claudeAssistantLine(id: "c")], to: ".claude-kb48/projects/-p/s.jsonl")
        try ClaudeCodeLimitsTests.profile(account: "one", email: "one@example.com").write(to: home.appending(path: ".claude.json"))
        try ClaudeCodeLimitsTests.profile(account: "two", email: "two@example.com").write(to: home.appending(path: ".claude-kb48/.claude.json"))
        let profiles = ClaudeProfiles.all(environment: ["HOME": home.path], userAdded: [])
        let reader = ClaudeCodeLimitsReader(profiles: {
            profiles.map { ClaudeAccountFiles(root: $0.root, files: $0.accountFiles(home: self.home)) }
        })
        XCTAssertEqual(reader.read().compactMap(\.label), ["one@example.com", "two@example.com"])

        let store = UsageStore(claudeRoots: { profiles.map(\.projectsRoot) }, prices: UsagePriceListTests.bundled)
        store.refresh(now: now)
        let summary = UsageSummary.make(records: store.records, range: .quarter, now: now, names: reader.emails)
        XCTAssertEqual(summary.byAccount.map(\.name), ["two@example.com", "one@example.com"], "ranked by spend")
        XCTAssertEqual(summary.byAccount.map(\.totals.replies), [2, 1])
        XCTAssertEqual(summary.byAgent.count, 1)
        XCTAssertTrue(summary.hasSeveralAccounts)
    }

    func testOneAccountPerAgentIsNotSeveral() {
        let record = UsageRecord(agent: .claude, date: now.addingTimeInterval(-60), model: "claude-opus-5-5", project: "p",
                                 session: "s", tokens: UsageTokens(output: 1))
        XCTAssertFalse(UsageSummary.make(records: [record], range: .day, now: now).hasSeveralAccounts)
    }
}
