import Foundation
@testable import OpusBarCore
import OpusBarWire
import XCTest

final class OrcaTerminalPickerTests: XCTestCase {
    /// Trimmed from `orca terminal list --json` (Orca 1.4.240).
    private func list(_ terminals: String, ok: Bool = true) -> Data {
        Data(#"{"id":"x","ok":\#(ok),"result":{"terminals":[\#(terminals)],"totalCount":2,"truncated":false}}"#.utf8)
    }

    private func terminal(_ handle: String, path: String, agent: String? = "claude", orphaned: Bool = false,
                          lastOutputAt: Int? = 1_793_468_185_267) -> String {
        let agentField = agent.map { #","agentIdentity":"\#($0)""# } ?? ""
        let output = lastOutputAt.map(String.init) ?? "null"
        return #"{"handle":"\#(handle)","orphaned":\#(orphaned),"worktreePath":"\#(path)","title":null,"#
            + #""connected":true,"lastOutputAt":\#(output),"executionHostId":"local"\#(agentField)}"#
    }

    func testPicksTheTerminalWithMatchingWorktreeAndAgent() {
        let json = list([terminal("term_a-1", path: "/Users/me/web"), terminal("term_b-2", path: "/Users/me/api")]
            .joined(separator: ","))
        XCTAssertEqual(OrcaTerminalPicker.handle(fromListJSON: json, cwd: "/Users/me/api", agent: .claude), "term_b-2")
    }

    func testSkipsOrphanedTerminalsAndOtherAgents() {
        let json = list([terminal("term_a-1", path: "/Users/me/api", orphaned: true),
                         terminal("term_b-2", path: "/Users/me/api", agent: "codex"),
                         terminal("term_c-3", path: "/Users/me/api", agent: nil)].joined(separator: ","))
        XCTAssertNil(OrcaTerminalPicker.handle(fromListJSON: json, cwd: "/Users/me/api", agent: .claude))
        XCTAssertEqual(OrcaTerminalPicker.handle(fromListJSON: json, cwd: "/Users/me/api", agent: .codex), "term_b-2")
    }

    func testPickedTerminalIsSkippedWhenItsHandleIsMalformed() {
        let json = list(terminal("--help", path: "/Users/me/api"))
        XCTAssertNil(OrcaTerminalPicker.handle(fromListJSON: json, cwd: "/Users/me/api", agent: .claude))
    }
}
