@testable import OpusBarCore
import OpusBarWire
import XCTest

final class AgentProcessClassifierTests: XCTestCase {
    private func kind(_ argv: [String], path: String = "") -> AgentKind? {
        AgentProcessClassifier.kind(of: AgentProcess(pid: 1, executablePath: path, arguments: argv))
    }

    func testNativeClaudeByArgv0() {
        XCTAssertEqual(kind(["claude"], path: "/Users/me/.local/share/claude/versions/2.1.283"), .claude)
        XCTAssertEqual(kind(["claude", "--resume"]), .claude)
    }

    func testHelpersAndOneShotsSkipped() {
        XCTAssertNil(kind(["claude", "--version"]))
        XCTAssertNil(kind(["claude", "--help"]))
        XCTAssertNil(kind(["node", "/x/claude-code-acp/index.js", "claude"]))
        XCTAssertNil(kind(["/usr/local/bin/claude-code-acp", "x"]))
        XCTAssertNil(kind(["codex", "app-server"]))
        XCTAssertNil(kind(["codex", "--version"]))
        XCTAssertNil(kind(["/Users/me/.local/bin/claude", "--chrome-native-host"]))
        XCTAssertNil(kind(["claude", "mcp", "serve"]))
        XCTAssertNil(kind(["claude", "update"]))
        XCTAssertEqual(kind(["claude", "-p", "fix the bug"]), .claude, "headless runs are sessions")
    }

    func testCodexNativeAndAppBundles() {
        XCTAssertEqual(kind(["/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex"]), .codex)
        XCTAssertEqual(kind(["/Applications/Codex.app/Contents/Resources/codex"]), .codex)
        XCTAssertNil(kind(["/Applications/Other.app/Contents/Resources/codex"]))
        XCTAssertNil(kind(["node", "/opt/homebrew/bin/codex.js"]), "the npm wrapper is not the session; its native child is")
    }

    func testClaudeDesktopBundledCLI() {
        let path = "/Users/me/Library/Application Support/Claude/claude-code/claude"
        XCTAssertEqual(kind([path]), .claude)
        XCTAssertNil(kind(["/Applications/Claude.app/Contents/MacOS/claude"]))
    }

    func testRemovedAgentsNotDiscovered() {
        XCTAssertNil(kind(["pi"]))
        XCTAssertNil(kind(["omp"]))
        XCTAssertNil(kind(["bun", "/Users/me/.bun/bin/omp"]))
        XCTAssertNil(kind(["zsh"]))
    }

    func testDisclaimerWrapperDedupedWhenChildListed() {
        let wrapper = AgentProcess(pid: 10, arguments: ["disclaimer", "claude"])
        let child = AgentProcess(pid: 11, ppid: 10, arguments: ["claude"])
        let lone = AgentProcess(pid: 20, arguments: ["disclaimer", "claude"])
        let pids = AgentProcessClassifier.agentProcesses(from: [wrapper, child, lone]).map(\.0.pid).sorted()
        XCTAssertEqual(pids, [11, 20])
    }

    func testNewestFirstAndLimit() {
        let processes = (1...5).map { AgentProcess(pid: Int32($0), startedAt: Date(timeIntervalSince1970: Double($0)), arguments: ["claude"]) }
        XCTAssertEqual(AgentProcessClassifier.agentProcesses(from: processes, limit: 2).map(\.0.pid), [5, 4])
    }
}

final class DarwinProcessListerTests: XCTestCase {
    func testParseArgumentsStopsBeforeEnvironment() {
        var data = Data()
        var argc = Int32(2).littleEndian
        withUnsafeBytes(of: &argc) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array("/usr/bin/claude".utf8) + [0, 0, 0])
        data.append(contentsOf: Array("claude".utf8) + [0] + Array("--resume".utf8) + [0])
        data.append(contentsOf: Array("SECRET_TOKEN=abc".utf8) + [0, 0])
        XCTAssertEqual(DarwinProcessLister.parseArguments(procArgs2: data), ["claude", "--resume"])
    }

    func testParseArgumentsRejectsTruncatedBuffer() {
        var data = Data()
        var argc = Int32(3).littleEndian
        withUnsafeBytes(of: &argc) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array("/bin/x".utf8) + [0] + Array("x".utf8) + [0])
        XCTAssertNil(DarwinProcessLister.parseArguments(procArgs2: data))
    }

    func testListsOwnProcessWithArgvAndCwd() throws {
        let lister = DarwinProcessLister()
        let me = try XCTUnwrap(lister.processes().first { $0.pid == getpid() })
        XCTAssertEqual(me.arguments.first, CommandLine.arguments.first)
        XCTAssertNotNil(me.startedAt)
        XCTAssertEqual(lister.workingDirectory(pid: getpid()), FileManager.default.currentDirectoryPath)
    }
}

private struct FakeLister: ProcessListing {
    var list: [AgentProcess]
    var cwds: [Int32: String]
    func processes() -> [AgentProcess] { list }
    func workingDirectory(pid: Int32) -> String? { cwds[pid] }
}

final class SessionDiscoveryTests: XCTestCase {
    func testScanReturnsAgentsWithCwdOnly() {
        let lister = FakeLister(list: [
            AgentProcess(pid: 1, arguments: ["claude"]),
            AgentProcess(pid: 2, arguments: ["zsh"]),
            AgentProcess(pid: 3, arguments: ["codex"]),
        ], cwds: [1: "/p/api", 2: "/p/shell", 3: "/p/blog"])
        let found = SessionDiscovery(lister: lister).scan().sorted { $0.pid < $1.pid }
        XCTAssertEqual(found, [
            DiscoveredProcess(pid: 1, agent: .claude, cwd: "/p/api", startedAt: nil),
            DiscoveredProcess(pid: 3, agent: .codex, cwd: "/p/blog", startedAt: nil),
        ])
    }

    @MainActor func testDiscoveredRowAppearsAndVanishesWithProcess() {
        let store = SessionStore(now: { Date(timeIntervalSince1970: 50) }, isAlive: { _ in true }, branchReader: { _ in "main" })
        store.applyDiscovery([DiscoveredProcess(pid: 7, agent: .codex, cwd: "/p/api", startedAt: Date(timeIntervalSince1970: 10))])
        let row = store.sessions.first
        XCTAssertEqual(row?.id, "pid:7")
        XCTAssertEqual(row?.agent, .codex)
        XCTAssertEqual(row?.projectName, "api")
        XCTAssertEqual(row?.branch, "main")
        XCTAssertEqual(row?.isDiscovered, true)
        XCTAssertEqual(row?.state, .idle)
        store.applyDiscovery([])
        XCTAssertTrue(store.sessions.isEmpty)
    }

    @MainActor func testHookEventReplacesDiscoveredRowForSamePid() {
        let store = SessionStore(now: { Date(timeIntervalSince1970: 50) }, isAlive: { _ in true }, branchReader: { _ in nil })
        store.applyDiscovery([DiscoveredProcess(pid: 7, agent: .claude, cwd: "/p/api", startedAt: nil)])
        store.apply(WireEvent(ts: 1, pid: 7, e: SlimEvent(sessionId: "real", event: .userPromptSubmit, cwd: "/p/api")))
        XCTAssertEqual(store.sessions.map(\.id), ["real"])
        store.applyDiscovery([DiscoveredProcess(pid: 7, agent: .claude, cwd: "/p/api", startedAt: nil)])
        XCTAssertEqual(store.sessions.map(\.id), ["real"], "a hooked pid is never re-added as a discovered row")
        XCTAssertEqual(store.sessions.first?.state, .thinking)
    }
}
