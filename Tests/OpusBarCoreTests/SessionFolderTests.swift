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

    func testPiRecordsReadBothLayouts() throws {
        let grouped = try mkdir("grouped")
        let bucket = try mkdir("grouped/--p-blog--")
        try (#"{"type":"session","version":3,"id":"in-bucket","cwd":"/p/blog"}"# + "\n").write(
            to: bucket.appending(path: "a.jsonl"), atomically: true, encoding: .utf8)
        let direct = try mkdir("direct")
        try (#"{"type":"session","version":3,"id":"flat","cwd":"/p/web"}"# + "\n").write(
            to: direct.appending(path: "b.jsonl"), atomically: true, encoding: .utf8)
        var budget = ScanBudget()
        let records = SessionRecordReader.piFamilyRecords(roots: [grouped, direct], dialect: .pi,
                                                          since: now.addingTimeInterval(-60), now: now, budget: &budget)
        XCTAssertEqual(Set(records.map(\.id)), ["in-bucket", "flat"])
    }

    func testPiRootsFromArgumentsEnvironmentAndUserFolders() throws {
        _ = try mkdir("custom-abs")
        _ = try mkdir("work/rel-sessions")
        _ = try mkdir("env-sessions")
        _ = try mkdir("agent-dir/sessions")
        _ = try mkdir("added")
        _ = try mkdir(".pi/agent/sessions")
        let roots = SessionRecordReader.piFamilyRoots(
            dialect: .pi, home: home,
            environment: ["PI_CODING_AGENT_SESSION_DIR": "~/env-sessions", "PI_CODING_AGENT_DIR": home.appending(path: "agent-dir").path],
            processes: [(["pi", "--session-dir", home.appending(path: "custom-abs").path], nil),
                        (["pi", "--session-dir=rel-sessions"], home.appending(path: "work").path)],
            userAdded: [home.appending(path: "added").path, home.appending(path: "missing").path])
        XCTAssertEqual(paths(roots), ["~/custom-abs", "~/work/rel-sessions", "~/env-sessions", "~/agent-dir/sessions",
                                      "~/.pi/agent/sessions", "~/added"])
    }

    func testOmpProfileAndConfigDir() throws {
        _ = try mkdir(".omp-work/profiles/team/agent/sessions")
        _ = try mkdir(".omp-work/agent/sessions")
        let roots = SessionRecordReader.piFamilyRoots(dialect: .omp, home: home, environment: ["PI_CONFIG_DIR": ".omp-work"],
                                                      processes: [(["omp", "--profile", "team"], nil)])
        XCTAssertEqual(paths(roots), ["~/.omp-work/profiles/team/agent/sessions", "~/.omp-work/agent/sessions"])
    }

    func testUnsafeConfigDirAndProfileAreIgnored() {
        XCTAssertEqual(SessionRecordReader.ompConfigRoot(home: home, environment: ["PI_CONFIG_DIR": "/etc"]).lastPathComponent, ".omp")
        XCTAssertEqual(SessionRecordReader.ompConfigRoot(home: home, environment: ["PI_CONFIG_DIR": "../x"]).lastPathComponent, ".omp")
        XCTAssertTrue(SessionRecordReader.ompProfileRoots("../../etc", home: home, environment: [:]).isEmpty)
    }

    func testRelativeSessionDirNeedsACwd() {
        XCTAssertNil(SessionRecordReader.expand("rel", home: home, relativeTo: nil))
        XCTAssertEqual(SessionRecordReader.expand("~/x", home: home, relativeTo: nil)?.lastPathComponent, "x")
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
