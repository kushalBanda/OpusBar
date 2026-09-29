import Foundation
import OpusBarCore
import XCTest

final class ElapsedFormatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func text(_ seconds: TimeInterval) -> String { ElapsedFormat.short(from: t0, to: t0.addingTimeInterval(seconds)) }

    func testUnitsStepUp() {
        XCTAssertEqual(text(42), "42s")
        XCTAssertEqual(text(185), "3m 05s")
        XCTAssertEqual(text(2 * 3600 + 14 * 60), "2h 14m")
        XCTAssertEqual(text(86_399), "23h 59m")
        XCTAssertEqual(text(122 * 3600 + 6 * 60), "5d 2h")
    }

    func testClockSkewNeverGoesNegative() {
        XCTAssertEqual(text(-5), "0s")
    }
}
