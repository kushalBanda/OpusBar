import Foundation
@testable import OpusBarCore
import XCTest

final class PreferencesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor
    func testDefaultsMatchTheMockup() {
        let prefs = Preferences(defaults: freshDefaults())
        XCTAssertTrue(prefs.animateCat)
        XCTAssertEqual(prefs.retention, .tenMinutes)
        XCTAssertEqual(prefs.naming, .folder)
        XCTAssertTrue(prefs.notifyNeedsYou)
        XCTAssertTrue(prefs.notifyError)
        XCTAssertFalse(prefs.notifyDone)
        XCTAssertFalse(prefs.connectCardDismissed)
    }

    @MainActor
    func testChangesPersistAcrossInstances() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.animateCat = false
        prefs.retention = .never
        prefs.naming = .folderAndBranch
        prefs.notifyDone = true
        prefs.notifyError = false
        prefs.connectCardDismissed = true

        let again = Preferences(defaults: defaults)
        XCTAssertFalse(again.animateCat)
        XCTAssertEqual(again.retention, .never)
        XCTAssertEqual(again.naming, .folderAndBranch)
        XCTAssertTrue(again.notifyDone)
        XCTAssertFalse(again.notifyError)
        XCTAssertTrue(again.connectCardDismissed)
    }

    @MainActor
    func testUnknownStoredValuesFallBackToDefaults() {
        let defaults = freshDefaults()
        defaults.set("forever", forKey: "finishedRetention")
        defaults.set("emoji", forKey: "sessionNaming")
        defaults.set("calico", forKey: "catCoat") // unlicensed upstream, never shipped (ADR 17)
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.retention, .tenMinutes)
        XCTAssertEqual(prefs.naming, .folder)
        XCTAssertEqual(prefs.coat, .classic)
    }

    @MainActor
    func testCoatPersists() {
        let defaults = freshDefaults()
        Preferences(defaults: defaults).coat = .tora
        XCTAssertEqual(Preferences(defaults: defaults).coat, .tora)
    }

    func testEveryCoatHasItsSheetInTheBundle() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/OpusBar/Resources/Coats").standardized
        for coat in CatCoat.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appending(path: coat.sheetName + ".png").path), coat.rawValue)
        }
    }

    func testRetentionSeconds() {
        XCTAssertEqual(FinishedRetention.fiveMinutes.seconds, 300)
        XCTAssertEqual(FinishedRetention.oneHour.seconds, 3600)
        XCTAssertEqual(FinishedRetention.never.seconds, .infinity)
    }

    func testNeverRetentionKeepsFinishedSessions() {
        var state = SessionsState()
        state.byId["s"] = Session(id: "s", cwd: "/tmp/p", state: .done, startedAt: Date(timeIntervalSince1970: 0))
        let pruned = SessionPruner.prune(state, now: Date(timeIntervalSince1970: 1e9),
                                         finishedTTL: FinishedRetention.never.seconds, isAlive: { _ in true })
        XCTAssertNotNil(pruned.byId["s"])
    }

    func testConnectCardOffer() {
        XCTAssertTrue(Preferences.offersConnect(anyConnected: false, anyConnectable: true, dismissed: false))
        XCTAssertFalse(Preferences.offersConnect(anyConnected: true, anyConnectable: true, dismissed: false))
        XCTAssertFalse(Preferences.offersConnect(anyConnected: false, anyConnectable: true, dismissed: true))
        XCTAssertFalse(Preferences.offersConnect(anyConnected: false, anyConnectable: false, dismissed: false))
    }
}
