@testable import OpusBarCore
import OpusBarWire
import XCTest

final class HookInstallerTests: XCTestCase {
    private var root: URL!
    private let clock = ClockBox(Date(timeIntervalSince1970: 1_700_000_000))

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "opusbar-inst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var settingsURL: URL { root.appending(path: "profile/settings.json") }
    private var backups: URL { root.appending(path: "backups") }

    private func installer() -> HookInstaller {
        let box = clock
        return HookInstaller(settingsURL: settingsURL, hookBinary: root.appending(path: "support/bin/opusbar-hook"),
                             backupsDir: backups, now: { box.tick() })
    }

    /// A fake hook executable to copy.
    private func hookSource(_ body: String = "#!/bin/sh\nexit 0\n") throws -> URL {
        let url = root.appending(path: "src-\(UUID().uuidString.prefix(4))/opusbar-hook")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func writeSettings(_ json: String) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    private func readSettings() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
    }

    private func quarantined(_ url: URL) -> Bool { getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 }

    private func quarantine(_ url: URL) {
        let mark = "0083;6abcc3b1;Safari;7B4DE5CC-8987-4E01-BFE0-91D538C270D5"
        setxattr(url.path, "com.apple.quarantine", mark, mark.utf8.count, 0, 0)
    }

    func testCopiedHookLosesTheDownloadMark() throws {
        let source = try hookSource()
        quarantine(source)
        XCTAssertTrue(quarantined(source))
        try installer().install(hookSource: source)
        let copy = root.appending(path: "support/bin/opusbar-hook")
        XCTAssertFalse(quarantined(copy), "Gatekeeper kills a quarantined unsigned hook when an agent runs it")
        quarantine(copy)
        try installer().install(hookSource: source)
        XCTAssertFalse(quarantined(copy), "an unchanged copy is cleared too")
    }

