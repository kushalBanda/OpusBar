import XCTest
@testable import OpusBarCore

final class ClaudeConfigPathsTests: XCTestCase {
    func testDefaultsToDotClaudeUnderHome() {
        let env = ["HOME": "/Users/me"]
        XCTAssertEqual(ClaudeConfigPaths.configRoot(environment: env).path, "/Users/me/.claude")
        XCTAssertEqual(ClaudeConfigPaths.settingsURL(environment: env).path, "/Users/me/.claude/settings.json")
    }

    func testEmptyConfigDirMeansDefault() {
        let env = ["HOME": "/Users/me", "CLAUDE_CONFIG_DIR": ""]
        XCTAssertEqual(ClaudeConfigPaths.configRoot(environment: env).path, "/Users/me/.claude")
    }

    func testAbsoluteConfigDirWins() {
        let env = ["HOME": "/Users/me", "CLAUDE_CONFIG_DIR": "/Users/me/.claude-kb48"]
        XCTAssertEqual(ClaudeConfigPaths.settingsURL(environment: env).path, "/Users/me/.claude-kb48/settings.json")
        XCTAssertEqual(ClaudeConfigPaths.projectsRoot(environment: env).path, "/Users/me/.claude-kb48/projects")
    }

    func testRelativeAndTildeResolveAgainstWorkingDirectory() {
        let cwd = URL(filePath: "/work", directoryHint: .isDirectory)
        XCTAssertEqual(ClaudeConfigPaths.configRoot(environment: ["CLAUDE_CONFIG_DIR": "profiles/a"], workingDirectory: cwd).path,
                       "/work/profiles/a")
        XCTAssertEqual(ClaudeConfigPaths.configRoot(environment: ["CLAUDE_CONFIG_DIR": "~/x"], workingDirectory: cwd).path,
                       "/work/~/x", "Claude does not expand ~")
    }
}
