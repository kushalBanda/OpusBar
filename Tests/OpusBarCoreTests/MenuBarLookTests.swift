import Foundation
import XCTest
@testable import OpusBarCore

final class MenuBarLookTests: XCTestCase {
    func testMenuBarNeverAnimatesFasterThanFourFramesASecond() {
        for pace in CatPace.allCases {
            let look = MenuBarLook(pace: pace)
            for pose in CatPose.allCases where pose.interval > 0 {
                XCTAssertGreaterThanOrEqual(look.frameInterval(for: pose.interval), 0.25, "\(pace) \(pose)")
            }
        }
        XCTAssertEqual(MenuBarLook(pace: .calm).frameInterval(for: 0.22), 0.5)
        XCTAssertEqual(MenuBarLook(pace: .normal).frameInterval(for: 0.7), 0.7)
    }

    func testNoSessionsLook() {
        let poses = CatPoses.defaults
        XCTAssertEqual(MenuBarLook(empty: .asleep).pose(for: nil, poses: poses), .nap)
        XCTAssertEqual(MenuBarLook(empty: .asleep).pose(for: .working, poses: poses), .run)
        XCTAssertEqual(MenuBarLook(empty: .dimmed).pose(for: nil, poses: poses), .sit)
        XCTAssertEqual(MenuBarLook(empty: .dimmed).alpha(hasSessions: false), 0.5)
        XCTAssertEqual(MenuBarLook(empty: .full).alpha(hasSessions: false), 1)
        XCTAssertEqual(MenuBarLook(empty: .dimmed).alpha(hasSessions: true), 1)
    }

    func testLargeCatShrinksToFitAShortMenuBar() {
        XCTAssertEqual(MenuBarLook(size: .large).catPoints(barThickness: 22), 20)
        XCTAssertEqual(MenuBarLook(size: .large).catPoints(barThickness: 37), 24)
        XCTAssertEqual(MenuBarLook(size: .small).catPoints(barThickness: 22), 16)
    }

    @MainActor
    func testLookPersistsInPreferences() {
        let defaults = UserDefaults(suiteName: "menu-bar-look-\(UUID().uuidString)")!
        Preferences(defaults: defaults).menuBar = MenuBarLook(size: .large, showsBadge: false, empty: .asleep, pace: .calm)
        XCTAssertEqual(Preferences(defaults: defaults).menuBar, MenuBarLook(size: .large, showsBadge: false, empty: .asleep, pace: .calm))
        XCTAssertEqual(Preferences(defaults: UserDefaults(suiteName: "menu-bar-look-\(UUID().uuidString)")!).menuBar, MenuBarLook())
    }
}