    func testRefreshReplacesAnOldCopyButNeverCreatesOne() throws {
        let copy = root.appending(path: "support/bin/opusbar-hook")
        try HookInstaller.refreshBinary(copy, from: try hookSource())
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), "not connected anywhere: nothing to refresh")
        try installer().install(hookSource: try hookSource("#!/bin/sh\necho old\n"))
        let new = try hookSource("#!/bin/sh\necho new\n")
        try HookInstaller.refreshBinary(copy, from: new)
        XCTAssertTrue(FileManager.default.contentsEqual(atPath: copy.path, andPath: new.path))
    }

    func testMergeAddsTwelveEntries() {
        let merged = HookInstaller.merged([:], command: "\"/x/opusbar-hook\"", events: HookEventName.subscribed)
        let hooks = merged["hooks"] as? [String: Any]
        XCTAssertEqual(hooks?.count, 12)
        let entry = ((hooks?["PreToolUse"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(entry?["command"] as? String, "\"/x/opusbar-hook\"")
        XCTAssertEqual(entry?["async"] as? Bool, true)
        XCTAssertEqual(entry?["timeout"] as? Int, 5)
    }

    func testMergePreservesUserHooksAndKeys() throws {
        try writeSettings(#"{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"my-guard.sh"}]}]}}"#)
        try installer().install(hookSource: hookSource())
        let settings = try readSettings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        let groups = try XCTUnwrap((settings["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual((groups[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "my-guard.sh")
    }

    func testMergeIsIdempotent() throws {
        let source = try hookSource()
        try installer().install(hookSource: source)
        let first = try Data(contentsOf: settingsURL)
        try installer().install(hookSource: source)
        XCTAssertEqual(try Data(contentsOf: settingsURL), first)
    }

    func testUnmergeRemovesOnlyOursIncludingDevEntries() throws {
        try writeSettings(#"""
        {"hooks":{"Stop":[{"matcher":"*","hooks":[{"type":"command","command":"say done"},
          {"type":"command","command":"/Users/me/OpusBar/.build/debug/opusbar-hook","async":true}]}],
          "PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"\"/A B/opusbar-hook\" --agent claude"}]}]},
         "theme":"dark"}
        """#)
        try installer().uninstall()
        let settings = try readSettings()
        XCTAssertEqual(settings["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertNil(hooks["PreToolUse"], "group left empty is dropped")
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual((stop[0]["hooks"] as? [[String: Any]])?.map { $0["command"] as? String }, ["say done"])
    }

    func testUninstallAfterInstallLeavesNoHooksKey() throws {
        try writeSettings(#"{"theme":"dark"}"#)
        try installer().install(hookSource: hookSource())
        XCTAssertEqual(try installer().uninstall(), .notInstalled)
        XCTAssertNil(try readSettings()["hooks"])
    }

    func testInstallBacksUpFirstAndKeepsTen() throws {
        try writeSettings(#"{"original":true}"#)
        let source = try hookSource()
        try installer().install(hookSource: source)
        var files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(files.count, 1)
        let backup = try Data(contentsOf: backups.appending(path: files[0]))
        XCTAssertEqual(String(decoding: backup, as: UTF8.self), #"{"original":true}"#, "backup is the file before our change")
        for _ in 0..<12 { try installer().uninstall(); try installer().install(hookSource: source) }
        files = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(files.count, HookInstaller.backupsKept)
    }

    func testInstallRefusesInvalidJSON() throws {
        try writeSettings("{ not json")
        XCTAssertEqual(installer().status(), .unreadable("Not valid JSON"))
        XCTAssertThrowsError(try installer().install(hookSource: hookSource()))
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "{ not json", "never written")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
    }

    func testInstallCreatesMissingFileAndCopiesBinary() throws {
        XCTAssertEqual(installer().status(), .notInstalled)
        try installer().install(hookSource: hookSource("#!/bin/sh\necho v1\n"))
        XCTAssertEqual(installer().status(), .installed)
        let binary = root.appending(path: "support/bin/opusbar-hook")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path))
        try installer().install(hookSource: hookSource("#!/bin/sh\necho v2\n"))
        XCTAssertTrue(try String(contentsOf: binary, encoding: .utf8).contains("v2"), "a changed hook replaces the copy")
    }

    func testStatusPartialListsMissingEvents() throws {
        let command = "\"/x/opusbar-hook\""
        let merged = HookInstaller.merged([:], command: command, events: [.stop, .sessionStart])
        guard case .partial(let missing) = HookInstaller.status(of: merged, events: HookEventName.subscribed) else {
            return XCTFail("expected partial")
        }
        XCTAssertEqual(missing.count, 10)
        XCTAssertFalse(missing.contains(.stop))
    }

    func testMissingHookBinaryThrowsBeforeWriting() throws {
        try writeSettings(#"{"a":1}"#)
        XCTAssertThrowsError(try installer().install(hookSource: root.appending(path: "nope/opusbar-hook")))
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), #"{"a":1}"#)
    }
}

private final class ClockBox: @unchecked Sendable {
    private var date: Date
    private let lock = NSLock()
    init(_ date: Date) { self.date = date }
    func tick() -> Date { lock.withLock { date = date.addingTimeInterval(1); return date } }
}

final class ClaudeProfilesTests: XCTestCase {
    func testStandardEnvironmentAndUserAddedThatExist() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "opusbar-prof-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for dir in [".claude", ".claude-work", "extra"] {
            try FileManager.default.createDirectory(at: home.appending(path: dir), withIntermediateDirectories: true)
        }
        let profiles = ClaudeProfiles.all(
            environment: ["HOME": home.path, "CLAUDE_CONFIG_DIR": home.appending(path: ".claude-work").path],
            userAdded: [home.appending(path: "extra").path, home.appending(path: "missing").path, "relative/x",
                        home.appending(path: ".claude").path])
        XCTAssertEqual(profiles.map(\.root.lastPathComponent), [".claude", ".claude-work", "extra"])
        XCTAssertEqual(profiles.map(\.origin), [.standard, .environment, .userAdded])
        XCTAssertEqual(profiles[1].settingsURL.lastPathComponent, "settings.json")
    }
}
