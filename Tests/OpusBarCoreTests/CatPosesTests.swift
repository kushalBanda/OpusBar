import Foundation
import XCTest
@testable import OpusBarCore

final class CatPosesTests: XCTestCase {
    func testDefaultsAreTheOriginalMapping() {
        let poses = CatPoses.defaults
        XCTAssertEqual(poses.pose(for: .idle), .sit)
        XCTAssertEqual(poses.pose(for: nil), .sit)
        XCTAssertEqual(poses.pose(for: .working), .run)
        XCTAssertEqual(poses.pose(for: .thinking), .groom)
        XCTAssertEqual(poses.pose(for: .needsAttention), .alert)
        XCTAssertEqual(poses.pose(for: .done), .nap)
        XCTAssertEqual(poses.pose(for: .error), .yawn)
    }

    func testEveryPoseIsOnTheSheet() {
        for pose in CatPose.allCases {
            XCTAssertFalse(pose.frames.isEmpty, pose.rawValue)
            for frame in pose.frames {
                XCTAssertTrue((0..<8).contains(frame.col) && (0..<4).contains(frame.row), "\(pose.rawValue) \(frame)")
            }
            XCTAssertEqual(pose.interval == 0, pose.frames.count == 1, pose.rawValue)
        }
    }

    func testChoiceNotOfferedForAStateIsIgnored() {
        var poses = CatPoses()
        poses.set(.runToYou, for: .done)
        XCTAssertEqual(poses.pose(for: .done), .nap)
        XCTAssertEqual(CatPoses(stored: ["done": "runToYou", "working": "bogus", "nope": "sit"]), .defaults)
    }

    func testStoredRoundTripKeepsOnlyChanges() {
        var poses = CatPoses()
        poses.set(.scratchWall, for: .working)
        poses.set(.alert, for: .needsAttention) // the default: nothing to store
        XCTAssertEqual(poses.stored, ["working": "scratchWall"])
        XCTAssertEqual(CatPoses(stored: poses.stored).pose(for: .working), .scratchWall)
    }

    @MainActor
    func testPosesPersistInPreferences() {
        let defaults = UserDefaults(suiteName: "cat-poses-\(UUID().uuidString)")!
        Preferences(defaults: defaults).poses.set(.sit, for: .done)
        XCTAssertEqual(Preferences(defaults: defaults).poses.pose(for: .done), .sit)
    }
}
