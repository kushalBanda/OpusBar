import AppKit
import OpusBarCore

/// How the cat moves for one state. Frames are (column, row) in the 8 x 4 oneko.js grid.
struct CatAnimation: Equatable {
    let frames: [(col: Int, row: Int)]
    /// Seconds per frame; 0 for a still pose.
    let interval: TimeInterval

    var isAnimated: Bool { interval > 0 && frames.count > 1 }

    static func == (a: CatAnimation, b: CatAnimation) -> Bool {
        a.interval == b.interval && a.frames.map { [$0.col, $0.row] } == b.frames.map { [$0.col, $0.row] }
    }

    init(frames: [(col: Int, row: Int)], interval: TimeInterval) {
        self.frames = frames
        self.interval = interval
    }

    init(pose: CatPose) {
        self.init(frames: pose.frames, interval: pose.interval)
    }

    static let idle = CatAnimation(pose: .sit)

    /// What the cat does for a state, per the user's poses (Cat pane).
    static func `for`(_ state: SessionState?, poses: CatPoses = .defaults) -> CatAnimation {
        CatAnimation(pose: poses.pose(for: state))
    }
}

/// A 256 x 128 sprite sheet sliced into 32 px frames.
final class CatSheet {
    static let framePixels = 32
    private static var sheets: [CatCoat: CatSheet] = [:]

    /// One sheet per coat, loaded the first time it's shown.
    static func sheet(for coat: CatCoat) -> CatSheet {
        if let sheet = sheets[coat] { return sheet }
        let sheet = CatSheet(named: coat.sheetName)
        sheets[coat] = sheet
        return sheet
    }

    private let sheet: CGImage?
    private var cache: [Int: CGImage] = [:]

    init(named name: String) {
        sheet = Self.url(forSheet: name)
            .flatMap { NSImage(contentsOf: $0) }
            .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    }

    func frame(col: Int, row: Int) -> CGImage? {
        let key = row * 8 + col
        if let cached = cache[key] { return cached }
        let size = Self.framePixels
        let image = sheet?.cropping(to: CGRect(x: col * size, y: row * size, width: size, height: size))
        cache[key] = image
        return image
    }

    /// Packaged app: Contents/Resources. `swift run`: the SwiftPM resource bundle next to the executable.
    /// Avoids `Bundle.module`, which traps when its bundle is missing.
    private static func url(forSheet name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Coats") { return url }
        let dev = Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle")
        return Bundle(url: dev)?.url(forResource: name, withExtension: "png", subdirectory: "Coats")
    }
}
