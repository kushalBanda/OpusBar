import Foundation
import OpusBarWire
import XCTest
@testable import OpusBarCore

final class PiExtensionTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "pi-ext-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func installer(hook: String = "/Users/me/Library/Application Support/OpusBar/bin/opusbar-hook",
                           agent: AgentKind = .pi) -> PiExtensionInstaller {
        PiExtensionInstaller(agent: agent, fileURL: dir.appending(path: "extensions/opusbar.ts"),
                             hookBinary: URL(fileURLWithPath: hook))
    }

    func testSourceEmbedsHookPathAndAgentAsStringLiterals() {
        let source = installer(hook: "/a b/\"q\"/opusbar-hook", agent: .omp).source
        XCTAssertTrue(source.hasPrefix(PiExtensionInstaller.marker))
        XCTAssertTrue(source.contains(#"const HOOK = "/a b/\"q\"/opusbar-hook";"#))
        XCTAssertTrue(source.contains(#"const AGENT = "omp";"#))
    }

    func testSourceMapsEveryEventTheReducerNeeds() {
        let source = installer().source
        for name in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "StopFailure", "SessionEnd"] {
            XCTAssertTrue(source.contains("\"\(name)\""), name)
        }
        XCTAssertTrue(source.contains("reason: \"\(SessionReducer.abortedReason)\""))
    }

    func testInstallWritesFileAndStatusIsInstalled() throws {
        let installer = installer()
        XCTAssertEqual(installer.status(), .notInstalled)
        var copied: URL?
        try installer.install(hookSource: URL(fileURLWithPath: "/src/opusbar-hook")) { copied = $0 }
        XCTAssertEqual(copied?.path, "/src/opusbar-hook")
        XCTAssertEqual(installer.status(), .installed)
    }

    func testOurFileForAnotherHookPathNeedsReconnect() throws {
        try installer(hook: "/old/opusbar-hook").install(hookSource: URL(fileURLWithPath: "/x")) { _ in }
        XCTAssertEqual(installer(hook: "/new/opusbar-hook").status(), .partial(missing: []))
    }

    func testForeignFileIsNeverOverwrittenOrRemoved() throws {
        let installer = installer()
        try FileManager.default.createDirectory(at: installer.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("export default function () {}\n".utf8).write(to: installer.fileURL)
        guard case .unreadable = installer.status() else { return XCTFail("expected unreadable") }
        XCTAssertThrowsError(try installer.install(hookSource: URL(fileURLWithPath: "/x")) { _ in })
        try installer.uninstall()
        XCTAssertEqual(try String(contentsOf: installer.fileURL), "export default function () {}\n")
    }

    func testUninstallRemovesOnlyOurFile() throws {
        let installer = installer()
        let neighbour = installer.fileURL.deletingLastPathComponent().appending(path: "mine.ts")
        try installer.install(hookSource: URL(fileURLWithPath: "/x")) { _ in }
        try Data("x".utf8).write(to: neighbour)
        XCTAssertEqual(try installer.uninstall(), .notInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: neighbour.path))
    }
}

final class AbortedTurnTests: XCTestCase {
    private func event(_ name: HookEventName, reason: String? = nil, ts: Int64) -> WireEvent {
        WireEvent(ts: ts, pid: 42, term: nil, agent: .pi, e: SlimEvent(sessionId: "s", event: name, reason: reason))
    }

    func testAbortedStopReturnsToIdleAndPlainStopIsDone() {
        let now = Date()
        var state = SessionReducer.reduce(SessionsState(), event(.userPromptSubmit, ts: 1), now: now)
        state = SessionReducer.reduce(state, event(.stop, reason: SessionReducer.abortedReason, ts: 2), now: now)
        XCTAssertEqual(state.byId["s"]?.state, .idle)
        XCTAssertNil(state.byId["s"]?.turnStartedAt)
        state = SessionReducer.reduce(state, event(.userPromptSubmit, ts: 3), now: now)
        state = SessionReducer.reduce(state, event(.stop, ts: 4), now: now)
        XCTAssertEqual(state.byId["s"]?.state, .done)
    }
}

final class LateEventAfterEndTests: XCTestCase {
    private func event(_ name: HookEventName, ts: Int64) -> WireEvent {
        WireEvent(ts: ts, pid: 42, term: nil, agent: .pi, e: SlimEvent(sessionId: "s", event: name))
    }

    func testEventSentBeforeEndButDeliveredAfterIsDropped() {
        let now = Date()
        var state = SessionReducer.reduce(SessionsState(), event(.userPromptSubmit, ts: 1), now: now)
        state = SessionReducer.reduce(state, event(.sessionEnd, ts: 3), now: now)
        state = SessionReducer.reduce(state, event(.stopFailure, ts: 2), now: now)
        XCTAssertNil(state.byId["s"])
    }

    func testSameSessionStartingAgainLaterComesBack() {
        let now = Date()
        var state = SessionReducer.reduce(SessionsState(), event(.sessionEnd, ts: 3), now: now)
        state = SessionReducer.reduce(state, event(.sessionStart, ts: 4), now: now)
        XCTAssertEqual(state.byId["s"]?.state, .idle)
    }
}
