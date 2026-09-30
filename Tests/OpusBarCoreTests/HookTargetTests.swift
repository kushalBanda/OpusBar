@testable import OpusBarCore
import OpusBarWire
import XCTest

final class HookTargetTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "opusbar-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func testCodexTargetOnlyWhenCodexHomeExists() throws {
        XCTAssertNil(HookTarget.codex(environment: ["HOME": home.path]))
        try FileManager.default.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true)
        let target = try XCTUnwrap(HookTarget.codex(environment: ["HOME": home.path]))
        XCTAssertEqual(target.fileURL.lastPathComponent, "hooks.json")
        XCTAssertEqual(target.hookArguments, ["--agent", "codex"])
        XCTAssertFalse(target.async)
        XCTAssertFalse(target.events.contains(.notification), "Codex has no Notification event")
    }

    func testCodexHomeOverride() throws {
        let custom = home.appending(path: "codex-home")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let target = try XCTUnwrap(HookTarget.codex(environment: ["HOME": home.path, "CODEX_HOME": custom.path]))
        XCTAssertEqual(target.fileURL.path, custom.appending(path: "hooks.json").path)
    }

    func testCodexInstallWritesSyncEntriesWithAgentArgument() throws {
        try FileManager.default.createDirectory(at: home.appending(path: ".codex"), withIntermediateDirectories: true)
        let paths = OpusBarPaths(home: home)
        let target = try XCTUnwrap(HookTarget.codex(environment: ["HOME": home.path]))
        let hook = home.appending(path: "src/opusbar-hook")
        try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        XCTAssertEqual(try target.installer(paths: paths).install(hookSource: hook), .installed)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: target.fileURL)) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(HookTarget.codexEvents.map(\.rawValue)))
        let entry = try XCTUnwrap(((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertNil(entry["async"], "Codex entries run synchronously")
        XCTAssertEqual(entry["command"] as? String, "\"\(paths.hookBinary.path)\" --agent codex")
    }

    func testClaudeTargetKeepsM1Shape() {
        let target = HookTarget.claude(ClaudeProfile(root: home.appending(path: ".claude"), origin: .standard))
        XCTAssertEqual(target.hookArguments, [], "no --agent: events without an agent are Claude Code")
        XCTAssertTrue(target.async)
        XCTAssertEqual(target.events.count, 12)
    }
}
