@testable import OpusBarCore
import XCTest

/// Values from the session reach AppleScript and `open`; only safe shapes may get through.
final class TerminalScriptTests: XCTestCase {
    func testSafeTtyAcceptsOnlyPlainDevicePaths() {
        XCTAssertEqual(TerminalScript.safeTty("ttys004"), "/dev/ttys004")
        XCTAssertNil(TerminalScript.safeTty("ttys004\" & do shell script \"x"))
        XCTAssertNil(TerminalScript.safeTty("/dev/console"))
        XCTAssertNil(TerminalScript.safeTty("/tmp/ttys004"))
    }

    func testITermRevealURLRefusesOtherShapes() {
        XCTAssertNotNil(TerminalScript.itermRevealURL(sessionId: "w0t1p2:6E5B2D3A-1C4F-4B7E-9A10-2F3E4D5C6B7A"))
        for id in [nil, "6E5B2D3A-1C4F", "w0t0p0:ABCD1234&cmd=x", "w0t0p0:ABCD1234 x"] {
            XCTAssertNil(TerminalScript.itermRevealURL(sessionId: id))
        }
    }

    func testFolderScriptEscapesQuotesAndRefusesControlCharacters() throws {
        let script = try XCTUnwrap(TerminalScript.focusByCwd(.ghostty, cwd: #"/Users/me/a"b\c"#))
        XCTAssertTrue(script.contains(#"working directory is "/Users/me/a\"b\\c""#))
        XCTAssertNil(TerminalScript.focusByCwd(.ghostty, cwd: "/Users/me/a\nb"))
    }

    /// A refused Automation must fall through, not count as focused.
    func testOutcomeRules() {
        XCTAssertEqual(TerminalScript.outcome(status: 0, stdout: "focused\n", stderr: ""), .focused)
        XCTAssertEqual(TerminalScript.outcome(status: 0, stdout: "none\n", stderr: ""), .notFound)
        XCTAssertEqual(TerminalScript.outcome(status: 1, stdout: "",
            stderr: "execution error: Not authorized to send Apple events to Terminal. (-1743)"), .denied)
    }
}
