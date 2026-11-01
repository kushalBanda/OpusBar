@testable import OpusBarCore
import XCTest

final class WindowPickerTests: XCTestCase {
    private let needles = WindowNeedles(folder: "api-server", title: "fix-login", branch: "main")

    func testPicksTheWindowNamingTheFolder() {
        let titles = ["README.md — web — Cursor", "server.ts — api-server — Cursor"]
        XCTAssertEqual(WindowPicker.pick(titles: titles, needles: needles), 1)
    }

    func testFolderMustBeAWholeName() {
        XCTAssertNil(WindowPicker.pick(titles: ["api-server-old — zsh", "my-api-server — zsh"],
                                       needles: WindowNeedles(folder: "api-server")))
        XCTAssertNil(WindowPicker.pick(titles: ["api-server — zsh"], needles: WindowNeedles(folder: "api")))
    }
}
