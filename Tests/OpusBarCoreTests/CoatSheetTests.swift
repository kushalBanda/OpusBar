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

    /// A pose drawn past its cell leaves a sliver of the next cat at the edge of a frame.
    /// Only the cat itself may cross a cell border; clean a new sheet before adding it.
    func testNoPoseFrameShowsASliverOfItsNeighbour() throws {
        for coat in CatCoat.allCases {
            let url = folder.appending(path: coat.sheetName + ".png")
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), coat.rawValue)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), coat.rawValue)
            let pixels = try rgba(image)
            for pose in CatPose.allCases {
                for frame in pose.frames {
                    XCTAssertEqual(straySlivers(pixels, width: image.width, height: image.height, col: frame.col, row: frame.row), 0,
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

    /// Clusters in the cell, other than the largest, that run on across the border into the next cell.
    private func straySlivers(_ pixels: [UInt8], width: Int, height: Int, col: Int, row: Int) -> Int {
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && pixels[(y * width + x) * 4 + 3] > 0
        }
        let x0 = col * 32, y0 = row * 32
        var seen = Set<Int>()
        var clusters: [(size: Int, crosses: Bool)] = []
        for y in 0..<32 {
            for x in 0..<32 where opaque(x0 + x, y0 + y) && !seen.contains(y * 32 + x) {
                var stack = [(x, y)], size = 0, crosses = false
                seen.insert(y * 32 + x)
                while let (cx, cy) = stack.popLast() {
                    size += 1
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = cx + dx, ny = cy + dy
                            guard opaque(x0 + nx, y0 + ny) else { continue }
                            if nx < 0 || ny < 0 || nx >= 32 || ny >= 32 { crosses = true; continue }
                            if seen.insert(ny * 32 + nx).inserted { stack.append((nx, ny)) }
                        }
                    }
                }
                clusters.append((size, crosses))
            }
        }
        guard let largest = clusters.indices.max(by: { clusters[$0].size < clusters[$1].size }) else { return 0 }
        return clusters.indices.filter { $0 != largest && clusters[$0].crosses }.count
    }

    /// Row 0 is the top of the sheet (the context above draws it top row first in memory).
    private func hasVisiblePixels(_ pixels: [UInt8], width: Int, col: Int, row: Int) -> Bool {
        for y in row * 32..<(row + 1) * 32 {
            for x in col * 32..<(col + 1) * 32 where pixels[(y * width + x) * 4 + 3] > 0 { return true }
        }
        return false
    }
}
