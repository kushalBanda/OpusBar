@testable import OpusBarCore
import XCTest

final class SessionHostTests: XCTestCase {
    private func table(_ rows: [(pid: Int32, ppid: Int32, path: String, tty: String?)]) -> [Int32: AgentProcess] {
        Dictionary(uniqueKeysWithValues: rows.map {
            ($0.pid, AgentProcess(pid: $0.pid, ppid: $0.ppid, executablePath: $0.path, arguments: [], tty: $0.tty))
        })
    }

    func testTerminalAppFoundThroughTheShell() {
        let processes = table([
            (32016, 31515, "/Users/me/.local/share/claude/versions/2.1.283", "ttys013"),
            (31515, 31483, "/bin/zsh", "ttys013"),
            (31483, 1, "/Applications/Terax.app/Contents/MacOS/terax", nil),
        ])
        let host = SessionHost.resolve(pid: 32016, processes: processes)
        XCTAssertEqual(host?.appName, "Terax")
        XCTAssertEqual(host?.appPath, "/Applications/Terax.app")
        XCTAssertEqual(host?.label, "Terax · ttys013")
    }

    func testEditorHelperResolvesToTheOutermostApp() {
        let processes = table([
            (10, 9, "/opt/homebrew/bin/claude", "ttys002"),
            (9, 8, "/bin/zsh", "ttys002"),
            (8, 1, "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)", nil),
        ])
        XCTAssertEqual(SessionHost.resolve(pid: 10, processes: processes)?.appName, "Visual Studio Code")
    }

    func testTmuxEndsAtLaunchdWithTtyOnly() {
        let processes = table([
            (20, 19, "/opt/homebrew/bin/claude", "ttys005"),
            (19, 18, "/bin/zsh", "ttys005"),
            (18, 1, "/opt/homebrew/bin/tmux", nil),
        ])
        let host = SessionHost.resolve(pid: 20, processes: processes)
        XCTAssertNil(host?.appName)
        XCTAssertEqual(host?.label, "ttys005")
    }

    func testUnknownProcessHasNoHost() {
        XCTAssertNil(SessionHost.resolve(pid: 99, processes: [:]))
    }

    func testNoTerminalDeviceMeansNoTty() {
        XCTAssertNil(DarwinProcessLister.ttyName(UInt32.max))
        XCTAssertNil(DarwinProcessLister.ttyName(0))
    }
}
