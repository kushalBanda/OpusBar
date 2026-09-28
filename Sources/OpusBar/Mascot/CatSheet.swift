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

    static let idle = CatAnimation(frames: [(3, 3)], interval: 0)                          // sits
    static let working = CatAnimation(frames: [(3, 0), (3, 1)], interval: 0.11)            // runs in place
    static let thinking = CatAnimation(frames: [(5, 0), (6, 0), (7, 0), (6, 0)], interval: 0.22) // grooms
    static let attention = CatAnimation(frames: [(7, 3)], interval: 0)                     // alert, ears up
    static let done = CatAnimation(frames: [(2, 0), (2, 1)], interval: 0.7)               // naps
    static let error = CatAnimation(frames: [(3, 2)], interval: 0)                         // slumps

    static func `for`(_ state: SessionState?) -> CatAnimation {
        switch state {
        case nil, .idle: .idle
        case .working: .working
        case .thinking: .thinking
        case .needsAttention: .attention
        case .done: .done
        case .error: .error
        }
    }
}

/// A 256 x 128 sprite sheet sliced into 32 px frames.
final class CatSheet {
    static let framePixels = 32
    static let shared = CatSheet(named: "oneko-classic")

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
        if let url = Bundle.main.url(forResource: name, withExtension: "png") { return url }
        let dev = Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle")
        return Bundle(url: dev)?.url(forResource: name, withExtension: "png")
    }
}
