import AppKit
import OpusBarWire
import SwiftUI

/// An agent's mark in its series color: a template image, so it follows `Theme.agent` in light and dark.
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 12

    var body: some View {
        if let image = Self.image(for: agent) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(Theme.agent(agent)).frame(width: size, height: size)
        } else {
            Circle().fill(Theme.agent(agent)).frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        }
    }

    private static let cache = LockedImages()

    private static func image(for agent: AgentKind) -> NSImage? {
        cache.image(named: agent.rawValue) {
            guard let url = url(for: agent.rawValue) else { return nil }
            return NSImage(contentsOf: url)
        }
    }

    /// Packaged app: Contents/Resources. `swift run`: the SwiftPM resource bundle next to the executable.
    private static func url(for name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "AgentLogos") { return url }
        let dev = Bundle.main.bundleURL.appending(path: "OpusBar_OpusBar.bundle")
        return Bundle(url: dev)?.url(forResource: name, withExtension: "png", subdirectory: "AgentLogos")
    }
}

private final class LockedImages: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: NSImage] = [:]

    func image(named name: String, load: () -> NSImage?) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = images[name] { return cached }
        let image = load()
        images[name] = image
        return image
    }
}
