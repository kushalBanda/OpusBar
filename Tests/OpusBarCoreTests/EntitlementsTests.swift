import XCTest
@testable import OpusBarCore

@MainActor
final class EntitlementsTests: XCTestCase {
    func testFreeUntilALicenseSaysOtherwise() {
        XCTAssertFalse(Entitlements().isPro)
    }

    func testHintNamesFeatureAndPrice() {
        XCTAssertEqual(Entitlements.hint(for: "Jump to session"), "Jump to session is Pro · one-time $6.99")
    }
}
