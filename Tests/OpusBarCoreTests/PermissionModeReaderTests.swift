import Foundation
@testable import OpusBarCore
import OpusBarWire
import XCTest

final class PermissionModeReaderTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PermissionModeReaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ lines: [String], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func testLaunchFlags() {
        XCTAssertEqual(PermissionModeReader.launchMode(arguments: ["claude", "--permission-mode", "plan"]), .plan)
        XCTAssertEqual(PermissionModeReader.launchMode(arguments: ["claude", "--permission-mode=acceptEdits"]), .acceptEdits)
        XCTAssertEqual(PermissionModeReader.launchMode(arguments: ["claude", "--dangerously-skip-permissions"]), .bypassPermissions)
        XCTAssertNil(PermissionModeReader.launchMode(arguments: ["claude", "--allow-dangerously-skip-permissions"]))
        XCTAssertNil(PermissionModeReader.launchMode(arguments: ["claude", "--permission-mode"]))
    }

    func testSettingsLocalThenProjectThenUser() throws {
        let base = try folder()
        let root = base.appending(path: "root"), project = base.appending(path: "proj")
        try write([#"{"permissions":{"defaultMode":"auto"}}"#], to: root.appending(path: "settings.json"))
        XCTAssertEqual(PermissionModeReader.defaultMode(cwd: project.path, configRoot: root), .auto)
        try write([#"{"permissions":{"defaultMode":"plan"}}"#], to: project.appending(path: ".claude/settings.json"))
        XCTAssertEqual(PermissionModeReader.defaultMode(cwd: project.path, configRoot: root), .plan)
        try write([#"{"permissions":{"defaultMode":"acceptEdits"}}"#], to: project.appending(path: ".claude/settings.local.json"))
        XCTAssertEqual(PermissionModeReader.defaultMode(cwd: project.path, configRoot: root), .acceptEdits)
    }

    func testTranscriptNewestModeOfThisRun() throws {
        let transcript = try folder().appending(path: "root/projects/-x/abc.jsonl")
        try write([#"{"type":"permission-mode","permissionMode":"auto"}"#,
                   #"{"type":"user","permissionMode":"plan","timestamp":"1970-01-01T00:20:00.000Z"}"#,
                   #"{"type":"assistant","message":"x"}"#], to: transcript)
        XCTAssertEqual(PermissionModeReader.lastPromptMode(transcript: transcript, since: nil), .plan)
        XCTAssertEqual(PermissionModeReader.lastPromptMode(transcript: transcript, since: Date(timeIntervalSince1970: 900)), .plan)
        // Resumed after that prompt: its mode belongs to the earlier run.
        XCTAssertNil(PermissionModeReader.lastPromptMode(transcript: transcript, since: Date(timeIntervalSince1970: 1300)))
        XCTAssertEqual(PermissionModeReader.configRoot(ofTranscript: transcript.path)?.lastPathComponent, "root")
    }

    func testPermissionModeLinesCountOnlyWhenTheFileChangedSinceStart() throws {
        let transcript = try folder().appending(path: "t.jsonl")
        try write([#"{"type":"user","permissionMode":"default","timestamp":"1970-01-01T00:10:00.000Z"}"#,
                   #"{"type":"permission-mode","permissionMode":"acceptEdits"}"#], to: transcript)
        XCTAssertEqual(PermissionModeReader.lastPromptMode(transcript: transcript, since: Date(timeIntervalSince1970: 1300)), .acceptEdits)
        XCTAssertNil(PermissionModeReader.lastPromptMode(transcript: transcript, since: Date().addingTimeInterval(3600)))
    }

    func testTranscriptBeatsFlagsBeatSettings() throws {
        let base = try folder()
        let transcript = base.appending(path: "t.jsonl")
        try write([#"{"type":"user","permissionMode":"plan","timestamp":"1970-01-01T00:20:00.000Z"}"#], to: transcript)
        try write([#"{"permissions":{"defaultMode":"acceptEdits"}}"#], to: base.appending(path: "settings.json"))
        let flags = ["claude", "--permission-mode", "auto"]
        XCTAssertEqual(PermissionModeReader.claudeMode(arguments: flags, transcript: transcript, startedAt: nil, cwd: nil, configRoot: base), .plan)
        XCTAssertEqual(PermissionModeReader.claudeMode(arguments: flags, transcript: nil, startedAt: nil, cwd: nil, configRoot: base), .auto)
        XCTAssertEqual(PermissionModeReader.claudeMode(arguments: ["claude"], transcript: nil, startedAt: nil, cwd: nil, configRoot: base), .acceptEdits)
    }

    func testClearKeepsTheModeOfTheProcess() {
        var ts: Int64 = 0
        func event(_ name: HookEventName, _ id: String, _ mode: String? = nil) -> WireEvent {
            ts += 1
            return WireEvent(ts: ts, pid: 42, e: SlimEvent(sessionId: id, event: name, cwd: "/x/api", permissionMode: mode))
        }
        var state = SessionsState()
        for e in [event(.sessionStart, "a"), event(.userPromptSubmit, "a", "plan"), event(.sessionEnd, "a"), event(.sessionStart, "b")] {
            state = SessionReducer.reduce(state, e, now: Date(timeIntervalSince1970: 0))
        }
        XCTAssertEqual(state.byId["b"]?.permissionMode, .plan)
        XCTAssertTrue(state.endedModeByPid.isEmpty)
    }

    @MainActor
    func testDiscoveryFillsUntilAHookReports() {
        let store = SessionStore(finishedTTL: 600)
        store.apply(WireEvent(ts: 1, pid: 77, e: SlimEvent(sessionId: "h", event: .sessionStart, cwd: "/x")))
        let found = [DiscoveredProcess(pid: 77, agent: .claude, cwd: "/x", startedAt: nil, permissionMode: .auto)]
        store.applyDiscovery(found)
        XCTAssertEqual(store.state.byId["h"]?.permissionMode, .auto)
        store.apply(WireEvent(ts: 2, pid: 77, e: SlimEvent(sessionId: "h", event: .userPromptSubmit, cwd: "/x", permissionMode: "plan")))
        store.applyDiscovery(found)
        XCTAssertEqual(store.state.byId["h"]?.permissionMode, .plan)
    }
}
