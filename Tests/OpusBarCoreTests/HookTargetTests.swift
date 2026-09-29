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

    func testPiFamilyTargetsOnlyWhenAgentFolderExists() throws {
        let env = ["HOME": home.path]
        XCTAssertEqual(HookTarget.piFamily(.pi, environment: env), [])
        XCTAssertEqual(HookTarget.piFamily(.omp, environment: env), [])
        try FileManager.default.createDirectory(at: home.appending(path: ".pi/agent"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: ".omp/agent"), withIntermediateDirectories: true)
        let pi = try XCTUnwrap(HookTarget.piFamily(.pi, environment: env).first)
        XCTAssertEqual(pi.fileURL.path, home.appending(path: ".pi/agent/extensions/opusbar.ts").path)
        XCTAssertTrue(pi.isExtension)
        XCTAssertFalse(pi.events.contains(.permissionRequest), "pi has no permission prompts")
        let omp = try XCTUnwrap(HookTarget.piFamily(.omp, environment: env).first)
        XCTAssertEqual(omp.fileURL.path, home.appending(path: ".omp/agent/extensions/opusbar.ts").path)
        XCTAssertEqual(HookTarget.piFamily(.claude, environment: env), [])
    }

    func testPiAgentDirAndOmpConfigDirFromOwnEnvironment() throws {
        try FileManager.default.createDirectory(at: home.appending(path: "custom-pi"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appending(path: ".omp-work/agent"), withIntermediateDirectories: true)
        let env = ["HOME": home.path, "PI_CODING_AGENT_DIR": "~/custom-pi", "PI_CONFIG_DIR": ".omp-work"]
        XCTAssertEqual(HookTarget.piFamily(.pi, environment: env).first?.fileURL.path,
                       home.appending(path: "custom-pi/extensions/opusbar.ts").path)
        XCTAssertEqual(HookTarget.piFamily(.omp, environment: ["HOME": home.path, "PI_CONFIG_DIR": ".omp-work"]).first?.fileURL.path,
                       home.appending(path: ".omp-work/agent/extensions/opusbar.ts").path)
        XCTAssertEqual(HookTarget.piFamily(.omp, environment: env).first?.fileURL.path,
                       home.appending(path: "custom-pi/extensions/opusbar.ts").path, "OMP honors PI_CODING_AGENT_DIR too")
    }

    func testPiConnectCopiesHookAndWritesExtensionThenDisconnectRemovesIt() throws {
        try FileManager.default.createDirectory(at: home.appending(path: ".pi/agent"), withIntermediateDirectories: true)
        let paths = OpusBarPaths(home: home)
        let target = try XCTUnwrap(HookTarget.piFamily(.pi, environment: ["HOME": home.path]).first)
        let hook = home.appending(path: "src/opusbar-hook")
        try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        XCTAssertEqual(target.status(paths: paths), .notInstalled)
        XCTAssertEqual(try target.install(paths: paths, hookSource: hook), .installed)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.hookBinary.path))
        let source = try String(contentsOf: target.fileURL)
        XCTAssertTrue(source.contains(paths.hookBinary.path))
        XCTAssertTrue(source.contains(#"const AGENT = "pi";"#))
        XCTAssertEqual(try target.uninstall(paths: paths), .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.fileURL.path))
    }

    func testOmpNamedProfilesEachGetATarget() throws {
        for dir in [".omp/agent", ".omp/profiles/work/agent", ".omp/profiles/empty"] {
            try FileManager.default.createDirectory(at: home.appending(path: dir), withIntermediateDirectories: true)
        }
        let targets = HookTarget.piFamily(.omp, environment: ["HOME": home.path])
        XCTAssertEqual(targets.map(\.profile), [nil, "work"], "a profile without an agent folder has never run")
        XCTAssertEqual(targets.last?.fileURL.path, home.appending(path: ".omp/profiles/work/agent/extensions/opusbar.ts").path)
        XCTAssertEqual(Set(targets.map(\.id)).count, 2)
    }
}
