import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import OpusBarCore

/// Every shipped coat must be a 256 x 128 oneko.js sheet where each pose's frames have visible pixels,
/// so no pose shows an empty tile in the menu bar.
final class CoatSheetTests: XCTestCase {
    private let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/OpusBar/Resources/Coats").standardized

    func testEverySheetHasTheOnekoLayoutAndNoEmptyPoseFrames() throws {
        for coat in CatCoat.allCases {
            let url = folder.appending(path: coat.sheetName + ".png")
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), coat.rawValue)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), coat.rawValue)
            XCTAssertEqual(image.width, 256, coat.rawValue)
            XCTAssertEqual(image.height, 128, coat.rawValue)
            let pixels = try rgba(image)
            for pose in CatPose.allCases {
                for frame in pose.frames {
                    XCTAssertTrue(hasVisiblePixels(pixels, width: image.width, col: frame.col, row: frame.row),
                                  "\(coat.rawValue) \(pose.rawValue) \(frame)")
                }
            }
        }
    }

    func testNoUnlicensedCoatIsBundled() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(Set(files), Set(CatCoat.allCases.map { $0.sheetName + ".png" }))
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// Row 0 is the top of the sheet (the context above draws it top row first in memory).
    private func hasVisiblePixels(_ pixels: [UInt8], width: Int, col: Int, row: Int) -> Bool {
        for y in row * 32..<(row + 1) * 32 {
            for x in col * 32..<(col + 1) * 32 where pixels[(y * width + x) * 4 + 3] > 0 { return true }
        }
        return false
    }
}
