@testable import OpusBarCore
import OpusBarWire
import XCTest

final class SessionFolderTests: XCTestCase {
    private var home: URL!
    private let now = Date()

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "opusbar-folders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    private func mkdir(_ path: String) throws -> URL {
        let url = home.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func paths(_ urls: [URL]) -> [String] {
        urls.map { $0.standardizedFileURL.path.replacingOccurrences(of: home.standardizedFileURL.path, with: "~") }
    }

    func testClaudeDesktopRootsWalkFourLevelsAndSkipBuildFolders() throws {
        let base = "Library/Application Support/Claude/claude-code-sessions"
        _ = try mkdir("\(base)/acct/workspace/.claude/projects")
        _ = try mkdir("\(base)/acct/node_modules/pkg/.claude/projects")
        _ = try mkdir("\(base)/a/b/c/d/e/.claude/projects")
        var budget = ScanBudget()
        let roots = SessionRecordReader.claudeDesktopProjectRoots(home: home, budget: &budget)
        XCTAssertEqual(paths(roots), ["~/\(base)/acct/workspace/.claude/projects"])
    }

    func testClaudeDesktopProcessDetection() {
        let desktop = AgentProcess(pid: 1, executablePath: "/Users/me/Library/Application Support/Claude/claude-code/claude/2.1/claude",
                                   arguments: ["claude"])
        XCTAssertTrue(AgentProcessClassifier.isClaudeDesktop(desktop))
        XCTAssertFalse(AgentProcessClassifier.isClaudeDesktop(AgentProcess(pid: 2, executablePath: "/opt/homebrew/bin/claude", arguments: ["claude"])))
    }
}
