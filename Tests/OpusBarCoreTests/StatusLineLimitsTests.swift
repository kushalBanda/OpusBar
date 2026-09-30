@testable import OpusBarCore
@testable import OpusBarWire
import XCTest

final class StatusLineLimitsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "opusbar-sl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var settingsURL: URL { root.appending(path: "profile/settings.json") }
    private var profile: URL { root.appending(path: "profile", directoryHint: .isDirectory) }
    private var hook: URL { root.appending(path: "support/bin/opusbar-hook") }

    private func installer(statusLine: Bool = true) -> HookInstaller {
        HookInstaller(settingsURL: settingsURL, hookBinary: hook, backupsDir: root.appending(path: "backups"),
                      statusLineRoot: statusLine ? profile : nil)
    }

    private func hookSource() throws -> URL {
        let url = root.appending(path: "src/opusbar-hook")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func writeSettings(_ json: String) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    private func settings() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
    }

    private func statusLine() throws -> [String: Any]? { try settings()["statusLine"] as? [String: Any] }

    // MARK: Wrapping

    func testConnectStepsInFrontOfTheOwnStatusLineAndDisconnectGivesItBack() throws {
        let own = "bash ~/.claude/statusline-command.sh"
        try writeSettings(#"{"statusLine":{"type":"command","command":"\#(own)","padding":2}}"#)
        try installer().install(hookSource: hookSource())
        let line = try XCTUnwrap(statusLine())
        let command = try XCTUnwrap(line["command"] as? String)
        XCTAssertTrue(command.hasPrefix("\"\(hook.path)\" statusline "))
        XCTAssertEqual(HookInstaller.relayed(command), own)
        XCTAssertEqual(line["padding"] as? Int, 2, "other keys stay")

        try installer().install(hookSource: hookSource())
        XCTAssertEqual(HookInstaller.relayed(try XCTUnwrap(statusLine()?["command"] as? String)), own,
                       "connecting again never wraps our own command")

        try installer().uninstall()
        XCTAssertEqual(try statusLine()?["command"] as? String, own)
        XCTAssertEqual(try statusLine()?["padding"] as? Int, 2)
    }

    func testAStatusLineOpusBarAddedIsRemovedOnDisconnect() throws {
        try writeSettings(#"{"theme":"dark"}"#)
        try installer().install(hookSource: hookSource())
        let command = try XCTUnwrap(statusLine()?["command"] as? String)
        XCTAssertNil(HookInstaller.relayed(command))
        try installer().uninstall()
        XCTAssertNil(try settings()["statusLine"])
        XCTAssertEqual(try settings()["theme"] as? String, "dark")
    }

    func testCodexTargetsLeaveTheStatusLineAlone() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"echo hi"}}"#)
        try installer(statusLine: false).install(hookSource: hookSource())
        XCTAssertEqual(try statusLine()?["command"] as? String, "echo hi")
    }

    func testLaunchAddsTheStatusLineOnlyToAConnectedProfile() throws {
        try writeSettings(#"{"statusLine":{"type":"command","command":"echo hi"}}"#)
        try installer().connectStatusLine()
        XCTAssertEqual(try statusLine()?["command"] as? String, "echo hi", "not connected: untouched")

        try installer(statusLine: false).install(hookSource: hookSource())  // connected before this version
        try FileManager.default.removeItem(at: hook)
        try installer().connectStatusLine()
        XCTAssertEqual(try statusLine()?["command"] as? String, "echo hi", "no hook copy: a wrap would blank it")
        try installer(statusLine: false).install(hookSource: hookSource())
        try installer().connectStatusLine()
        XCTAssertEqual(HookInstaller.relayed(try XCTUnwrap(statusLine()?["command"] as? String)), "echo hi")
    }

    func testCommandsWithQuotesAndSpacesSurviveTheRoundTrip() throws {
        let own = #"sh -c 'printf "%s" "$(cat)" | jq -r .model' && echo "a b""#
        let wrapped = HookInstaller.wrappedStatusLine(["statusLine": ["type": "command", "command": own]],
                                                      hookBinary: URL(fileURLWithPath: "/A B/opusbar-hook"),
                                                      root: URL(fileURLWithPath: "/Users/me/My Profile"))
        let command = try XCTUnwrap((wrapped["statusLine"] as? [String: Any])?["command"] as? String)
        XCTAssertEqual(HookInstaller.relayed(command), own)
        XCTAssertEqual((HookInstaller.unwrappedStatusLine(wrapped)["statusLine"] as? [String: Any])?["command"] as? String, own)
    }

    // MARK: The hook

    func testParsesClaudesRateLimitsAndDropsEverythingElse() throws {
        let input = Data(#"""
        {"cwd":"/secret","model":{"display_name":"Opus"},"cost":{"total_cost_usd":3},
         "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1790800000},
                        "seven_day":{"used_percentage":12,"resets_at":"2026-10-04T10:00:00Z"}}}
        """#.utf8)
        let now = Date(timeIntervalSince1970: 1_790_770_000)
        let live = try XCTUnwrap(LiveLimits.parse(statusLine: input, now: now))
        XCTAssertEqual(live.observedAt, now.timeIntervalSince1970)
        XCTAssertEqual(live.windows["five_hour"], .init(usedPercent: 42.5, resetsAt: 1_790_800_000))
        XCTAssertEqual(live.windows["seven_day"]?.resetsAt,
                       ISO8601DateFormatter().date(from: "2026-10-04T10:00:00Z")?.timeIntervalSince1970)
        let saved = String(decoding: try JSONEncoder().encode(live), as: UTF8.self)
        XCTAssertFalse(saved.contains("secret") || saved.contains("Opus") || saved.contains("cost"))
    }

    func testNoRateLimitsNoReading() {
        XCTAssertNil(LiveLimits.parse(statusLine: Data(#"{"model":{}}"#.utf8), now: Date()))
        XCTAssertNil(LiveLimits.parse(statusLine: Data("not json".utf8), now: Date()))
        XCTAssertNil(LiveLimits.parse(statusLine: Data(#"{"rate_limits":{"seven_day":{"used_percentage":0}}}"#.utf8), now: Date()),
                     "a resumed session's placeholder, before its first reply")
    }

    func testAnUnchangedReadingIsSavedAgainOnlyAfterAWhile() throws {
        let url = root.appending(path: "limits/claude-x.json")
        let windows = ["five_hour": LiveLimits.Window(usedPercent: 10, resetsAt: nil)]
        StatusLineRelay.save(LiveLimits(observedAt: 1000, windows: windows), to: url)
        StatusLineRelay.save(LiveLimits(observedAt: 1005, windows: windows), to: url)
        XCTAssertEqual(LiveLimits.read(url)?.observedAt, 1000)
        StatusLineRelay.save(LiveLimits(observedAt: 1030, windows: windows), to: url)
        XCTAssertEqual(LiveLimits.read(url)?.observedAt, 1030)
        StatusLineRelay.save(LiveLimits(observedAt: 1031, windows: ["five_hour": .init(usedPercent: 11, resetsAt: nil)]), to: url)
        XCTAssertEqual(LiveLimits.read(url)?.windows["five_hour"]?.usedPercent, 11, "a change is saved at once")
    }

    func testTheOwnCommandGetsTheInputAndItsExitStatusComesBack() {
        XCTAssertEqual(StatusLineRelay.runCommand(#"test "$(cat)" = "abc" && exit 7"#, input: Data("abc".utf8)), 7)
        XCTAssertEqual(StatusLineRelay.runCommand("exit 0", input: Data(repeating: 65, count: 1 << 18)), 0,
                       "a command that never reads its input doesn't hang or kill the hook")
    }

    // MARK: The reader

    func testALiveReadingReplacesTheStaleCacheForItsAccount() throws {
        let profileRoot = root.appending(path: "p", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        let account = profileRoot.appending(path: ".claude.json")
        try #"""
        {"oauthAccount":{"accountUuid":"acc-1","emailAddress":"me@example.com"},
         "cachedUsageUtilization":{"fetchedAtMs":1790700000000,"accountUuid":"acc-1","utilization":{
           "five_hour":{"utilization":5,"resets_at":"2026-09-30T20:00:00Z"},
           "seven_day":{"utilization":40},"seven_day_opus":{"utilization":30}}}}
        """#.write(to: account, atomically: true, encoding: .utf8)
        let live = root.appending(path: "live.json")
        let reader = ClaudeCodeLimitsReader(profiles: { [ClaudeAccountFiles(root: profileRoot, files: [account])] },
                                            liveFile: { _ in live })
        XCTAssertEqual(reader.read().first?.source, .claudeCode, "no live file yet: the cache")

        StatusLineRelay.save(LiveLimits(observedAt: 1_790_770_000, windows: [
            "five_hour": .init(usedPercent: 63, resetsAt: 1_790_780_000),
            "seven_day": .init(usedPercent: 44, resetsAt: nil)]), to: live)
        let limits = try XCTUnwrap(reader.read().first)
        XCTAssertEqual(limits.source, .statusLine)
        XCTAssertEqual(limits.account, "acc-1")
        XCTAssertEqual(limits.label, "me@example.com")
        XCTAssertEqual(limits.observedAt, Date(timeIntervalSince1970: 1_790_770_000))
        let byID = Dictionary(uniqueKeysWithValues: limits.windows.map { ($0.id, $0) })
        XCTAssertEqual(byID["claude.five_hour"]?.usedPercent, 63)
        XCTAssertEqual(byID["claude.five_hour"]?.resetsAt, Date(timeIntervalSince1970: 1_790_780_000))
        XCTAssertEqual(byID["claude.seven_day"]?.usedPercent, 44)
        XCTAssertEqual(byID["claude.seven_day_opus"]?.usedPercent, 30, "a window the status line lacks stays cached")

        StatusLineRelay.save(LiveLimits(observedAt: 1_790_600_000, windows: ["five_hour": .init(usedPercent: 1, resetsAt: nil)]),
                             to: live)
        XCTAssertEqual(reader.read().first?.source, .claudeCode, "a live reading older than the cache loses")
    }
}
